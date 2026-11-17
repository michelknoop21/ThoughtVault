// RecordingViewModel+Notule.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// On-device notule generation: generate once, audit, then either save the approved
// notule or keep the rejected draft apart for review.

import AVFoundation
import Foundation
import os

private let log = AppLog(category: "RecordingVM")

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
    private static func localNotuleProvider() -> NotulenProvider {
        let provider = NotulenProvider.configured()
        return provider == .cloud ? .ollama : provider
    }

    /// Generates with `provider`, and once with the configured fallback provider when that fails.
    /// The usage is that of the run that produced the notule.
    private static func generateNotule(provider: NotulenProvider, merging: Bool = false, transcription: String, profile: Profile, participants: [Participant],
                                       quickNote: String?, createdAt: Date,
                                       onStep: @escaping @Sendable (ModelStep) -> Void) async throws -> (html: String, usage: NotuleUsage?) {
        let usage = OSAllocatedUnfairLock<NotuleUsage?>(initialState: nil)
        let once: @Sendable (NotulenProvider) async throws -> String = { p in
            try await generateNotuleOnce(provider: p, merging: merging, transcription: transcription, profile: profile, participants: participants,
                                         quickNote: quickNote, createdAt: createdAt, onStep: onStep,
                                         onUsage: { run in usage.withLock { $0 = run } })
        }
        let fallback = NotuleGenerator.fallbackProvider(for: provider).map { fb in
            { @Sendable () async throws -> String in
                log.info("Notule generation failed with \(provider.rawValue), retrying with fallback \(fb.rawValue)")
                return try await once(fb)
            }
        }
        let html = try await NotuleGenerator.withFallback(fallback) { try await once(provider) }
        return (html, usage.withLock { $0 })
    }

    /// Generates with the glossary and people context block for `provider`'s budget.
    private static func generateNotuleOnce(provider: NotulenProvider, merging: Bool = false, transcription: String, profile: Profile, participants: [Participant],
                                           quickNote: String?, createdAt: Date,
                                           onStep: @escaping @Sendable (ModelStep) -> Void,
                                           onUsage: @Sendable (NotuleUsage) -> Void) async throws -> String {
        let corrections = PersonalCorrections.loadOrEmpty()
        // Context-checked spellings must not become global correction instructions to the generator.
        let fixedContext = corrections.map { entry in var entry = entry; entry.learned = nil; return entry }
        log.info("Notule start provider=\(provider.rawValue) \(DiagnosticLog.notuleTarget(provider)) transcript_chars=\(transcription.count)")
        return try await NotuleGenerator(service: LLMServiceFactory.service(for: provider, serverURL: ""),
                                         noteConcurrency: provider.auditNoteConcurrency, provider: provider, merging: merging).generate(
            transcription: transcription, profile: profile, participants: participants, quickNote: RecordingFeatures.enabled ? nil : quickNote,
            createdAt: createdAt, corrections: corrections,
            context: PersonalCorrections.contextBlock(entries: fixedContext, transcript: transcription, profileId: profile.id, provider: provider),
            onStep: onStep, onUsage: onUsage)
    }

    /// Persist corrections before generation, including when generation subsequently fails.
    private static func correctTranscription(_ transcription: String, profile: Profile, taskId: String, provider: NotulenProvider) async throws -> String {
        let corrections = PersonalCorrections.loadOrEmpty()
        let fixed = PersonalCorrections.text(transcription, entries: corrections, profileId: profile.id)
        let corrected = await GlossaryAutoMatch.matchGlossary(fixed, corrections: corrections, profileId: profile.id,
                                                             service: LLMServiceFactory.service(for: provider, serverURL: ""), taskId: taskId)
        try Task.checkCancellation()
        guard let record = LocalTranscriptStore.shared.record(forTaskId: taskId) else { throw LocalStoreError.recordNotFound }
        if corrected != transcription {
            try LocalTranscriptStore.shared.updateNotule(taskId: taskId, html: record.notuleHtml, transcription: corrected)
        }
        return corrected
    }

    /// Shows the running notule step as the task label; a late update after completion is ignored by `updateTask`.
    private func showStep(taskId: String) -> @Sendable (ModelStep) -> Void {
        { step in
            Task { @MainActor in
                self.updateTask(taskId, status: .generatingLocal, statusDetail: step.displayLabel)
                ContinuedProcessing.shared?.update(runId: taskId, phase: .notule(step))
            }
        }
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
            let provider = Self.localNotuleProvider()
            let transcription = try await Self.correctTranscription(transcription, profile: profile, taskId: localId, provider: provider)
            let (generatedHTML, usage) = try await Self.generateNotule(
                provider: provider, transcription: transcription, profile: profile, participants: participants,
                quickNote: QuickNoteStore.note(audioFilename: url.lastPathComponent), createdAt: createdAt,
                onStep: showStep(taskId: localId))
            try Task.checkCancellation()

            let html = RecordingFeatures.enabled ? QuickNoteStore.exportHTML(generatedHTML, note: QuickNoteStore.note(audioFilename: url.lastPathComponent), includeNotes: true) : generatedHTML
            let entry = TaskHistoryStore.shared.entry(localId)
            let chosenTitle = entry?.titleEdited == true ? entry?.title : RecordingIdentity.load(audioFilename: url.lastPathComponent)?.title
            let title = chosenTitle ?? NotuleTitleExtractor.extract(from: html) ?? fallbackTitle
            try LocalTranscriptStore.shared.finalizeNotule(taskId: localId, html: html, title: title, usage: usage)
            ContextSuggestions.runInBackground(taskId: localId, transcript: transcription, participants: participants, profileId: profile.id, profileName: profile.name, provider: provider)

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
            log.error("[RecordingVM] Local notule rejected by the audit: \(LogRedact.mask(review.supportReason ?? "Inhoudscontrole mislukt"))")
            let message = keepRejectedDraft(review, taskId: localId)
            isGeneratingLocally = false
            updateTask(localId, status: .error, errorMessage: message, supportMessage: review.supportReason ?? "Inhoudscontrole mislukt", failure: review)
        } catch {
            log.error("[RecordingVM] Local notule generation failed: \(LogRedact.mask(Self.supportFailureMessage(error))) error=\(LogRedact.describe(error))")
            // No cloud fallback either: the backend notule is unaudited. The transcription
            // is already saved, so the user can retry.
            let reason = Self.friendlyNotuleFailureReason(error)
            await MainActor.run {
                self.isGeneratingLocally = false
                self.updateTask(localId, status: .error,
                           errorMessage: "Transcriptie opgeslagen, notule mislukt: \(reason)", supportMessage: Self.supportFailureMessage(error),
                           failure: error)
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
            let provider = Self.localNotuleProvider()
            let transcription = record.mergeSourcesJSON != nil ? record.rawTranscription
                : try await Self.correctTranscription(record.rawTranscription, profile: profile, taskId: taskId, provider: provider)
            let (generatedHTML, usage) = try await Self.generateNotule(
                provider: provider, merging: record.mergeSourcesJSON != nil, transcription: transcription, profile: profile, participants: record.participants,
                quickNote: QuickNoteStore.note(forTranscriptId: taskId), createdAt: record.createdAt,
                onStep: showStep(taskId: regenerationId))
            let html = RecordingFeatures.enabled ? QuickNoteStore.exportHTML(generatedHTML, note: QuickNoteStore.note(forTranscriptId: taskId), includeNotes: true) : generatedHTML
            let title = RecordingIdentity.forTask(taskId)?.title != nil ? record.title : NotuleTitleExtractor.extract(from: html) ?? record.title
            try LocalTranscriptStore.shared.finalizeNotule(taskId: taskId, html: html, title: title, profileId: profile.id,
                                                           profileName: profile.name, usage: usage)
            ContextSuggestions.runInBackground(taskId: taskId, transcript: record.rawTranscription, participants: record.participants, profileId: profile.id, profileName: profile.name, provider: provider)
            updateTask(regenerationId, status: .completed, progress: 1)
            return (html, title)
        } catch let review as NotuleReviewError {
            let message = keepRejectedDraft(review, taskId: taskId)
            updateTask(regenerationId, status: .error, errorMessage: message, supportMessage: review.supportReason ?? "Inhoudscontrole mislukt", failure: review)
            throw NotuleReviewError(reason: message, draftHtml: review.draftHtml, supportReason: review.supportReason)
        } catch {
            updateTask(regenerationId, status: .error, errorMessage: error.localizedDescription, supportMessage: Self.supportFailureMessage(error), failure: error)
            throw error
        }
    }
}


extension RecordingViewModel {
    /// Resolve current saved content before generating; never edit or replace a source record.
    func mergeNotulen(sourceIDs: [String], profileId: String) async throws -> Transcript {
        guard !isMerging, !updateInstalling else {
            throw LLMError.generationFailed(String(localized: "Samenvoegen is al bezig of de app wordt bijgewerkt."))
        }
        guard let profile = (availableProfiles.isEmpty ? Profile.defaults : availableProfiles).first(where: { $0.id == profileId }) else {
            throw LLMError.generationFailed(String(localized: "Kies een notulenprofiel."))
        }
        let id = "local-merge-" + UUID().uuidString
        let task = Task { @MainActor in
            var sources: [Transcript] = []
            for sourceID in Set(sourceIDs).sorted() {
                try Task.checkCancellation()
                if let record = LocalTranscriptStore.shared.record(forTaskId: sourceID),
                   record.source != "cloud" || !record.notuleHtml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sources.append(record.asTranscript)
                } else {
                    guard !sourceID.hasPrefix("local-") else { throw LocalStoreError.recordNotFound }
                    var source = try await APIService.shared.getTranscript(taskId: sourceID)
                    if (source.notuleHtml ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        source.notuleHtml = try await APIService.shared.getTranscriptNotes(taskId: sourceID)
                    }
                    sources.append(source)
                }
            }
            let snapshot = try NotuleMerge.prepare(sources)
            try Task.checkCancellation()
            let createdAt = Date()
            let (html, usage) = try await Self.generateNotule(provider: Self.localNotuleProvider(), merging: true,
                transcription: snapshot.text, profile: profile, participants: [], quickNote: nil, createdAt: createdAt,
                onStep: self.showStep(taskId: id))
            try Task.checkCancellation()
            let record = TranscriptRecord(id: id, title: NotuleTitleExtractor.extract(from: html) ?? String(localized: "Samengevoegde notule"),
                rawTranscription: snapshot.text, notuleHtml: html, profileId: profile.id, profileName: profile.name, createdAt: createdAt)
            record.mergeSourcesJSON = snapshot.metadata
            record.notuleUsageJSON = usage?.json
            try LocalTranscriptStore.shared.save(record)
            return record.asTranscript
        }
        mergeTask = task
        isMerging = true
        pendingRegenerations += 1
        addTask(TranscriptTask(id: id, taskId: id, filename: String(localized: "Notulen samenvoegen"),
            status: .generatingLocal, progress: 0.1, profileId: profileId, createdAt: Date()))
        defer { mergeTask = nil; isMerging = false; pendingRegenerations -= 1 }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            updateTask(id, status: .completed, progress: 1)
            return result
        } catch {
            let failure: Error = task.isCancelled ? CancellationError() : error
            updateTask(id, status: .error, errorMessage: failure is CancellationError ? String(localized: "Samenvoegen geannuleerd.") : failure.localizedDescription,
                       supportMessage: Self.supportFailureMessage(failure), failure: failure)
            throw failure
        }
    }
}
