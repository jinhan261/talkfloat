import Foundation

/// Suppress weak loudspeaker residue only in speculative on-device ASR. The
/// untouched microphone packet always goes to AST. Zeroing preserves audio time.
public final class PreviewAudioGate:@unchecked Sendable {
    private let lock=NSLock()
    private var lastSystemVoice = -Double.infinity
    private var lastNearVoice = -Double.infinity
    private var suppressed=0
    private struct Evidence {let end:Double;let duration:Double;let weakLeak:Bool;let nearVoice:Bool;let correlation:Double}
    private var evidence:[Evidence]=[]
    private var correlation=PlaybackCorrelation()
    public init(){}
    private static func peak(_ data:Data)->Float {
        data.withUnsafeBytes{bytes in
            var peak:Int32=0
            for i in stride(from:0,to:bytes.count-1,by:2){peak=max(peak,abs(Int32(bytes.loadUnaligned(fromByteOffset:i,as:Int16.self))))}
            return Float(peak)/32768
        }
    }
    public func observeSystem(_ data:Data,now:Double=ProcessInfo.processInfo.systemUptime){
        let level=Self.peak(data)
        lock.withLock{correlation.observeSystem(data,end:now);if level>0.003{lastSystemVoice=now}}
    }
    public func microphonePreview(_ data:Data,now:Double=ProcessInfo.processInfo.systemUptime)->Data {
        let level=Self.peak(data)
        let mute=lock.withLock{
            if level>=0.008{lastNearVoice=now}
            let weakEcho=now-lastSystemVoice<0.45 && level<0.008 && now-lastNearVoice>0.30
            // Much stricter than speculative preview gating. This evidence is used
            // only to classify very weak cloud hallucinations during playback.
            let score=correlation.observeMicrophone(data,end:now)
            evidence.append(Evidence(end:now,duration:Double(data.count)/32000,weakLeak:now-lastSystemVoice<0.45 && level<0.003 && now-lastNearVoice>0.30,nearVoice:level>=0.008,correlation:score))
            if evidence.count>2400{evidence.removeFirst(400)}
            if weakEcho{suppressed+=1}
            return weakEcho
        }
        return mute ? Data(count:data.count):data
    }
    public var suppressedPackets:Int{lock.withLock{suppressed}}
    public var latestCorrelation:Double{lock.withLock{correlation.latestScore}}
    public func playbackConfidence(start:Double,end:Double)->Double {
        guard end-start>=0.4 else{return 0}
        return lock.withLock{
            var covered=0.0,weighted=0.0
            for frame in evidence {
                let overlap=max(0,min(end,frame.end)-max(start,frame.end-frame.duration))
                covered+=overlap;weighted+=overlap*frame.correlation
            }
            guard covered/(end-start)>=0.7 else{return 0}
            return weighted/max(covered,0.001)
        }
    }
    public func isWeakPlaybackLeak(start:Double,end:Double)->Bool {
        guard end>start else{return false}
        return lock.withLock{
            var covered=0.0,weak=0.0
            for frame in evidence {
                if frame.nearVoice && frame.end>start-0.3 && frame.end-frame.duration<end+0.3{return false}
                let overlap=max(0,min(end,frame.end)-max(start,frame.end-frame.duration))
                covered+=overlap;if frame.weakLeak{weak+=overlap}
            }
            return covered>=0.16 && covered/(end-start)>=0.7 && weak/covered>=0.9
        }
    }
}
