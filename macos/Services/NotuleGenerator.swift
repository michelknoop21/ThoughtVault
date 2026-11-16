import Foundation
import os

private let log = AppLog(category: "NotuleGenerator")

/// Generates a notule once and audits it. Port of `LLMService.generateNotulen` in
/// windows/src/services/llm.ts: audit problems end up in an "Even nalopen" section, never block (DEC-063).
struct NotuleGenerator: Sendable {
    let service: any LLMService
    /// Step-2 audit checks in flight; the caller knows the provider (`NotulenProvider.auditNoteConcurrency`).
    var noteConcurrency = NotuleAudit.auditConcurrency
    /// Names the run in its usage and decides how its cost counts in the monthly ledger.
    var provider: NotulenProvider? = nil

    /// `onStep` reports the running step for the task label (`ModelStep.displayLabel`).
    /// `onUsage` gets length, requests, tokens, cost and duration of a successful run. Every run, also a
    /// failed one, is added to the monthly `UsageLedger`.
    /// `detailLevel` shortens the notule below volledig; volledig sends exactly the prompts of before.
    func generate(transcription: String, profile: Profile, participants: [Participant], quickNote: String?,
                  createdAt: Date, corrections: [PersonalCorrection], context: String = "",
                  detailLevel: NotuleDetailLevel = .volledig,
                  onStep: @escaping @Sendable (ModelStep) -> Void = { _ in },
                  onUsage: @Sendable (NotuleUsage) -> Void = { _ in }) async throws -> String {
        let meter = UsageMeter()
        let run: Run
        do {
            run = try await UsageMeter.$current.withValue(meter) {
                try await generateRun(transcription: transcription, profile: profile, participants: participants, quickNote: quickNote,
                                      createdAt: createdAt, corrections: corrections, context: context, detailLevel: detailLevel,
                                      onStep: onStep)
            }
        } catch {
            recordInLedger(meter.totals, notule: false)
            throw error
        }
        let totals = meter.totals
        recordInLedger(totals, notule: true)
        onUsage(NotuleUsage(provider: provider?.rawValue ?? "", model: totals.model ?? "", transcriptCharacters: transcription.count,
                            notuleHtml: run.html, notuleSentences: NotuleAudit.noteSentenceCount(run.checkedHtml),
                            totals: totals, durationMs: meter.elapsedMilliseconds, contentCheckSkipReason: run.skipReason,
                            detailLevel: detailLevel.rawValue))
        return run.html
    }

    /// The saved notule, the part the audit checked, and why the content check could not run.
    private struct Run: Sendable {
        let html: String
        let checkedHtml: String
        let skipReason: String?
    }

    private func recordInLedger(_ totals: UsageMeter.Totals, notule: Bool) {
        // Tests run inside the real app: never touch its ledger.
        guard !AppEnvironment.isRunningTests, let provider else { return }
        UsageLedger.record(totals, provider: provider, notule: notule)
    }

    private func generateRun(transcription: String, profile: Profile, participants: [Participant], quickNote: String?,
                             createdAt: Date, corrections: [PersonalCorrection], context: String,
                             detailLevel: NotuleDetailLevel,
                             onStep: @escaping @Sendable (ModelStep) -> Void) async throws -> Run {
        let source = PersonalCorrections.text(transcription, entries: corrections, profileId: profile.id)
        // Below volledig only the essential constraints stay mandatory, for the draft and for the audit.
        let constraints = detailLevel == .volledig ? NotuleAudit.constraintSentences(source) : NotuleAudit.essentialConstraints(source)

        // NotuleAudit turns every request error into an audit message; remember cancellation separately.
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let service = service
        let request: AuditRequest = { system, user in
            do { return try await service.complete(system: system, user: user) } catch is CancellationError {
                cancelled.withLock { $0 = true }
                throw CancellationError()
            }
        }
        // The source check never sees the notule (DEC-062), so it runs while the draft is written. Any throw
        // below cancels it and waits for it, so a draft error still wins and no request is left running.
        async let sourceWarning = NotuleAudit.auditSource(source: source, quickNote: quickNote ?? "", request: request)

        // Keep the unverified draft out of progress updates and saved notes.
        onStep(ModelStep(.draft))
        let draft = try await ModelStep.$current.withValue(ModelStep(.draft)) {
            try await service.generateNotulen(
                transcription: source,
                systemPrompt: notuleSystemPrompt(profile.systemPrompt ?? ""),
                notulePrompt: QuickNoteStore.promptBlock(quickNote)
                    + Self.injectParticipants(into: profile.notulePrompt ?? "", participants: participants)
                    + context,
                outputTemplate: profile.template,
                constraints: constraints,
                detailBlock: detailLevel.draftBlock(transcriptCharacters: source.utf16.count),
                onProgress: { _ in }
            )
        }
        try Task.checkCancellation()
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.generationFailed("De notule-generator gaf een leeg concept. De transcriptie is bewaard.")
        }
        // Judge the model's own output: an appended notes section must not make an empty notule usable.
        let stripped = Self.stripCodeFences(draft)
        guard Self.hasUsableNotule(stripped) else {
            throw LLMError.generationFailed("De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.")
        }
        let candidate = PersonalCorrections.html(
            Self.injectDate(into: QuickNoteStore.ensureNotesSection(stripped, note: quickNote), date: createdAt),
            entries: corrections, profileId: profile.id)

        var warning: String?
        do {
            onStep(ModelStep(.sourceCheck))
            warning = try await sourceWarning
            if Task.isCancelled || cancelled.withLock({ $0 }) { throw CancellationError() }
            try await NotuleAudit.auditNotule(source: source, html: candidate, quickNote: quickNote ?? "",
                                              request: request, requiredSentences: constraints, sourceUnclear: warning != nil,
                                              noteConcurrency: noteConcurrency, detailLevel: detailLevel, onProgress: onStep)
            log.info("Notule audit ran outcome=ok source_warning=\(warning != nil)")
            return Run(html: NotuleAudit.appendingWarnings([warning].compactMap { $0 }, to: candidate), checkedHtml: candidate, skipReason: nil)
        } catch {
            if Task.isCancelled || cancelled.withLock({ $0 }) { throw CancellationError() }
            log.info("Notule audit ran outcome=\(LogRedact.describe(error)) source_warning=\(warning != nil)")
            // DEC-063: an audit problem never blocks the notule; it becomes a line in the warning section.
            let auditError = error as? NotuleAuditError
            let finding = auditError?.finding ?? NotuleAudit.uncheckedContentWarning
            // A concrete finding means the check ran; otherwise the content was not checked.
            let skipReason = auditError?.finding == nil ? (auditError?.message ?? LogRedact.describe(error)) : nil
            return Run(html: NotuleAudit.appendingWarnings([warning, finding].compactMap { $0 }, to: candidate),
                       checkedHtml: candidate, skipReason: skipReason)
        }
    }

    /// Rejects empty output, a copied template of `[placeholders]`, and a missing-transcript reply.
    /// Bracketed text inside real content (e.g. "[onverstaanbaar]") is left to the fact audit.
    static func hasUsableNotule(_ html: String) -> Bool {
        let visible = html
            .replacingOccurrences(of: "<(style|script|template)\\b[^>]*>[\\s\\S]*?</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let content = visible.replacingOccurrences(of: "\\[[^\\]]+\\]", with: "", options: .regularExpression)
        guard content.unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count >= 20 else { return false }
        return visible.range(of: "geen transcriptie|transcriptie ontbreekt|onvoldoende transcriptie", options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// Removes the markdown code fences some models wrap around their HTML output.
    /// The cloud backend strips these server-side; on-device generation needs the
    /// same guard because the prompt discourages fences but cannot prevent them.
    static func stripCodeFences(_ html: String) -> String {
        var text = html.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "^```(?:html)?\\s*\\n?", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\\n?```\\s*$", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces the {{DATE}} template placeholder with a localized date. The cloud
    /// backend fills this server-side; for on-device generation the app does it.
    static func injectDate(into html: String, date: Date) -> String {
        guard html.contains("{{DATE}}") else { return html }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "d MMMM yyyy"
        return html.replacingOccurrences(of: "{{DATE}}", with: formatter.string(from: date))
    }

    /// Injects the DEELNEMERS block into a notule prompt for on-device generation.
    /// Substitutes a {{PARTICIPANTS}} placeholder when present, otherwise prepends
    /// the block. Mirrors what the cloud backend does server-side so both paths
    /// produce an attendee list + name attribution.
    static func injectParticipants(into notulePrompt: String, participants: [Participant]) -> String {
        let block = participants.notulePromptBlock
        if notulePrompt.contains("{{PARTICIPANTS}}") {
            return notulePrompt.replacingOccurrences(of: "{{PARTICIPANTS}}", with: block)
        }
        guard !block.isEmpty else { return notulePrompt }
        return block + "\n\n" + notulePrompt
    }
}

// MARK: - Fallback

extension NotuleGenerator {
    /// UserDefaults key of the optional fallback provider; empty means no fallback.
    static let fallbackProviderKey = "notulenFallbackProvider"

    /// The configured fallback, or nil when none is set or it is the primary itself.
    static func fallbackProvider(for primary: NotulenProvider) -> NotulenProvider? {
        guard let raw = UserDefaults.standard.string(forKey: fallbackProviderKey),
              let provider = NotulenProvider(rawValue: raw), provider != .cloud, provider != primary else { return nil }
        return provider
    }

    /// Runs `primary`; on a model error tries `fallback` once. Cancellation and a draft
    /// rejected by the audit are not model errors, so they never trigger the fallback.
    static func withFallback(_ fallback: (@Sendable () async throws -> String)?,
                             primary: @Sendable () async throws -> String) async throws -> String {
        do {
            return try await primary()
        } catch is CancellationError {
            throw CancellationError()
        } catch let review as NotuleReviewError {
            throw review
        } catch {
            guard let fallback, !Task.isCancelled else { throw error }
            log.warning("Notule fallback provider used after error=\(LogRedact.describe(error))")
            return try await fallback()
        }
    }
}
