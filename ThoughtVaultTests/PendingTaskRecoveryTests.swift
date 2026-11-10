import XCTest
@testable import ThoughtVault

final class PendingTaskRecoveryTests: XCTestCase {
    private func task(_ id: String, _ status: TaskStatus) -> TranscriptTask {
        TranscriptTask(taskId: id, status: status)
    }

    func testTerminalTasksAreNotResumed() {
        let tasks = [task("a", .completed), task("b", .error), task("c", .transcribing)]
        XCTAssertEqual(RecordingViewModel.tasksToResume(tasks).map(\.taskId), ["c"])
    }

    func testEveryActiveStatusIsResumed() {
        let active: [TaskStatus] = [.pending, .uploading, .downloading, .converting, .transcribing,
                                    .transcribed, .queued, .processingWebhook, .generatingLocal]
        let tasks = active.enumerated().map { task("t\($0.offset)", $0.element) }
        XCTAssertEqual(RecordingViewModel.tasksToResume(tasks).count, active.count)
    }

    func testDuplicateTaskIdsResumeOnce() {
        let tasks = [task("a", .queued), task("a", .transcribing), task("b", .queued)]
        let result = RecordingViewModel.tasksToResume(tasks)
        XCTAssertEqual(result.map(\.taskId), ["a", "b"])
        XCTAssertEqual(result.first?.status, .queued, "first occurrence wins")
    }

    func testOrderIsKept() {
        let tasks = [task("z", .queued), task("m", .completed), task("a", .pending)]
        XCTAssertEqual(RecordingViewModel.tasksToResume(tasks).map(\.taskId), ["z", "a"])
    }

    // Ported from windows uploadAndTrack.terminal.test.ts: failed/cancelled/error are terminal.
    func testServerFailedAndCancelledStatusesAreTerminal() throws {
        let json = #"[{"task_id":"f","status":"failed"},{"task_id":"c","status":"cancelled"},{"task_id":"e","status":"error"},{"task_id":"ok","status":"queued"}]"#
        let tasks = try JSONDecoder().decode([TranscriptTask].self, from: Data(json.utf8))
        XCTAssertEqual(RecordingViewModel.tasksToResume(tasks).map(\.taskId), ["ok"])
    }
}
