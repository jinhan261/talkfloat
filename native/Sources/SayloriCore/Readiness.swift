import Foundation

/// Successful tap startup alone does not prove that usable audio is arriving.
public struct AudioProbeResult: Equatable, Sendable {
    public enum Outcome: String, Sendable { case audible, silent, noFrames }
    public let bytes: Int
    public let peak: Float
    public var outcome: Outcome { bytes == 0 ? .noFrames : (peak > 0.001 ? .audible : .silent) }
    public init(bytes: Int, peak: Float) { self.bytes = bytes; self.peak = peak }
    public var message: String {
        switch outcome {
        case .audible: return "已收到声音，可以继续测试翻译。"
        case .silent: return "采音已启动，暂时没有声音。请播放英语，并检查播放器是否静音。"
        case .noFrames: return "尚未收到音频。请播放声音后重试；若仍无信号，请检查仅系统录音权限与输出设备。"
        }
    }
}

/// Updating must never end a meeting, lose an unsaved record or interrupt setup.
public enum UpdateSafety {
    public static func canInstall(active: Bool, hasMeeting: Bool, preparingModels: Bool, setupBusy: Bool, hasSaveError: Bool, editingSettings: Bool = false) -> Bool {
        !active && !hasMeeting && !preparingModels && !setupBusy && !hasSaveError && !editingSettings
    }
}

public enum SampleCoverage {
    /// Coverage only, not an accuracy score: all three fixture statements need
    /// a final English/Chinese pair before the onboarding can report completion.
    public static func isComplete(_ segments:[CaptionSegment])->Bool {
        let paired=segments.filter{$0.sourceFinal && $0.translationFinal && !$0.translation.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
        let text=paired.map(\.source).joined(separator:" ").lowercased()
        return text.contains("tuesday") && text.contains("budget") && text.contains("friday") && text.contains("proposal")
    }
}
