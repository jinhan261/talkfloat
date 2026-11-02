import XCTest
@testable import SayloriCore

final class PlaybackCorrelationTests:XCTestCase {
    private func pcm(_ start:Double,gain:Double,independent:Bool=false)->Data {
        let values=(0..<1280).map { i -> Int16 in
            let t=start+Double(i)/16000
            let envelope=independent ? pow(0.55+0.20*sin(t*13)+0.22*cos(t*31),2):pow(0.5+0.25*sin(t*7)+0.23*cos(t*19),2)
            return Int16(max(-32000,min(32000,32767*gain*envelope*(sin(t*1300)+sin(t*3800)+sin(t*8700))/3)))
        }
        return values.withUnsafeBytes{Data($0)}
    }
    func testMissingTranslationRemainsExplicitInArchive(){
        var record=MeetingRecord(sourceName:"Chrome")
        var missing=CaptionSegment(sessionID:"mic",startMS:0);missing.source="We have two plans,";missing.endMS=1000;missing.sourceFinal=true;missing.translationFinal=true
        var next=CaptionSegment(sessionID:"mic",startMS:1100);next.source="and we will review them tomorrow.";next.endMS=2000;next.translation="明天我们会审查它们。";next.translationFinal=true
        record.segments=[missing,next]
        XCTAssertEqual(CaptionPresentation.sentences(record.segments).count,2)
        XCTAssertTrue(record.markdown.contains("中文：未收到译文"))
    }
    func testPunctuationCannotReplaceReadableCaption(){
        var text=CaptionSegment(sessionID:"system",startMS:0);text.source="The meeting is tomorrow.";text.translation="会议在明天。";text.translationFinal=true
        var noise=CaptionSegment(sessionID:"mic",startMS:2000);noise.origin = .microphone;noise.source="...";noise.translation="。"
        XCTAssertEqual(CaptionPresentation.live(cloud:[text,noise],drafts:[]).map(\.id),[text.id])
    }
    func testExactExcerptIgnoresUnrelatedEarlierNegation(){
        XCTAssertTrue(SystemEchoMatcher.sameUtterance("The potential future value of that.", "Not just today, but the potential future value of that is really interesting."))
        XCTAssertFalse(SystemEchoMatcher.sameUtterance("Approve the proposal.", "We will not approve the proposal."))
    }
    func testEchoWithDelayAndGainHasAcousticEvidence(){
        let gate=PreviewAudioGate()
        for i in 0..<60 {
            let t=Double(i)*0.08
            gate.observeSystem(pcm(t,gain:0.7),now:t+0.08)
            _ = gate.microphonePreview(pcm(t,gain:0.12),now:t+0.25)
        }
        XCTAssertGreaterThan(gate.playbackConfidence(start:2,end:4),0.90)
    }
    func testIndependentNearSpeechIsNotClassifiedFromVolumeAlone(){
        let gate=PreviewAudioGate()
        for i in 0..<60 {
            let t=Double(i)*0.08
            gate.observeSystem(pcm(t,gain:0.7),now:t+0.08)
            _ = gate.microphonePreview(pcm(t,gain:0.12,independent:true),now:t+0.25)
        }
        XCTAssertLessThan(gate.playbackConfidence(start:2,end:4),0.72)
    }
    func testRecognizerNumberErrorNeedsAcousticSupport(){
        let mic="There's millions of dollars at stake."
        let system="There's billions of dollars at stake every single hour of the day."
        XCTAssertFalse(SystemEchoMatcher.sameUtterance(mic,system))
        XCTAssertTrue(SystemEchoMatcher.sameUtterance(mic,system,acousticConfidence:0.93))
        XCTAssertFalse(SystemEchoMatcher.sameUtterance("No, we cannot afford this proposal.",system,acousticConfidence:0.93))
    }
    func testPreviewRevisionReplacesOldFragmentWithoutCrossingSources(){
        var old=CaptionSegment(sessionID:"mic",startMS:0);old.source="Because he thinks";old.previewUpdatedAt=Date(timeIntervalSince1970:1)
        var updated=CaptionSegment(sessionID:"mic",startMS:500);updated.source="Because he thinks I could build it";updated.previewUpdatedAt=Date(timeIntervalSince1970:2)
        var system=CaptionSegment(sessionID:"system",startMS:0);system.source="System speech"
        let values=CaptionPresentation.latestDrafts([old,system,updated])
        XCTAssertEqual(values.count,2);XCTAssertFalse(values.contains{$0.id==old.id});XCTAssertTrue(values.contains{$0.id==system.id})
    }
}
