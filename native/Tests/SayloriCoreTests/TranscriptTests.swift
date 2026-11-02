import XCTest
@testable import SayloriCore

final class TranscriptTests:XCTestCase {
    private func e(_ type:Int,_ text:String="",_ start:Int=0,_ end:Int=0)throws->ASTEvent {
        try ASTEvent(data:Proto.number(2,UInt64(type))+Proto.string(4,text)+Proto.number(5,UInt64(start))+Proto.number(6,UInt64(end)))
    }
    func testTranslationArrivingBehindTwoSourcesStaysPaired()throws {
        var state=CaptionState();state.beginStream("one")
        try state.apply(e(650,"",100));try state.apply(e(652,"First.",100,500))
        try state.apply(e(650,"",600));try state.apply(e(651,"Second",600))
        try state.apply(e(653,"",100));try state.apply(e(654,"第一",100));try state.apply(e(655,"第一句。",100,500))
        XCTAssertEqual(state.current?.source,"Second");XCTAssertEqual(state.current?.translation,"")
        XCTAssertEqual(state.context.first?.source,"First.");XCTAssertEqual(state.context.first?.translation,"第一句。")
        try state.apply(e(652,"Second.",600,1000));try state.apply(e(653,"",600));try state.apply(e(655,"第二句。",600,1000))
        XCTAssertEqual(state.segments.count,2);XCTAssertEqual(state.current?.translation,"第二句。")
    }
    func testResumeKeepsHistoryEvenWhenAudioTimestampsRestart()throws {
        var state=CaptionState()
        for session in ["a","b"] {
            state.beginStream(session)
            try state.apply(e(650));try state.apply(e(652,"Again."));try state.apply(e(653));try state.apply(e(655,"再来。"))
        }
        XCTAssertEqual(state.segments.count,2)
        XCTAssertNotEqual(state.segments[0].sessionID,state.segments[1].sessionID)
        XCTAssertEqual(state.segments.map(\.translation),["再来。","再来。"])
    }
    func testFinalCorrectionReplacesPartialWithoutLosingOldSentences()throws {
        var state=CaptionState()
        for index in 0..<20 {
            try state.apply(e(650,"",index*100));try state.apply(e(651,"Thirteen"));try state.apply(e(652,"Three thousand."))
            try state.apply(e(653,"",index*100));try state.apply(e(654,"一万三"));try state.apply(e(655,"三千。"))
        }
        XCTAssertEqual(state.segments.count,20);XCTAssertEqual(state.context.count,3)
        XCTAssertTrue(state.segments.allSatisfy{$0.source=="Three thousand." && $0.translation=="三千。"})
    }
    func testArchiveRoundTripAndInterruptedRecovery() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("saylori-test-\(UUID())")
        defer{try? FileManager.default.removeItem(at:dir)}
        var state=CaptionState();try state.apply(e(650));try state.apply(e(652,"Not thirteen."));try state.apply(e(653));try state.apply(e(654,"不是十三"))
        var record=MeetingRecord(sourceName:"Chrome");record.segments=state.segments
        let store=TranscriptStore(directory:dir)
        let result=try await store.save(record);let md=try XCTUnwrap(result)
        XCTAssertTrue(try String(contentsOf:md).contains("中文（未定稿）：不是十三"))
        try await store.recoverInterrupted()
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let recovered=try decoder.decode(MeetingRecord.self,from:Data(contentsOf:md.deletingPathExtension().appendingPathExtension("json")))
        XCTAssertNotNil(recovered.endedAt);XCTAssertTrue(recovered.status.contains("已恢复"))
        XCTAssertEqual(recovered.segments[0].source,"Not thirteen.")
    }
    func testLateAutosaveCannotOverwriteFinalArchive() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("saylori-test-\(UUID())")
        defer{try? FileManager.default.removeItem(at:dir)}
        var record=MeetingRecord(sourceName:"系统")
        var s=CaptionSegment(sessionID:"s",startMS:0);s.source="Hello";record.segments=[s]
        let old=record;record.status="已结束";record.endedAt=Date();record.revision=2
        let store=TranscriptStore(directory:dir);let saved=try await store.save(record);let md=try XCTUnwrap(saved)
        _ = try await store.save(old)
        XCTAssertTrue(try String(contentsOf:md).contains("状态：已结束"))
    }
    func testSimultaneousMicrophoneAndSystemNeverCrossPair()throws {
        func event(_ sid:String,_ type:Int,_ text:String="")throws->ASTEvent {
            try ASTEvent(data:Proto.bytes(1,Proto.string(1,sid))+Proto.number(2,UInt64(type))+Proto.string(4,text)+Proto.number(5,100))
        }
        var state=CaptionState();state.beginStream("speaker");state.beginStream("mic",origin:.microphone)
        try state.apply(event("speaker",650));try state.apply(event("speaker",651,"Other"))
        try state.apply(event("mic",650));try state.apply(event("mic",651,"My"))
        try state.apply(event("speaker",652,"Other voice."));try state.apply(event("mic",652,"My voice."))
        try state.apply(event("mic",653));try state.apply(event("speaker",653))
        try state.apply(event("mic",654,"我"));try state.apply(event("speaker",654,"对"))
        try state.apply(event("mic",655,"我的声音。"));try state.apply(event("speaker",655,"对方声音。"))
        XCTAssertEqual(state.segments.count,2)
        XCTAssertEqual(state.segments.map(\.translation),["对方声音。","我的声音。"])
        XCTAssertEqual(state.segments.map(\.audioOrigin),[.system,.microphone])
        var record=MeetingRecord(sourceName:"Chrome + mic");record.segments=state.segments
        XCTAssertTrue(record.markdown.contains("麦克风声音"))
    }
    func testOldArchiveWithoutOriginStillDecodes()throws {
        let item=CaptionSegment(sessionID:"old",startMS:1)
        let data=try JSONEncoder().encode(item)
        let decoded=try JSONDecoder().decode(CaptionSegment.self,from:data)
        XCTAssertNil(decoded.origin);XCTAssertEqual(decoded.audioOrigin,.system)
    }
    func testExplicitChannelHandlesMissingServerSessionID()throws {
        var state=CaptionState();state.beginStream("sys");state.beginStream("mic",origin:.microphone)
        try state.apply(e(650),streamID:"sys");try state.apply(e(650),streamID:"mic")
        try state.apply(e(652,"You."),streamID:"sys");try state.apply(e(652,"Me."),streamID:"mic")
        XCTAssertEqual(state.segments.map(\.audioOrigin),[.system,.microphone])
        XCTAssertEqual(state.segments.map(\.source),["You.","Me."])
    }
    func testRetryOnlyTransientFailureAndArchiveDisclosesGap()throws {
        XCTAssertTrue(SayError.canRetry(SayError.service(55000001,"simul err")))
        XCTAssertTrue(SayError.canRetry(URLError(.networkConnectionLost)))
        XCTAssertFalse(SayError.canRetry(SayError.service(45000001,"bad request")))
        XCTAssertFalse(SayError.canRetry(SayError.message("Permission denied")))
        var record=MeetingRecord(sourceName:"Chrome")
        record.interruptions=[MeetingInterruption(origin:.system,reason:"暂时中断")]
        XCTAssertTrue(record.markdown.contains("未恢复"))
        let decoded=try JSONDecoder().decode(MeetingRecord.self,from:JSONEncoder().encode(record))
        XCTAssertEqual(decoded.interruptions?.count,1)
    }
    func testSilentFinalsCannotEraseCurrentCaptionOrPolluteArchive()throws {
        var state=CaptionState();state.beginStream("s")
        try state.apply(e(650));try state.apply(e(652,"Hello."));try state.apply(e(653));try state.apply(e(655,"你好。"))
        try state.apply(e(650,"",1000));try state.apply(e(652,"",1000));try state.apply(e(653,"",1000));try state.apply(e(655,"",1000))
        XCTAssertEqual(state.current?.source,"Hello.");XCTAssertEqual(state.segments.count,1)
        try state.apply(e(650,"",2000));try state.apply(e(652,"Next.",2000));try state.apply(e(653,"",2000));try state.apply(e(655,"下一句。",2000))
        XCTAssertEqual(state.segments.count,2);XCTAssertEqual(state.current?.translation,"下一句。")
    }
    func testEmptyConnectionDoesNotCreateMeetingFile() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("saylori-test-\(UUID())")
        let result=try await TranscriptStore(directory:dir).save(MeetingRecord(sourceName:"系统"))
        XCTAssertNil(result);XCTAssertFalse(FileManager.default.fileExists(atPath:dir.path))
    }
}

final class SentencePresentationTests:XCTestCase {
    func segment(_ text:String,_ cn:String,_ start:Int,_ end:Int,_ session:String="mic")->CaptionSegment{
        var s=CaptionSegment(sessionID:session,startMS:start);s.endMS=end;s.source=text;s.translation=cn;s.sourceFinal=true;s.translationFinal=true;s.origin = .microphone;return s
    }
    func testActualSplitQuestionRemainsOneSentence(){
        let a=segment("Do you think ","你认为",106112,106752)
        let b=segment("tomorrow will be raining? ","明天会下雨吗？",107552,108992)
        let grouped=CaptionPresentation.sentences([a,b])
        XCTAssertEqual(grouped.count,1);XCTAssertEqual(grouped[0].source,"Do you think tomorrow will be raining?")
        XCTAssertEqual(grouped[0].translation,"你认为明天会下雨吗？")
        var record=MeetingRecord(sourceName:"麦克风");record.segments=[a,b]
        XCTAssertEqual(record.segments.count,2);XCTAssertTrue(record.markdown.contains("Do you think tomorrow will be raining?"))
    }
    func testPausesStopsAndOtherChannelsDoNotMerge(){
        let a=segment("Do you think","你认为",0,640)
        XCTAssertEqual(CaptionPresentation.sentences([a,segment("Next?","下一句？",3000,5000)]).count,2)
        XCTAssertEqual(CaptionPresentation.sentences([a,segment("Next?","下一句？",800,1200,"system")]).count,2)
        XCTAssertEqual(CaptionPresentation.sentences([segment("Done.","完。",0,640),segment("Next?","下一句？",800,1200)]).count,2)
    }
    func testPreviewStaysAheadAndFinalReplacesIt(){
        let a=segment("Hello.","你好。",0,1000)
        var draft=segment("We will discuss","我们将讨论",1100,2500);draft.provisional=true;draft.translationFinal=false
        XCTAssertEqual(CaptionPresentation.live(cloud:[a],drafts:[draft]).last?.translation,"我们将讨论")
        let final=segment("We will discuss the budget.","我们将讨论预算。",1100,4000)
        let result=CaptionPresentation.live(cloud:[a,final],drafts:[draft])
        XCTAssertEqual(result.count,2);XCTAssertNil(result.last?.provisional)
        XCTAssertEqual(result.last?.translation,"我们将讨论预算。")
    }
}

final class PreviewSafetyTests:XCTestCase {
    func testVolatileSubwordAndDanglingConjunctionAreNotTranslated(){
        XCTAssertEqual(PreviewText.translationInput("In support of a strong econ",stable:false),"In support of a strong")
        XCTAssertEqual(PreviewText.translationInput("The labor market with continued strong job gains and"),"The labor market with continued strong job gains")
        XCTAssertEqual(PreviewText.translationInput("Do you think tomorrow will be raining?",stable:false),"Do you think tomorrow will be raining?")
    }
    func testEchoPreviewSuppressedButCloudMicRecordRetained(){
        var sys=CaptionSegment(sessionID:"sys",startMS:100);sys.source="Our economy has made considerable progress";sys.endMS=4000;sys.origin = .system
        var mic=sys;mic.id=UUID();mic.sessionID="mic";mic.origin = .microphone;mic.provisional=true;mic.translation="经济已经取得进展";mic.previewUpdatedAt=Date()
        XCTAssertEqual(CaptionPresentation.live(cloud:[sys],drafts:[mic]).count,1)
        mic.provisional=nil;mic.translationFinal=true
        XCTAssertEqual(CaptionPresentation.live(cloud:[sys,mic],drafts:[]).count,2)
        XCTAssertFalse(PreviewText.likelyEcho("I disagree with this proposal","Our economy has made considerable progress"))
    }
    func testTextConfirmationRetiresPreviewDespiteDifferentTimestamp(){
        var cloud=CaptionSegment(sessionID:"s",startMS:1000);cloud.source="Good afternoon.";cloud.translation="下午好。";cloud.endMS=2000;cloud.translationFinal=true
        var preview=cloud;preview.id=UUID();preview.endMS=2900;preview.provisional=true;preview.translationFinal=false
        XCTAssertEqual(CaptionPresentation.live(cloud:[cloud],drafts:[preview]).count,1)
    }
}

final class PreviewAudioGateTests:XCTestCase {
    func pcm(_ amplitude:Int16)->Data{var value=amplitude;return Data(bytes:&value,count:2)}
    func testOnlyWeakMicDuringPlaybackIsSuppressedAndLengthPreserved(){
        let gate=PreviewAudioGate(),quiet=pcm(20),loud=pcm(2000)
        XCTAssertEqual(gate.microphonePreview(quiet,now:1),quiet)
        gate.observeSystem(loud,now:2)
        XCTAssertEqual(gate.microphonePreview(quiet,now:2.1),Data(count:2))
        XCTAssertEqual(gate.microphonePreview(loud,now:2.2),loud)
        XCTAssertEqual(gate.microphonePreview(quiet,now:2.3),quiet) // hold soft word endings
        XCTAssertEqual(gate.microphonePreview(quiet,now:3),quiet) // playback ended
        XCTAssertEqual(gate.suppressedPackets,1)
    }
}
