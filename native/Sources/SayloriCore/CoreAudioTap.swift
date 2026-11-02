import Foundation
import CoreAudio
import AVFoundation
import AudioRing

public struct AudioSource: Identifiable, Hashable, Sendable {
    public let id: String; public let name: String
    public init(id: String, name: String) { self.id=id; self.name=name }
    public static let chrome = AudioSource(id: "com.google.Chrome", name: "Chrome")
    public static let system = AudioSource(id: "system", name: "所有系统声音")
}

@available(macOS 14.2, *)
public final class CoreAudioTap: @unchecked Sendable {
    public let frames: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let queue = DispatchQueue(label: "app.saylori.audio", qos: .userInitiated)
    private var tap: AudioObjectID = 0; private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var ring: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var converter: AVAudioConverter?
    private var input: AVAudioPCMBuffer?
    private var output: AVAudioPCMBuffer?
    private var pending = Data()
    public var onLevel: (@Sendable (Float) -> Void)?
    private var ticks = 0
    public init() {
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(12))
        frames=pair.stream; continuation=pair.continuation
    }
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func check(_ status: OSStatus, _ context: String) throws {
        if status != noErr { throw SayError.message("\(context)失败（\(status)）。请检查系统音频录制权限。") }
    }
    public static func processIDs() -> [AudioObjectID] {
        var a=address(kAudioHardwarePropertyProcessObjectList); var size: UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)==0 else{return []}
        var ids=[AudioObjectID](repeating:0,count:Int(size)/4)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)==0 else{return []}
        return ids
    }
    public static func bundleID(_ process: AudioObjectID) -> String {
        var a=address(kAudioProcessPropertyBundleID); var value: Unmanaged<CFString>?
        var size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process,&a,0,nil,&size,&value)==0 else{return ""}; return value?.takeRetainedValue() as String? ?? ""
    }
    private static func processPID(_ process: AudioObjectID) -> pid_t {
        var a=address(kAudioProcessPropertyPID); var p:pid_t=0; var size=UInt32(MemoryLayout<pid_t>.size)
        _=AudioObjectGetPropertyData(process,&a,0,nil,&size,&p);return p
    }
    private final class Startup {
        let semaphore=DispatchSemaphore(value:0)
        let lock=NSLock()
        var result:Result<Void,Error>?
        func complete(_ value:Result<Void,Error>)->Bool {
            lock.lock();defer{lock.unlock()}
            guard result==nil else{return false};result=value;semaphore.signal();return true
        }
        func wait() throws {
            _ = semaphore.wait(timeout:.now()+12)
            lock.lock();defer{lock.unlock()}
            if result==nil{result = .failure(SayError.message("系统采音启动超时。请允许 TalkFloat 的系统音频录制权限后重试。"))}
            try result!.get()
        }
    }
    public func start(source: AudioSource) throws {
        let startup=Startup()
        queue.async {
            do{
                try self.setup(source)
                if !startup.complete(.success(())){self.teardown()}
            }catch{self.teardown();_ = startup.complete(.failure(error))}
        }
        try startup.wait()
    }
    private func setup(_ source: AudioSource) throws {
        let ids=Self.processIDs()
        let own=ids.filter { Self.processPID($0)==getpid() }
        let selected=ids.filter { let b=Self.bundleID($0); return b==source.id || b.hasPrefix(source.id+".") }
        if source.id != "system" && selected.isEmpty {
            throw SayError.message("\(source.name)还没有可捕获的音频进程。请先在该应用播放声音，或选择所有系统声音。")
        }
        let desc = source.id == "system" ? CATapDescription(stereoGlobalTapButExcludeProcesses: own) : CATapDescription(stereoMixdownOfProcesses: selected)
        desc.name="TalkFloat System Audio"; desc.uuid=UUID(); desc.isPrivate=true; desc.muteBehavior = .unmuted
        if #available(macOS 26, *), source.id != "system" {
            desc.bundleIDs=Array(Set(selected.map(Self.bundleID))); desc.isProcessRestoreEnabled=true
        }
        try Self.check(AudioHardwareCreateProcessTap(desc,&tap),"创建音源")
        var a=Self.address(kAudioTapPropertyFormat); var asbd=AudioStreamBasicDescription()
        var size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(AudioObjectGetPropertyData(tap,&a,0,nil,&size,&asbd),"读取音频格式")
        guard asbd.mFormatID==kAudioFormatLinearPCM, asbd.mBitsPerChannel==32,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mSampleRate>0, asbd.mChannelsPerFrame>0 else {throw SayError.message("当前音频设备未提供兼容的浮点 PCM 格式")}
        let inputFormat=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:asbd.mSampleRate,channels:1,interleaved:false)!
        let outputFormat=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false)!
        converter=AVAudioConverter(from:inputFormat,to:outputFormat)
        input=AVAudioPCMBuffer(pcmFormat:inputFormat,frameCapacity:AVAudioFrameCount(asbd.mSampleRate))
        output=AVAudioPCMBuffer(pcmFormat:outputFormat,frameCapacity:18000)
        ring=say_ring_create(Int(asbd.mSampleRate),asbd.mChannelsPerFrame,asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 ? 1:0)
        guard ring != nil,converter != nil,input != nil,output != nil else{throw SayError.message("音频缓冲初始化失败")}
        var outputAddress=Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var outputDevice:AudioObjectID=0;var outputSize=UInt32(MemoryLayout<AudioObjectID>.size)
        try Self.check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&outputAddress,0,nil,&outputSize,&outputDevice),"读取扬声器")
        var uidAddress=Self.address(kAudioDevicePropertyDeviceUID);var outputUID:Unmanaged<CFString>?
        var uidSize=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try Self.check(AudioObjectGetPropertyData(outputDevice,&uidAddress,0,nil,&uidSize,&outputUID),"读取设备标识")
        guard let uid=outputUID?.takeRetainedValue() as String? else{throw SayError.message("未找到声音输出设备")}
        let config:[String:Any]=[
            kAudioAggregateDeviceNameKey:"TalkFloat Private Capture",
            kAudioAggregateDeviceUIDKey:"app.saylori.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey:true,
            kAudioAggregateDeviceIsStackedKey:true,
            kAudioAggregateDeviceMainSubDeviceKey:uid,
            kAudioAggregateDeviceSubDeviceListKey:[[kAudioSubDeviceUIDKey:uid,kAudioSubDeviceInputChannelsKey:0]],
            kAudioAggregateDeviceTapAutoStartKey:true,
            kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:desc.uuid.uuidString,kAudioSubTapDriftCompensationKey:true]]
        ]
        try Self.check(AudioHardwareCreateAggregateDevice(config as CFDictionary,&aggregate),"创建采音设备")
        try Self.check(AudioDeviceCreateIOProcID(aggregate,{device,now,input,time,output,outTime,context in say_audio_callback(device,now,input,time,output,outTime,context)},UnsafeMutableRawPointer(ring),&io),"创建采音回调")
        try Self.check(AudioDeviceStart(aggregate,io),"启动系统采音")
        let timer=DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now()+0.04,repeating:0.04,leeway:.milliseconds(5))
        timer.setEventHandler{[weak self] in self?.drain()};self.timer=timer;timer.resume()
    }
    private func drain() {
        guard let ring,let input,let output,let converter else{return}
        if say_ring_overflow(ring) != 0 { fail("本机音频处理积压，请重新开始"); return }
        let count=say_ring_read(ring,input.floatChannelData![0],Int(input.frameCapacity))
        guard count>0 else{return}; input.frameLength=AVAudioFrameCount(count)
        ticks+=1
        if ticks%5==0 {
            var peak:Float=0;for i in 0..<count{peak=max(peak,abs(input.floatChannelData![0][i]))};onLevel?(min(1,peak))
        }
        var supplied=false;var error:NSError?
        let status=converter.convert(to:output,error:&error){_,state in
            if supplied{state.pointee = .noDataNow; return nil}
            supplied=true;state.pointee = .haveData;return input
        }
        guard error==nil,status != .error else{fail("音频重采样失败");return}
        for i in 0..<Int(output.frameLength){
            let value=output.floatChannelData![0][i]
            var v=Int16((max(-1,min(1,value.isFinite ? value:0))*32767).rounded()).littleEndian
            withUnsafeBytes(of:&v){pending.append(contentsOf:$0)}
        }
        while pending.count>=2560 {
            let chunk=Data(pending.prefix(2560));pending.removeFirst(2560)
            if case .dropped = continuation.yield(chunk){fail("网络发送积压超过约 1 秒，已停止收听。请重新开始。");return}
        }
    }
    private func fail(_ text:String){timer?.cancel();timer=nil;continuation.finish(throwing:SayError.message(text))}
    public func stop() {
        // Never block AppKit on a HAL call or a pending system permission dialog.
        let continuation=self.continuation
        queue.async {
            self.timer?.cancel();self.timer=nil
            if self.ring != nil{self.drain()}
            if !self.pending.isEmpty{continuation.yield(self.pending);self.pending.removeAll()}
            continuation.finish()
            self.teardown()
        }
        // A stuck HAL startup must not keep the stream consumer alive indefinitely.
        DispatchQueue.global().asyncAfter(deadline:.now()+0.2){continuation.finish()}
    }
    private func teardown() {
        timer?.cancel();timer=nil
        if aggregate != 0,let io{AudioDeviceStop(aggregate,io);AudioDeviceDestroyIOProcID(aggregate,io)};io=nil
        if aggregate != 0{AudioHardwareDestroyAggregateDevice(aggregate);aggregate=0}
        if tap != 0{AudioHardwareDestroyProcessTap(tap);tap=0}
        if let ring{say_ring_destroy(ring);self.ring=nil}
        converter=nil;input=nil;output=nil
    }
}
