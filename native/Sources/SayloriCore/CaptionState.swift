import Foundation

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
    /// Read backwards and stop once the visible window is filled; archives still
    /// use `segments` so a long meeting never loses its earlier turns.
    public func recentSegments(limit:Int)->[CaptionSegment] {
        guard limit>0 else{return []}
        return Array(storage.reversed().lazy.filter{!$0.source.isEmpty || !$0.translation.isEmpty}.prefix(limit).reversed())
    }
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
    public var current: CaptionSegment? { storage.last{!$0.source.isEmpty || !$0.translation.isEmpty} }
    public var source: String { current?.source ?? "" }
    // Compatibility for diagnostics: the newest received translation, not necessarily the latest source.
    public var translation: String { storage.last(where:{!$0.translation.isEmpty})?.translation ?? "" }
    public var isFinal: Bool { storage.last(where:{!$0.translation.isEmpty})?.translationFinal ?? false }
    public var previous: String { storage.reversed().lazy.filter{!$0.translation.isEmpty}.dropFirst().first?.translation ?? "" }
    public var context: [CaptionSegment] { Array(recentSegments(limit:4).dropLast()) }
    /// Full local snapshots have stable IDs; a delayed draft cannot overwrite a final.
    public mutating func upsertLocal(_ value:CaptionSegment){
        guard !PreviewText.normalized(value.source+value.translation).isEmpty else{return}
        var item=value;item.audioEpoch=streamClocks[item.sessionID]?.timeIntervalSince1970 ?? item.audioEpoch
        if let i=storage.lastIndex(where:{$0.id==item.id}){
            let old=storage[i]
            guard !old.translationFinal || item.translationFinal else{return}
            guard !old.sourceFinal || item.sourceFinal else{return}
            item.receivedAt=old.receivedAt
            if item.translation.isEmpty && item.source==old.source {item.translation=old.translation}
            storage[i]=item
        }else{storage.append(item)}
    }
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
            storage[i].translationFinal = !storage[i].translation.isEmpty; storage[i].endMS=max(storage[i].endMS,event.end)
        default: break
        }
    }
}
