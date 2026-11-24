// LocalTranscriptStore.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Owns the SwiftData container for locally processed transcripts/notulen and
// provides simple CRUD so the app can keep a history without the backend server.

import Foundation
import SwiftData

private let logger = AppLog(category: "LocalTranscriptStore")

@MainActor
final class LocalTranscriptStore {

    static let shared = LocalTranscriptStore()

    static let didChange = Notification.Name("LocalTranscriptStore.didChange")
    static let recoveryKey = "localStoreRecoveryRequiresReview"
    var onTranscriptChange: (() -> Void)?

    private var library: LibraryOrganization { organizationStore ?? .shared }
    private var organizationStore: LibraryOrganization?
    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    /// Test seam: a store over an injected (in-memory) container.
    init(container: ModelContainer, library: LibraryOrganization? = nil) {
        self.organizationStore = library
        self.container = container
    }

    private init() {
        // Use an app-specific store URL instead of SwiftData's default
        // (`Application Support/default.store`). That default store is shared with
        // every other unsandboxed SwiftData app on the machine, which caused an
        // incompatible-schema "store not reachable" failure in dev builds.
        let newURL = Self.storeURL
        let oldDefaultURL = AppEnvironment.supportDirectory.appending(path: "default.store")
        // Earlier builds saved local history to the default store. Migrate it once,
        // before the new (empty) store exists.
        let shouldMigrate = !FileManager.default.fileExists(atPath: newURL.path)
            && FileManager.default.fileExists(atPath: oldDefaultURL.path)

        // The watchdog flag must not leak into the real app's defaults from a test run.
        container = Self.makeContainer(at: newURL, defaults: AppEnvironment.isRunningTests ? UserDefaults(suiteName: "ThoughtVaultTests")! : .standard)

        if shouldMigrate {
            migrateFromDefaultStore(at: oldDefaultURL)
        }
    }

    /// Opens the on-disk store with implicit lightweight migration, guarded by a
    /// crash-watchdog.
    ///
    /// SwiftData infers lightweight migration for additive/relaxing schema changes
    /// (new entity, new attribute, `Bool` → `Bool?`), so no explicit
    /// `SchemaMigrationPlan` is used. A versioned plan whose stages reuse the same
    /// live model types produces "Duplicate version checksums detected" — an
    /// uncatchable CoreData `NSException` that aborts the process during migration.
    ///
    /// Because that exception cannot be caught in Swift, a watchdog flag is set in
    /// `UserDefaults` immediately before the open and cleared only on success. If a
    /// previous launch aborted inside CoreData migration, the flag is still set on the
    /// next launch, and we move the incompatible store aside so the app starts cleanly
    /// instead of crash-looping. The set-aside store is preserved (not deleted) for
    /// manual recovery. `defaults` holds the watchdog flag; tests pass their own suite.
    static func makeContainer(at url: URL, defaults: UserDefaults = .standard) -> ModelContainer {
        let watchdogKey = "localStoreOpenInProgress"

        if defaults.bool(forKey: watchdogKey) {
            logger.error("Previous store open aborted during migration; moving incompatible store aside.")
            defaults.set(true, forKey: recoveryKey)
            moveStoreAside(at: url)
            defaults.set(false, forKey: watchdogKey)
        }

        func openPersistent() -> ModelContainer? {
            defaults.set(true, forKey: watchdogKey)
            do {
                let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
                let created = try ModelContainer(
                    for: TranscriptRecord.self, PersonProfile.self,
                    configurations: config
                )
                defaults.set(false, forKey: watchdogKey)
                return created
            } catch {
                defaults.set(false, forKey: watchdogKey)
                logger.error("Persistent store open failed: \(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))")
                return nil
            }
        }

        if let created = openPersistent() { return created }

        // Swift-level failure: set the bad store aside and retry once on a clean store.
        defaults.set(true, forKey: recoveryKey)
        moveStoreAside(at: url)
        if let created = openPersistent() { return created }

        // Last resort so the app still launches; local history is unavailable this session.
        logger.error("Falling back to in-memory store.")
        let memConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: TranscriptRecord.self, PersonProfile.self, configurations: memConfig)
    }

    /// Renames the store (and its `-wal`/`-shm` sidecars) to a timestamped
    /// "-incompatible-…" name so a fresh store can be created without destroying data.
    private static func moveStoreAside(at url: URL) {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for ext in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: url.path + ext)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dest = URL(fileURLWithPath: url.path + ext + "-incompatible-\(stamp)")
            try? fm.moveItem(at: src, to: dest)
        }
    }

    /// True when an earlier launch created the store. Unlike `storeURL` this creates no folder.
    nonisolated static var storeFileExists: Bool {
        FileManager.default.fileExists(atPath: AppEnvironment.supportDirectory.appending(path: "ThoughtVault/Local.store").path)
    }

    /// Dedicated on-disk location: `Application Support/ThoughtVault/Local.store`.
    private static var storeURL: URL {
        let base = AppEnvironment.supportDirectory.appending(path: "ThoughtVault", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "Local.store")
    }

    /// One-time copy of records from the old default store into the new store.
    /// Opens the old store read-only as `TranscriptRecord`; if it holds a different
    /// schema (another app's default store), the open throws and migration is skipped.
    private func migrateFromDefaultStore(at oldURL: URL) {
        do {
            let oldConfig = ModelConfiguration(url: oldURL, allowsSave: false, cloudKitDatabase: .none)
            let oldContainer = try ModelContainer(for: TranscriptRecord.self, configurations: oldConfig)
            let oldRecords = try ModelContext(oldContainer).fetch(FetchDescriptor<TranscriptRecord>())
            guard !oldRecords.isEmpty else { return }

            for r in oldRecords {
                let migrated = TranscriptRecord(id: r.id, title: r.title, localAudioPath: r.localAudioPath)
                SyncedNotule(r).apply(to: migrated)
                context.insert(migrated)
            }
            try context.save()
            logger.info("Migrated \(oldRecords.count) record(s) from the previous local store.")
        } catch {
            // No compatible local store to migrate (different schema or unreadable). Skip.
            logger.info("No compatible local store to migrate: \(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))")
        }
    }

    // MARK: - PersonProfile

    /// Returns the single isSelf==true PersonProfile, or nil if none has been created.
    func fetchSelfProfile() -> PersonProfile? {
        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == true }
        )
        return try? context.fetch(descriptor).first
    }

    /// Creates or updates the single isSelf==true PersonProfile (singleton upsert, D-09).
    /// Fetch-first-then-insert from the MainActor service preserves the one-record invariant.
    func upsertSelfProfile(
        name: String,
        role: String,
        organization: String,
        aliases: [String],
        meetingTypes: [String],
        expertiseTags: [String]
    ) throws {
        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == true }
        )
        if let existing = try? context.fetch(descriptor).first {
            let before = PersonSnapshot(existing)
            existing.name = name
            existing.role = role
            existing.organization = organization
            existing.aliases = aliases
            existing.meetingTypes = meetingTypes
            existing.expertiseTags = expertiseTags
            if PersonSnapshot(existing) != before {
                do { try ContextHistory.record(kind: .person, itemId: existing.id, source: "handmatig", snapshot: before) }
                catch { before.apply(to: existing); throw error }
            }
            existing.updatedAt = Date()
            logger.debug("upsertSelfProfile: updated existing isSelf record")
        } else {
            context.insert(PersonProfile(
                name: name,
                role: role,
                organization: organization,
                aliases: aliases,
                meetingTypes: meetingTypes,
                expertiseTags: expertiseTags,
                isSelf: true,
                isInternal: true
            ))
            logger.debug("upsertSelfProfile: created new isSelf record")
        }
        try context.save()
    }

    /// A failed fetch must never be mistaken for deleting every record.
    func recordsForSync() throws -> [TranscriptRecord] {
        try context.fetch(FetchDescriptor<TranscriptRecord>())
    }

    private func saveTranscriptChanges() throws {
        do { try context.save() } catch { context.rollback(); throw error }
        onTranscriptChange?()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func applySyncedNotule(_ note: SyncedNotule, preservingLocalConflict: Bool) throws {
        if let snapshot = note.documentBrandingJSON { _ = try DocumentBranding.parse(snapshot) }
        if let json = note.organizationJSON {
            _ = try JSONDecoder().decode(NoteOrganization.self, from: Data(json.utf8))
        }
        let existing = try recordsForSync().first { $0.id == note.id }
        do {
            if preservingLocalConflict, let existing, SyncedNotule(existing) != note {
                try preserveConflict(existing)
            }
            let record = existing ?? TranscriptRecord(id: note.id, title: note.title)
            if existing == nil { context.insert(record) }
            note.apply(to: record)
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func deleteSyncedNotule(id: String, preservingLocalConflict: Bool) throws {
        guard let record = try recordsForSync().first(where: { $0.id == id }) else { return }
        do {
            if preservingLocalConflict { try preserveConflict(record) }
            context.delete(record)
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func preserveRemoteConflict(_ note: SyncedNotule) throws {
        let copy = try note.conflictCopy()
        guard try !recordsForSync().contains(where: { $0.id == copy.id }) else { return }
        try applySyncedNotule(copy, preservingLocalConflict: false)
    }

    private func preserveConflict(_ record: TranscriptRecord) throws {
        let copy = try SyncedNotule(record).conflictCopy()
        guard try !recordsForSync().contains(where: { $0.id == copy.id }) else { return }
        let duplicate = TranscriptRecord(id: copy.id, title: copy.title, localAudioPath: record.localAudioPath)
        copy.apply(to: duplicate)
        context.insert(duplicate)
    }

    // MARK: - CRUD

    func save(_ record: TranscriptRecord) throws {
        if self.record(forTaskId: record.taskId) == nil, record.documentBrandingJSON == nil {
            record.documentBrandingJSON = try DocumentBrandingStore.shared.defaultSnapshot()
        }
        context.insert(record)
        do { try saveTranscriptChanges() } catch { context.delete(record); throw error }
        scheduleAutoLabels(record)
    }

    func applyBranding(taskId: String, snapshot: String?) throws {
        if let snapshot { _ = try DocumentBranding.parse(snapshot) }
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let old = record.documentBrandingJSON
        record.documentBrandingJSON = snapshot
        do { try saveTranscriptChanges() } catch { record.documentBrandingJSON = old; throw error }
    }

    /// All locally stored records, newest first.
    func allRecords() -> [TranscriptRecord] {
        let descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetch failed: \(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))")
            return []
        }
    }

    /// All locally stored records mapped to the `Transcript` value type for the UI.
    func allTranscripts() -> [Transcript] {
        allRecords().map(\.asTranscript)
    }

    func record(forTaskId taskId: String) -> TranscriptRecord? {
        let descriptor = FetchDescriptor<TranscriptRecord>(
            predicate: #Predicate { $0.taskId == taskId }
        )
        return try? context.fetch(descriptor).first
    }

    func delete(taskId: String) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        context.delete(record)
        do { try saveTranscriptChanges() } catch { context.rollback(); throw error }
        try? ContextSuggestions.save(ContextSuggestionSet(), taskId: taskId)
    }

    func updateTags(taskId: String, tags: [String]) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = (record.tags, record.organizationJSON)
        var organization = record.organization
        for label in library.labels {
            if record.tags.contains(label.name) && !tags.contains(label.name) && organization.automaticLabelIDs.contains(label.id) {
                if !organization.suppressedLabelIDs.contains(label.id) { organization.suppressedLabelIDs.append(label.id) }
            }
            if tags.contains(label.name) && !record.tags.contains(label.name) {
                organization.suppressedLabelIDs.removeAll { $0 == label.id }
                organization.automaticLabelIDs.removeAll { $0 == label.id }
            }
        }
        record.organization = organization
        record.tags = tags
        do { try saveTranscriptChanges() } catch { (record.tags, record.organizationJSON) = original; throw error }
    }

    func updateNotule(taskId: String, html: String) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = record.notuleHtml
        record.notuleHtml = html
        do { try saveTranscriptChanges() } catch { record.notuleHtml = original; throw error }
    }

    /// Saves a corrected notule and transcript together.
    func updateNotule(taskId: String, html: String, transcription: String?, title: String? = nil) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = (record.notuleHtml, record.rawTranscription, record.title)
        record.notuleHtml = html
        if let transcription, record.mergeSourcesJSON == nil { record.rawTranscription = transcription }
        if let title { record.title = title }
        do { try saveTranscriptChanges() } catch { (record.notuleHtml, record.rawTranscription, record.title) = original; throw error }
    }

    func updateParticipants(taskId: String, participants: [Participant]) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = record.participantsJSON
        record.participants = participants
        do { try saveTranscriptChanges() } catch { record.participantsJSON = original; throw error }
    }

    /// Records with a participant linked to `personId`, newest first.
    /// Decodes every record's participants (linear scan); add an indexed link if this gets slow.
    func records(linkedTo personId: String, limit: Int = 50) -> [TranscriptRecord] {
        Array(allRecords().filter { $0.participants.contains { $0.personId == personId } }.prefix(limit))
    }

    func updateTitle(taskId: String, title: String) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = record.title
        record.title = title
        do { try saveTranscriptChanges() } catch { record.title = original; throw error }
    }

    /// Updates the generated notule + title for a previously saved (partial) record.
    /// Throwing so callers can surface persistence failures instead of silently
    /// reporting success.
    /// `usage` replaces the stored usage, so a regenerated notule never shows the numbers of the previous one.
    /// `detailLevel` is stored when given, so a regeneration starts from the level of this notule.
    func finalizeNotule(taskId: String, html: String, title: String, profileId: String? = nil, profileName: String? = nil,
                        usage: NotuleUsage? = nil, detailLevel: NotuleDetailLevel? = nil) throws {
        guard let record = record(forTaskId: taskId) else {
            throw LocalStoreError.recordNotFound
        }
        let original = (record.notuleHtml, record.title, record.profileId, record.profileName, record.notuleDraftHtml, record.notuleReviewReason)
        let originalUsage = (record.notuleUsageJSON, record.detailLevel)
        record.notuleHtml = html
        record.title = title
        if let profileId { record.profileId = profileId; record.profileName = profileName }
        record.notuleDraftHtml = nil
        record.notuleReviewReason = nil
        record.notuleUsageJSON = usage?.json
        if let detailLevel { record.detailLevel = detailLevel.rawValue }
        do { try saveTranscriptChanges() } catch {
            (record.notuleHtml, record.title, record.profileId, record.profileName, record.notuleDraftHtml, record.notuleReviewReason) = original
            (record.notuleUsageJSON, record.detailLevel) = originalUsage
            throw error
        }
        scheduleAutoLabels(record)
    }

    func move(taskIDs: [String], to folderID: String?) throws {
        if let folderID, !library.folders.contains(where: { $0.id == folderID }) { throw LocalStoreError.recordNotFound }
        let records = try taskIDs.map { id in
            guard let record = record(forTaskId: id) else { throw LocalStoreError.recordNotFound }
            return record
        }
        for record in records { var metadata = record.organization; metadata.folderID = folderID; record.organization = metadata }
        try saveTranscriptChanges()
    }

    private func scheduleAutoLabels(_ record: TranscriptRecord) {
        guard !AppEnvironment.isRunningTests, !record.notuleHtml.isEmpty, record.notuleDraftHtml == nil else { return }
        let taskID = record.taskId
        Task { await AutomaticLabels.shared.run(taskIDs: [taskID]) }
    }

    func saveAutomaticLabels(taskId: String, chosen: [LibraryEntry], eligible: [LibraryEntry]) throws {
        guard let record = record(forTaskId: taskId) else { return }
        var metadata = record.organization
        let active = library.labels.filter { $0.automatic && eligible.contains($0) }
        let automaticNames = active.filter { metadata.automaticLabelIDs.contains($0.id) }.map(\.name)
        var tags = record.tags.filter { !automaticNames.contains($0) }
        metadata.automaticLabelIDs.removeAll { id in active.contains { $0.id == id } }
        for label in chosen where active.contains(label) && !metadata.suppressedLabelIDs.contains(label.id) {
            if !tags.contains(label.name) { tags.append(label.name); metadata.automaticLabelIDs.append(label.id) }
        }
        record.tags = tags
        record.organization = metadata
        record.autoLabelError = nil
        try saveTranscriptChanges()
    }

    func setAutoLabelError(taskId: String, message: String) throws {
        guard let record = record(forTaskId: taskId) else { return }
        record.autoLabelError = message
        try saveTranscriptChanges()
    }

    /// Keeps a notule that failed the audit apart for review; the approved `notuleHtml` is never touched.
    func saveRejectedDraft(taskId: String, html: String, reason: String) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = (record.notuleDraftHtml, record.notuleReviewReason)
        record.notuleDraftHtml = html
        record.notuleReviewReason = reason
        do { try saveTranscriptChanges() } catch {
            (record.notuleDraftHtml, record.notuleReviewReason) = original
            throw error
        }
    }

}

#if DEBUG
extension LocalTranscriptStore {
    /// Screenshot hook (`-TVDebugSeedDraft YES`): one record with an approved notule plus a rejected draft.
    func seedDebugDraftIfRequested() {
        guard UserDefaults.standard.string(forKey: "TVDebugSeedDraft") == "YES",
              record(forTaskId: "debug-draft-demo") == nil else { return }
        let record = TranscriptRecord(
            id: "debug-draft-demo",
            taskId: "debug-draft-demo",
            title: "Projectoverleg Noord",
            rawTranscription: "We bespraken de planning van fase twee. De leverancier meldt een vertraging van twee weken. Iris kijkt of de oplevering daardoor schuift. Het budget blijft voorlopig ongewijzigd.",
            notuleHtml: "<h2>Projectoverleg Noord</h2><p>De planning van fase twee is besproken.</p><p>De leverancier meldt een vertraging van twee weken en het budget blijft voorlopig ongewijzigd.</p><ul><li>Iris onderzoekt of de oplevering schuift.</li></ul>"
        )
        record.notuleDraftHtml = "<h2>Projectoverleg Noord</h2><p>Fase twee loopt door, maar de leverancier is twee weken later.</p><p>Het budget wordt niet aangepast.</p><ul><li>Iris belt de leverancier vóór vrijdag.</li></ul>"
        record.notuleReviewReason = "Feiten, acties en beperkingen konden niet worden bevestigd: De notule bevat een onbevestigde bewering: Iris belt de leverancier vóór vrijdag."
        try? save(record)
    }
}
#endif

// MARK: - LocalStoreError

enum LocalStoreError: LocalizedError {
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .recordNotFound: return "Het lokale record kon niet worden gevonden."
        }
    }
}
