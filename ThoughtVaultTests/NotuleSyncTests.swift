import XCTest
import SwiftData
import CloudKit
@testable import ThoughtVault

@MainActor
final class NotuleSyncTests: XCTestCase {
    private func store() throws -> LocalTranscriptStore {
        try LocalTranscriptStore(container: ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
    }

    func testPortableContentRoundTripsWithoutAudioOrCredentials() throws {
        let local = TranscriptRecord(id: "note", title: "Overleg", rawTranscription: "Gesprek", notuleHtml: "<p>Besluit</p>",
                                     tags: ["project"], localAudioPath: "/private/recording.wav")
        local.notuleDraftHtml = "<p>Concept</p>"
        local.notuleReviewReason = "Controle nodig"
        local.durationSeconds = 5400
        local.notuleUsageJSON = "{}"
        let payload = SyncedNotule(local)
        let data = try payload.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("recording.wav"))
        let remote = try JSONDecoder().decode(SyncedNotule.self, from: data)
        let target = try store()
        try target.applySyncedNotule(remote, preservingLocalConflict: false)
        let copied = try XCTUnwrap(target.record(forTaskId: "note"))
        XCTAssertEqual(SyncedNotule(copied), payload)
        XCTAssertNil(copied.localAudioPath)
        copied.localAudioPath = "/this-device/audio.wav"
        try target.applySyncedNotule(remote, preservingLocalConflict: false)
        XCTAssertEqual(copied.localAudioPath, "/this-device/audio.wav")
    }

    func testOfflineQueueSurvivesRestartAndDelete() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)/state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let record = SyncedNotule(TranscriptRecord(id: "a", title: "Voor offline"))
        var state = NotuleSyncState()
        try state.bindAccount("account-a")
        try state.reconcile([record])
        try state.save(to: url)
        state = try NotuleSyncState.load(from: url)
        XCTAssertTrue(state.entries["a"]?.pending == true)
        state.acknowledged(id: "a", digest: try record.digest(), fields: Data([1]))
        XCTAssertFalse(state.entries["a"]!.pending)
        try state.reconcile([])
        try state.save(to: url)
        let restarted = try NotuleSyncState.load(from: url)
        XCTAssertTrue(restarted.entries["a"]!.pending)
        XCTAssertNil(restarted.entries["a"]!.digest)
        XCTAssertEqual(restarted.entries["a"]!.serverDigest, try record.digest())
        XCTAssertEqual(restarted.entries["a"]!.systemFields, Data([1]))
    }

    func testServerEchoDoesNotRevertOfflineEditOrResurrectDeletion() throws {
        var note = SyncedNotule(TranscriptRecord(id: "a", title: "Gesynchroniseerd"))
        var state = NotuleSyncState()
        try state.reconcile([note])
        let serverDigest = try note.digest()
        state.acknowledged(id: "a", digest: serverDigest, fields: nil)
        note.title = "Offline bewerkt"
        try state.reconcile([note])
        XCTAssertTrue(state.entries["a"]!.keepsLocalChange(against: serverDigest))
        XCTAssertFalse(state.entries["a"]!.keepsLocalChange(against: "another-device-edit"))
        XCTAssertFalse(state.entries["a"]!.keepsLocalChange(against: try note.digest()))
        try state.reconcile([])
        XCTAssertTrue(state.entries["a"]!.keepsLocalChange(against: serverDigest))
        XCTAssertFalse(state.entries["a"]!.keepsLocalChange(against: "another-device-edit"))
    }

    func testEchoBeforeUploadAcknowledgementKeepsNewerLocalEdit() throws {
        var note = SyncedNotule(TranscriptRecord(id: "a", title: "Upload in behandeling"))
        var state = NotuleSyncState()
        try state.reconcile([note])
        let uploading = try note.digest()
        state.entries["a"]?.uploadDigest = uploading
        note.title = "Bewerkt terwijl upload loopt"
        try state.reconcile([note])
        XCTAssertTrue(state.entries["a"]!.keepsLocalChange(against: uploading))
        state.acknowledged(id: "a", digest: uploading, fields: nil)
        XCTAssertTrue(state.entries["a"]!.pending)
        XCTAssertNil(state.entries["a"]!.uploadDigest)
        XCTAssertTrue(state.entries["a"]!.keepsLocalChange(against: uploading))
    }

    func testUploadAcknowledgementDoesNotLoseNewerEditOrDelete() throws {
        var note = SyncedNotule(TranscriptRecord(id: "a", title: "Eerste"))
        var state = NotuleSyncState()
        try state.reconcile([note])
        let sent = try note.digest()
        note.title = "Bewerkt tijdens upload"
        try state.reconcile([note])
        state.acknowledged(id: "a", digest: sent, fields: Data([2]))
        XCTAssertTrue(state.entries["a"]!.pending)
        XCTAssertEqual(state.entries["a"]!.digest, try note.digest())
        try state.reconcile([])
        state.acknowledged(id: "a", digest: try note.digest(), fields: Data([3]))
        XCTAssertTrue(state.entries["a"]!.pending)
        XCTAssertNil(state.entries["a"]!.digest)
    }

    func testConflictPreservesBothVersionsAndReplayDoesNotDuplicate() throws {
        let target = try store()
        let local = TranscriptRecord(id: "a", title: "Lokaal", notuleHtml: "Lokale tekst", localAudioPath: "/local.wav")
        try target.save(local)
        var incoming = SyncedNotule(local)
        incoming.title = "Ander apparaat"
        incoming.notuleHtml = "Andere tekst"
        let expectedCopy = try SyncedNotule(local).conflictCopy()
        try target.applySyncedNotule(incoming, preservingLocalConflict: true)
        try target.applySyncedNotule(incoming, preservingLocalConflict: true)
        let records = try target.recordsForSync()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.id == "a" }?.notuleHtml, "Andere tekst")
        let copy = try XCTUnwrap(records.first { $0.id == expectedCopy.id })
        XCTAssertEqual(copy.notuleHtml, "Lokale tekst")
        XCTAssertEqual(copy.localAudioPath, "/local.wav")
        XCTAssertTrue(copy.title.hasSuffix("(bewerkingsconflict)"))
    }

    func testRemoteDeletePreservesUnsyncedEditAsCopy() throws {
        let target = try store()
        try target.save(TranscriptRecord(id: "a", title: "Offline bewerkt", notuleHtml: "Nog niet verstuurd"))
        try target.deleteSyncedNotule(id: "a", preservingLocalConflict: true)
        let records = try target.recordsForSync()
        XCTAssertEqual(records.count, 1)
        XCTAssertNotEqual(records.first?.id, "a")
        XCTAssertEqual(records.first?.notuleHtml, "Nog niet verstuurd")
        try target.deleteSyncedNotule(id: "a", preservingLocalConflict: true)
        XCTAssertEqual(try target.recordsForSync().count, 1)
    }

    func testReplayedDeleteConflictDoesNotOverwriteEditedConflictCopy() throws {
        let target = try store()
        let incoming = SyncedNotule(TranscriptRecord(id: "a", title: "Bewerkt elders", notuleHtml: "Binnenkomend"))
        try target.preserveRemoteConflict(incoming)
        let id = try incoming.conflictCopy().id
        try target.updateNotule(taskId: id, html: "Daarna lokaal bewerkt")
        try target.preserveRemoteConflict(incoming)
        XCTAssertEqual(try target.recordsForSync().count, 1)
        XCTAssertEqual(target.record(forTaskId: id)?.notuleHtml, "Daarna lokaal bewerkt")
    }

    func testPermanentFailuresAreNotImmediatelyRequeued() {
        XCTAssertTrue(NotuleSyncService.engineRetries(.requestRateLimited))
        XCTAssertTrue(NotuleSyncService.engineRetries(.networkUnavailable))
        XCTAssertFalse(NotuleSyncService.engineRetries(.quotaExceeded))
        XCTAssertFalse(NotuleSyncService.engineRetries(.permissionFailure))
        XCTAssertFalse(NotuleSyncService.engineRetries(.invalidArguments))
    }

    func testStoreRecoverySetsPersistentSyncBlock() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sync-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Local.store")
        try Data("unreadable database".utf8).write(to: url)
        let suite = "NotuleSyncRecovery-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = LocalTranscriptStore.makeContainer(at: url, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: LocalTranscriptStore.recoveryKey))
        XCTAssertEqual(container.configurations.first?.url, url)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains("incompatible") })
    }

    func testDifferentAccountAndCorruptStateFailClosed() throws {
        var state = NotuleSyncState()
        try state.bindAccount("first")
        XCTAssertNoThrow(try state.bindAccount("first"))
        XCTAssertThrowsError(try state.bindAccount("second"))
        XCTAssertEqual(state.accountID, "first")
        let url = FileManager.default.temporaryDirectory.appending(path: "corrupt-sync-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try NotuleSyncState.load(from: url))
    }

    func testEveryTranscriptMutationNotifiesSyncButIncomingDoesNotLoop() throws {
        let target = try store()
        var count = 0
        target.onTranscriptChange = { count += 1 }
        let note = TranscriptRecord(id: "a", title: "Een")
        try target.save(note)
        try target.updateTitle(taskId: "a", title: "Twee")
        try target.updateTags(taskId: "a", tags: ["tag"])
        try target.updateNotule(taskId: "a", html: "Notule")
        try target.updateNotule(taskId: "a", html: "Correctie", transcription: "Transcriptie")
        try target.updateParticipants(taskId: "a", participants: [])
        try target.saveRejectedDraft(taskId: "a", html: "Concept", reason: "Controle")
        try target.finalizeNotule(taskId: "a", html: "Klaar", title: "Titel")
        XCTAssertEqual(count, 8)
        try target.applySyncedNotule(SyncedNotule(note), preservingLocalConflict: false)
        XCTAssertEqual(count, 8)
        try target.delete(taskId: "a")
        XCTAssertEqual(count, 9)
    }
}
