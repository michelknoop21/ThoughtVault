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
        do {
            container = try ModelContainer(for: TranscriptRecord.self)
        } catch {
            // A failed local store is unrecoverable; fall back to an in-memory store
            // so the app still launches rather than crashing.
            logger.error("Failed to create persistent store, using in-memory: \(error.localizedDescription)")
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: TranscriptRecord.self, configurations: config)
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
