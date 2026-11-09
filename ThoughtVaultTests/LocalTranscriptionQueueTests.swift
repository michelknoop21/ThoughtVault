import XCTest
@testable import ThoughtVault

final class LocalTranscriptionQueueTests: XCTestCase {

    /// One-shot signal: `wait()` returns once `fire()` has been called, before or after.
    private final class Signal: Sendable {
        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation
        init() { (stream, continuation) = AsyncStream.makeStream(of: Void.self) }
        func fire() { continuation.yield() }
        func wait() async { for await _ in stream { return } }
    }

    private actor Log {
        var events: [String] = []
        func add(_ event: String) { events.append(event) }
    }

    private struct Boom: Error {}

    func testJobsRunOneAtATimeInFIFOOrder() async throws {
        let queue = LocalTranscriptionQueue()
        let log = Log()
        let aStarted = Signal(), releaseA = Signal(), bQueued = Signal(), cQueued = Signal()

        let a = Task {
            try await queue.run(id: "A") {
                await log.add("A-start"); aStarted.fire()
                await releaseA.wait()
                await log.add("A-end")
            }
        }
        await aStarted.wait()
        let b = Task {
            try await queue.run(id: "B", onWait: { bQueued.fire() }) {
                await log.add("B-start")
                try await Task.sleep(for: .milliseconds(50))
                await log.add("B-end")
            }
        }
        await bQueued.wait()
        let c = Task {
            try await queue.run(id: "C", onWait: { cQueued.fire() }) {
                await log.add("C-start")
                try await Task.sleep(for: .milliseconds(50))
                await log.add("C-end")
            }
        }
        await cQueued.wait()
        releaseA.fire()

        _ = try await (a.value, b.value, c.value)
        let events = await log.events
        XCTAssertEqual(events, ["A-start", "A-end", "B-start", "B-end", "C-start", "C-end"])
    }

    func testCancelledWaitingJobNeverRuns() async throws {
        let queue = LocalTranscriptionQueue()
        let log = Log()
        let aStarted = Signal(), releaseA = Signal(), bQueued = Signal(), cQueued = Signal()

        let a = Task {
            try await queue.run(id: "A") {
                aStarted.fire()
                await releaseA.wait()
                await log.add("A")
            }
        }
        await aStarted.wait()
        let b = Task {
            try await queue.run(id: "B", onWait: { bQueued.fire() }) { await log.add("B") }
        }
        await bQueued.wait()

        b.cancel()
        do {
            try await b.value
            XCTFail("Cancelled waiting job must throw")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let positionB = await queue.position(of: "B")
        XCTAssertNil(positionB)

        let c = Task {
            try await queue.run(id: "C", onWait: { cQueued.fire() }) { await log.add("C") }
        }
        await cQueued.wait()
        releaseA.fire()

        _ = try await (a.value, c.value)
        let events = await log.events
        XCTAssertEqual(events, ["A", "C"])
    }

    func testFailureReleasesQueue() async throws {
        let queue = LocalTranscriptionQueue()
        let aStarted = Signal(), releaseA = Signal(), bQueued = Signal()

        let a = Task {
            try await queue.run(id: "A") {
                aStarted.fire()
                await releaseA.wait()
                throw Boom()
            }
        }
        await aStarted.wait()
        let b = Task {
            try await queue.run(id: "B", onWait: { bQueued.fire() }) { 42 }
        }
        await bQueued.wait()
        releaseA.fire()

        do {
            try await a.value
            XCTFail("A must rethrow its error")
        } catch is Boom {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let bDone = expectation(description: "B runs after A failed")
        Task {
            let result = try? await b.value
            XCTAssertEqual(result, 42)
            bDone.fulfill()
        }
        await fulfillment(of: [bDone], timeout: 5)
    }

    func testPositionReportsWaiting() async throws {
        let queue = LocalTranscriptionQueue()
        let aStarted = Signal(), releaseA = Signal(), bQueued = Signal()

        let a = Task {
            try await queue.run(id: "A") {
                aStarted.fire()
                await releaseA.wait()
            }
        }
        await aStarted.wait()
        let b = Task {
            try await queue.run(id: "B", onWait: { bQueued.fire() }) {}
        }
        await bQueued.wait()

        let positionA = await queue.position(of: "A")
        let positionB = await queue.position(of: "B")
        let positionUnknown = await queue.position(of: "unknown")
        XCTAssertEqual(positionA, 0)
        XCTAssertEqual(positionB, 1)
        XCTAssertNil(positionUnknown)

        releaseA.fire()
        _ = try await (a.value, b.value)
        let positionAfter = await queue.position(of: "A")
        XCTAssertNil(positionAfter)
    }
}
