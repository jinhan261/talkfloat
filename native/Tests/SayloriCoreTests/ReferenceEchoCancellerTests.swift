import XCTest
@testable import SayloriCore

final class ReferenceEchoCancellerTests:XCTestCase {
    func testReferenceEchoReductionAndIndependentDoubleTalk(){
        runFixture(delay:640)
    }
    func testDifferentCaptureClocksStillCancelEcho(){
        runFixture(delay:-512)
    }
    private func runFixture(delay:Int){
        let canceller=ReferenceEchoCanceller()
        var seed:UInt64=42
        let far=(0..<322560).map { _ -> Int16 in
            seed=seed &* 6364136223846793005 &+ 1
            return Int16(Int((seed>>32)%12001)-6000)
        }
        var echoIn=0.0,echoOut=0.0,nearOut=0.0,nearExpected=0.0
        for frame in 0..<250 {
            let index=frame*1280,end=10+Double(index+1280)/16000
            let ref=Array(far[index..<index+1280])
            if frame==0{canceller.observeSystem(ref.withUnsafeBytes{Data($0)},end:end)}
            let nextRef=Array(far[index+1280..<index+2560])
            let mic=(0..<1280).map { i -> Int16 in
                let delayed=index+i-delay
                let echo=delayed>=0 ? Double(far[delayed])*0.4:0
                let t=Double(index+i)/16000
                let near=frame>=180 ? 3000*sin(t*1400)*(0.6+0.4*sin(t*17)):0
                return Int16(echo+near)
            }
            canceller.observeSystem(nextRef.withUnsafeBytes{Data($0)},end:end+0.08)
            let result=canceller.process(AudioPacket(data:mic.withUnsafeBytes{Data($0)},queuedAt:end))
            let outputEnergy=result.data.withUnsafeBytes { p -> Double in
                var e=0.0
                for i in stride(from:0,to:p.count,by:2){let v=Double(p.loadUnaligned(fromByteOffset:i,as:Int16.self));e+=v*v}
                return e
            }
            if (120..<170).contains(frame){echoIn+=mic.reduce(0){$0+Double($1)*Double($1)};echoOut+=outputEnergy}
            if frame>=200{nearOut+=outputEnergy;nearExpected+=Double(1280)*3000*3000*0.22}
        }
        print("AEC fixture: echo attenuation=\(10*log10(echoIn/max(1,echoOut))) dB; double-talk energy=\(nearOut/nearExpected)")
        XCTAssertGreaterThan(10*log10(echoIn/max(1,echoOut)),15)
        XCTAssertGreaterThan(nearOut/nearExpected,0.25,"Independent near-end speech must survive simultaneous playback")
    }
}
