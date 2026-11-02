import Foundation
import Speech
import Translation
import AVFoundation
import SayloriCore

/// Shared on-device speech/translation pipeline. Cloud preview keeps the latest
/// hypothesis; complete mode also preserves and drains every recognized final.
@available(macOS 26.4, *)
@MainActor final class FastPreview {
    private let sessionID:String
    private let origin:AudioOrigin
    private let complete:Bool
    private let translator=TranslationSession(installedSource:Locale.Language(identifier:"en"),target:Locale.Language(identifier:"zh-Hans"),preferredStrategy:.lowLatency)
    private var analyzer:SpeechAnalyzer?
    private var inputTask:Task<Void,Never>?
    private var resultTask:Task<Void,Never>?
    private var translationTask:Task<Void,Never>?
    private var pending:CaptionSegment?
    private var queue=LocalTranslationQueue()
    private var identities=LocalSpeechIdentity()
    private var ended=false
    private var hasFailure=false
    private var lastRequest=Date.distantPast
    private var lastResult=""
    private let packets:AsyncStream<Data>
    nonisolated private let continuation:AsyncStream<Data>.Continuation
    var onCaption:((CaptionSegment)->Void)?
    var onFailure:((String)->Void)?
    init(sessionID:String,origin:AudioOrigin,complete:Bool=false){
        self.sessionID=sessionID;self.origin=origin;self.complete=complete
        let pair=AsyncStream<Data>.makeStream(bufferingPolicy:.bufferingOldest(8))
        packets=pair.stream;continuation=pair.continuation
    }
    static func available() async -> Bool {
        let speech=SpeechTranscriber(locale:Locale(identifier:"en-US"),preset:.progressiveTranscription)
        let installed=await AssetInventory.status(forModules:[speech]) == .installed
        let translated=await LanguageAvailability(preferredStrategy:.lowLatency).status(from:Locale.Language(identifier:"en"),to:Locale.Language(identifier:"zh-Hans")) == .installed
        return installed && translated
    }
    @discardableResult nonisolated func feed(_ data:Data)->Bool {
        switch continuation.yield(data){
        case .enqueued:return true
        case .dropped:
            continuation.finish()
            Task{@MainActor [weak self] in self?.fail("本地识别跟不上音频，已停止该路处理。")}
            return false
        case .terminated:return false
        @unknown default:return false
        }
    }
    private func fail(_ message:String){
        guard !hasFailure,!ended else{return};hasFailure=true
        onFailure?(complete ? message:message+"豆包翻译继续。")
    }
    func start() async throws {
        let transcriber=SpeechTranscriber(locale:Locale(identifier:"en-US"),preset:.timeIndexedProgressiveTranscription)
        let engine=SpeechAnalyzer(modules:[transcriber]);analyzer=engine
        guard let format=await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[transcriber]),
              let source=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false),
              let converter=AVAudioConverter(from:source,to:format) else{throw SayError.message("本地识别音频格式不可用")}
        try await engine.prepareToAnalyze(in:format)
        let pair=AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingOldest(8))
        resultTask=Task{[weak self] in
            do{for try await result in transcriber.results {
                guard let self,!self.ended else{return}
                let text=String(result.text.characters).trimmingCharacters(in:.whitespacesAndNewlines)
                guard !PreviewText.normalized(text).isEmpty else{continue}
                let start=Int(result.range.start.seconds*1000)
                let end=Int(CMTimeRangeGetEnd(result.range).seconds*1000)
                let key="\(start):\(text):\(result.isFinal)"
                guard key != self.lastResult else{continue};self.lastResult=key
                var item=CaptionSegment(sessionID:self.sessionID,startMS:start)
                item.id=self.identities.identify(start:start,end:end,final:result.isFinal)
                item.endMS=end;item.source=text;item.origin=self.origin
                item.provisional=true;item.sourceFinal=result.isFinal
                TestDiagnostics.record("local-asr",["session":self.sessionID,"origin":self.origin.rawValue,"startMS":start,"endMS":end,"text":text,"final":result.isFinal,"uptime":ProcessInfo.processInfo.systemUptime])
                if self.complete{self.onCaption?(item)}
                if text.split(whereSeparator:{$0.isWhitespace}).count>=3 || result.isFinal{self.enqueue(item)}
            }}catch{if !Task.isCancelled{self?.fail("本地语音识别已停止："+error.localizedDescription)}}
        }
        let packets=self.packets
        inputTask=Task.detached{[weak self] in
            let analysis=Task{try await engine.start(inputSequence:pair.stream)}
            var samples:Int64=0
            do{
                for await bytes in packets {
                    try Task.checkCancellation()
                    guard let input=AVAudioPCMBuffer(pcmFormat:source,frameCapacity:AVAudioFrameCount(bytes.count/2)),let ptr=input.int16ChannelData?[0] else{throw SayError.message("本地音频缓冲分配失败")}
                    input.frameLength=input.frameCapacity
                    bytes.withUnsafeBytes{if let base=$0.baseAddress{memcpy(ptr,base,bytes.count)}}
                    let capacity=AVAudioFrameCount(ceil(Double(input.frameLength)*format.sampleRate/16000)+32)
                    guard let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:capacity) else{throw SayError.message("本地重采样缓冲分配失败")}
                    var used=false;var error:NSError?
                    converter.convert(to:output,error:&error){_,status in
                        if used{status.pointee = .noDataNow;return nil};used=true;status.pointee = .haveData;return input
                    }
                    if let error{throw error}
                    if output.frameLength>0 {
                        let value=AnalyzerInput(buffer:output,bufferStartTime:CMTime(value:samples,timescale:CMTimeScale(format.sampleRate)))
                        samples += Int64(output.frameLength)
                        if case .dropped = pair.continuation.yield(value){throw SayError.message("本地识别缓冲已满")}
                    }
                }
                pair.continuation.finish();try await analysis.value
                try await engine.finalizeAndFinishThroughEndOfInput()
            }catch{
                pair.continuation.finish();analysis.cancel();await engine.cancelAndFinishNow()
                if !Task.isCancelled{await self?.fail("本地音频处理已停止："+error.localizedDescription)}
            }
        }
    }
    private func enqueue(_ item:CaptionSegment){
        do{if complete{try queue.enqueue(item)}else{pending=item}}
        catch{fail(error.localizedDescription);return}
        guard translationTask==nil else{return}
        translationTask=Task{[weak self] in
            guard let self else{return}
            try? await Task.sleep(for:.milliseconds(80))
            while !ended,!Task.isCancelled {
                // Coalesce volatile ASR, while never replacing queued final sentences.
                let wait=0.25-Date().timeIntervalSince(lastRequest)
                if wait>0{try? await Task.sleep(for:.seconds(wait))}
                guard !Task.isCancelled,!ended else{break}
                let selected:CaptionSegment?
                if complete{selected=queue.next()}else{selected=pending;pending=nil}
                guard let value=selected else{break}
                lastRequest=Date()
                do{
                    let text=complete && value.sourceFinal ? value.source:PreviewText.translationInput(value.source,stable:value.sourceFinal)
                    let response=try await translator.translate(text)
                    guard !Task.isCancelled,!ended else{break}
                    if !complete,let newer=pending,newer.startMS>value.endMS+800{continue}
                    var translated=value
                    translated.translation=response.targetText.applyingTransform(StringTransform("Traditional-Simplified"),reverse:false) ?? response.targetText
                    translated.translationStarted=true
                    translated.translationFinal=complete && value.sourceFinal
                    translated.provisional = !translated.translationFinal
                    translated.previewUpdatedAt=Date()
                    TestDiagnostics.record("local-translation",["session":sessionID,"origin":origin.rawValue,"startMS":value.startMS,"endMS":value.endMS,"source":value.source,"text":translated.translation,"final":translated.translationFinal,"uptime":ProcessInfo.processInfo.systemUptime,"translateMS":Date().timeIntervalSince(lastRequest)*1000,"pending":queue.count])
                    onCaption?(translated)
                }catch{if !Task.isCancelled{fail("本地中文翻译已停止："+error.localizedDescription)};break}
            }
            translationTask=nil
        }
    }
    func finish() async ->Bool {
        continuation.finish()
        let deadline=Task{[weak self] in
            try? await Task.sleep(for:.seconds(12))
            guard !Task.isCancelled,let self else{return}
            self.fail("本地收尾超时；未定稿的内容已保留并标注。")
            await self.stop()
        }
        await inputTask?.value
        await resultTask?.value
        await translationTask?.value
        deadline.cancel()
        let ok = !hasFailure
        await stop();return ok
    }
    func stop() async {
        ended=true;continuation.finish();pending=nil;queue.removeAll()
        translationTask?.cancel();translator.cancel();inputTask?.cancel();resultTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        inputTask=nil;resultTask=nil;translationTask=nil;analyzer=nil
    }
}
