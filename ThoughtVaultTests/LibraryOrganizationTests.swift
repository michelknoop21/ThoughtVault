import XCTest
import SwiftData
@testable import ThoughtVault

@MainActor
final class LibraryOrganizationTests: XCTestCase {
    private func fixture() throws -> (LocalTranscriptStore, LibraryOrganization, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "library-test-\(UUID().uuidString)")
        let library = LibraryOrganization(url: directory.appending(path: "library.json"))
        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (LocalTranscriptStore(container: container, library: library), library, directory)
    }

    func testFoldersBulkMovesDeletionAndRestart() throws {
        let (store, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = LibraryEntry(name: "Werk", kind: "folder")
        try library.save(folder)
        for id in ["a", "b"] { try store.save(TranscriptRecord(id: id, title: id, notuleHtml: "<p>Bewaren</p>", tags: ["Bestaand"], localAudioPath: "/audio.wav")) }
        try store.move(taskIDs: ["a", "b"], to: folder.id)
        XCTAssertTrue(store.allRecords().allSatisfy { $0.organization.folderID == folder.id })
        XCTAssertThrowsError(try store.move(taskIDs: ["a", "missing"], to: nil))
        XCTAssertEqual(store.record(forTaskId: "a")?.organization.folderID, folder.id)
        var renamed = folder; renamed.name = "Project"
        try library.save(renamed)
        let reopened = LibraryOrganization(url: directory.appending(path: "library.json"))
        XCTAssertEqual(reopened.folders.first?.name, "Project")
        try library.remove(renamed)
        for record in store.allRecords() {
            XCTAssertTrue(library.matches("unfiled", folderID: record.organization.folderID, tags: record.tags))
            XCTAssertEqual(record.notuleHtml, "<p>Bewaren</p>")
            XCTAssertEqual(record.localAudioPath, "/audio.wav")
            XCTAssertEqual(record.tags, ["Bestaand"])
        }
    }

    func testSmartFoldersAndManualCorrections() throws {
        let (store, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var label = LibraryEntry(name: "Project", kind: "label"); label.automatic = true
        try library.save(label)
        let eligible = library.labels
        let savedLabel = try XCTUnwrap(eligible.first)
        try store.save(TranscriptRecord(id: "a", title: "Overleg", notuleHtml: "<p>Inhoud</p>", tags: ["Handmatig"]))
        try store.saveAutomaticLabels(taskId: "a", chosen: eligible, eligible: eligible)
        XCTAssertEqual(store.record(forTaskId: "a")?.tags, ["Handmatig", "Project"])
        var smart = LibraryEntry(name: "Slim", kind: "smart"); smart.labelIDs = [savedLabel.id]
        try library.save(smart)
        XCTAssertTrue(library.matches(smart.id, folderID: nil, tags: ["Project"]))
        XCTAssertFalse(library.matches(smart.id, folderID: nil, tags: []))
        try store.updateTags(taskId: "a", tags: ["Handmatig"])
        try store.saveAutomaticLabels(taskId: "a", chosen: eligible, eligible: eligible)
        XCTAssertEqual(store.record(forTaskId: "a")?.tags, ["Handmatig"])
        try store.updateTags(taskId: "a", tags: ["Handmatig", "Project"])
        try store.saveAutomaticLabels(taskId: "a", chosen: [], eligible: eligible)
        XCTAssertEqual(store.record(forTaskId: "a")?.tags, ["Handmatig", "Project"])
        XCTAssertEqual(store.record(forTaskId: "a")?.organization.suppressedLabelIDs, [])
        XCTAssertEqual(try AutomaticLabels.parse("[]", allowed: eligible), [])
        XCTAssertThrowsError(try AutomaticLabels.parse("[\"invented\"]", allowed: eligible))
        XCTAssertThrowsError(try AutomaticLabels.parse("{}", allowed: eligible))
    }

    func testCatalogSyncMergesConcurrentEditsAndKeepsDeletion() throws {
        let (_, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = LibraryEntry(name: "Werk", kind: "folder")
        try library.save(folder)
        let remote = LibraryEntry(name: "Ander apparaat", kind: "folder")
        try library.merge([remote])
        XCTAssertEqual(library.folders.count, 2)
        let stale = library.entries
        try library.remove(folder)
        try library.merge(stale)
        XCTAssertEqual(library.folders.map(\.id), [remote.id])
        let payload = SyncedNotule.library(library.entries)
        let decoded = try JSONDecoder().decode(SyncedNotule.self, from: payload.encoded())
        XCTAssertEqual(decoded.libraryEntries, library.entries.sorted { $0.id < $1.id })
        XCTAssertEqual(try payload.digest(), try SyncedNotule.library(library.entries).digest())
    }

    func testOldSyncPayloadKeepsOrganizationAndConflictCopyCarriesIt() throws {
        let (store, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = TranscriptRecord(id: "a", title: "Voor")
        record.organization = NoteOrganization(folderID: "folder", automaticLabelIDs: ["label"], suppressedLabelIDs: ["removed"])
        try store.save(record)
        var old = SyncedNotule(record)
        old.organizationJSON = nil
        old.title = "Oud apparaat"
        try store.applySyncedNotule(old, preservingLocalConflict: true)
        XCTAssertEqual(record.organization.folderID, "folder")
        XCTAssertEqual(record.organization.suppressedLabelIDs, ["removed"])
        let conflict = try XCTUnwrap(store.allRecords().first { $0.id.hasPrefix("conflict-") })
        XCTAssertEqual(conflict.organization, record.organization)
        var updated = SyncedNotule(record)
        updated.organizationJSON = "{\"automaticLabelIDs\":[],\"suppressedLabelIDs\":[]}"
        try store.applySyncedNotule(updated, preservingLocalConflict: false)
        XCTAssertNil(record.organization.folderID)
    }

    func testFailedCatalogWriteKeepsMemoryAndCorruptFileIsNotOverwritten() throws {
        let (_, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try library.save(LibraryEntry(name: "Bewaren", kind: "folder"))
        let before = library.entries
        let file = directory.appending(path: "library.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.save(LibraryEntry(name: "Mislukt", kind: "folder")))
        XCTAssertEqual(library.entries, before)
        try FileManager.default.removeItem(at: file)
        try Data("invalid".utf8).write(to: file)
        let corrupt = LibraryOrganization(url: file)
        XCTAssertNotNil(corrupt.error)
        XCTAssertThrowsError(try corrupt.save(LibraryEntry(name: "Niet overschrijven", kind: "folder")))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "invalid")
    }
}

private enum OrganizationLegacySchema {
@Model
final class TranscriptRecord {

    /// Stable local identifier (also used as the task id for locally processed items).
    @Attribute(.unique) var id: String
    var taskId: String
    var title: String
    var filename: String
    var rawTranscription: String
    var notuleHtml: String
    var profileId: String
    var profileName: String?
    var tags: [String]
    var createdAt: Date
    var localAudioPath: String?
    /// "local" for on-device processed records, "cloud" for server-synced records.
    var source: String
    /// JSON-encoded [Participant] captured at record time, so local notule
    /// regeneration (other profile) can re-inject the deelnemerslijst. Optional →
    /// lightweight-migration safe for existing stores.
    var participantsJSON: String?
    /// A generated notule that failed the fact audit, kept apart from `notuleHtml`
    /// for manual review. Optional → lightweight-migration safe.
    var notuleDraftHtml: String?
    /// Why that draft was not approved (Dutch, shown to the user).
    var notuleReviewReason: String?
    /// Audio length in seconds, set on record/import. Optional → lightweight-migration safe.
    var durationSeconds: Double?
    /// JSON-encoded `NotuleUsage` of the run that generated `notuleHtml`. Optional → lightweight-migration safe.
    var notuleUsageJSON: String?

    init(
        id: String = UUID().uuidString,
        taskId: String = "",
        title: String,
        filename: String = "",
        rawTranscription: String = "",
        notuleHtml: String = "",
        profileId: String = "",
        profileName: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        localAudioPath: String? = nil,
        source: String = "local",
        participantsJSON: String? = nil
    ) {
        self.id = id
        self.taskId = taskId.isEmpty ? id : taskId
        self.title = title
        self.filename = filename
        self.rawTranscription = rawTranscription
        self.notuleHtml = notuleHtml
        self.profileId = profileId
        self.profileName = profileName
        self.tags = tags
        self.createdAt = createdAt
        self.localAudioPath = localAudioPath
        self.source = source
        self.participantsJSON = participantsJSON
    }

}
}

@MainActor
extension LibraryOrganizationTests {
    func testRealOnDiskMigrationFromPreviousTranscriptSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "library-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Local.store")
        do {
            let old = try ModelContainer(for: OrganizationLegacySchema.TranscriptRecord.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let record = OrganizationLegacySchema.TranscriptRecord(id: "legacy", title: "Bestaand", rawTranscription: "Gesprek", notuleHtml: "<p>Notule</p>", tags: ["Label"], localAudioPath: "/audio.wav")
            old.mainContext.insert(record)
            try old.mainContext.save()
        }
        do {
            let migrated = try ModelContainer(for: TranscriptRecord.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let record = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<TranscriptRecord>()).first)
            XCTAssertEqual(record.id, "legacy")
            XCTAssertEqual(record.rawTranscription, "Gesprek")
            XCTAssertEqual(record.notuleHtml, "<p>Notule</p>")
            XCTAssertEqual(record.tags, ["Label"])
            XCTAssertEqual(record.localAudioPath, "/audio.wav")
            XCTAssertNil(record.organizationJSON)
            record.organization = NoteOrganization(folderID: "folder")
            try migrated.mainContext.save()
        }
        let restarted = try ModelContainer(for: TranscriptRecord.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        XCTAssertEqual(try restarted.mainContext.fetch(FetchDescriptor<TranscriptRecord>()).first?.organization.folderID, "folder")
    }
}

private actor LabelProvider: LLMService {
    var output: String
    var fail: Bool
    init(output: String, fail: Bool = false) { self.output = output; self.fail = fail }
    var isAvailable: Bool { true }
    func generateNotulen(transcription: String, systemPrompt: String, notulePrompt: String, outputTemplate: String?, constraints: [String], onProgress: @Sendable (String) -> Void) async throws -> String { output }
    func complete(system: String, user: String) async throws -> String {
        if fail { throw LLMError.providerUnavailable }
        return output
    }
}

@MainActor
extension LibraryOrganizationTests {
    func testProviderFailureAndRetryPreserveContent() async throws {
        let (store, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var label = LibraryEntry(name: "Project", kind: "label"); label.automatic = true
        try library.save(label)
        let note = TranscriptRecord(id: "a", title: "Overleg", notuleHtml: "<p>Inhoud</p>", tags: ["Handmatig"])
        try store.save(note)
        let job = AutomaticLabels()
        await job.run(taskIDs: ["a"], store: store, library: library, service: LabelProvider(output: "", fail: true))
        XCTAssertNotNil(note.autoLabelError)
        XCTAssertEqual(note.notuleHtml, "<p>Inhoud</p>")
        XCTAssertEqual(note.tags, ["Handmatig"])
        let id = try XCTUnwrap(library.labels.first?.id)
        await job.run(taskIDs: ["a"], store: store, library: library, service: LabelProvider(output: "[\"\(id)\"]"))
        XCTAssertNil(note.autoLabelError)
        XCTAssertEqual(note.tags, ["Handmatig", "Project"])
        XCTAssertEqual(job.completed, 1)
        XCTAssertFalse(job.busy)
    }
}

@MainActor
extension LibraryOrganizationTests {
    func testFailedNoteSaveRollsBackMove() throws {
        let (_, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try library.save(LibraryEntry(name: "Map", kind: "folder"))
        let folder = try XCTUnwrap(library.folders.first)
        let url = directory.appending(path: "readonly.store")
        do {
            let container = try ModelContainer(for: TranscriptRecord.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            container.mainContext.insert(TranscriptRecord(id: "a", title: "Bewaren", notuleHtml: "<p>Inhoud</p>", tags: ["Handmatig"]))
            try container.mainContext.save()
        }
        let container = try ModelContainer(for: TranscriptRecord.self,
            configurations: ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none))
        let store = LocalTranscriptStore(container: container, library: library)
        XCTAssertThrowsError(try store.move(taskIDs: ["a"], to: folder.id))
        XCTAssertNil(store.record(forTaskId: "a")?.organization.folderID)
        XCTAssertEqual(store.record(forTaskId: "a")?.notuleHtml, "<p>Inhoud</p>")
        XCTAssertEqual(store.record(forTaskId: "a")?.tags, ["Handmatig"])
    }
}

private actor PausingLabelProvider: LLMService {
    let output: String
    var calls = 0
    var response: CheckedContinuation<String, Never>?
    init(output: String) { self.output = output }
    var isAvailable: Bool { true }
    func generateNotulen(transcription: String, systemPrompt: String, notulePrompt: String, outputTemplate: String?, constraints: [String], onProgress: @Sendable (String) -> Void) async throws -> String { output }
    func complete(system: String, user: String) async throws -> String {
        calls += 1
        if calls == 1 { return output }
        return await withCheckedContinuation { response = $0 }
    }
    func waitUntilSuspended() async { while response == nil { await Task.yield() } }
    func finish() { response?.resume(returning: output); response = nil }
}

@MainActor
extension LibraryOrganizationTests {
    func testCancellationRetainsCompletedResultsAndDiscardsInFlightResult() async throws {
        let (store, library, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var label = LibraryEntry(name: "Project", kind: "label"); label.automatic = true
        try library.save(label)
        for id in ["a", "b"] { try store.save(TranscriptRecord(id: id, title: id, notuleHtml: "<p>Inhoud</p>", tags: ["Handmatig"])) }
        let id = try XCTUnwrap(library.labels.first?.id)
        let provider = PausingLabelProvider(output: "[\"\(id)\"]")
        let job = AutomaticLabels()
        let task = Task { await job.run(taskIDs: ["a", "b"], store: store, library: library, service: provider) }
        await provider.waitUntilSuspended()
        job.cancel()
        await provider.finish()
        await task.value
        XCTAssertEqual(store.record(forTaskId: "a")?.tags, ["Handmatig", "Project"])
        XCTAssertEqual(store.record(forTaskId: "b")?.tags, ["Handmatig"])
        XCTAssertFalse(job.busy)
    }
}

@MainActor
extension LibraryOrganizationTests {
    func testMissingCatalogDoesNotQueueCloudDeletion() throws {
        var state = NotuleSyncState()
        let catalog = SyncedNotule.library([LibraryEntry(name: "Bewaren", kind: "folder")])
        try state.reconcile([catalog])
        state.acknowledged(id: catalog.id, digest: try catalog.digest(), fields: nil)
        XCTAssertThrowsError(try state.reconcile([]))
        XCTAssertEqual(state.entries[catalog.id]?.digest, try catalog.digest())
        XCTAssertEqual(state.entries[catalog.id]?.pending, false)
    }
}
