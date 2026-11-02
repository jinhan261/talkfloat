import AVFoundation
import CoreAudio
import AudioRing

/// The audio tap only copies into a bounded, preallocated C ring. Conversion,
/// allocation and stream delivery run on a serial worker, never the audio thread.
public final class MicrophoneAudio: @unchecked Sendable {
    public let frames:AsyncThrowingStream<AudioPacket,Error>
    private let continuation:AsyncThrowingStream<AudioPacket,Error>.Continuation
    private let queue=DispatchQueue(label:"app.saylori.microphone",qos:.userInitiated)
    private var engine:AVAudioEngine?
    private var ring:OpaquePointer?
    private var converter:AVAudioConverter?
    private var input:AVAudioPCMBuffer?
    private var output:AVAudioPCMBuffer?
    private var timer:DispatchSourceTimer?
    private var observer:NSObjectProtocol?
    private var running=false
    private var deviceListener:AudioObjectPropertyListenerBlock?
    private var deviceID:AudioDeviceID=0
    private var pending=Data()
    private var lastLevel=0.0
    private var lastModeCheck=0.0
    private let modeQueue=DispatchQueue(label:"app.saylori.microphone-mode",qos:.utility)
    private var modeTimer:DispatchSourceTimer?
    private var inputChannels:Double=0
    public var onDiagnostics:(([String:Double])->Void)?
    public var onProcessingMode:((Int)->Void)?
    public static func showMicrophoneModes(){AVCaptureDevice.showSystemUserInterface(.microphoneModes)}
    public var onLevel:((Float)->Void)?
    public var onDevice:((String)->Void)?
    public init(){var c:AsyncThrowingStream<AudioPacket,Error>.Continuation!;frames=AsyncThrowingStream(bufferingPolicy:.bufferingOldest(4)){c=$0};continuation=c}
    private static var defaultInputAddress:AudioObjectPropertyAddress{AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)}
    private static var defaultInputID:AudioDeviceID{
        var a=defaultInputAddress;var device=AudioDeviceID(0);var n=UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&n,&device);return device
    }
    public static var deviceName:String {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var device=AudioDeviceID(0);var size=UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device)==noErr,device != 0 else{return "未找到输入设备"}
        address.mSelector=kAudioObjectPropertyName;var name:CFString="麦克风" as CFString;size=UInt32(MemoryLayout<CFString>.size)
        _ = AudioObjectGetPropertyData(device,&address,0,nil,&size,&name)
        return name as String
    }
    public func start() async throws {
        let allowed=await AVCaptureDevice.requestAccess(for:.audio)
        guard allowed else{throw SayError.message("麦克风未获授权；请在系统设置 → 隐私与安全 → 麦克风中允许 Saylori。系统声音仍可翻译。")}
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in queue.async{
            do{
                self.running=true;try self.configure()
                let listener:AudioObjectPropertyListenerBlock={[weak self] _,_ in
                    guard let self,self.running,self.deviceID != Self.defaultInputID else{return}
                    self.restart()
                }
                self.deviceListener=listener;var a=Self.defaultInputAddress
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&a,self.queue,listener)
                c.resume()
            }catch{self.close();c.resume(throwing:error)}
        }}
    }
    private func configure() throws {
        deviceID=Self.defaultInputID
        let e=AVAudioEngine();let node=e.inputNode
        // Enable Apple's hardware-aware processing so Control Center can apply
        // Voice Isolation. Disable AGC: quiet room conversations must not be
        // automatically amplified to the same level as near-end speech.
        try node.setVoiceProcessingEnabled(true)
        node.isVoiceProcessingAGCEnabled=false
        node.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking:false,duckingLevel:.min)
        let format=node.outputFormat(forBus:0)
        guard format.sampleRate>0,format.channelCount>0 else{throw SayError.message("麦克风暂不可用，请检查系统声音输入设备。")}
        let mono=AVAudioFormat(standardFormatWithSampleRate:format.sampleRate,channels:1)!
        let target=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true)!
        guard let cv=AVAudioConverter(from:mono,to:target),
              let ib=AVAudioPCMBuffer(pcmFormat:mono,frameCapacity:8192),
              let ob=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:8192),
              let r=say_ring_create_channel(Int(format.sampleRate*0.32),format.channelCount,format.isInterleaved ? 1:0,0) else{throw SayError.message("无法准备麦克风缓冲区。")}
        // VoiceProcessingIO can expose additional hardware channels on macOS.
        // Explicitly select its primary speech channel; never downmix raw auxiliaries.
        ring=r;engine=e;converter=cv;input=ib;output=ob;inputChannels=Double(format.channelCount)
        node.installTap(onBus:0,bufferSize:512,format:format){buffer,_ in
            say_ring_write_frames(r,buffer.audioBufferList,Int(buffer.frameLength))
        }
        try e.start()
        // Startup can block while VoiceProcessingIO negotiates its device graph.
        // These pre-authentication frames are never part of the live session.
        say_ring_discard(r)
        let deviceCallback=onDevice,modeCallback=onProcessingMode
        modeQueue.async{deviceCallback?(Self.deviceName)}
        let mt=DispatchSource.makeTimerSource(queue:modeQueue);modeTimer=mt
        mt.schedule(deadline:.now(),repeating:.seconds(1))
        mt.setEventHandler{modeCallback?(AVCaptureDevice.activeMicrophoneMode.rawValue)};mt.resume()
        observer=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:e,queue:nil){[weak self] _ in
            self?.queue.async{[weak self,weak e] in
                guard let self,self.running,self.engine === e else{return}
                self.restart()
            }
        }
        let t=DispatchSource.makeTimerSource(queue:queue);timer=t
        t.schedule(deadline:.now(),repeating:.milliseconds(20),leeway:.milliseconds(2))
        t.setEventHandler{[weak self] in self?.drain()};t.resume()
    }
    private func restart(){
        // Flush the old-format tail before following the new default device.
        drain()
        guard running else{return}
        if !pending.isEmpty{continuation.yield(AudioPacket(data:pending,queuedAt:ProcessInfo.processInfo.systemUptime));pending.removeAll(keepingCapacity:true)}
        teardown()
        do{try configure()}catch{continuation.finish(throwing:error);close()}
    }
    private func drain(){
        guard let ring,let converter,let input,let output else{return}
        guard say_ring_overflow(ring)==0 else{reportBufferStats();continuation.finish(throwing:SayError.message("麦克风处理已落后，已停止该路收听，请重新开启麦克风。"));close();return}
        let n=say_ring_read(ring,input.floatChannelData![0],Int(input.frameCapacity));guard n>0 else{return}
        input.frameLength=AVAudioFrameCount(n)
        var supplied=false;var error:NSError?
        output.frameLength=0
        let result=converter.convert(to:output,error:&error){_,status in
            if supplied{status.pointee = .noDataNow;return nil};supplied=true;status.pointee = .haveData;return input
        }
        if result == .error{continuation.finish(throwing:error ?? SayError.message("麦克风格式转换失败") as NSError);close();return}
        let count=Int(output.frameLength);guard count>0 else{return}
        let samples=output.int16ChannelData![0]
        let now=ProcessInfo.processInfo.systemUptime
        if now-lastModeCheck>1{lastModeCheck=now;reportBufferStats()}
        if now-lastLevel>0.2{lastLevel=now;var peak:Float=0;for i in 0..<count{peak=max(peak,abs(Float(samples[i])/32768))};onLevel?(peak)}
        pending.append(UnsafeBufferPointer(start:UnsafeRawPointer(samples).assumingMemoryBound(to:UInt8.self),count:count*2))
        while pending.count>=2560{
            let bytes=Data(pending.prefix(2560));pending.removeFirst(2560)
            if case .dropped=continuation.yield(AudioPacket(data:bytes,queuedAt:now)){
                continuation.finish(throwing:SayError.message("麦克风上传积压，已停止该路收听。请检查网络后重新开启。"));close();return
            }
        }
    }
    public func stop() async {
        await withCheckedContinuation{(c:CheckedContinuation<Void,Never>) in queue.async{
            self.drain()
            if !self.pending.isEmpty{self.continuation.yield(AudioPacket(data:self.pending,queuedAt:ProcessInfo.processInfo.systemUptime));self.pending.removeAll()}
            self.close();self.continuation.finish();c.resume()
        }}
    }
    private func reportBufferStats(){
        if let ring,let input {onDiagnostics?(["sampleRate":input.format.sampleRate,"channels":inputChannels,"maxCallbackFrames":Double(say_ring_max_callback_frames(ring)),"maxDeclaredFrames":Double(say_ring_max_declared_frames(ring))])}
    }
    private func teardown(){
        modeTimer?.cancel();modeTimer=nil
        if let observer{NotificationCenter.default.removeObserver(observer)};observer=nil
        timer?.cancel();timer=nil
        engine?.stop();engine?.inputNode.removeTap(onBus:0);engine=nil
        if let ring{say_ring_destroy(ring)};ring=nil;converter=nil;input=nil;output=nil
    }
    private func close(){
        running=false
        if let listener=deviceListener{var a=Self.defaultInputAddress;AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&a,queue,listener)}
        deviceListener=nil;teardown()
    }
}
