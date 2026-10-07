// RecordingViewModel+Restart.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Restart a failed task from the Taken view or the global processing bar.

import Foundation

extension RecordingViewModel {

    /// A regeneration task ("local-regen-<id>") belongs to the stored record <id>.
    private func recordTaskId(for task: TranscriptTask) -> String {
        let prefix = "local-regen-"
        return task.taskId.hasPrefix(prefix) ? String(task.taskId.dropFirst(prefix.count)) : task.taskId
    }

    private func restartAudioURL(for task: TranscriptTask) -> URL? {
        guard let path = task.localAudioPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Restartable when the transcription is already stored (only the notule failed)
    /// or the recording is still on disk (transcription failed). Cloud tasks without
    /// local data are not restartable from here.
    func canRestartTask(_ task: TranscriptTask) -> Bool {
        guard task.status == .error else { return false }
        if LocalTranscriptStore.shared.record(forTaskId: recordTaskId(for: task)) != nil { return true }
        return restartAudioURL(for: task) != nil
    }

    func restartTask(_ task: TranscriptTask) {
        guard canRestartTask(task) else { return }
        let profileId = task.profileId ?? selectedProfile?.id ?? Profile.defaults[0].id
        let recordId = recordTaskId(for: task)
        removeTask(task.taskId)
        if LocalTranscriptStore.shared.record(forTaskId: recordId) != nil {
            // Transcription is safe: only regenerate the notule. A failure shows up
            // again as its own (restartable) task.
            Task { _ = try? await regenerateNotuleLocally(taskId: recordId, profileId: profileId) }
        } else if let url = restartAudioURL(for: task) {
            Task { await processLocally(url: url, profileId: profileId) }
        }
    }
}
