import XCTest
@testable import SayloriCore

final class NearSpeechGateTests:XCTestCase {
    private func tone(_ amplitude:Double)->Data{
        let values=(0..<1280).map{Int16(sin(Double($0)*0.12)*amplitude*32767)}
        return values.withUnsafeBytes{Data($0)}
    }
    func testWeakBackgroundIsRejectedWhileNearSpeechPasses(){
        let gate=NearSpeechGate()
        for _ in 0..<100{XCTAssertFalse(gate.shouldPass(tone(0.008)))}
        XCTAssertTrue(gate.shouldPass(tone(0.08)))
    }
    func testExistingLookaheadPreservesQuietWordOnset(){
        let gate=NearSpeechGate()
        XCTAssertTrue(gate.shouldPass(tone(0.006),upcoming:[tone(0.008),tone(0.08)]))
    }
    func testBackgroundCannotKeepGateOpenAfterSentence(){
        let gate=NearSpeechGate();XCTAssertTrue(gate.shouldPass(tone(0.08)))
        for _ in 0..<2{XCTAssertTrue(gate.shouldPass(tone(0.008)))}
        XCTAssertFalse(gate.shouldPass(tone(0.008)))
    }
    func testDisableAndResetDoNotLeaveGateStuck(){
        let gate=NearSpeechGate();gate.setEnabled(false)
        XCTAssertTrue(gate.shouldPass(tone(0.001)))
        gate.setEnabled(true);XCTAssertFalse(gate.shouldPass(tone(0.001)))
        XCTAssertTrue(gate.shouldPass(tone(0.08)));gate.reset()
        XCTAssertFalse(gate.shouldPass(tone(0.001)))
    }
    func testThresholdCanRejectSoundThatPassedOldSetting(){
        let gate=NearSpeechGate();gate.setThresholdDB(-36)
        XCTAssertTrue(gate.shouldPass(tone(0.04)))
        gate.setThresholdDB(-28)
        XCTAssertFalse(gate.shouldPass(tone(0.04)))
        XCTAssertTrue(gate.shouldPass(tone(0.12)))
        gate.setThresholdDB(-18)
        XCTAssertFalse(gate.shouldPass(tone(0.12)))
    }
    func testBriefLoudClickDoesNotOpenGate(){
        let gate=NearSpeechGate()
        var samples=Array(repeating:Int16(0),count:1280)
        for i in 0..<160{samples[i]=i%2==0 ? 30000:-30000}
        let click=samples.withUnsafeBytes{Data($0)}
        XCTAssertFalse(gate.shouldPass(click))
        XCTAssertFalse(gate.shouldPass(tone(0.008)))
    }
    func testSustainedOnsetAcrossPacketBoundaryPasses(){
        let gate=NearSpeechGate()
        var before=Array(repeating:Int16(0),count:1280),after=before
        for i in 960..<1280{before[i]=4000}
        for i in 0..<320{after[i]=4000}
        XCTAssertTrue(gate.shouldPass(before.withUnsafeBytes{Data($0)},upcoming:[after.withUnsafeBytes{Data($0)}]))
    }
    func testInvalidThresholdIsBoundedAndMeterUsesActualInput(){
        let gate=NearSpeechGate();gate.setThresholdDB(.nan)
        XCTAssertEqual(gate.observation.thresholdDB,-28)
        gate.setThresholdDB(100);XCTAssertEqual(gate.observation.thresholdDB,-12)
        gate.setThresholdDB(-200);XCTAssertEqual(gate.observation.thresholdDB,-50)
        XCTAssertTrue(gate.shouldPass(tone(0.08)))
        XCTAssertEqual(gate.observation.rmsDB,-24.95,accuracy:0.15)
        XCTAssertTrue(gate.observation.isPassing)
    }
}
