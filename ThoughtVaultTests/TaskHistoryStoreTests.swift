import XCTest
@testable import ThoughtVault

@MainActor
final class TaskHistoryStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appending(path: "task-history-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private let context = TaskHistoryContext(transcriptionEngine: "Engine", notuleProvider: "Provider",
                                             notuleModel: "model-a", profileName: "Meeting")

    private func task(_ id: String = "local-1", status: TaskStatus, detail: String? = nil, error: String? = nil) -> TranscriptTask {
        var task = TranscriptTask(id: id, taskId: id, filename: "recording_1.wav", status: status, errorMessage: error,
                                  localAudioPath: "/tmp/recording_1.wav", profileId: "meeting",
                                  createdAt: Date(timeIntervalSince1970: 1_000))
        task.statusDetail = detail
        return task
    }

    func testPersistsStepsAndOutcomeAcrossReload() {
        let store = TaskHistoryStore(url: url)
        let t0 = Date(timeIntervalSince1970: 1_000)
        store.track(task(status: .transcribing), context: context, now: t0)
        store.track(task(status: .transcribing), context: context, now: t0.addingTimeInterval(5))  // progress only
        store.track(task(status: .generatingLocal, detail: "Concept schrijven"), context: context, now: t0.addingTimeInterval(60))
        store.track(task(status: .completed), context: context, now: t0.addingTimeInterval(90))

        let reloaded = TaskHistoryStore(url: url)
        let entry = try! XCTUnwrap(reloaded.entry("local-1"))
        XCTAssertEqual(entry.status, .completed)
        XCTAssertEqual(entry.steps.map(\.label), ["Transcriberen", "Concept schrijven"])
        XCTAssertEqual(entry.steps.map(\.duration), [60, 30])
        XCTAssertEqual(entry.totalDuration, 90)
        XCTAssertEqual(entry.notuleModel, "model-a")
        XCTAssertEqual(entry.profileName, "Meeting")
        XCTAssertEqual(entry.audioPath, "/tmp/recording_1.wav")
        XCTAssertEqual(entry.outcomeLabel, "Voltooid")
    }

    func testUpdateRemoveAndCancelledOutcome() {
        let store = TaskHistoryStore(url: url)
        store.track(task(status: .transcribing), context: context)
        store.track(task(status: .error, error: TaskHistoryEntry.cancelledMessage), context: context)
        XCTAssertEqual(store.entry("local-1")?.outcomeLabel, "Geannuleerd")

        store.update("local-1") { $0.title = "Nieuwe titel"; $0.recordingDeleted = true }
        XCTAssertEqual(TaskHistoryStore(url: url).entry("local-1")?.title, "Nieuwe titel")
        XCTAssertEqual(TaskHistoryStore(url: url).entry("local-1")?.recordingDeleted, true)

        store.remove("local-1")
        XCTAssertNil(TaskHistoryStore(url: url).entry("local-1"))
    }

    func testRegenerationLinksToNotuleAndTakesCarriedTitle() {
        let store = TaskHistoryStore(url: url)
        store.carryTitle("Eigen titel", to: "local-1")
        store.track(task("local-regen-local-1", status: .generatingLocal), context: context)
        let entry = try! XCTUnwrap(store.entry("local-regen-local-1"))
        XCTAssertEqual(entry.transcriptId, "local-1")
        XCTAssertEqual(entry.title, "Eigen titel")
        XCTAssertTrue(entry.titleEdited)
    }

    func testRetryUnderSameIdReopensFinishedEntry() {
        let store = TaskHistoryStore(url: url)
        store.track(task(status: .error, error: "Mislukt"), context: context)
        XCTAssertNotNil(store.entry("local-1")?.finishedAt)
        store.track(task(status: .transcribing), context: context)
        XCTAssertNil(store.entry("local-1")?.finishedAt)
        XCTAssertNil(store.entry("local-1")?.errorMessage)
    }
}
