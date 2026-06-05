// LocalTranscriptStore.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Owns the SwiftData container for locally processed transcripts/notulen and
// provides simple CRUD so the app can keep a history without the backend server.

import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "LocalTranscriptStore")

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

        do {
            let config = ModelConfiguration(url: newURL)
            container = try ModelContainer(
                for: TranscriptRecord.self, PersonProfile.self,
                migrationPlan: AppMigrationPlan.self,
                configurations: config
            )
        } catch {
            // A failed local store is unrecoverable; fall back to an in-memory store
            // so the app still launches rather than crashing.
            logger.error("Failed to create persistent store, using in-memory: \(error.localizedDescription)")
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: TranscriptRecord.self, PersonProfile.self, configurations: config)
        }

        if shouldMigrate {
            migrateFromDefaultStore(at: oldDefaultURL)
        }
    }

    /// Dedicated on-disk location: `Application Support/TranscriptStudio/Local.store`.
    private static var storeURL: URL {
        let base = URL.applicationSupportDirectory.appending(path: "TranscriptStudio", directoryHint: .isDirectory)
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
