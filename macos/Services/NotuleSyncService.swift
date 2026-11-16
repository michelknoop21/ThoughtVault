import CloudKit
import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class NotuleSyncService: CKSyncEngineDelegate {
    static let shared = NotuleSyncService()
    static let enabledKey = "notuleICloudSyncEnabled"
    static let didImport = Notification.Name("NotuleSyncDidImport")
    static let containerID = "iCloud.com.buildmind.ThoughtVault"
    static let zoneID = CKRecordZone.ID(zoneName: "Notulen", ownerName: CKCurrentUserDefaultName)

    private(set) var enabled = UserDefaults.standard.bool(forKey: enabledKey)
    private(set) var busy = false
    private(set) var errorMessage: String?
    private(set) var lastSync: Date?
    private(set) var pendingCount = 0
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var state = NotuleSyncState()
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var accountObserver: Task<Void, Never>?
    @ObservationIgnored private var assetFiles: [URL] = []
    private var folder: URL { AppEnvironment.supportDirectory.appending(path: "ThoughtVault/iCloud") }
    private var stateURL: URL { folder.appending(path: "sync-state.json") }
    private var store: LocalTranscriptStore { .shared }

    private init() {}

    func setEnabled(_ value: Bool) async {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value { await syncNow() } else { await stop() }
    }

    private func stop() async {
        generation += 1
        let previous = engine
        let previousAssets = assetFiles
        assetFiles.removeAll()
        engine = nil
        busy = false
        await previous?.cancelOperations()
        for url in previousAssets { try? FileManager.default.removeItem(at: url) }
    }

    func start() async {
        guard enabled, engine == nil, !starting, !AppEnvironment.isRunningTests, !AppEnvironment.isDebugSnapshot else { return }
        starting = true
        defer { starting = false }
        let attempt = generation
        do {
            let localStore = store
            guard !UserDefaults.standard.bool(forKey: LocalTranscriptStore.recoveryKey),
                  !localStore.container.configurations.contains(where: \.isStoredInMemoryOnly) else {
                throw NotuleSyncError.localRecovery
            }
            state = try NotuleSyncState.load(from: stateURL)
            guard state.zoneWasRemoved != true else { throw NotuleSyncError.zoneRemoved }
            let container = CKContainer(identifier: Self.containerID)
            guard try await container.accountStatus() == .available else { throw NotuleSyncError.noAccount }
            let account = try await container.userRecordID()
            guard enabled, attempt == generation else { return }
            try state.bindAccount(account.recordName)
            try reconcile()
            let serialization = try state.engineState.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
            let config = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                     stateSerialization: serialization, delegate: self)
            let newEngine = CKSyncEngine(config)
            engine = newEngine
            newEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            enqueue()
            errorMessage = nil
            if accountObserver == nil {
                accountObserver = Task { [weak self] in
                    for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                        guard let self else { return }
                        await self.stop()
                        await self.start()
                    }
                }
            }
            #if os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
            #else
            UIApplication.shared.registerForRemoteNotifications()
            #endif
            store.onTranscriptChange = { [weak self] in self?.localChanged() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncNow() async {
        await start()
        guard let engine, !busy else { return }
        busy = true
        errorMessage = nil
        do {
            try reconcile()
            enqueue()
            try await engine.fetchChanges()
            guard self.engine === engine else { return }
            try await engine.sendChanges()
            guard self.engine === engine else { return }
            if errorMessage == nil && pendingCount == 0 { lastSync = Date() }
        } catch { errorMessage = error.localizedDescription }
        busy = false
    }

    private func reconcile() throws {
        let records = try store.recordsForSync().map(SyncedNotule.init)
        try state.reconcile(records)
        try persist()
    }

    private func persist() throws {
        try state.save(to: stateURL)
        pendingCount = state.entries.values.filter(\.pending).count
    }

    private func enqueue(excluding deferred: Set<String> = []) {
        guard let engine else { return }
        let changes = state.entries.filter { $0.value.pending && !deferred.contains($0.key) }.map { id, entry in
            let recordID = CKRecord.ID(recordName: id, zoneID: Self.zoneID)
            return entry.digest == nil ? CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID) : .saveRecord(recordID)
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func localChanged() {
        guard enabled, engine != nil else { return }
        do { try reconcile(); enqueue() }
        catch { fail(error) }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        // Do not persist a newer server cursor after a failed local write.
        let previous = engine
        engine = nil
        busy = false
        generation += 1
        let previousAssets = assetFiles
        assetFiles.removeAll()
        Task {
            await previous?.cancelOperations()
            for url in previousAssets { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Leave throttling and connectivity retry timing to the system scheduler.
    static func engineRetries(_ code: CKError.Code) -> Bool {
        [.notAuthenticated, .accountTemporarilyUnavailable, .networkFailure, .networkUnavailable,
         .requestRateLimited, .serviceUnavailable, .zoneBusy].contains(code)
    }

    private func cleanAssets() {
        for url in assetFiles { try? FileManager.default.removeItem(at: url) }
        assetFiles.removeAll()
    }

    private func fields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func makeRecord(_ note: SyncedNotule) throws -> CKRecord {
        let id = CKRecord.ID(recordName: note.id, zoneID: Self.zoneID)
        let record: CKRecord
        if let data = state.entries[note.id]?.systemFields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
            decoder.requiresSecureCoding = true
            defer { decoder.finishDecoding() }
            guard let restored = CKRecord(coder: decoder), restored.recordID == id else { throw NotuleSyncError.invalidData }
            record = restored
        } else {
            record = CKRecord(recordType: "Notule", recordID: id)
        }
        let url = folder.appending(path: "upload-\(UUID().uuidString).json")
        let data = try note.encoded()
        guard data.count <= 64 * 1024 * 1024 else { throw NotuleSyncError.invalidData }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        assetFiles.append(url)
        // Assets also support long transcripts that exceed CloudKit's per-record field limit.
        record["content"] = CKAsset(fileURL: url)
        record["contentHash"] = try note.digest() as CKRecordValue
        record["schemaVersion"] = 1 as CKRecordValue
        state.entries[note.id]?.uploadDigest = try note.digest()
        return record
    }

    private func decode(_ record: CKRecord) throws -> SyncedNotule {
        guard record.recordType == "Notule", record.recordID.zoneID == Self.zoneID,
              record["schemaVersion"] as? Int == 1,
              let asset = record["content"] as? CKAsset, let url = asset.fileURL else { throw NotuleSyncError.invalidData }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 64 * 1024 * 1024 else { throw NotuleSyncError.invalidData }
        let note = try JSONDecoder().decode(SyncedNotule.self, from: Data(contentsOf: url))
        guard note.id == record.recordID.recordName, !note.taskId.isEmpty,
              try note.digest() == record["contentHash"] as? String else { throw NotuleSyncError.invalidData }
        return note
    }

    private func receive(_ record: CKRecord) throws {
        let note = try decode(record)
        let id = note.id
        let digest = try note.digest()
        // Fetch may echo our last upload: it must not revert an offline edit or undo a delete.
        if state.entries[id]?.keepsLocalChange(against: digest) == true {
            state.entries[id]?.systemFields = fields(record)
            return
        }
        // A local delete must not be undone by a concurrent remote edit.
        if let entry = state.entries[id], entry.pending && entry.digest == nil {
            if digest != entry.serverDigest { try store.preserveRemoteConflict(note) }
            state.entries[id]?.systemFields = fields(record)
            return
        }
        let pending = state.entries[id]?.pending == true
        try store.applySyncedNotule(note, preservingLocalConflict: pending)
        state.entries[id] = .init(digest: digest, serverDigest: digest, systemFields: fields(record))
        engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
    }

    private func receiveDeletion(_ id: CKRecord.ID) throws {
        guard id.zoneID == Self.zoneID else { return }
        try store.deleteSyncedNotule(id: id.recordName, preservingLocalConflict: state.entries[id.recordName]?.pending == true)
        state.entries[id.recordName] = .init()
        engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id), .deleteRecord(id)])
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, enabled else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                state.engineState = try JSONEncoder().encode(update.stateSerialization)
                try persist()
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let user): try state.bindAccount(user.recordName); try persist()
                case .signOut, .switchAccounts: throw NotuleSyncError.accountChanged
                @unknown default: throw NotuleSyncError.accountChanged
                }
            case .fetchedRecordZoneChanges(let changes):
                try reconcile()
                for modification in changes.modifications { try receive(modification.record) }
                for deletion in changes.deletions { try receiveDeletion(deletion.recordID) }
                try reconcile()
                enqueue()
                NotificationCenter.default.post(name: Self.didImport, object: nil)
            case .sentRecordZoneChanges(let changes):
                try reconcile()
                for record in changes.savedRecords {
                    state.acknowledged(id: record.recordID.recordName, digest: record["contentHash"] as? String, fields: fields(record))
                }
                for id in changes.deletedRecordIDs { state.acknowledged(id: id.recordName, digest: nil, fields: nil) }
                var deferred = Set<String>()
                for failure in changes.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                        try receive(server)
                    } else if failure.error.code == .unknownItem {
                        state.entries[failure.record.recordID.recordName]?.systemFields = nil
                    } else if Self.engineRetries(failure.error.code) {
                        deferred.insert(failure.record.recordID.recordName)
                        errorMessage = failure.error.localizedDescription
                    } else { throw failure.error }
                }
                for (id, error) in changes.failedRecordDeletes {
                    if error.code == .unknownItem { state.acknowledged(id: id.recordName, digest: nil, fields: nil) }
                    else if Self.engineRetries(error.code) {
                        deferred.insert(id.recordName)
                        errorMessage = error.localizedDescription
                    } else { throw error }
                }
                try reconcile()
                enqueue(excluding: deferred)
                NotificationCenter.default.post(name: Self.didImport, object: nil)
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                    state.zoneWasRemoved = true
                    try persist()
                    throw NotuleSyncError.zoneRemoved
                }
            case .sentDatabaseChanges(let changes):
                if let failure = changes.failedZoneSaves.first {
                    if Self.engineRetries(failure.error.code) { errorMessage = failure.error.localizedDescription }
                    else { throw failure.error }
                }
            case .didFetchRecordZoneChanges(let result):
                if let error = result.error { errorMessage = error.localizedDescription }
            case .willFetchChanges, .willSendChanges: busy = true
            case .didFetchChanges, .didSendChanges:
                busy = false
                if pendingCount == 0 && errorMessage == nil { lastSync = Date() }
                if case .didSendChanges = event { cleanAssets() }
            case .willFetchRecordZoneChanges: break
            @unknown default: break
            }
        } catch { fail(error) }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, enabled else { return nil }
        do {
            try reconcile()
            let records = Dictionary(uniqueKeysWithValues: try store.recordsForSync().map { ($0.id, SyncedNotule($0)) })
            var saves: [CKRecord] = []
            var deletes: [CKRecord.ID] = []
            for change in syncEngine.state.pendingRecordZoneChanges.filter({ context.options.scope.contains($0) }).prefix(50) {
                switch change {
                case .saveRecord(let id):
                    if let note = records[id.recordName] { saves.append(try makeRecord(note)) }
                    else { deletes.append(id) }
                case .deleteRecord(let id):
                    if let note = records[id.recordName] { saves.append(try makeRecord(note)) }
                    else { deletes.append(id) }
                @unknown default: break
                }
            }
            guard !saves.isEmpty || !deletes.isEmpty else { return nil }
            try persist()
            return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: saves, recordIDsToDelete: deletes)
        } catch { fail(error); return nil }
    }
}
