import Foundation

/// Deduplicate overlapping transcriptions, not speakers. The two capture streams
/// have different sample-zero clocks; arrival order is not evidence of echo.
public enum SystemEchoMatcher {
    public static func matches(in segments:[CaptionSegment])->[UUID:UUID]{
        let references=segments.filter{$0.audioOrigin == .system && !$0.source.isEmpty}
        var result:[UUID:UUID]=[:]
        for mic in segments where mic.audioOrigin == .microphone && !mic.source.isEmpty {
            let nearby=references.filter{overlaps(mic,$0)}
            if let match=nearby.first(where:{sameUtterance(mic.source,$0.source,acousticConfidence:mic.playbackConfidence ?? 0)}) {
                result[mic.id]=match.id
            }else if nearby.count>1 {
                // ASR providers may split the same utterance at different boundaries.
                let ordered=nearby.sorted{($0.audioEpoch ?? $0.receivedAt.timeIntervalSince1970)+Double($0.startMS)/1000<($1.audioEpoch ?? $1.receivedAt.timeIntervalSince1970)+Double($1.startMS)/1000}
                if sameUtterance(mic.source,ordered.map(\.source).joined(separator:" "),acousticConfidence:mic.playbackConfidence ?? 0){result[mic.id]=ordered[0].id}
            }
        }
        return result
    }
    private static func overlaps(_ mic:CaptionSegment,_ system:CaptionSegment)->Bool {
        guard let m=mic.audioEpoch,let s=system.audioEpoch else {
            // Legacy records lack a shared clock: never silently hide finalized mic text.
            return mic.provisional == true && abs((mic.previewUpdatedAt ?? mic.receivedAt).timeIntervalSince(system.previewUpdatedAt ?? system.receivedAt))<3
        }
        let m0=m+Double(mic.startMS)/1000
        let m1=m+Double(max(mic.startMS+80,mic.endMS))/1000
        let s0=s+Double(system.startMS)/1000
        let s1=s+Double(max(system.startMS+80,system.endMS))/1000
        return m0<s1+0.6 && s0<m1+0.6
    }
    public static func sameUtterance(_ microphone:String,_ system:String,acousticConfidence:Double=0)->Bool {
        func words(_ text:String)->[String]{
            var value=text.lowercased().replacingOccurrences(of:"’",with:"'")
            for (a,b) in [("won't","will not"),("can't","can not"),("n't"," not")]{value=value.replacingOccurrences(of:a,with:b)}
            return PreviewText.normalized(value).split(separator:" ").map(String.init)
        }
        let a=words(microphone),b=words(system)
        guard a.count>=3,b.count>=3,a.joined().count>=12 else{return false}
        let negations:Set<String>=["no","not","never","neither","nor"]
        // Compare an exact excerpt with its local context. A negation elsewhere
        // in a long system segment must not turn an identical excerpt into a
        // supposedly independent microphone utterance.
        if b.count>=a.count {
            for start in 0...(b.count-a.count) where Array(b[start..<start+a.count])==a {
                let preceding=b[max(0,start-2)..<start]
                if Set(a).intersection(negations).isEmpty && !Set(preceding).intersection(negations).isEmpty{continue}
                return true
            }
        }
        if acousticConfidence<0.86,Set(a).intersection(negations) != Set(b).intersection(negations){return false}
        let numbers:Set<String>=["zero","one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen","twenty","thirty","forty","fifty","hundred","thousand","million","billion"]
        func numeric(_ words:[String])->Set<String>{Set(words.filter{numbers.contains($0) || $0.contains(where:\.isNumber)})}
        if acousticConfidence<0.86,!numeric(a).isSubset(of:numeric(b)){return false}
        // Ordered coverage preserves an independent response with similar vocabulary.
        var row=Array(repeating:0,count:b.count+1)
        for word in a {
            var previous=0
            for j in b.indices {
                let old=row[j+1]
                row[j+1]=word==b[j] ? previous+1:max(row[j],row[j+1]);previous=old
            }
        }
        let coverage=Double(row[b.count])/Double(a.count)
        return coverage >= (acousticConfidence>=0.86 ? 0.64:(acousticConfidence>=0.72 ? 0.76:0.88))
    }
}
