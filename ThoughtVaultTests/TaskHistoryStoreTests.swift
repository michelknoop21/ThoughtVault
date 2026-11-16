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

    // MARK: - Review findings

    func testCorruptFileIsMovedAsideAndHistoryStartsEmpty() throws {
        let garbage = Data(#"[{"id":"local-1","title":"#.utf8)
        try garbage.write(to: url)
        let store = TaskHistoryStore(url: url)
        XCTAssertTrue(store.entries.isEmpty)
        store.track(task(status: .transcribing), context: context)
        XCTAssertNotNil(TaskHistoryStore(url: url).entry("local-1"))

        let siblings = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let aside = try XCTUnwrap(siblings.first { $0.lastPathComponent.hasPrefix(url.deletingPathExtension().lastPathComponent + ".corrupt-") })
        defer { try? FileManager.default.removeItem(at: aside) }
        XCTAssertEqual(try Data(contentsOf: aside), garbage)
    }

    func testNewRunUnderSameIdTakesOnlyItsOwnTitle() {
        let store = TaskHistoryStore(url: url)
        let regen = "local-regen-local-1"
        store.carryTitle("Eerste", to: "local-1")
        store.track(task(regen, status: .generatingLocal), context: context)
        store.track(task(regen, status: .completed), context: context)

        store.carryTitle("Tweede", to: "local-1")
        store.track(task(regen, status: .generatingLocal), context: context)
        XCTAssertEqual(store.entry(regen)?.title, "Tweede")
        store.track(task(regen, status: .completed), context: context)

        // A run without a chosen title must not write an earlier run's title over the notule.
        store.track(task(regen, status: .generatingLocal), context: context)
        XCTAssertEqual(store.entry(regen)?.titleEdited, false)
    }

    func testDeletingASharedRecordingMarksEveryEntryThatUsesIt() throws {
        let audio = FileManager.default.temporaryDirectory.appending(path: "shared-\(UUID().uuidString).wav")
        try Data([1]).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        let store = TaskHistoryStore.shared
        let ids = ["local-shared-\(UUID().uuidString)", "local-shared-\(UUID().uuidString)"]
        defer { ids.forEach(store.remove) }
        for id in ids {
            store.track(TranscriptTask(id: id, taskId: id, filename: "x.wav", status: .completed, localAudioPath: audio.path),
                        context: context)
        }

        RecordingViewModel().deleteHistoryRecording(try XCTUnwrap(store.entry(ids[0])))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertEqual(ids.map { store.entry($0)?.recordingDeleted }, [true, true])
    }

    func testOldRemovalTimerDoesNotRemoveANewRunUnderTheSameId() async throws {
        let vm = RecordingViewModel()
        let id = "local-regen-timer-\(UUID().uuidString)"
        defer { vm.removeTask(id); TaskHistoryStore.shared.remove(id) }
        let run = TranscriptTask(id: id, taskId: id, filename: "x", status: .generatingLocal, progress: 0.5)
        vm.addTask(run)
        vm.updateTask(id, status: .completed, progress: 1)  // schedules the removal of this run
        vm.removeTask(id)
        vm.addTask(run)  // the next run under the same id
        try await Task.sleep(for: .seconds(3.5))
        XCTAssertTrue(vm.activeTasks.contains { $0.taskId == id })
    }
}
