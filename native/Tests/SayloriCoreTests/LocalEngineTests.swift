import XCTest
@testable import SayloriCore

final class LocalEngineTests:XCTestCase {
    private func item(_ text:String,_ start:Int=0,final:Bool=false)->CaptionSegment {
        var s=CaptionSegment(sessionID:"local",startMS:start)
        s.source=text;s.sourceFinal=final;s.provisional=true;return s
    }
    func testAppleFinalTrimmingReusesDraftIdentity(){
        var ids=LocalSpeechIdentity()
        let first=ids.identify(start:0,end:4880,final:false)
        XCTAssertEqual(ids.identify(start:1440,end:4380,final:true),first)
        let next=ids.identify(start:4380,end:8720,final:false)
        XCTAssertNotEqual(first,next)
        XCTAssertEqual(ids.identify(start:4440,end:8100,final:true),next)
        XCTAssertEqual(ids.identify(start:1440,end:4380,final:true),first)
    }
    func testAdjacentIdenticalUtterancesHaveIndependentIdentity(){
        var ids=LocalSpeechIdentity()
        let a=ids.identify(start:0,end:1000,final:false)
        XCTAssertEqual(ids.identify(start:100,end:900,final:true),a)
        XCTAssertNotEqual(ids.identify(start:900,end:2000,final:false),a)
    }
    func testFinalQueueKeepsEverySentenceWhileCoalescingDrafts()throws {
        var q=LocalTranslationQueue()
        let a=item("First.",final:true),b=item("Second.",100,final:true)
        try q.enqueue(a);try q.enqueue(item("Obsolete draft",200));try q.enqueue(b)
        try q.enqueue(item("Newest draft",300))
        XCTAssertEqual(q.next()?.id,a.id);XCTAssertEqual(q.next()?.id,b.id)
        XCTAssertEqual(q.next()?.source,"Newest draft");XCTAssertNil(q.next())
    }
    func testFinalReplacesOwnDraftAndQueuedCorrection()throws {
        var q=LocalTranslationQueue();var s=item("thirteen")
        try q.enqueue(s);s.source="Three thousand.";s.sourceFinal=true
        try q.enqueue(s);s.source="Not thirteen thousand.";try q.enqueue(s)
        XCTAssertEqual(q.count,1);XCTAssertEqual(q.next()?.source,s.source)
    }
    func testOverloadFailsExplicitlyWithoutDiscardingFinals()throws {
        var q=LocalTranslationQueue()
        for i in 0..<32{try q.enqueue(item("Sentence \(i)",i,final:true))}
        XCTAssertThrowsError(try q.enqueue(item("Overflow",33,final:true)))
        XCTAssertEqual(q.count,32);XCTAssertEqual(q.next()?.source,"Sentence 0")
    }
    func testReadablePairSurvivesASRRevisionWithoutChangingArchive(){
        var old=item("We are ready");old.translation="我们准备好了"
        var revised=old;revised.source="We are ready for the meeting";revised.translation=""
        XCTAssertEqual(CaptionPresentation.keepingReadableTranslation(revised,previous:old).translation,old.translation)
        XCTAssertEqual(CaptionPresentation.keepingReadableTranslation(revised,previous:old).source,old.source)
        XCTAssertEqual(revised.translation,"")
        revised.translation="我们为会议做好准备"
        XCTAssertEqual(CaptionPresentation.keepingReadableTranslation(revised,previous:old).source,revised.source)
    }
    func testLocalFinalCannotBeOverwrittenByLatePartial(){
        var state=CaptionState();var s=item("Three thousand.",final:true)
        s.translation="三千。";s.translationFinal=true;s.provisional=false
        state.upsertLocal(s)
        s.sourceFinal=false;s.translationFinal=false;s.source="Thirteen";s.translation="十三"
        state.upsertLocal(s)
        XCTAssertEqual(state.segments.count,1);XCTAssertEqual(state.current?.translation,"三千。")
    }
    func testCorrectedSourceNeverKeepsMismatchedOldTranslation(){
        var state=CaptionState();var s=item("Thirteen")
        s.translation="十三";state.upsertLocal(s)
        s.source="Three thousand.";s.sourceFinal=true;s.translation="";state.upsertLocal(s)
        XCTAssertEqual(state.current?.translation,"")
        s.translation="三千。";s.translationFinal=true;state.upsertLocal(s)
        XCTAssertEqual(state.current?.translation,"三千。")
    }
    func testPunctuationOnlyLocalNoiseDoesNotCreateMissingTranslationRow(){
        var state=CaptionState()
        for source in [".","?!", " "]{state.upsertLocal(item(source))}
        XCTAssertTrue(state.segments.isEmpty)
        state.upsertLocal(item("Hello"));XCTAssertEqual(state.segments.count,1)
    }
    func testLocalHistoryAndIndependentChannelsSurviveLiveWindow(){
        var state=CaptionState()
        for i in 0..<160 {
            var s=item("Sentence \(i)",i*100,final:true)
            s.origin=i.isMultiple(of:2) ? .system:.microphone
            s.sessionID=s.audioOrigin.rawValue;s.translation="译文 \(i)";s.translationFinal=true
            state.upsertLocal(s)
        }
        XCTAssertEqual(state.segments.count,160);XCTAssertEqual(state.recentSegments(limit:64).count,64)
        XCTAssertEqual(state.segments.filter{$0.audioOrigin == .microphone}.count,80)
    }
    func testEngineMetadataIsBackwardCompatibleAndArchived()throws {
        var record=MeetingRecord(sourceName:"系统声音")
        let old=try JSONEncoder().encode(record)
        XCTAssertNil(try JSONDecoder().decode(MeetingRecord.self,from:old).engine)
        record.engine = .local
        var s=item("Hello.",final:true);s.translation="你好。";s.translationFinal=true
        record.segments=[s]
        let roundTrip=try JSONDecoder().decode(MeetingRecord.self,from:JSONEncoder().encode(record))
        XCTAssertEqual(roundTrip.engine,.local);XCTAssertTrue(roundTrip.markdown.contains("翻译模式：本地免费"))
        XCTAssertTrue(roundTrip.markdown.contains("你好。"));XCTAssertTrue(roundTrip.markdown.contains("Hello."))
    }
}
