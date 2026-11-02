import Foundation

/// A level gate for the processed microphone signal, not a speaker identifier.
/// Look-ahead reuses the route's existing two-packet AEC buffer, so opening
/// the gate preserves word onsets without adding another audio queue.
public final class NearSpeechGate: @unchecked Sendable {
    public static let defaultThresholdDB = -28.0
    public static let thresholdRange = -50.0 ... -12.0
    public static func boundedThreshold(_ value:Double)->Double{
        value.isFinite ? min(thresholdRange.upperBound,max(thresholdRange.lowerBound,value)):defaultThresholdDB
    }
    public struct Observation:Sendable {
        public let rmsDB:Double
        public let thresholdDB:Double
        public let isPassing:Bool
        public let enabled:Bool
    }
    private let lock=NSLock()
    private var enabled=true
    private var tailSamples=0
    private var inspected=0
    private var suppressed=0
    private var levelDB = -120.0
    private var thresholdDB=NearSpeechGate.defaultThresholdDB
    private var isPassing=false
    public init(){}
    public func setEnabled(_ value:Bool){lock.withLock{enabled=value;tailSamples=0;isPassing=false}}
    public func setThresholdDB(_ value:Double){lock.withLock{thresholdDB=Self.boundedThreshold(value);tailSamples=0;isPassing=false}}
    public func reset(){lock.withLock{tailSamples=0;inspected=0;suppressed=0;levelDB = -120;isPassing=false}}
    public var observation:Observation{lock.withLock{Observation(rmsDB:levelDB,thresholdDB:thresholdDB,isPassing:isPassing,enabled:enabled)}}
    public var diagnostics:[String:Double]{lock.withLock{["rmsDB":levelDB,"thresholdDB":thresholdDB,"passing":isPassing ? 1:0,"packets":Double(inspected),"suppressedPackets":Double(suppressed),"enabled":enabled ? 1:0]}}
    public func shouldPass(_ data:Data,upcoming:[Data]=[])->Bool{lock.withLock{
        let rms=Self.rms(data);levelDB=20*log10(max(rms,0.000001));inspected+=1
        guard enabled else{isPassing=true;return true}
        // Require two consecutive 20 ms windows above threshold. A short click
        // must not open the microphone for the following room conversation.
        let opens=Self.hasSustainedSignal([data]+Array(upcoming.prefix(2)),level:pow(10,thresholdDB/20))
        if opens{tailSamples=2560;isPassing=true;return true}
        if tailSamples>0{tailSamples=max(0,tailSamples-data.count/2);isPassing=true;return true}
        suppressed+=1;isPassing=false;return false
    }}
    private static func hasSustainedSignal(_ packets:[Data],level:Double)->Bool{
        var consecutive=0
        for packet in packets {
            let found=packet.withUnsafeBytes{raw->Bool in
                let count=raw.count/2
                for start in stride(from:0,to:count,by:320){
                    let end=min(start+320,count)
                    guard end-start==320 else{consecutive=0;continue}
                    var sum=0.0
                    for i in start..<end{let sample=Double(raw.loadUnaligned(fromByteOffset:i*2,as:Int16.self))/32768;sum+=sample*sample}
                    consecutive=sqrt(sum/320)>=level ? consecutive+1:0
                    if consecutive>=2{return true}
                }
                return false
            }
            if found{return true}
        }
        return false
    }
    private static func rms(_ data:Data)->Double{
        data.withUnsafeBytes{raw in
            let count=raw.count/2
            guard count>0 else{return 0}
            var sum=0.0
            for i in 0..<count{let v=Double(raw.loadUnaligned(fromByteOffset:i*2,as:Int16.self))/32768;sum+=v*v}
            return sqrt(sum/Double(count))
        }
    }
}
