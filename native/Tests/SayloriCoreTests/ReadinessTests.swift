import XCTest
@testable import SayloriCore

final class ReadinessTests:XCTestCase {
    func testSilenceDoesNotClaimPermissionDenied(){
        let silent=AudioProbeResult(bytes:32_000,peak:0)
        XCTAssertEqual(silent.outcome,.silent)
        XCTAssertFalse(silent.message.contains("权限"))
        XCTAssertEqual(AudioProbeResult(bytes:0,peak:0).outcome,.noFrames)
        XCTAssertEqual(AudioProbeResult(bytes:32_000,peak:0.02).outcome,.audible)
    }
    func testEveryUnfinishedOperationBlocksInstallation(){
        XCTAssertTrue(UpdateSafety.canInstall(active:false,hasMeeting:false,preparingModels:false,setupBusy:false,hasSaveError:false))
        for blocked in 0..<6 {
            let state=(0..<6).map{$0==blocked}
            XCTAssertFalse(UpdateSafety.canInstall(active:state[0],hasMeeting:state[1],preparingModels:state[2],setupBusy:state[3],hasSaveError:state[4],editingSettings:state[5]),"Unfinished operation \(blocked) must block installation")
        }
    }
    func testSampleRequiresEveryStatementAndFinalTranslations(){
        var items=["The meeting starts on Tuesday at ten.","The budget is three thousand dollars.","Send the proposal on Friday."].enumerated().map{index,text in
            var item=CaptionSegment(sessionID:"sample",startMS:index*1000)
            item.source=text;item.translation="测试译文";item.sourceFinal=true;item.translationFinal=true;return item
        }
        XCTAssertTrue(SampleCoverage.isComplete(items))
        XCTAssertFalse(SampleCoverage.isComplete(Array(items.prefix(2))))
        items[2].translation=""
        XCTAssertFalse(SampleCoverage.isComplete(items))
        items[2].translation="测试译文";items[2].translationFinal=false
        XCTAssertFalse(SampleCoverage.isComplete(items))
    }
}
