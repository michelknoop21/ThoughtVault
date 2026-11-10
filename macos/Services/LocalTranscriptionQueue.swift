import Foundation

/// Runs on-device transcriptions one at a time, first in first out. Two jobs in
/// parallel would load the WhisperKit model twice, and `OnDeviceTranscriber`
/// keeps a single recognition task that a second job would cancel.
actor LocalTranscriptionQueue {
    static let shared = LocalTranscriptionQueue()

    private struct Waiter {
        let ticket: UInt64
        let id: String
        let continuation: CheckedContinuation<Void, Error>
    }

    /// Id of the job that holds the queue, nil when idle.
    private var running: String?
    /// Invariant: a continuation is resumed only by the code that removes it from
    /// `waiting` (`finish` or `cancelWaiter`). Both run on this actor, so each
    /// continuation is resumed exactly once and none is left behind.
    private var waiting: [Waiter] = []
    private var nextTicket: UInt64 = 0

    init() {}

    /// Runs `work` once every job enqueued before it has finished. `onWait` is
    /// called once, right after the job is queued, when it has to wait.
    /// Cancelling the caller while it waits throws `CancellationError` without
    /// running `work`; cancelling a running job is up to `work` itself.
    func run<T: Sendable>(
        id: String,
        onWait: @Sendable () -> Void = {},
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        if running == nil {
            running = id
        } else {
            try await waitForTurn(id: id, onWait: onWait)
        }
        defer { finish() }
        return try await work()
    }

    /// 0 = running, 1... = waiting, nil = unknown.
    func position(of id: String) -> Int? {
        if running == id { return 0 }
        return waiting.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    private func waitForTurn(id: String, onWait: @Sendable () -> Void) async throws {
        let ticket = nextTicket
        nextTicket += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Already cancelled: never queue, so cancelWaiter finds nothing.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.waiting.append(Waiter(ticket: ticket, id: id, continuation: continuation))
                onWait()
            }
        } onCancel: {
            Task { await self.cancelWaiter(ticket) }
        }
    }

    /// No-op when the waiter already got its turn (or was never queued).
    private func cancelWaiter(_ ticket: UInt64) {
        guard let index = waiting.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Hands the queue to the next waiter, or marks it idle.
    private func finish() {
        guard !waiting.isEmpty else {
            running = nil
            return
        }
        let next = waiting.removeFirst()
        running = next.id
        next.continuation.resume()
    }
}
