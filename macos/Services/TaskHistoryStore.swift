// TaskHistoryStore.swift
// ThoughtVault
//
// Persistent history of processing tasks (a small JSON file next to the app's
// other data), so Taken can show finished and failed work after a restart.

import Foundation
import Observation

struct TaskHistoryStep: Codable, Equatable, Sendable {
    var label: String
    var startedAt: Date
    var finishedAt: Date?

    var duration: TimeInterval? { finishedAt.map { $0.timeIntervalSince(startedAt) } }
}

struct TaskHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    /// The task id (`local-…`, `local-regen-…` or a server id).
    var id: String
    var title: String
    var titleEdited = false
    var filename: String
    var profileId: String?
    var profileName: String?
    var createdAt: Date
    var finishedAt: Date?
    var status: TaskStatus
    var errorMessage: String?
    var recordingSeconds: Double?
    var audioPath: String?
    var recordingDeleted = false
    /// Task id of the stored notule record.
    var transcriptId: String
    var transcriptionEngine: String?
    var notuleProvider: String?
    var notuleModel: String?
    /// Set when the stored model was above the price cap and another model was used.
    var notuleNotice: String?
    var steps: [TaskHistoryStep] = []

    static let cancelledMessage = "Geannuleerd door gebruiker."

    var isCancelled: Bool { status == .error && errorMessage == Self.cancelledMessage }

    var outcomeLabel: String {
        if isCancelled { return "Geannuleerd" }
        switch status {
        case .completed: return "Voltooid"
        case .error: return "Mislukt"
        default: return "Bezig"
        }
    }

    var totalDuration: TimeInterval? { finishedAt.map { $0.timeIntervalSince(createdAt) } }
}

/// Settings in force when a task started, recorded with the entry.
struct TaskHistoryContext: Sendable {
    var transcriptionEngine: String?
    var notuleProvider: String?
    var notuleModel: String?
    var notuleNotice: String?
    var profileName: String?
}

@MainActor
@Observable
final class TaskHistoryStore {

    static let shared = TaskHistoryStore()
    static let limit = 200
    static var defaultURL: URL {
        AppEnvironment.supportDirectory.appending(path: "ThoughtVault/task-history.json")
    }

    /// Newest first.
    private(set) var entries: [TaskHistoryEntry] = []
    /// Titles chosen for a reprocess, keyed by audio path or notule id; picked up by the next new entry.
    @ObservationIgnored private var pendingTitles: [String: String] = [:]
    @ObservationIgnored private let url: URL

    init(url: URL = TaskHistoryStore.defaultURL) {
        self.url = url
        entries = Self.load(from: url)
    }

    /// A missing file is an empty history. An unreadable one is kept aside under a timestamped
    /// name and the history starts empty, so processing never depends on it.
    private static func load(from url: URL) -> [TaskHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder.history.decode([TaskHistoryEntry].self, from: data)
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            AppLog(category: "TaskHistory").error("Task history unreadable (\(type(of: error))), moved aside to \(aside.lastPathComponent)")
            return []
        }
    }

    func entry(_ id: String) -> TaskHistoryEntry? { entries.first { $0.id == id } }

    /// Records a new task or a status/step change. Only real changes are written.
    func track(_ task: TranscriptTask, context: @autoclosure () -> TaskHistoryContext, now: Date = Date()) {
        guard !task.taskId.isEmpty else { return }
        let label = task.statusLabel
        guard var entry = entry(task.taskId) else {
            insertNew(task, label: label, context: context(), now: now)
            return
        }
        let before = entry
        if entry.status != task.status, !entry.status.isActive, task.status.isActive {
            // A finished task that runs again (retry under the same id).
            entry.finishedAt = nil
            entry.errorMessage = nil
            // A regeneration reuses its id per run: only a title chosen for this run may name the notule.
            if task.taskId.hasPrefix("local-regen-") { entry.titleEdited = false }
        }
        if task.status.isActive, let carried = takeCarriedTitle(task, transcriptId: entry.transcriptId) {
            entry.title = carried
            entry.titleEdited = true
        }
        entry.status = task.status
        if let error = task.errorMessage { entry.errorMessage = error }
        if task.status.isActive {
            if entry.steps.last?.label != label || entry.steps.last?.finishedAt != nil {
                closeLastStep(&entry, at: now)
                entry.steps.append(TaskHistoryStep(label: label, startedAt: now))
            }
        } else if entry.finishedAt == nil {
            closeLastStep(&entry, at: now)
            entry.finishedAt = now
        }
        if entry != before { replace(entry) }
    }

    func update(_ id: String, _ change: (inout TaskHistoryEntry) -> Void) {
        guard var entry = entry(id) else { return }
        change(&entry)
        replace(entry)
    }

    /// A reprocess shares the recording, so every entry that uses `path` loses it.
    func markRecordingDeleted(_ path: String) {
        for index in entries.indices where entries[index].audioPath == path {
            entries[index].recordingDeleted = true
        }
        save()
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// The next new entry for this audio path or notule id gets `title`.
    func carryTitle(_ title: String, to key: String) {
        pendingTitles[key] = title
    }

    // MARK: - Private

    private func insertNew(_ task: TranscriptTask, label: String, context: TaskHistoryContext, now: Date) {
        let regenPrefix = "local-regen-"
        let transcriptId = task.taskId.hasPrefix(regenPrefix) ? String(task.taskId.dropFirst(regenPrefix.count)) : task.taskId
        let carried = takeCarriedTitle(task, transcriptId: transcriptId)
        let created = task.createdAt ?? now
        var entry = TaskHistoryEntry(
            id: task.taskId, title: carried ?? (task.filename.isEmpty ? "Naamloze opname" : task.filename),
            titleEdited: carried != nil, filename: task.filename, profileId: task.profileId,
            profileName: context.profileName, createdAt: created, status: task.status,
            errorMessage: task.errorMessage, audioPath: task.localAudioPath, transcriptId: transcriptId,
            transcriptionEngine: context.transcriptionEngine, notuleProvider: context.notuleProvider,
            notuleModel: context.notuleModel, notuleNotice: context.notuleNotice)
        if task.status.isActive {
            entry.steps = [TaskHistoryStep(label: label, startedAt: now)]
        } else {
            entry.finishedAt = now
        }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    private func takeCarriedTitle(_ task: TranscriptTask, transcriptId: String) -> String? {
        task.localAudioPath.flatMap { pendingTitles.removeValue(forKey: $0) } ?? pendingTitles.removeValue(forKey: transcriptId)
    }

    private func closeLastStep(_ entry: inout TaskHistoryEntry, at now: Date) {
        guard let last = entry.steps.indices.last, entry.steps[last].finishedAt == nil else { return }
        entry.steps[last].finishedAt = now
    }

    private func replace(_ entry: TaskHistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.history.encode(entries).write(to: url, options: .atomic)
        } catch {
            AppLog(category: "TaskHistory").error("Task history not saved: \(LogRedact.mask(error.localizedDescription))")
        }
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
