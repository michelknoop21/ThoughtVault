import XCTest
@testable import ThoughtVault

@MainActor
final class ContinuedProcessingTests: XCTestCase {

    private final class FakeTask: ContinuedTask {
        var reports: [(fraction: Double, subtitle: String)] = []
        var completions: [Bool] = []
        func report(fraction: Double, subtitle: String) { reports.append((fraction, subtitle)) }
        func complete(success: Bool) { completions.append(success) }
    }

    private final class FakeScheduler: ContinuedTaskScheduler {
        struct Refused: Error {}
        var refuse = false
        var titles: [String] = []
        var onStart: [String: @MainActor (any ContinuedTask) -> Void] = [:]
        var onExpire: [String: @MainActor () -> Void] = [:]
        func submit(id: String, title: String, subtitle: String,
                    onStart: @escaping @MainActor (any ContinuedTask) -> Void,
                    onExpire: @escaping @MainActor () -> Void) async throws {
            if refuse { throw Refused() }
            titles.append(title)
            self.onStart[id] = onStart
            self.onExpire[id] = onExpire
        }
    }

    // MARK: Progress mapping

    func testPhasesMapToRisingBands() {
        XCTAssertEqual(ContinuedPhase.waiting.band.fraction, 0)
        XCTAssertEqual(ContinuedPhase.transcribing(0).band.fraction, 0.02, accuracy: 1e-9)
        XCTAssertEqual(ContinuedPhase.transcribing(0.5).band.fraction, 0.31, accuracy: 1e-9)
        XCTAssertEqual(ContinuedPhase.transcribing(1).band.fraction, 0.6, accuracy: 1e-9)
        XCTAssertEqual(ContinuedPhase.transcribing(7).band.fraction, 0.6, accuracy: 1e-9)  // clamped
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.draft)).band.fraction, 0.6)
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.draft)).band.ceiling, 0.75)
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.sourceCheck)).band.fraction, 0.75)
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.coverage, 0, of: 4)).band.fraction, 0.82, accuracy: 1e-9)
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.coverage, 2, of: 4)).band.fraction, 0.86, accuracy: 1e-9)
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.sentenceCheck, 61, of: 61)).band.fraction, 0.98, accuracy: 1e-9)
    }

    func testSubtitleNamesTheStep() {
        XCTAssertTrue(ContinuedPhase.transcribing(0.4).subtitle.contains("40"))
        XCTAssertEqual(ContinuedPhase.notule(ModelStep(.draft)).subtitle, ModelStep(.draft).displayLabel)
    }

    // MARK: Run to task

    func testAcceptedRunReportsProgressAndCompletes() async {
        let scheduler = FakeScheduler()
        let continued = ContinuedProcessing(scheduler: scheduler)
        continued.track(runId: "r1") {}
        XCTAssertTrue(continued.needsAppOpen)
        await continued.submit(runId: "r1")
        XCTAssertFalse(continued.needsAppOpen)
        XCTAssertEqual(scheduler.titles.count, 1)

        let task = FakeTask()
        scheduler.onStart["r1"]?(task)
        continued.update(runId: "r1", phase: .transcribing(0.5))
        continued.update(runId: "r1", phase: .transcribing(0.2))  // never backwards
        XCTAssertEqual(task.reports.last?.fraction ?? 0, 0.31, accuracy: 1e-9)
        continued.update(runId: "r1", phase: .notule(ModelStep(.draft)))
        XCTAssertEqual(task.reports.last?.subtitle, ModelStep(.draft).displayLabel)

        continued.heartbeat()
        XCTAssertEqual(task.reports.last?.fraction ?? 0, 0.602, accuracy: 1e-9)

        continued.finish(runId: "r1", success: true)
        XCTAssertEqual(task.completions, [true])
        XCTAssertEqual(task.reports.last?.fraction, 1)
        XCTAssertTrue(continued.runIds.isEmpty)
        continued.finish(runId: "r1", success: false)  // second end is ignored
        XCTAssertEqual(task.completions, [true])
    }

    func testHeartbeatStopsAtPhaseCeiling() async {
        let scheduler = FakeScheduler()
        let continued = ContinuedProcessing(scheduler: scheduler)
        continued.track(runId: "r1") {}
        await continued.submit(runId: "r1")
        let task = FakeTask()
        scheduler.onStart["r1"]?(task)
        continued.update(runId: "r1", phase: .notule(ModelStep(.sourceCheck)))  // 0.75 ... 0.78
        for _ in 0..<100 { continued.heartbeat() }
        XCTAssertEqual(task.reports.last?.fraction ?? 0, 0.78, accuracy: 1e-9)
    }

    func testExpirationCancelsTheRunAndFailsTheTask() async {
        let scheduler = FakeScheduler()
        let continued = ContinuedProcessing(scheduler: scheduler)
        var cancelled = 0
        continued.track(runId: "r1") { cancelled += 1 }
        await continued.submit(runId: "r1")
        let task = FakeTask()
        scheduler.onStart["r1"]?(task)

        scheduler.onExpire["r1"]?()
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(task.completions, [false])
        XCTAssertTrue(continued.runIds.isEmpty)
        continued.finish(runId: "r1", success: false)  // the cancelled run's own failure
        XCTAssertEqual(task.completions, [false])
    }

    func testRefusedSubmitLeavesTheRunUncovered() async {
        let scheduler = FakeScheduler()
        scheduler.refuse = true
        let continued = ContinuedProcessing(scheduler: scheduler)
        continued.track(runId: "r1") {}
        await continued.submit(runId: "r1")
        XCTAssertTrue(continued.needsAppOpen)
        continued.finish(runId: "r1", success: true)
        XCTAssertFalse(continued.needsAppOpen)
    }

    func testNoSchedulerBelowIOS26KeepsTheAppOpenLine() async {
        let continued = ContinuedProcessing(scheduler: nil)
        continued.track(runId: "r1") {}
        await continued.submit(runId: "r1")
        XCTAssertTrue(continued.needsAppOpen)
        continued.finish(runId: "r1", success: false)
        XCTAssertFalse(continued.needsAppOpen)
    }

    func testQueuedTaskStartingAfterTheRunEndedCompletesAtOnce() async {
        let scheduler = FakeScheduler()
        let continued = ContinuedProcessing(scheduler: scheduler)
        continued.track(runId: "r1") {}
        await continued.submit(runId: "r1")
        continued.finish(runId: "r1", success: true)

        let task = FakeTask()
        scheduler.onStart["r1"]?(task)
        XCTAssertEqual(task.completions, [true])
    }

    func testFinishedRunIsNotSubmitted() async {
        let scheduler = FakeScheduler()
        let continued = ContinuedProcessing(scheduler: scheduler)
        continued.track(runId: "r1") {}
        continued.finish(runId: "r1", success: false)
        await continued.submit(runId: "r1")
        XCTAssertTrue(scheduler.titles.isEmpty)
    }
}
