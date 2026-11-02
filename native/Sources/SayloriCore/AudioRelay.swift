import Foundation

public protocol AudioSending:Sendable {
    func send(_ audio:Data) async throws
}

public struct AudioSendStats:Sendable {
    public let queueMS:Double
    public let sendMS:Double
    public let audioEndMS:Double
    public let sendUptime:Double
    public let streamStartedUptime:Double
}

/// One serial caller per audio stream. Discards pre-authentication packets and
/// rejects stale audio instead of building an ever-growing translation delay.
public actor AudioRelay {
    private let service:any AudioSending
    private let uptime:@Sendable ()->TimeInterval
    private var enabled=false
    private var sentBytes=0
    private var streamStartedUptime:Double?

    public init(service:any AudioSending,uptime:@escaping @Sendable ()->TimeInterval={ProcessInfo.processInfo.systemUptime}){
        self.service=service;self.uptime=uptime
    }
    public func enable(){enabled=true}
    public func forward(_ packet:AudioPacket) async throws->AudioSendStats? {
        guard enabled else{return nil}
        let now=uptime(),age=now-packet.queuedAt
        guard age<0.4 else{throw SayError.message("音频处理已落后，已停止收听并保留文字。请重新开始，并检查网络或输入设备。")}
        try await service.send(packet.data)
        if streamStartedUptime==nil{streamStartedUptime=packet.queuedAt-Double(packet.data.count)/32000}
        sentBytes += packet.data.count
        return AudioSendStats(queueMS:age*1000,sendMS:(uptime()-now)*1000,audioEndMS:Double(sentBytes)/32,sendUptime:now,streamStartedUptime:streamStartedUptime!)
    }
}
