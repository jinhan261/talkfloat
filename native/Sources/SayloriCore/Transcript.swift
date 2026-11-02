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

public enum CaptionPresentation {
    public static func latestDrafts(_ drafts:[CaptionSegment])->[CaptionSegment] {
        var latest:[String:CaptionSegment]=[:]
        for item in drafts {
            if let previous=latest[item.sessionID],(previous.previewUpdatedAt ?? previous.receivedAt)>(item.previewUpdatedAt ?? item.receivedAt){continue}
            latest[item.sessionID]=item
        }
        return latest.values.sorted{$0.receivedAt<$1.receivedAt}
    }
    /// Service packets are not sentences. Join unfinished, adjacent phrases only within
    /// the same audio session and channel; a pause or terminal punctuation closes a turn.
    public static func sentences(_ segments:[CaptionSegment]) -> [CaptionSegment] {
        var result:[CaptionSegment]=[]
        for item in segments {
            if var last=result.last, last.sessionID==item.sessionID,last.audioOrigin==item.audioOrigin,
               last.translation.isEmpty==item.translation.isEmpty,
               last.endMS>0,item.startMS>=last.endMS-100,item.startMS-last.endMS<=1400,
               item.endMS-last.startMS<=16000,last.source.count+item.source.count<=300,
               !".?!。？！".contains(last.source.trimmingCharacters(in:.whitespacesAndNewlines).suffix(1)),
               !last.source.isEmpty {
                result.removeLast()
                last.source=last.source.trimmingCharacters(in:.whitespacesAndNewlines)+" "+item.source.trimmingCharacters(in:.whitespacesAndNewlines)
                last.translation += item.translation
                last.endMS=max(last.endMS,item.endMS)
                last.sourceFinal = last.sourceFinal && item.sourceFinal
                last.translationFinal = last.translationFinal && item.translationFinal
                last.provisional = last.provisional == true || item.provisional == true
                result.append(last)
            }else{result.append(item)}
        }
        return result
    }
    public static func live(cloud allCloud:[CaptionSegment],drafts allDrafts:[CaptionSegment]) -> [CaptionSegment] {
        // The floating window adapts its recent turns to available space. Keep
        // echo matching bounded even when the raw archive grows for hours.
        let cloud=Array(allCloud.suffix(64)).filter{!PreviewText.normalized($0.source+$0.translation).isEmpty}
        let drafts=latestDrafts(allDrafts).filter{!PreviewText.normalized($0.source+$0.translation).isEmpty}
        let echoes=SystemEchoMatcher.matches(in:cloud+drafts)
        let pending=drafts.filter{draft in
            if echoes[draft.id] != nil || draft.weakPlaybackLeak == true{return false}
            if let updated=draft.previewUpdatedAt,Date().timeIntervalSince(updated)>4{return false}
            let finalized=cloud.filter{$0.sessionID==draft.sessionID && $0.translationFinal}
            let confirmed=finalized.map(\.endMS).max() ?? -1
            let overlapping=finalized.filter{$0.endMS>=draft.startMS && $0.startMS<=draft.endMS}
            let full=PreviewText.normalized(overlapping.map(\.source).joined(separator:" "))
            let source=PreviewText.normalized(draft.source)
            let covered = !source.isEmpty && full.contains(source)
            return draft.endMS>confirmed+200 && !covered
        }.sorted{$0.receivedAt<$1.receivedAt}
        // Keep cloud text for history, but do not show it over a newer local preview.
        let history=cloud.filter{item in item.weakPlaybackLeak != true && echoes[item.id]==nil && !pending.contains{draft in
            draft.sessionID==item.sessionID && draft.startMS<item.endMS && draft.endMS>item.startMS
        }}
        return sentences(history)+sentences(pending)
    }
}

public enum PreviewText {
    public static func normalized(_ text:String)->String {
        text.lowercased().components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.joined(separator:" ")
    }
    public static func translationInput(_ text:String,stable:Bool = true)->String {
        var words=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        // Volatile ASR can end in a subword (e.g. "econ"). Keep a one-word
        // lookahead until punctuation or a final result confirms that boundary.
        if !stable,words.count>=3,let last=text.last,!".?!,;:".contains(last){words.removeLast()}
        let unfinished:Set<String>=["and","or","but","with","of","to","a","an","the","that"]
        while words.count>2,let last=words.last,unfinished.contains(last.lowercased()){words.removeLast()}
        return words.joined(separator:" ")
    }
    public static func likelyEcho(_ microphone:String,_ system:String)->Bool {
        let a=normalized(microphone).split(separator:" ").map(String.init)
        let b=normalized(system).split(separator:" ").map(String.init)
        guard a.count>=4,b.count>=4 else{return false}
        let overlap=Set(a).intersection(Set(b)).count
        return Double(overlap)/Double(min(Set(a).count,Set(b).count))>=0.72
    }
}

/// Source and translation channels may interleave. Match their audio timestamps;
/// when a server omits timestamps, fall back to the oldest unmatched source turn.
public struct CaptionState: Sendable {
    private var storage: [CaptionSegment] = []
    private var sourceIndices: [String:Int] = [:]
    private var targetIndices: [String:Int] = [:]
    private var origins: [String:AudioOrigin] = [:]
    private var sessionID = ""
    private var streamClocks:[String:Date]=[:]
    public init() {}
    public var segments:[CaptionSegment]{storage.filter{!$0.source.isEmpty || !$0.translation.isEmpty}}
    public mutating func beginStream(_ id: String, origin:AudioOrigin = .system) { sessionID=id; sourceIndices[id]=nil; targetIndices[id]=nil; origins[id]=origin }
    public mutating func setStreamClock(_ id:String,startedAt:Date){
        guard streamClocks[id]==nil else{return};streamClocks[id]=startedAt
        for i in storage.indices where storage[i].sessionID==id{storage[i].audioEpoch=startedAt.timeIntervalSince1970}
    }
    public mutating func classifyMicrophone(_ id:String,using classify:(CaptionSegment)->Bool){
        for i in storage.indices.suffix(16) where storage[i].sessionID==id{storage[i].weakPlaybackLeak=classify(storage[i])}
    }
    public mutating func measurePlayback(_ id:String,using measure:(CaptionSegment)->Double){
        for i in storage.indices.suffix(16) where storage[i].sessionID==id{storage[i].playbackConfidence=measure(storage[i])}
    }
    public var current: CaptionSegment? { segments.last }
    public var source: String { current?.source ?? "" }
    // Compatibility for diagnostics: the newest received translation, not necessarily the latest source.
    public var translation: String { storage.last(where:{!$0.translation.isEmpty})?.translation ?? "" }
    public var isFinal: Bool { storage.last(where:{!$0.translation.isEmpty})?.translationFinal ?? false }
    public var previous: String { storage.filter{!$0.translation.isEmpty}.dropLast().last?.translation ?? "" }
    public var context: [CaptionSegment] { Array(segments.dropLast().suffix(3)) }
    public mutating func apply(_ event: ASTEvent, streamID:String? = nil) {
        guard (650...655).contains(event.type) else { return }
        let sid=streamID ?? (event.sessionID.isEmpty ? sessionID:event.sessionID)
        if origins[sid] == nil { beginStream(sid) }
        let isSource=event.type < 653
        let starting=event.type == 650 || event.type == 653
        var index=isSource ? sourceIndices[sid]:targetIndices[sid]
        if starting || index == nil {
            if isSource {
                index=storage.indices.last(where:{storage[$0].sessionID==sid && storage[$0].source.isEmpty && !storage[$0].sourceFinal && storage[$0].startMS==event.start})
            } else {
                index=storage.indices.first(where:{storage[$0].sessionID==sid && !storage[$0].translationStarted && storage[$0].startMS==event.start})
                if index == nil { index=storage.indices.first(where:{storage[$0].sessionID==sid && !storage[$0].translationStarted}) }
            }
            if index == nil { var item=CaptionSegment(sessionID:sid,startMS:event.start); item.origin=origins[sid];item.audioEpoch=streamClocks[sid]?.timeIntervalSince1970; storage.append(item); index=storage.count-1 }
            if isSource { sourceIndices[sid]=index } else { targetIndices[sid]=index; storage[index!].translationStarted=true }
        }
        guard let i=index else { return }
        switch event.type {
        case 651: storage[i].source += event.text
        case 652:
            if !event.text.isEmpty { storage[i].source=event.text }
            storage[i].sourceFinal=true; storage[i].endMS=max(storage[i].endMS,event.end)
        case 654: storage[i].translation += event.text
        case 655:
            if !event.text.isEmpty { storage[i].translation=event.text }
            storage[i].translationFinal=true; storage[i].endMS=max(storage[i].endMS,event.end)
        default: break
        }
    }
}

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
    public var sourceName: String
    public var segments: [CaptionSegment] = []
    public var pauses: [Date] = []
    public var interruptions:[MeetingInterruption]?
    public init(sourceName: String) { self.sourceName=sourceName }
    public var hasText: Bool { segments.contains{!$0.source.isEmpty || !$0.translation.isEmpty} }
    public var markdown: String {
        let formatter=DateFormatter(); formatter.dateFormat="yyyy-MM-dd HH:mm:ss"
        var rows=["# Saylori · 英中会议记录", "", "开始：\(formatter.string(from:startedAt))", "音源：\(sourceName)", "状态：\(status)", ""]
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

/// All disk work runs on this actor, never on the audio or UI queues. JSON is the
/// recoverable source of truth; Markdown is the user-readable, portable archive.
public actor TranscriptStore {
    public nonisolated let directory: URL
    public init(directory: URL? = nil) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Saylori/Recordings",isDirectory:true)
    }
    private var revisions:[UUID:Int]=[:]
    public func save(_ record: MeetingRecord) throws -> URL? {
        guard record.hasText else { return nil }
        guard record.revision >= (revisions[record.id] ?? -1) else{return nil}
        var record=record
        let echoes=SystemEchoMatcher.matches(in:record.segments)
        for i in record.segments.indices{record.segments[i].possibleEchoOf=echoes[record.segments[i].id]}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let formatter=DateFormatter(); formatter.dateFormat="yyyyMMdd-HHmmss"
        let base=directory.appendingPathComponent("\(formatter.string(from:record.startedAt))-\(record.id.uuidString.prefix(8))")
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to:base.appendingPathExtension("json"),options:.atomic)
        let markdown=base.appendingPathExtension("md")
        try Data(record.markdown.utf8).write(to:markdown,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:base.appendingPathExtension("json").path)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:markdown.path)
        revisions[record.id]=record.revision
        return markdown
    }
    public func recoverInterrupted() throws {
        guard FileManager.default.fileExists(atPath:directory.path) else { return }
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where url.pathExtension=="json" {
            guard var record=try? decoder.decode(MeetingRecord.self,from:Data(contentsOf:url)),record.endedAt==nil else { continue }
            record.status="意外退出 · 已恢复收到的内容"; record.endedAt=record.segments.last?.receivedAt ?? record.startedAt
            _ = try save(record)
        }
    }
}
