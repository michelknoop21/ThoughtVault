// RecordingViewModel+Notule.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// On-device notule generation: generate once, audit, then either save the approved
// notule or keep the rejected draft apart for review.

import AVFoundation
import Foundation
import os.log

private let log = OSLog(subsystem: "com.buildmind.ThoughtVault", category: "RecordingVM")

extension RecordingViewModel {

    /// Audio length in seconds; nil when unreadable, zero or non-finite.
    nonisolated static func audioDuration(_ url: URL) async -> Double? {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds,
              seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// Task message for a failed transcription: the thrown error's own text (localPipeline.retry.test.ts).
    nonisolated static func transcriptionFailureMessage(_ error: Error) -> String {
        error.localizedDescription
    }

    /// The configured notule provider; the cloud is meaningless for on-device generation.
    private static func localNotuleService() -> any LLMService {
        var provider = NotulenProvider(rawValue: UserDefaults.standard.string(forKey: "notulenProvider") ?? NotulenProvider.platformDefault.rawValue) ?? .ollama
        if provider == .cloud { provider = .ollama }
        return LLMServiceFactory.service(for: provider, serverURL: "")
    }

    /// Keeps a rejected draft next to the record and returns the task message (localPipeline.ts).
    private func keepRejectedDraft(_ review: NotuleReviewError, taskId: String) -> String {
        do {
            try LocalTranscriptStore.shared.saveRejectedDraft(taskId: taskId, html: review.draftHtml, reason: review.reason)
            return "\(review.reason). Het concept is apart bewaard voor beoordeling; er is geen nieuwe goedgekeurde notule opgeslagen."
        } catch {
            return "\(review.reason). Het concept kon niet worden bewaard. De transcriptie en opname zijn niet vervangen."
        }
    }

    /// Step 3 of local processing: the transcription is already saved as a partial record.
    func generateLocalNotule(url: URL, localId: String, transcription: String, createdAt: Date,
                             fallbackTitle: String, profile: Profile, participants: [Participant]) async {
        do {
            try Task.checkCancellation()
            let html = try await NotuleGenerator(service: Self.localNotuleService()).generate(
                transcription: transcription, profile: profile, participants: participants,
                quickNote: QuickNoteStore.note(audioFilename: url.lastPathComponent),
                createdAt: createdAt, corrections: PersonalCorrections.loadOrEmpty())
            try Task.checkCancellation()

            let title = NotuleTitleExtractor.extract(from: html) ?? fallbackTitle
            try LocalTranscriptStore.shared.finalizeNotule(taskId: localId, html: html, title: title)

            // Auto-export the finished notule to Obsidian (no-op when disabled).
            await MainActor.run {
                let record = LocalTranscriptStore.shared.record(forTaskId: localId)
                if let record { ObsidianService.autoExport(record) }
            }

            await MainActor.run {
                self.updateTask(localId, status: .completed, progress: 1.0)
                self.isGeneratingLocally = false
                self.localGenerationProgress = 1.0
            }

        } catch is CancellationError {
            await MainActor.run { self.cancelLocalTaskCleanup(localId) }
            return
        } catch let review as NotuleReviewError {
            // No cloud fallback: the backend would produce an unaudited notule.
            os_log("[RecordingVM] Local notule rejected by the audit: %{public}@", log: log, type: .error, review.reason)
            let message = keepRejectedDraft(review, taskId: localId)
            isGeneratingLocally = false
            updateTask(localId, status: .error, errorMessage: message)
        } catch {
            os_log("[RecordingVM] Local notule generation failed: %{public}@", log: log, type: .error, error.localizedDescription)

            // Cloud fallback: the transcription is already saved locally, so let
            // the backend generate the notule (it also triggers the Obsidian
            // export via the normal SSE completion path). Skipped in local mode:
            // the API layer refuses server calls there anyway.
            if !ProcessingMode.isLocalMode {
                do {
                    let cloudTask = try await APIService.shared.uploadTranscriptionText(
                        transcription: transcription,
                        profileId: profile.id,
                        participants: participants
                    )
                    self.saveLocalAudioPath(url: url, taskId: cloudTask.taskId)   // links the quick note
                    await MainActor.run {
                        self.isGeneratingLocally = false
                        self.removeTask(localId)
                        self.addTask(cloudTask)
                        self.localProcessingTasks.removeValue(forKey: localId)
                    }
                    await self.startSSEStream(for: cloudTask.taskId)
                    return
                } catch {
                    os_log("[RecordingVM] Cloud fallback also failed: %{public}@", log: log, type: .error, error.localizedDescription)
                }
            }

            let reason = Self.friendlyNotuleFailureReason(error)
            await MainActor.run {
                self.isGeneratingLocally = false
                self.updateTask(localId, status: .error,
                           errorMessage: "Transcriptie opgeslagen, notule mislukt: \(reason)")
            }
        }
        await MainActor.run { self.localProcessingTasks.removeValue(forKey: localId) }
    }

    /// Turns cryptic connection errors into a message the user can act on.
    /// The classic case: no Apple Intelligence available, provider falls back
    /// to Ollama on localhost, which does not exist on an iPhone.
    private static func friendlyNotuleFailureReason(_ error: Error) -> String {
        let urlError = error as? URLError
        if urlError?.code == .cannotConnectToHost || urlError?.code == .cannotFindHost {
            return "geen lokale AI bereikbaar. Stel een AI-provider in bij Instellingen, of schakel de cloud-modus in."
        }
        return error.localizedDescription
    }

    /// Regenerates the notule for an already-stored local record using its saved
    /// transcription and the given profile — entirely on-device. Returns the new
    /// HTML and title so the open detail view can stay in sync with SwiftData.
    /// A rejected draft is stored apart and the approved notule stays untouched.
    func regenerateNotuleLocally(taskId: String, profileId: String) async throws -> (html: String, title: String) {
        guard !updateInstalling else { throw LLMError.generationFailed("De app wordt bijgewerkt. Probeer na de herstart opnieuw.") }
        pendingRegenerations += 1
        defer { pendingRegenerations -= 1 }
        guard let record = LocalTranscriptStore.shared.record(forTaskId: taskId) else {
            throw LocalStoreError.recordNotFound
        }
        let regenerationId = "local-regen-\(taskId)"
        removeTask(regenerationId)
        addTask(TranscriptTask(id: regenerationId, taskId: regenerationId,
                               filename: record.title, status: .generatingLocal,
                               progress: 0.65, profileId: profileId, createdAt: Date()))
        let profile = availableProfiles.first { $0.id == profileId }
            ?? Profile.defaults.first { $0.id == profileId }
            ?? selectedProfile
            ?? Profile.defaults[0]

        do {
            let html = try await NotuleGenerator(service: Self.localNotuleService()).generate(
                transcription: record.rawTranscription, profile: profile, participants: record.participants,
                quickNote: QuickNoteStore.note(forTranscriptId: taskId),
                createdAt: record.createdAt, corrections: PersonalCorrections.loadOrEmpty())
            let title = NotuleTitleExtractor.extract(from: html) ?? record.title
            try LocalTranscriptStore.shared.finalizeNotule(taskId: taskId, html: html, title: title, profileId: profile.id, profileName: profile.name)
            updateTask(regenerationId, status: .completed, progress: 1)
            return (html, title)
        } catch let review as NotuleReviewError {
            let message = keepRejectedDraft(review, taskId: taskId)
            updateTask(regenerationId, status: .error, errorMessage: message)
            throw NotuleReviewError(reason: message, draftHtml: review.draftHtml)
        } catch {
            updateTask(regenerationId, status: .error, errorMessage: error.localizedDescription)
            throw error
        }
    }
}
