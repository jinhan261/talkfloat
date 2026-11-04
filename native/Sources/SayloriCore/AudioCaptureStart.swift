import Foundation

/// Resolve startup once, including when HAL returns after cancellation or timeout.
final class AudioCaptureStart: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let completed = lock.withLock { () -> Result<Void, Error>? in
                if let result { return result }
                precondition(waiter == nil, "A capture startup has only one waiter")
                waiter = continuation; return nil
            }
            if let completed { continuation.resume(with: completed) }
        }
    }
    @discardableResult func resolve(_ value: Result<Void, Error>) -> Bool {
        let delivery = lock.withLock { () -> (Bool, CheckedContinuation<Void, Error>?) in
            guard result == nil else { return (false, nil) }
            result = value; let pending = waiter; waiter = nil
            return (true, pending)
        }
        delivery.1?.resume(with: value)
        return delivery.0
    }
}
