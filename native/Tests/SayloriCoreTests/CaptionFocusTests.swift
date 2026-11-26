import XCTest
@testable import SayloriCore

final class CaptionFocusTests: XCTestCase {
    private let epoch = 100_000.0

    private func turn(_ origin: AudioOrigin, _ start: Int, _ end: Int,
                      streamOffset: Double = 0, translated: Bool = true) -> CaptionSegment {
        var item = CaptionSegment(sessionID: origin.rawValue, startMS: start)
        item.origin = origin
        item.audioEpoch = epoch + streamOffset
        item.endMS = end
        item.receivedAt = Date(timeIntervalSince1970: epoch + streamOffset + Double(end) / 1000)
        item.source = origin == .system ? "Please review the new proposal." : "I have a question."
        item.translation = translated ? (origin == .system ? "请看一下新提案。" : "我有个问题。") : ""
        return item
    }

    func testOverlappingMicrophoneTurnCannotCoverCurrentSystemSpeech() {
        let system = turn(.system, 3_580_000, 3_585_000)
        // Microphone capture started 40 seconds after system capture.
        let mic = turn(.microphone, 3_542_000, 3_544_000, streamOffset: 40)
        let visible = CaptionPresentation.live(cloud: [system, mic], drafts: [])
        XCTAssertEqual(visible.last?.id, system.id)
        XCTAssertEqual(visible.dropLast().map(\.id), [mic.id])
    }

    func testDelayedOldSystemResultCannotReplaceNewerMicrophoneSpeech() {
        let system = turn(.system, 3_580_000, 3_583_000)
        let mic = turn(.microphone, 1800, 4000, streamOffset: 3582)
        XCTAssertEqual(CaptionPresentation.live(cloud: [mic, system], drafts: []).last?.id, mic.id)
    }

    func testStalePreviewFromAnotherChannelCannotCoverNewSystemTurn() {
        var draft = turn(.microphone, 1000, 1800)
        draft.provisional = true
        draft.previewUpdatedAt = Date()
        let system = turn(.system, 4300, 6700)
        let visible = CaptionPresentation.live(cloud: [system], drafts: [draft])
        XCTAssertEqual(visible.map(\.id), [draft.id, system.id])
    }

    func testLateChineseForPreviousTurnGetsBrieflyShownBeforeNextTranslation() {
        var first = turn(.system, 1000, 3300)
        var next = turn(.system, 3400, 4200, translated: false)
        let arrived = next.receivedAt.addingTimeInterval(0.2)
        first.previewUpdatedAt = arrived
        let frame = CaptionPresentation.window(cloud: [first, next], drafts: [], now: arrived)
        XCTAssertEqual(frame.current?.id, first.id)
        XCTAssertTrue(frame.history.isEmpty)
        XCTAssertEqual(frame.nextRefresh, next.receivedAt.addingTimeInterval(1.5))
        let expired = CaptionPresentation.window(cloud: [first, next], drafts: [], now: next.receivedAt.addingTimeInterval(1.5))
        XCTAssertEqual(expired.current?.id, next.id)
        XCTAssertEqual(expired.history.map(\.id), [first.id])
        next.translation = "下一句译文。"
        XCTAssertEqual(CaptionPresentation.window(cloud: [first, next], drafts: [], now: arrived).current?.id, next.id)
        let later = turn(.system, 15_000, 16_000, translated: false)
        first.previewUpdatedAt = later.receivedAt
        XCTAssertEqual(CaptionPresentation.window(cloud: [first, later], drafts: [], now: later.receivedAt).current?.id, later.id)
    }

    func testOngoingMicrophoneTakesOverAfterSystemSpeakerStops() {
        let system = turn(.system, 1000, 4200)
        var mic = turn(.microphone, 3200, 4100)
        XCTAssertEqual(CaptionPresentation.window(cloud: [system, mic], drafts: []).current?.id, system.id)
        mic.endMS = 5500
        XCTAssertEqual(CaptionPresentation.window(cloud: [system, mic], drafts: []).current?.id, mic.id)
    }

    func testLateShorterTranslationPreservesNewerASRTimeAndTheReadablePair() {
        var state = CaptionState()
        let earlier = turn(.system, 2100, 3200)
        var longer = earlier
        longer.source += " Before Friday."
        longer.endMS = 5800
        longer.translation = ""
        state.upsertLocal(longer)
        state.upsertLocal(earlier)
        guard let raw = state.current else { return XCTFail("Missing source") }
        XCTAssertEqual(raw.source, longer.source)
        let displayed = CaptionPresentation.keepingReadableTranslation(raw, previous: earlier)
        XCTAssertEqual(displayed.source, earlier.source)
        XCTAssertEqual(displayed.translation, earlier.translation)
        XCTAssertEqual(displayed.endMS, longer.endMS)
        XCTAssertFalse(raw.hasReadableTranslation)
    }

    func testOlderDraftCorrectionCannotReviveAnEarlierUtterance() {
        var earlier = turn(.system, 1000, 2500)
        let later = turn(.system, 4000, 5700)
        earlier.previewUpdatedAt = later.receivedAt.addingTimeInterval(0.1)
        XCTAssertEqual(CaptionPresentation.latestDrafts([later, earlier]).map(\.id), [later.id])
    }

    func testSixtyFiveMinutesOfOverlappingTurnsKeepRemoteSpeechInFocusAndBothInArchive() {
        var state = CaptionState()
        for i in 0..<390 {
            let start = i*10_000
            let system = turn(.system, start, start+6000)
            let mic = turn(.microphone, start+1500, start+3200)
            state.upsertLocal(system)
            state.upsertLocal(mic)
            let frame = CaptionPresentation.window(cloud: state.recentSegments(limit:64), drafts: [])
            XCTAssertEqual(frame.current?.id, system.id)
            XCTAssertTrue(frame.history.contains { $0.id == mic.id })
        }
        var record = MeetingRecord(sourceName: "Test")
        record.segments = state.segments
        XCTAssertEqual(record.markdown.components(separatedBy: " · 系统声音 · ").count-1, 390)
        XCTAssertEqual(record.markdown.components(separatedBy: " · 麦克风声音 · ").count-1, 390)
    }
}
