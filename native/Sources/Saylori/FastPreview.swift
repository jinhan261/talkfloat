import Foundation
import Speech
import Translation
import AVFoundation
import SayloriCore

/// A speculative, entirely on-device path. Never blocks the cloud audio sender.
@available(macOS 26.4, *)
@MainActor final class FastPreview {
    private let sessionID:String
    private let origin:AudioOrigin
    private let translator=TranslationSession(installedSource:Locale.Language(identifier:"en"),target:Locale.Language(identifier:"zh-Hans"),preferredStrategy:.lowLatency)
    private var analyzer:SpeechAnalyzer?
    private var inputTask:Task<Void,Never>?
    private var resultTask:Task<Void,Never>?
    private var translationTask:Task<Void,Never>?
    private var pending:CaptionSegment?
    private var ended=false
    private var lastRequest=Date.distantPast
    private var lastText=""
    private let packets:AsyncStream<Data>
    nonisolated private let continuation:AsyncStream<Data>.Continuation
    var onCaption:((CaptionSegment)->Void)?
    var onFailure:((String)->Void)?
    init(sessionID:String,origin:AudioOrigin){
        self.sessionID=sessionID;self.origin=origin
        let pair=AsyncStream<Data>.makeStream(bufferingPolicy:.bufferingNewest(8))
        packets=pair.stream;continuation=pair.continuation
    }
    static func available() async -> Bool {
        let speech=SpeechTranscriber(locale:Locale(identifier:"en-US"),preset:.progressiveTranscription)
        let installed=await AssetInventory.status(forModules:[speech]) == .installed
        let translated=await LanguageAvailability(preferredStrategy:.lowLatency).status(from:Locale.Language(identifier:"en"),to:Locale.Language(identifier:"zh-Hans")) == .installed
        return installed && translated
    }
    nonisolated func feed(_ data:Data){
        if case .dropped = continuation.yield(data){
            continuation.finish()
            Task{@MainActor [weak self] in self?.onFailure?("本机预览跟不上音频，已停用；豆包翻译继续。")}
        }
    }
    func start() async throws {
        let transcriber=SpeechTranscriber(locale:Locale(identifier:"en-US"),preset:.timeIndexedProgressiveTranscription)
        let engine=SpeechAnalyzer(modules:[transcriber]);analyzer=engine
        guard let format=await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[transcriber]),
              let source=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false),
              let converter=AVAudioConverter(from:source,to:format) else{throw SayError.message("本机预览音频格式不可用")}
        try await engine.prepareToAnalyze(in:format)
        let pair=AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingNewest(8))
        resultTask=Task{[weak self] in
            do{for try await result in transcriber.results {
                guard let self,!self.ended else{return}
                let text=String(result.text.characters).trimmingCharacters(in:.whitespacesAndNewlines)
                guard !text.isEmpty else{continue}
                let ranges=result.text.runs.compactMap{$0.audioTimeRange}
                let start=ranges.map{ $0.start.seconds }.min() ?? result.range.start.seconds
                let end=ranges.map{ CMTimeRangeGetEnd($0).seconds }.max() ?? CMTimeRangeGetEnd(result.range).seconds
                var item=CaptionSegment(sessionID:self.sessionID,startMS:Int(start*1000))
                item.endMS=Int(end*1000)
                item.source=text;item.origin=self.origin;item.provisional=true;item.sourceFinal=result.isFinal
                if text.split(whereSeparator:{$0.isWhitespace}).count>=3 || result.isFinal{self.enqueue(item)}
            }}catch{if !Task.isCancelled{self?.onFailure?("本机预览已停止；豆包翻译继续。")}}
        }
        let packets=self.packets
        inputTask=Task.detached{[weak self] in
            let analysis=Task{try await engine.start(inputSequence:pair.stream)}
            var samples:Int64=0
            do{
                for await bytes in packets {
                    try Task.checkCancellation()
                    guard let input=AVAudioPCMBuffer(pcmFormat:source,frameCapacity:AVAudioFrameCount(bytes.count/2)),let ptr=input.int16ChannelData?[0] else{continue}
                    input.frameLength=input.frameCapacity
                    bytes.withUnsafeBytes{if let base=$0.baseAddress{memcpy(ptr,base,bytes.count)}}
                    let capacity=AVAudioFrameCount(ceil(Double(input.frameLength)*format.sampleRate/16000)+32)
                    guard let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:capacity) else{continue}
                    var used=false;var error:NSError?
                    converter.convert(to:output,error:&error){_,status in
                        if used{status.pointee = .noDataNow;return nil};used=true;status.pointee = .haveData;return input
                    }
                    if let error{throw error}
                    if output.frameLength>0 {
                        let value=AnalyzerInput(buffer:output,bufferStartTime:CMTime(value:samples,timescale:CMTimeScale(format.sampleRate)))
                        samples += Int64(output.frameLength)
                        if case .dropped = pair.continuation.yield(value){throw SayError.message("本机识别缓冲已满")}
                    }
                }
                pair.continuation.finish();try await analysis.value
                try await engine.finalizeAndFinishThroughEndOfInput()
            }catch{pair.continuation.finish();analysis.cancel();await engine.cancelAndFinishNow();if !Task.isCancelled{await self?.onFailure?("本机预览已停止；豆包翻译继续。")}}
        }
    }
    private func enqueue(_ item:CaptionSegment){
        guard item.source != lastText else{return};lastText=item.source;pending=item
        TestDiagnostics.record("local-asr",["session":sessionID,"origin":origin.rawValue,"startMS":item.startMS,"endMS":item.endMS,"text":item.source,"uptime":ProcessInfo.processInfo.systemUptime])
        guard translationTask==nil else{return}
        translationTask=Task{[weak self] in
            guard let self else{return}
            // The recognizer may deliver several revisions in one batch. Translate its
            // newest hypothesis instead of briefly displaying a mistranslated lone word.
            try? await Task.sleep(for:.milliseconds(100))
            while !ended,let item=pending {
                let wait=0.30-Date().timeIntervalSince(lastRequest)
                if wait>0{try? await Task.sleep(for:.seconds(wait))}
                guard !Task.isCancelled,!ended else{break}
                let value=pending ?? item;pending=nil;lastRequest=Date()
                do{
                    let response=try await translator.translate(PreviewText.translationInput(value.source,stable:value.sourceFinal))
                    guard !Task.isCancelled,!ended else{break}
                    // A newer utterance must never be replaced by a delayed previous one.
                    if let newer=pending,newer.startMS>value.endMS+800{continue}
                    var translated=value;translated.translation=response.targetText.applyingTransform(StringTransform("Traditional-Simplified"),reverse:false) ?? response.targetText;translated.previewUpdatedAt=Date()
                    TestDiagnostics.record("local-translation",["session":sessionID,"origin":origin.rawValue,"startMS":value.startMS,"endMS":value.endMS,"source":value.source,"text":response.targetText,"uptime":ProcessInfo.processInfo.systemUptime,"translateMS":Date().timeIntervalSince(lastRequest)*1000])
                    onCaption?(translated)
                }catch{if !Task.isCancelled{onFailure?("本机预览暂不可用；豆包翻译继续。")};break}
            }
            translationTask=nil
        }
    }
    func stop() async {
        ended=true;continuation.finish();pending=nil
        translationTask?.cancel();translator.cancel();inputTask?.cancel();resultTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        inputTask=nil;resultTask=nil;translationTask=nil;analyzer=nil
    }
}
