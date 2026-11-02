import Foundation

/// Owned by the microphone sender task. Its only cross-thread control is the
/// internally synchronized gate. The two-packet lookahead is bounded at 160 ms.
public struct MicrophonePacketProcessor:Sendable {
    private let gate:NearSpeechGate
    private let transform:@Sendable (AudioPacket)->AudioPacket
    private var pending:[AudioPacket]=[]

    public init(gate:NearSpeechGate,transform:@escaping @Sendable (AudioPacket)->AudioPacket = {$0}){
        self.gate=gate;self.transform=transform
    }
    public mutating func append(_ packet:AudioPacket)->AudioPacket? {
        pending.append(packet)
        return pending.count>2 ? next():nil
    }
    public mutating func finish()->[AudioPacket] {
        var tail:[AudioPacket]=[]
        while !pending.isEmpty{tail.append(next())}
        return tail
    }
    private mutating func next()->AudioPacket {
        let packet=pending.removeFirst()
        let pass=gate.shouldPass(packet.data,upcoming:pending.map(\.data))
        // AEC must keep learning even while the level gate is closed.
        let processed=transform(packet)
        return pass ? processed:AudioPacket(data:Data(count:processed.data.count),queuedAt:processed.queuedAt)
    }
}
