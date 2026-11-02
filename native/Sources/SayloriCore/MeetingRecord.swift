import Foundation

public struct MeetingInterruption:Codable,Sendable {
    public var startedAt=Date()
    public var endedAt:Date?
    public var origin:AudioOrigin
    public var reason:String
    public init(origin:AudioOrigin,reason:String){self.origin=origin;self.reason=reason}
}

public struct MeetingRecord: Codable, Sendable {
    public var schemaVersion = 2
    public var revision = 0
    public var id = UUID()
    public var startedAt = Date()
    public var endedAt: Date?
    public var status = "进行中"
    public var engine:TranslationMode?
    public var sourceName: String
    public var segments: [CaptionSegment] = []
    public var pauses: [Date] = []
    public var interruptions:[MeetingInterruption]?
    public init(sourceName: String) { self.sourceName=sourceName }
    public var hasText: Bool { segments.contains{!$0.source.isEmpty || !$0.translation.isEmpty} }
    public var markdown: String {
        let formatter=DateFormatter(); formatter.dateFormat="yyyy-MM-dd HH:mm:ss"
        var rows=["# Saylori · 英中会议记录", "", "开始：\(formatter.string(from:startedAt))", "音源：\(sourceName)", "状态：\(status)", ""]
        if let engine{rows += ["翻译模式：\(engine.title)", ""]}
        if let endedAt { rows += ["结束：\(formatter.string(from:endedAt))", ""] }
        rows += ["仅保存已收到的原文与译文，不保存录音。暂停期间不收听；未定稿内容保留并标注。", ""]
        for (i,s) in CaptionPresentation.sentences(segments.filter{$0.possibleEchoOf==nil && $0.weakPlaybackLeak != true}).enumerated() where !s.source.isEmpty || !s.translation.isEmpty {
            rows += ["## \(i+1) · \(s.audioOrigin.label) · \(formatter.string(from:s.receivedAt))", "", "原文\(s.sourceFinal ? "":"（未定稿）")：\(s.source.isEmpty ? "未收到":s.source)", "", "中文\(s.translationFinal ? "":"（未定稿）")：\(s.translation.isEmpty ? "未收到译文":s.translation)", ""]
        }
        let echoes=segments.filter{$0.possibleEchoOf != nil || $0.weakPlaybackLeak == true}
        if !echoes.isEmpty {
            rows += ["## 疑似系统外放回声", "", "以下内容由麦克风收录，与同时段系统声音高度重复，或仅有极弱外放残留，未作为独立发言显示；保留原文与译文供核对。", ""]
            for s in echoes{rows += ["### 麦克风原始收录 · \(formatter.string(from:s.receivedAt))", "", "原文：\(s.source)", "", "中文：\(s.translation)", ""]}
        }
        if let interruptions,!interruptions.isEmpty {
            rows += ["## 连接中断", "", "中断期间及此前未定稿的内容可能不完整；不会用旧音频追赶当前讲话。", ""]
            rows += interruptions.map{"\($0.origin.label) · \(formatter.string(from:$0.startedAt)) → \($0.endedAt.map{formatter.string(from:$0)} ?? "未恢复") · \($0.reason)"}
        }
        if !pauses.isEmpty { rows += ["## 暂停时间", ""] + pauses.map{formatter.string(from:$0)} }
        return rows.joined(separator:"\n")
    }
}
