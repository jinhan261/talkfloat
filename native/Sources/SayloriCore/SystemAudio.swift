import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

// First release uses Apple's supported SCStream audio output. No screen output is
// registered, no pixel buffers are read, and no recording output or file is created.
public struct AudioPacket: Sendable {
    public let data: Data
    public let queuedAt: TimeInterval
    public init(data:Data,queuedAt:TimeInterval){self.data=data;self.queuedAt=queuedAt}
}

public final class SystemAudio:NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public let frames:AsyncThrowingStream<AudioPacket,Error>
    private let continuation:AsyncThrowingStream<AudioPacket,Error>.Continuation
    private let queue=DispatchQueue(label:"app.saylori.sck-audio",qos:.userInitiated)
    private let lock=NSLock()
    private var stream:SCStream?
    private var stopped=false
    private var pending=Data()
    private var lastLevel=Date.distantPast
    public var onLevel:(@Sendable(Float)->Void)?
    public override init(){
        let pair=AsyncThrowingStream<AudioPacket,Error>.makeStream(bufferingPolicy:.bufferingOldest(4))
        frames=pair.stream;continuation=pair.continuation;super.init()
    }
    public func start(source:AudioSource) async throws {
        do{
            let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:false)
            guard !lock.withLock({stopped}) else{throw CancellationError()}
            guard let display=content.displays.first else{throw SayError.message("未找到可捕获的显示器")}
            let filter:SCContentFilter
            if source.id=="system"{
                let own=content.applications.filter{$0.bundleIdentifier==Bundle.main.bundleIdentifier}
                filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
            }else{
                let apps=content.applications.filter{$0.bundleIdentifier==source.id || $0.bundleIdentifier.hasPrefix(source.id+".")}
                guard !apps.isEmpty else{throw SayError.message("未找到 \(source.name)，请打开应用后重试")}
                filter=SCContentFilter(display:display,including:apps,exceptingWindows:[])
            }
            let config=SCStreamConfiguration()
            config.capturesAudio=true;config.excludesCurrentProcessAudio=true
            config.sampleRate=16000;config.channelCount=1
            config.width=2;config.height=2;config.minimumFrameInterval=CMTime(value:1,timescale:1)
            config.queueDepth=3;config.showsCursor=false
            let capture=SCStream(filter:filter,configuration:config,delegate:self)
            try capture.addStreamOutput(self,type:.audio,sampleHandlerQueue:queue)
            let installed=lock.withLock{if stopped{return false};stream=capture;return true}
            guard installed else{throw CancellationError()}
            try await capture.startCapture()
            if lock.withLock({stopped}){try? await capture.stopCapture();throw CancellationError()}
        }catch{
            stop()
            let ns=error as NSError
            if ns.domain==SCStreamErrorDomain && ns.code == -3801 {
                throw SayError.message("macOS 未允许当前安装版本采集声音（-3801）。如果录屏与系统录音开关已开启，可能仍对应旧版签名；请退出 TalkFloat，在系统设置中重新授权当前版本后打开。")
            };throw error
        }
    }
    public func stream(_ stream:SCStream,didStopWithError error:Error){continuation.finish(throwing:error);stop()}
    public func stream(_ stream:SCStream,didOutputSampleBuffer sampleBuffer:CMSampleBuffer,of type:SCStreamOutputType){
        guard type == .audio,!lock.withLock({stopped}),sampleBuffer.isValid,
              let description=sampleBuffer.formatDescription,
              let format=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else{return}
        guard format.mSampleRate==16000,format.mChannelsPerFrame==1 else{
            continuation.finish(throwing:SayError.message("系统返回了意外的音频格式，请重新开始"));stop();return
        }
        var list=AudioBufferList();var block:CMBlockBuffer?
        let status=CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer,
            bufferListSizeNeededOut:nil,bufferListOut:&list,bufferListSize:MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator:kCFAllocatorDefault,blockBufferMemoryAllocator:kCFAllocatorDefault,
            flags:UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),blockBufferOut:&block)
        defer{withExtendedLifetime(block){}}
        guard status==noErr,let pointer=list.mBuffers.mData else{return}
        let length=Int(list.mBuffers.mDataByteSize);var peak:Float=0
        if format.mBitsPerChannel==32 && format.mFormatFlags & kAudioFormatFlagIsFloat != 0{
            let samples=pointer.assumingMemoryBound(to:Float.self)
            for i in 0..<(length/4){
                let f=samples[i].isFinite ? max(-1,min(1,samples[i])):0;peak=max(peak,abs(f))
                var s=Int16((f*32767).rounded()).littleEndian
                withUnsafeBytes(of:&s){pending.append(contentsOf:$0)}
            }
        }else if format.mBitsPerChannel==16 && format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0{
            let samples=pointer.assumingMemoryBound(to:Int16.self)
            for i in 0..<(length/2){peak=max(peak,abs(Float(samples[i])/32768))}
            pending.append(pointer.assumingMemoryBound(to:UInt8.self),count:length)
        }else{continuation.finish(throwing:SayError.message("系统返回了不支持的 PCM 类型"));stop();return}
        if Date().timeIntervalSince(lastLevel)>=0.2{lastLevel=Date();onLevel?(peak)}
        while pending.count>=2560{
            let data=Data(pending.prefix(2560));pending.removeFirst(2560)
            if case .dropped = continuation.yield(AudioPacket(data:data,queuedAt:ProcessInfo.processInfo.systemUptime)){
                continuation.finish(throwing:SayError.message("网络发送跟不上实时声音，已停止收听并保留文字。请检查网络后重新开始。"));stop();return
            }
        }
    }
    public func stop(){
        let capture:SCStream?=lock.withLock{
            if stopped{return nil};stopped=true;let value=stream;stream=nil;return value
        }
        queue.async{
            if !self.pending.isEmpty{self.continuation.yield(AudioPacket(data:self.pending,queuedAt:ProcessInfo.processInfo.systemUptime));self.pending.removeAll()}
            self.continuation.finish()
        }
        if let capture{Task{try? await capture.stopCapture()}}
    }
}
