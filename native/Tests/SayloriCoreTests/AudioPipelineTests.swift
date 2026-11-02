import XCTest
@testable import SayloriCore

private actor RecordingSender:AudioSending {
    enum Failure:Error{case disconnected}
    private(set) var packets:[Data]=[]
    private var failNext=false
    func rejectNext(){failNext=true}
    func send(_ audio:Data) async throws {
        if failNext{failNext=false;throw Failure.disconnected}
        packets.append(audio)
    }
}

private final class TestClock:@unchecked Sendable {
    private let lock=NSLock()
    private var value:Double
    init(_ value:Double){self.value=value}
    func read()->Double{lock.withLock{value}}
    func set(_ value:Double){lock.withLock{self.value=value}}
}

final class AudioRelayTests:XCTestCase {
    func testPreauthenticationAudioIsDiscardedRatherThanReplayed() async throws {
        let sender=RecordingSender(),clock=TestClock(10)
        let relay=AudioRelay(service:sender,uptime:{clock.read()})
        let dropped=try await relay.forward(AudioPacket(data:Data(count:2560),queuedAt:1))
        XCTAssertNil(dropped)
        await relay.enable()
        let sent=try await relay.forward(AudioPacket(data:Data(repeating:1,count:2560),queuedAt:9.9))
        let packets=await sender.packets
        XCTAssertEqual(packets.count,1)
        XCTAssertEqual(sent?.audioEndMS,80)
        XCTAssertEqual(try XCTUnwrap(sent).streamStartedUptime,9.82,accuracy:0.001)
    }
    func testStalePacketFailsBeforeItReachesTransport() async throws {
        let sender=RecordingSender(),relay=AudioRelay(service:sender,uptime:{0.4})
        await relay.enable()
        do{
            _ = try await relay.forward(AudioPacket(data:Data(count:2560),queuedAt:0))
            XCTFail("Stale audio must stop the route instead of adding latency")
        }catch{XCTAssertTrue(error.localizedDescription.contains("落后"))}
        let packets=await sender.packets
        XCTAssertTrue(packets.isEmpty)
    }
    func testAudioTimelineUsesPCMBytesInsteadOfNetworkJitter() async throws {
        let sender=RecordingSender(),clock=TestClock(2)
        let relay=AudioRelay(service:sender,uptime:{clock.read()})
        await relay.enable()
        let first=try await relay.forward(AudioPacket(data:Data(count:2560),queuedAt:1.9))
        clock.set(2.25)
        let second=try await relay.forward(AudioPacket(data:Data(count:1280),queuedAt:2.1))
        XCTAssertEqual(first?.audioEndMS,80)
        XCTAssertEqual(second?.audioEndMS,120)
        XCTAssertEqual(first?.streamStartedUptime,second?.streamStartedUptime)
        XCTAssertEqual(try XCTUnwrap(second).queueMS,150,accuracy:0.001)
    }
    func testFailedSendDoesNotAdvanceAudioClock() async throws {
        let sender=RecordingSender(),relay=AudioRelay(service:sender,uptime:{10})
        await relay.enable();await sender.rejectNext()
        do{
            _ = try await relay.forward(AudioPacket(data:Data(count:2560),queuedAt:9.8))
            XCTFail("Expected a transport failure")
        }catch{}
        let result=try await relay.forward(AudioPacket(data:Data(count:2560),queuedAt:9.9))
        XCTAssertEqual(result?.audioEndMS,80)
        XCTAssertEqual(try XCTUnwrap(result).streamStartedUptime,9.82,accuracy:0.001)
    }
}

final class MicrophonePacketProcessorTests:XCTestCase {
    private func packet(_ amplitude:Int16,_ time:Double)->AudioPacket{
        let samples=Array(repeating:amplitude,count:1280)
        return AudioPacket(data:samples.withUnsafeBytes{Data($0)},queuedAt:time)
    }
    func testTwoPacketBufferPreservesOrderAndFlushesOnlyOnce(){
        let gate=NearSpeechGate();gate.setEnabled(false)
        var processor=MicrophonePacketProcessor(gate:gate)
        XCTAssertNil(processor.append(packet(100,1)))
        XCTAssertNil(processor.append(packet(200,2)))
        XCTAssertEqual(processor.append(packet(300,3))?.queuedAt,1)
        XCTAssertEqual(processor.append(packet(400,4))?.queuedAt,2)
        XCTAssertEqual(processor.finish().map(\.queuedAt),[3,4])
        XCTAssertTrue(processor.finish().isEmpty)
    }
    func testMutedPacketsKeepLengthAndClockWhileEchoProcessorStillRuns(){
        let gate=NearSpeechGate(),calls=TestClock(0)
        var processor=MicrophonePacketProcessor(gate:gate,transform:{packet in
            calls.set(calls.read()+1)
            return packet
        })
        let input=packet(30,1)
        XCTAssertNil(processor.append(input))
        let output=processor.finish()
        XCTAssertEqual(calls.read(),1)
        XCTAssertEqual(output.first?.data,Data(count:input.data.count))
        XCTAssertEqual(output.first?.queuedAt,input.queuedAt)
    }
    func testLookaheadKeepsQuietOnsetAndFinalBufferedSpeech(){
        var processor=MicrophonePacketProcessor(gate:NearSpeechGate())
        let onset=packet(30,1),middle=packet(50,2),speech=packet(4000,3)
        XCTAssertNil(processor.append(onset));XCTAssertNil(processor.append(middle))
        XCTAssertEqual(processor.append(speech)?.data,onset.data)
        XCTAssertEqual(processor.finish().map(\.data),[middle.data,speech.data])
    }
    func testShortStreamRetainsAvailableLookaheadAtShutdown(){
        var processor=MicrophonePacketProcessor(gate:NearSpeechGate())
        let onset=packet(30,1),speech=packet(4000,2)
        XCTAssertNil(processor.append(onset));XCTAssertNil(processor.append(speech))
        XCTAssertEqual(processor.finish().map(\.data),[onset.data,speech.data])
    }
}
