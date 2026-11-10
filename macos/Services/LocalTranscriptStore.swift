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

    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    /// Test seam: a store over an injected (in-memory) container.
    init(container: ModelContainer) {
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
            moveStoreAside(at: url)
            defaults.set(false, forKey: watchdogKey)
        }

        func openPersistent() -> ModelContainer? {
            defaults.set(true, forKey: watchdogKey)
            do {
                let config = ModelConfiguration(url: url)
                let created = try ModelContainer(
                    for: TranscriptRecord.self, PersonProfile.self,
                    configurations: config
                )
                defaults.set(false, forKey: watchdogKey)
                return created
            } catch {
                defaults.set(false, forKey: watchdogKey)
                logger.error("Persistent store open failed: \(LogRedact.mask(error.localizedDescription))")
                return nil
            }
        }

        if let created = openPersistent() { return created }

        // Swift-level failure: set the bad store aside and retry once on a clean store.
        moveStoreAside(at: url)
        if let created = openPersistent() { return created }

        // Last resort so the app still launches; local history is unavailable this session.
        logger.error("Falling back to in-memory store.")
        let memConfig = ModelConfiguration(isStoredInMemoryOnly: true)
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
            let oldConfig = ModelConfiguration(url: oldURL, allowsSave: false)
            let oldContainer = try ModelContainer(for: TranscriptRecord.self, configurations: oldConfig)
            let oldRecords = try ModelContext(oldContainer).fetch(FetchDescriptor<TranscriptRecord>())
            guard !oldRecords.isEmpty else { return }

            for r in oldRecords {
                context.insert(TranscriptRecord(
                    id: r.id, taskId: r.taskId, title: r.title, filename: r.filename,
                    rawTranscription: r.rawTranscription, notuleHtml: r.notuleHtml,
                    profileId: r.profileId, profileName: r.profileName, tags: r.tags,
                    createdAt: r.createdAt, localAudioPath: r.localAudioPath, source: r.source
                ))
            }
            try context.save()
            logger.info("Migrated \(oldRecords.count) record(s) from the previous local store.")
        } catch {
            // No compatible local store to migrate (different schema or unreadable). Skip.
            logger.info("No compatible local store to migrate: \(LogRedact.mask(error.localizedDescription))")
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

    // MARK: - CRUD

    func save(_ record: TranscriptRecord) throws {
        context.insert(record)
        try context.save()
    }

    /// All locally stored records, newest first.
    func allRecords() -> [TranscriptRecord] {
        let descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetch failed: \(LogRedact.mask(error.localizedDescription))")
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
        do { try context.save() } catch { context.rollback(); throw error }
        try? ContextSuggestions.save(ContextSuggestionSet(), taskId: taskId)
    }

    func updateTags(taskId: String, tags: [String]) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = record.tags
        record.tags = tags
        do { try context.save() } catch { record.tags = original; throw error }
    }

    func updateNotule(taskId: String, html: String) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = record.notuleHtml
        record.notuleHtml = html
        do { try context.save() } catch { record.notuleHtml = original; throw error }
    }

    func updateParticipants(taskId: String, participants: [Participant]) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = record.participantsJSON
        record.participants = participants
        do { try context.save() } catch { record.participantsJSON = original; throw error }
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
        do { try context.save() } catch { record.title = original; throw error }
    }

    /// Updates the generated notule + title for a previously saved (partial) record.
    /// Throwing so callers can surface persistence failures instead of silently
    /// reporting success.
    func finalizeNotule(taskId: String, html: String, title: String, profileId: String? = nil, profileName: String? = nil) throws {
        guard let record = record(forTaskId: taskId) else {
            throw LocalStoreError.recordNotFound
        }
        let original = (record.notuleHtml, record.title, record.profileId, record.profileName, record.notuleDraftHtml, record.notuleReviewReason)
        record.notuleHtml = html
        record.title = title
        if let profileId { record.profileId = profileId; record.profileName = profileName }
        record.notuleDraftHtml = nil
        record.notuleReviewReason = nil
        do { try context.save() } catch {
            (record.notuleHtml, record.title, record.profileId, record.profileName, record.notuleDraftHtml, record.notuleReviewReason) = original
            throw error
        }
    }

    /// Keeps a notule that failed the audit apart for review; the approved `notuleHtml` is never touched.
    func saveRejectedDraft(taskId: String, html: String, reason: String) throws {
        guard let record = record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        let original = (record.notuleDraftHtml, record.notuleReviewReason)
        record.notuleDraftHtml = html
        record.notuleReviewReason = reason
        do { try context.save() } catch {
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
