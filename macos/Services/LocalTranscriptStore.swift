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

    func save(_ record: TranscriptRecord) {
        context.insert(record)
        persist()
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

    // MARK: - Private

    private func persist() {
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
        }
    }
}
