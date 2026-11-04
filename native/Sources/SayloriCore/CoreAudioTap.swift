import Foundation
import CoreAudio
import AVFoundation
import AudioRing
import os

public struct AudioSource: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public static let chrome = AudioSource(id: "com.google.Chrome", name: "Chrome")
    public static let system = AudioSource(id: "system", name: "所有系统声音")
}

/// The hardware callback only writes a C ring. HAL, conversion and delivery run
/// on a serial worker, never on AppKit or the hardware callback thread.
public final class CoreAudioTap: @unchecked Sendable {
    public let frames: AsyncThrowingStream<AudioPacket, Error>
    public var onLevel: (@Sendable (Float) -> Void)?
    private static let log = Logger(subsystem: "app.saylori.mac", category: "system-audio")
    private static let startupLock = NSLock()
    private static var halStarting = false
    private let queue = DispatchQueue(label: "app.saylori.audio-tap", qos: .userInitiated)
    private let lock = NSLock()
    private let startup = AudioCaptureStart()
    private let continuation: AsyncThrowingStream<AudioPacket, Error>.Continuation
    private var started = false
    private var stopped = false
    private var timeout: DispatchWorkItem?
    // Owned by queue. The C ring has its own atomic producer/consumer positions.
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var ring: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var converter: AVAudioConverter?
    private var input: AVAudioPCMBuffer?
    private var output: AVAudioPCMBuffer?
    private var pending = Data()
    private var lastLevel = 0.0
    private var formatListener: AudioObjectPropertyListenerBlock?
    private var processListener: AudioObjectPropertyListenerBlock?
    private var selectedProcesses: Set<AudioObjectID> = []
    private var source = AudioSource.system
    private var description: CATapDescription?
    private var tapFormat = AudioStreamBasicDescription()

    public init() {
        let pair = AsyncThrowingStream<AudioPacket, Error>.makeStream(bufferingPolicy: .bufferingOldest(4))
        frames = pair.stream; continuation = pair.continuation
    }
    private var isStopped: Bool { lock.withLock { stopped } }
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func check(_ status: OSStatus, _ context: String) throws {
        guard status == noErr else {
            throw SayError.message("\(context)失败（\(status)）。请在系统设置 → 隐私与安全 → 录屏与系统录音 → 仅系统录音中允许 TalkFloat；无需开启录屏。")
        }
    }
    public static func processIDs() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    public static func bundleID(_ process: AudioObjectID) -> String {
        var a = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &a, 0, nil, &size, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }
    private static func processPID(_ process: AudioObjectID) -> pid_t {
        var a = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        _ = AudioObjectGetPropertyData(process, &a, 0, nil, &size, &pid)
        return pid
    }
    private static func matches(_ bundle: String, source: AudioSource) -> Bool {
        bundle == source.id || bundle.hasPrefix(source.id + ".")
    }

    public func start(source: AudioSource) async throws {
        guard lock.withLock({ if started || stopped { return false }; started = true; return true }) else { throw CancellationError() }
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(error: SayError.message("系统采音启动超时。请允许 TalkFloat 的“仅系统录音”权限后重新打开 App；无需开启录屏。"))
        }
        lock.withLock { timeout = deadline }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 15, execute: deadline)
        queue.async { [self] in
            guard !isStopped else { return }
            // HAL permission calls cannot be force-cancelled. Prevent retries
            // from accumulating devices and blocked startup threads.
            guard Self.startupLock.withLock({ if Self.halStarting { return false }; Self.halStarting = true; return true }) else {
                finish(error: SayError.message("系统仍在完成上一次采音授权，请处理系统提示后重新打开 TalkFloat。")); return
            }
            defer { Self.startupLock.withLock { Self.halStarting = false } }
            do {
                try setup(source)
                guard !isStopped else { teardown(); return }
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
                timer.setEventHandler { [weak self] in self?.drain() }
                self.timer = timer; timer.resume()
                lock.withLock { timeout?.cancel(); timeout = nil }
                startup.resolve(.success(()))
                Self.log.info("Core Audio tap started; screen capture is not used")
            } catch { finish(error: error) }
        }
        try await withTaskCancellationHandler { try await startup.wait() } onCancel: { self.stop() }
    }

    private func setup(_ source: AudioSource) throws {
        self.source = source
        let ids = Self.processIDs()
        let own = ids.filter { Self.processPID($0) == getpid() }
        let selected = ids.filter { Self.matches(Self.bundleID($0), source: source) }
        if source.id != "system", selected.isEmpty {
            if #unavailable(macOS 26) { throw SayError.message("请先在 Chrome 播放声音，再开始翻译。") }
        }
        let desc = source.id == "system" ? CATapDescription(monoGlobalTapButExcludeProcesses: own) : CATapDescription(monoMixdownOfProcesses: selected)
        desc.name = "TalkFloat System Audio"; desc.uuid = UUID(); desc.isPrivate = true; desc.muteBehavior = .unmuted
        if #available(macOS 26, *) {
            desc.bundleIDs = source.id == "system" ? [Bundle.main.bundleIdentifier ?? "app.saylori.mac"] : Array(Set([source.id] + selected.map(Self.bundleID)))
            desc.isProcessRestoreEnabled = true
        }
        description = desc; selectedProcesses = Set(selected)
        Self.log.info("Creating private process tap")
        try Self.check(AudioHardwareCreateProcessTap(desc, &tap), "创建音源")
        guard !isStopped else { throw CancellationError() }
        var a = Self.address(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &asbd), "读取音频格式")
        tapFormat = asbd
        guard asbd.mFormatID == kAudioFormatLinearPCM, asbd.mBitsPerChannel == 32,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mChannelsPerFrame == 1,
              asbd.mSampleRate.isFinite, (8_000...192_000).contains(asbd.mSampleRate),
              let inputFormat = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate, channels: 1),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(asbd.mSampleRate * 0.32)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8_192),
              let ring = say_ring_create(Int(asbd.mSampleRate * 0.32), 1, 0) else {
            throw SayError.message("系统音频格式不可用，请检查声音输出设备后重新开始。")
        }
        self.converter = converter; self.input = input; self.output = output; self.ring = ring
        // A tap-only aggregate never opens physical microphone channels and
        // does not pin system capture to one speaker/headphone device.
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "TalkFloat Private Capture",
            kAudioAggregateDeviceUIDKey: "app.saylori.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        Self.log.info("Creating tap-only aggregate device")
        try Self.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "创建采音设备")
        guard !isStopped else { throw CancellationError() }
        try Self.check(AudioDeviceCreateIOProcID(aggregate, say_audio_callback, UnsafeMutableRawPointer(ring), &io), "创建采音回调")
        Self.log.info("Starting aggregate device")
        try Self.check(AudioDeviceStart(aggregate, io), "启动系统采音")
        say_ring_discard(ring)
        guard !isStopped else { throw CancellationError() }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.validateTapFormat()
        }
        formatListener = listener
        try Self.check(AudioObjectAddPropertyListenerBlock(tap, &a, queue, listener), "监听音频格式")
        if source.id != "system" {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refreshProcesses() }
            processListener = listener
            var processes = Self.address(kAudioHardwarePropertyProcessObjectList)
            try Self.check(AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processes, queue, listener), "监听 Chrome 声音")
        }
    }

    private func validateTapFormat() {
        guard !isStopped, tap != 0 else { return }
        var a = Self.address(kAudioTapPropertyFormat)
        var current = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &current)
        // HAL can notify after a process/route refresh without changing the
        // format. Do not end a meeting for an unchanged format notification.
        guard status == noErr,
              current.mSampleRate == tapFormat.mSampleRate,
              current.mFormatID == tapFormat.mFormatID,
              current.mFormatFlags == tapFormat.mFormatFlags,
              current.mBytesPerPacket == tapFormat.mBytesPerPacket,
              current.mFramesPerPacket == tapFormat.mFramesPerPacket,
              current.mBytesPerFrame == tapFormat.mBytesPerFrame,
              current.mChannelsPerFrame == tapFormat.mChannelsPerFrame,
              current.mBitsPerChannel == tapFormat.mBitsPerChannel else {
            finish(error: SayError.message("系统声音的采样格式已改变或无法读取。已保留文字，请重新开始翻译。")); return
        }
    }

    private func refreshProcesses() {
        guard !isStopped, tap != 0, let description else { return }
        let ids = Set(Self.processIDs().filter { Self.matches(Self.bundleID($0), source: source) })
        guard ids != selectedProcesses else { return }
        description.processes = Array(ids)
        if #available(macOS 26, *) { description.bundleIDs = Array(Set([source.id] + ids.map(Self.bundleID))) }
        var value = Unmanaged.passUnretained(description).toOpaque()
        var a = Self.address(kAudioTapPropertyDescription)
        let status = withExtendedLifetime(description) {
            AudioObjectSetPropertyData(tap, &a, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &value)
        }
        if status != noErr { finish(error: SayError.message("Chrome 音频进程已改变，更新收听失败（\(status)）。请重新开始翻译。")) }
        else { selectedProcesses = ids }
    }

    private func drain(flushing: Bool = false) {
        guard flushing || !isStopped, let ring, let input, let output, let converter else { return }
        guard say_ring_overflow(ring) == 0 else {
            finish(error: SayError.message("系统音频处理已落后，已停止收听并保留文字。请重新开始。")); return
        }
        let count = say_ring_read(ring, input.floatChannelData![0], Int(input.frameCapacity))
        guard count > 0 else { return }
        input.frameLength = AVAudioFrameCount(count); output.frameLength = 0
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastLevel >= 0.2 {
            lastLevel = now
            var peak: Float = 0
            for i in 0..<count { let v = input.floatChannelData![0][i]; if v.isFinite { peak = max(peak, abs(v)) } }
            onLevel?(min(1, peak))
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        guard error == nil, status != .error else { finish(error: error ?? SayError.message("系统音频重采样失败") as NSError); return }
        if output.frameLength > 0 {
            pending.append(UnsafeBufferPointer(start: UnsafeRawPointer(output.int16ChannelData![0]).assumingMemoryBound(to: UInt8.self), count: Int(output.frameLength) * 2))
        }
        while pending.count >= 2_560 {
            let queuedAt = now - Double(pending.count) / 32_000
            let packet = AudioPacket(data: Data(pending.prefix(2_560)), queuedAt: queuedAt)
            pending.removeFirst(2_560)
            if case .dropped = continuation.yield(packet) {
                finish(error: SayError.message("音频处理跟不上实时声音，已停止收听并保留文字。请稍后重新开始。")); return
            }
        }
    }

    public func stop() { finish(error: nil) }
    private func finish(error: Error?) {
        guard lock.withLock({ if stopped { return false }; stopped = true; timeout?.cancel(); timeout = nil; return true }) else { return }
        startup.resolve(.failure(error ?? CancellationError()))
        if let error { continuation.finish(throwing: error) }
        queue.async { [self] in
            timer?.cancel(); timer = nil
            if error == nil {
                drain(flushing: true)
                if !pending.isEmpty { continuation.yield(AudioPacket(data: pending, queuedAt: ProcessInfo.processInfo.systemUptime - Double(pending.count) / 32_000)) }
            }
            pending.removeAll(); continuation.finish(); teardown()
        }
        // A pending HAL permission dialog must not keep an ended session alive.
        let continuation = continuation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { continuation.finish() }
    }
    private func teardown() {
        timer?.cancel(); timer = nil
        if let processListener {
            var a = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, processListener)
        }
        processListener = nil
        if tap != 0, let formatListener {
            var a = Self.address(kAudioTapPropertyFormat)
            AudioObjectRemovePropertyListenerBlock(tap, &a, queue, formatListener)
        }
        formatListener = nil
        if aggregate != 0, let io { AudioDeviceStop(aggregate, io); AudioDeviceDestroyIOProcID(aggregate, io) }
        io = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if let ring { say_ring_destroy(ring); self.ring = nil }
        converter = nil; input = nil; output = nil; description = nil
        Self.log.info("Core Audio tap released")
    }
}
