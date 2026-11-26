import Foundation

public struct CaptionWindow: Equatable {
    public let current: CaptionSegment?
    /// Chronological, excluding the turn displayed in large type.
    public let history: [CaptionSegment]
    public let nextRefresh: Date?

    public init(current: CaptionSegment? = nil, history: [CaptionSegment] = [], nextRefresh: Date? = nil) {
        self.current = current
        self.history = history
        self.nextRefresh = nextRefresh
    }
}

private extension CaptionSegment {
    var spokenRange: ClosedRange<TimeInterval> {
        guard let audioEpoch, startMS > 0 || endMS > 0 else {
            let receipt = receivedAt.timeIntervalSince1970
            return receipt...receipt
        }
        return (audioEpoch + Double(startMS) / 1000)...(audioEpoch + Double(max(startMS, endMS)) / 1000)
    }
}

public enum CaptionPresentation {
    /// Keep the last translated pair readable while the next ASR revision is
    /// being translated. The raw archive still retains the latest source state.
    public static func keepingReadableTranslation(_ current:CaptionSegment,previous:CaptionSegment?)->CaptionSegment {
        guard !current.hasReadableTranslation,let previous,previous.id==current.id,previous.hasReadableTranslation else{return current}
        var result=previous
        // The words are still a pair, but the speaker may have continued.
        result.startMS=current.startMS;result.endMS=max(current.endMS,previous.endMS)
        result.audioEpoch=current.audioEpoch ?? previous.audioEpoch;result.receivedAt=current.receivedAt
        result.weakPlaybackLeak=current.weakPlaybackLeak;result.playbackConfidence=current.playbackConfidence
        result.possibleEchoOf=current.possibleEchoOf
        return result
    }

    public static func latestDrafts(_ drafts:[CaptionSegment])->[CaptionSegment] {
        var latest:[String:CaptionSegment]=[:]
        for item in drafts {
            if let previous=latest[item.sessionID] {
                if previous.id != item.id, previous.startMS != item.startMS {
                    if previous.startMS > item.startMS { continue }
                } else if (previous.previewUpdatedAt ?? previous.receivedAt) > (item.previewUpdatedAt ?? item.receivedAt) {
                    continue
                }
            }
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
                last.previewUpdatedAt = [last.previewUpdatedAt, item.previewUpdatedAt].compactMap { $0 }.max()
                last.sourceFinal = last.sourceFinal && item.sourceFinal
                last.translationFinal = last.translationFinal && item.translationFinal
                last.provisional = last.provisional == true || item.provisional == true
                result.append(last)
            }else{result.append(item)}
        }
        return result
    }
    public static func window(cloud allCloud:[CaptionSegment], drafts allDrafts:[CaptionSegment], now:Date = Date()) -> CaptionWindow {
        // The floating window adapts its recent turns to available space. Keep
        // echo matching bounded even when the raw archive grows for hours.
        let cloud=Array(allCloud.suffix(64)).filter{!PreviewText.normalized($0.source+$0.translation).isEmpty}
        let drafts=latestDrafts(allDrafts).filter{!PreviewText.normalized($0.source+$0.translation).isEmpty}
        let echoes=SystemEchoMatcher.matches(in:cloud+drafts)
        let pending=drafts.filter{draft in
            if echoes[draft.id] != nil || draft.weakPlaybackLeak == true{return false}
            if let updated=draft.previewUpdatedAt,now.timeIntervalSince(updated)>=4{return false}
            let finalized=cloud.filter{$0.sessionID==draft.sessionID && $0.translationFinal}
            let confirmed=finalized.map(\.endMS).max() ?? -1
            let overlapping=finalized.filter{$0.endMS>=draft.startMS && $0.startMS<=draft.endMS}
            let full=PreviewText.normalized(overlapping.map(\.source).joined(separator:" "))
            let source=PreviewText.normalized(draft.source)
            let covered = !source.isEmpty && full.contains(source)
            return draft.endMS>confirmed+200 && !covered
        }
        let history=cloud.filter{item in item.weakPlaybackLeak != true && echoes[item.id]==nil && !pending.contains{draft in
            draft.sessionID==item.sessionID && draft.startMS<item.endMS && draft.endMS>item.startMS && draft.endMS>=item.endMS
        }}
        func spokenBefore(_ a: CaptionSegment, _ b: CaptionSegment) -> Bool {
            let lhs = a.spokenRange, rhs = b.spokenRange
            if lhs.lowerBound != rhs.lowerBound { return lhs.lowerBound < rhs.lowerBound }
            if lhs.upperBound != rhs.upperBound { return lhs.upperBound < rhs.upperBound }
            return a.receivedAt < b.receivedAt
        }
        let turns = (sentences(history.sorted(by: spokenBefore)) + pending).sorted(by: spokenBefore)
        guard var focus = turns.last else { return CaptionWindow() }
        // A late mic callback can describe speech that actually overlapped the
        // remote speaker. Let the microphone take over when it continues alone.
        if let system = turns.last(where: { $0.audioOrigin == .system }),
           let mic = turns.last(where: { $0.audioOrigin == .microphone }),
           system.spokenRange.overlaps(mic.spokenRange) {
            focus = mic.spokenRange.upperBound > system.spokenRange.upperBound + 0.5 ? mic : system
        }
        var refresh = pending.compactMap { $0.previewUpdatedAt?.addingTimeInterval(4) }.min()
        var deferred: UUID?
        // A translation can arrive just after ASR opens the next English turn.
        // Give this adjacent pair a short reading opportunity; a newer available
        // translation always wins immediately and old backlog never replays.
        if !focus.hasReadableTranslation,
           let index = turns.firstIndex(where: { $0.id == focus.id }),
           let previous = turns[..<index].last(where: { $0.sessionID == focus.sessionID }),
           previous.hasReadableTranslation, let translatedAt = previous.previewUpdatedAt,
           translatedAt >= focus.receivedAt,
           focus.spokenRange.lowerBound - previous.spokenRange.upperBound <= 1.5 {
            let deadline = focus.receivedAt.addingTimeInterval(1.5)
            if now < deadline {
                deferred = focus.id
                focus = previous
                refresh = min(refresh ?? deadline, deadline)
            }
        }
        return CaptionWindow(current: focus, history: turns.filter { $0.id != focus.id && $0.id != deferred },
                             nextRefresh: refresh)
    }

    public static func live(cloud: [CaptionSegment], drafts: [CaptionSegment]) -> [CaptionSegment] {
        let frame = window(cloud: cloud, drafts: drafts)
        return frame.history + [frame.current].compactMap { $0 }
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
