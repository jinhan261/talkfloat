import XCTest
@testable import SayloriCore

final class SystemEchoTests:XCTestCase {
    private let epoch=Date(timeIntervalSince1970:1000)
    private func segment(_ origin:AudioOrigin,_ text:String,_ start:Int,_ end:Int,_ offset:Double=0)->CaptionSegment {
        var item=CaptionSegment(sessionID:origin.rawValue,startMS:start)
        item.origin=origin;item.source=text;item.translation="测试译文";item.endMS=end
        item.sourceFinal=true;item.translationFinal=true;item.audioEpoch=epoch.timeIntervalSince1970+offset
        return item
    }
    func testFinalEchoUsesAudioClocksNotArrivalOrder(){
        let sys=segment(.system,"Our economy has made considerable progress.",5000,9000)
        var mic=segment(.microphone,sys.source,2000,6000,3);mic.receivedAt=Date().addingTimeInterval(15)
        XCTAssertEqual(SystemEchoMatcher.matches(in:[sys,mic])[mic.id],sys.id)
        XCTAssertEqual(CaptionPresentation.live(cloud:[sys,mic],drafts:[]).map(\.audioOrigin),[.system])
    }
    func testIndependentDoubleTalkIsPreserved(){
        let sys=segment(.system,"We will send the final proposal tomorrow morning.",1000,5000)
        let mic=segment(.microphone,"I disagree because we need more time to finish it.",1000,5000)
        XCTAssertTrue(SystemEchoMatcher.matches(in:[sys,mic]).isEmpty)
        XCTAssertEqual(CaptionPresentation.live(cloud:[sys,mic],drafts:[]).count,2)
    }
    func testRepeatingAfterPlaybackIsNotEcho(){
        let sys=segment(.system,"Do you think tomorrow will be raining?",1000,4000)
        let mic=segment(.microphone,sys.source,6000,9000)
        XCTAssertTrue(SystemEchoMatcher.matches(in:[sys,mic]).isEmpty)
    }
    func testNegationAndChangedNumbersRemainIndependent(){
        XCTAssertFalse(SystemEchoMatcher.sameUtterance("I do not agree with the final proposal.","I do agree with the final proposal."))
        XCTAssertFalse(SystemEchoMatcher.sameUtterance("The budget is thirteen thousand dollars.","The budget is three thousand dollars."))
    }
    func testDifferentSegmentationAndPartialMicEcho(){
        let a=segment(.system,"Our economy has made",0,2000)
        let b=segment(.system,"considerable progress over the past year.",2000,5000)
        var mic=segment(.microphone,"Our economy has made considerable progress",100,4300)
        mic.provisional=true;mic.translationFinal=false;mic.previewUpdatedAt=Date()
        XCTAssertNotNil(SystemEchoMatcher.matches(in:[a,b,mic])[mic.id])
        XCTAssertFalse(CaptionPresentation.live(cloud:[a,b],drafts:[mic]).contains{$0.audioOrigin == .microphone})
    }
    func testSimilarUnorderedVocabularyNotEnough(){
        XCTAssertFalse(SystemEchoMatcher.sameUtterance("Tomorrow I will send the proposal, not today.","I will not send the proposal tomorrow, but today."))
    }
    func testLegacyFinalMicIsNotRemoved(){
        var sys=segment(.system,"The meeting starts on Tuesday morning.",0,3000)
        var mic=segment(.microphone,sys.source,0,3000);mic.audioEpoch=nil;sys.audioEpoch=nil
        XCTAssertTrue(SystemEchoMatcher.matches(in:[sys,mic]).isEmpty)
    }
    func testArchiveRetainsOriginalMicAndMarksEcho()async throws{
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let sys=segment(.system,"Our economy has made considerable progress.",1000,4000)
        let mic=segment(.microphone,sys.source,1100,4100)
        var record=MeetingRecord(sourceName:"Chrome");record.segments=[sys,mic]
        let store=TranscriptStore(directory:dir)
        let md=try await store.save(record)!
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let archived=try decoder.decode(MeetingRecord.self,from:Data(contentsOf:md.deletingPathExtension().appendingPathExtension("json")))
        XCTAssertEqual(archived.segments.count,2)
        XCTAssertEqual(archived.segments[1].source,mic.source)
        XCTAssertEqual(archived.segments[1].possibleEchoOf,sys.id)
        XCTAssertTrue(try String(contentsOf:md,encoding:.utf8).contains("疑似系统外放回声"))
    }
    func testWeakLeakNeedsSustainedPlaybackEvidenceAndNoNearSpeech(){
        let gate=PreviewAudioGate()
        func pcm(_ amplitude:Int16)->Data{Data(repeating:0,count:0)+[Int16](repeating:amplitude,count:1280).withUnsafeBytes{Data($0)}}
        for i in 0..<10{let time=1+Double(i)*0.08;gate.observeSystem(pcm(2000),now:time);_ = gate.microphonePreview(pcm(20),now:time)}
        XCTAssertTrue(gate.isWeakPlaybackLeak(start:1,end:1.6))
        _ = gate.microphonePreview(pcm(2000),now:1.7)
        XCTAssertFalse(gate.isWeakPlaybackLeak(start:1,end:1.75))
        XCTAssertFalse(gate.isWeakPlaybackLeak(start:4,end:5))
    }
    func testLowLevelAloneDoesNotHideIndependentSpeech(){
        let gate=PreviewAudioGate()
        var sample=Int16(20);let data=Data(bytes:&sample,count:2)
        _ = gate.microphonePreview(data,now:1)
        XCTAssertFalse(gate.isWeakPlaybackLeak(start:0.5,end:1.1))
    }
    func testWeakPlaybackHallucinationNotShownButRawRecordKept(){
        let sys=segment(.system,"Our economy has made considerable progress.",1000,4000)
        var mic=segment(.microphone,"Storing gods creation opens the underworld.",1000,4000);mic.weakPlaybackLeak=true
        XCTAssertEqual(CaptionPresentation.live(cloud:[sys,mic],drafts:[]).count,1)
        var record=MeetingRecord(sourceName:"Chrome");record.segments=[sys,mic]
        XCTAssertEqual(record.segments.count,2)
        XCTAssertTrue(record.markdown.contains(mic.source))
        XCTAssertTrue(record.markdown.contains("疑似系统外放回声"))
    }
}
