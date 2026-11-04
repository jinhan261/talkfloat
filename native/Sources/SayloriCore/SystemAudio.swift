import Foundation

public struct AudioPacket: Sendable {
    public let data: Data
    public let queuedAt: TimeInterval
    public init(data:Data,queuedAt:TimeInterval){self.data=data;self.queuedAt=queuedAt}
}

// Audio-only production path. No screen enumeration or ScreenCaptureKit fallback.
public typealias SystemAudio = CoreAudioTap
