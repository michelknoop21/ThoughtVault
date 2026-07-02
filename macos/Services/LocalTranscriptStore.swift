// LocalTranscriptStore.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Owns the SwiftData container for locally processed transcripts/notulen and
// provides simple CRUD so the app can keep a history without the backend server.

import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "LocalTranscriptStore")

@MainActor
final class LocalTranscriptStore {

    static let shared = LocalTranscriptStore()

    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    private init() {
        // Use an app-specific store URL instead of SwiftData's default
        // (`Application Support/default.store`). That default store is shared with
        // every other unsandboxed SwiftData app on the machine, which caused an
        // incompatible-schema "store not reachable" failure in dev builds.
        let newURL = Self.storeURL
        let oldDefaultURL = URL.applicationSupportDirectory.appending(path: "default.store")
        // Earlier builds saved local history to the default store. Migrate it once,
        // before the new (empty) store exists.
        let shouldMigrate = !FileManager.default.fileExists(atPath: newURL.path)
            && FileManager.default.fileExists(atPath: oldDefaultURL.path)

        container = Self.makeContainer(at: newURL)

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
    /// manual recovery.
    private static func makeContainer(at url: URL) -> ModelContainer {
        let defaults = UserDefaults.standard
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
                logger.error("Persistent store open failed: \(error.localizedDescription)")
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
        let base = URL.applicationSupportDirectory.appending(path: "ThoughtVault", directoryHint: .isDirectory)
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
            logger.info("No compatible local store to migrate: \(error.localizedDescription)")
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
            existing.name = name
            existing.role = role
            existing.organization = organization
            existing.aliases = aliases
            existing.meetingTypes = meetingTypes
            existing.expertiseTags = expertiseTags
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
            logger.error("Fetch failed: \(error.localizedDescription)")
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

    func delete(taskId: String) {
        guard let record = record(forTaskId: taskId) else { return }
        context.delete(record)
        persist()
    }

    func updateTags(taskId: String, tags: [String]) {
        guard let record = record(forTaskId: taskId) else { return }
        record.tags = tags
        persist()
    }

    func updateNotule(taskId: String, html: String) {
        guard let record = record(forTaskId: taskId) else { return }
        record.notuleHtml = html
        persist()
    }

    func updateTitle(taskId: String, title: String) {
        guard let record = record(forTaskId: taskId) else { return }
        record.title = title
        persist()
    }

    /// Updates the generated notule + title for a previously saved (partial) record.
    /// Throwing so callers can surface persistence failures instead of silently
    /// reporting success.
    func finalizeNotule(taskId: String, html: String, title: String) throws {
        guard let record = record(forTaskId: taskId) else {
            throw LocalStoreError.recordNotFound
        }
        record.notuleHtml = html
        record.title = title
        try context.save()
    }

    // MARK: - Private

    private func persist() {
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - LocalStoreError

enum LocalStoreError: LocalizedError {
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .recordNotFound: return "Het lokale record kon niet worden gevonden."
        }
    }
}
