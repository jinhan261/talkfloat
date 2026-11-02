import Foundation

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
