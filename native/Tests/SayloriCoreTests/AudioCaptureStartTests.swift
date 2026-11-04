import XCTest
@testable import SayloriCore

final class AudioCaptureStartTests: XCTestCase {
    func testCancellationBeforeHALReturnsRejectsLateSuccess() async {
        let start = AudioCaptureStart()
        XCTAssertTrue(start.resolve(.failure(CancellationError())))
        XCTAssertFalse(start.resolve(.success(())))
        do { try await start.wait(); XCTFail("Cancelled capture must not become live") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSuccessBeforeAwaitingIsDelivered() async throws {
        let start = AudioCaptureStart()
        XCTAssertTrue(start.resolve(.success(())))
        try await start.wait()
        XCTAssertFalse(start.resolve(.failure(CancellationError())))
    }

    func testConcurrentTimeoutAndHALReturnResolveExactlyOnce() async {
        for _ in 0..<100 {
            let start = AudioCaptureStart()
            let waiting = Task { try await start.wait() }
            async let success = Task.detached { start.resolve(.success(())) }.value
            async let cancel = Task.detached { start.resolve(.failure(CancellationError())) }.value
            let winners = await (success, cancel)
            XCTAssertNotEqual(winners.0, winners.1)
            _ = try? await waiting.value
        }
    }

    func testStopBeforeStartDoesNotOpenHAL() async {
        let capture = CoreAudioTap()
        capture.stop()
        do { try await capture.start(source: .system); XCTFail("Stopped capture must not open HAL") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
