// RecordingViewModel+TaskHistory.swift
// ThoughtVault
//
// Task history and the task actions of the Taken page: reprocess with another
// title, profile or model, open the notule, delete the recording, delete the task.

import Foundation

extension RecordingViewModel {

    // MARK: - History hook

    /// Called whenever a task is added or changes; writes the history entry.
    func taskHistoryDidChange(_ task: TranscriptTask) {
        guard !task.taskId.hasPrefix("upload-") else { return }  // temporary until the server answers
        var task = task
        if task.localAudioPath == nil {
            task.localAudioPath = UserDefaults.standard.string(forKey: "localAudio_\(task.taskId)")
        }
        let store = TaskHistoryStore.shared
        let isNew = store.entry(task.taskId) == nil
        store.track(task, context: historyContext(profileId: task.profileId))
        if isNew, let path = task.localAudioPath {
            let id = task.taskId
            Task { @MainActor in
                guard let seconds = await Self.audioDuration(URL(fileURLWithPath: path)) else { return }
                store.update(id) { $0.recordingSeconds = seconds }
            }
        }
        if task.status == .completed, let entry = store.entry(task.taskId), entry.titleEdited {
            try? LocalTranscriptStore.shared.updateTitle(taskId: entry.transcriptId, title: entry.title)
        }
    }

    private func historyContext(profileId: String?) -> TaskHistoryContext {
        let profileName = profileId.flatMap { id in
            (availableProfiles.first { $0.id == id } ?? Profile.defaults.first { $0.id == id })?.name
        }
        guard isLocalMode else {
            return TaskHistoryContext(transcriptionEngine: "ThoughtVault-server", notuleProvider: "ThoughtVault-server", profileName: profileName)
        }
        let rawEngine = UserDefaults.standard.string(forKey: "localTranscriber") ?? LocalTranscriberEngine.whisperKit.rawValue
        let engine = LocalTranscriberEngine(rawValue: rawEngine) ?? .whisperKit
        let engineLabel = engine == .whisperKit
            ? "WhisperKit · \(UserDefaults.standard.string(forKey: "whisperModel") ?? LocalTranscriberFactory.defaultWhisperModel)"
            : "Apple Spraakherkenning"
        let provider = SuggestedModels.currentProvider
        let model = SuggestedModels.currentModel(for: provider)
        return TaskHistoryContext(transcriptionEngine: engineLabel, notuleProvider: provider.displayName,
                                  notuleModel: model.isEmpty ? nil : model,
                                  notuleNotice: SuggestedModels.capNotice(for: provider), profileName: profileName)
    }

    // MARK: - Lookups

    func historyRecord(for entry: TaskHistoryEntry) -> TranscriptRecord? {
        LocalTranscriptStore.shared.record(forTaskId: entry.transcriptId)
    }

    func historyAudioURL(for entry: TaskHistoryEntry) -> URL? {
        guard !entry.recordingDeleted, let path = entry.audioPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Reprocessing needs the stored transcription or the recording.
    func canReprocess(_ entry: TaskHistoryEntry) -> Bool {
        !isHistoryTaskRunning(entry) && (historyRecord(for: entry) != nil || historyAudioURL(for: entry) != nil)
    }

    /// True while the task still runs in this session; an active status without a running task means it was interrupted.
    func isHistoryTaskRunning(_ entry: TaskHistoryEntry) -> Bool {
        activeTasks.contains { $0.taskId == entry.id && $0.status.isActive }
    }

    // MARK: - Actions

    /// Saves a new title on the history entry and on the notule, when there is one.
    func renameHistoryTask(_ entry: TaskHistoryEntry, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.title else { return }
        TaskHistoryStore.shared.update(entry.id) { $0.title = trimmed; $0.titleEdited = true }
        if historyRecord(for: entry) != nil {
            try? LocalTranscriptStore.shared.updateTitle(taskId: entry.transcriptId, title: trimmed)
        }
    }

    /// Runs the task again with the chosen title, profile and model. With a stored
    /// transcription only the notule is regenerated; otherwise the recording is processed again.
    func reprocessHistoryTask(_ entry: TaskHistoryEntry, title: String, profileId: String, model: String?) {
        guard canReprocess(entry) else { return }
        let provider = SuggestedModels.currentProvider
        if let model, !model.isEmpty, let key = SuggestedModels.modelKey(for: provider),
           SuggestedModels.isAllowed(model, provider: provider) {
            UserDefaults.standard.set(model, forKey: key)
        }
        renameHistoryTask(entry, title: title)
        // Only a title the user chose travels to the new task; otherwise the notule names itself.
        let chosenTitle = TaskHistoryStore.shared.entry(entry.id).flatMap { $0.titleEdited ? $0.title : nil }
        if activeTasks.contains(where: { $0.taskId == entry.id }) { removeTask(entry.id) }

        if isLocalMode, historyRecord(for: entry) != nil {
            if let chosenTitle { TaskHistoryStore.shared.carryTitle(chosenTitle, to: entry.transcriptId) }
            let recordId = entry.transcriptId
            Task { _ = try? await regenerateNotuleLocally(taskId: recordId, profileId: profileId) }
        } else if let url = historyAudioURL(for: entry) {
            if let chosenTitle { TaskHistoryStore.shared.carryTitle(chosenTitle, to: url.path) }
            Task {
                if isLocalMode { await processLocally(url: url, profileId: profileId) }
                else { await uploadFile(url, profileId: profileId) }
            }
        }
    }

    /// Deletes the audio file of the task; the notule and transcription stay.
    /// Other entries that share the file (a reprocess) are marked as well.
    func deleteHistoryRecording(_ entry: TaskHistoryEntry) {
        if let url = historyAudioURL(for: entry) {
            try? FileManager.default.removeItem(at: url)
        }
        if let path = entry.audioPath { TaskHistoryStore.shared.markRecordingDeleted(path) }
        TaskHistoryStore.shared.update(entry.id) { $0.recordingDeleted = true }
        loadSavedRecordings()
    }

    /// Stops the task when it runs and removes it from Taken. The notule is only
    /// deleted when `includeNotule` is set.
    func deleteHistoryTask(_ entry: TaskHistoryEntry, includeNotule: Bool) {
        if isHistoryTaskRunning(entry), entry.id.hasPrefix("local-") {
            cancelLocalProcessing(entry.id)
        }
        removeTask(entry.id)
        TaskHistoryStore.shared.remove(entry.id)
        if includeNotule {
            try? LocalTranscriptStore.shared.delete(taskId: entry.transcriptId)
        }
    }
}
