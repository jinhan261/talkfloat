import Foundation

public enum AudioOrigin: String, Codable, Sendable {
    case system, microphone
    public var label:String { self == .microphone ? "麦克风声音":"系统声音" }
    public var icon:String { self == .microphone ? "mic.fill":"speaker.wave.2" }
}

public struct CaptionSegment: Codable, Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var sessionID: String
    public var startMS: Int
    public var endMS = 0
    public var source = ""
    public var translation = ""
    public var sourceFinal = false
    public var translationFinal = false
    public var translationStarted = false
    public var receivedAt = Date()
    public var origin: AudioOrigin?
    /// Local preview only; cloud archives never substitute speculative text for final text.
    public var provisional: Bool?
    public var previewUpdatedAt: Date?
    /// Absolute clock of sample zero, shared by cloud and local ASR in this stream.
    public var audioEpoch:Double?
    /// Original mic text remains in JSON; presentation may identify overlapping echo.
    public var possibleEchoOf:UUID?
    public var weakPlaybackLeak:Bool?
    public var playbackConfidence:Double?
    public var audioOrigin: AudioOrigin { origin ?? .system }
    public init(sessionID: String, startMS: Int) { self.sessionID=sessionID; self.startMS=startMS }
}
