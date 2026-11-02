import Foundation

/// SpeechTranscriber trims leading silence when a volatile range becomes final.
/// Match the overlapping hypothesis, not its provisional start timestamp.
public struct LocalSpeechIdentity:Sendable {
    private struct Range:Sendable {let id:UUID;var start:Int;var end:Int}
    private var drafts:[Range]=[]
    private var finals:[Range]=[]
    public init(){}
    public mutating func identify(start:Int,end:Int,final:Bool)->UUID {
        if final,let old=finals.last(where:{$0.start==start && $0.end==end}){return old.id}
        let match=drafts.indices.max {a,b in
            overlap(drafts[a],start,end)<overlap(drafts[b],start,end)
        }.flatMap{i in drafts[i].start==start || overlap(drafts[i],start,end)>0 ? i:nil}
        let id=match.map{drafts[$0].id} ?? UUID()
        let range=Range(id:id,start:start,end:end)
        if final {
            if let match{drafts.remove(at:match)}
            finals.append(range);if finals.count>64{finals.removeFirst()}
        }else if let match{drafts[match]=range}else{drafts.append(range)}
        return id
    }
    private func overlap(_ range:Range,_ start:Int,_ end:Int)->Int {max(0,min(range.end,end)-max(range.start,start))}
}
