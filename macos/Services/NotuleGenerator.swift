import Foundation
import os

/// Generates a notule once and audits it. Port of `LLMService.generateNotulen` in
/// windows/src/services/llm.ts: audit problems end up in an "Even nalopen" section, never block (DEC-063).
struct NotuleGenerator: Sendable {
    let service: any LLMService

    func generate(transcription: String, profile: Profile, participants: [Participant], quickNote: String?,
                  createdAt: Date, corrections: [PersonalCorrection], context: String = "") async throws -> String {
        let source = PersonalCorrections.text(transcription, entries: corrections, profileId: profile.id)
        let constraints = NotuleAudit.constraintSentences(source)
        // Keep the unverified draft out of progress updates and saved notes.
        let draft = try await service.generateNotulen(
            transcription: source,
            systemPrompt: notuleSystemPrompt(profile.systemPrompt ?? ""),
            notulePrompt: QuickNoteStore.promptBlock(quickNote)
                + Self.injectParticipants(into: profile.notulePrompt ?? "", participants: participants)
                + context,
            outputTemplate: profile.template,
            constraints: constraints,
            onProgress: { _ in }
        )
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

        // NotuleAudit turns every request error into an audit message; remember cancellation separately.
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let service = service
        let request: AuditRequest = { system, user in
            do { return try await service.complete(system: system, user: user) } catch is CancellationError {
                cancelled.withLock { $0 = true }
                throw CancellationError()
            }
        }
        var warning: String?
        do {
            warning = try await NotuleAudit.auditSource(source: source, quickNote: quickNote ?? "", request: request)
            if Task.isCancelled || cancelled.withLock({ $0 }) { throw CancellationError() }
            try await NotuleAudit.auditNotule(source: source, html: candidate, quickNote: quickNote ?? "",
                                              request: request, requiredSentences: constraints, sourceUnclear: warning != nil)
            return NotuleAudit.appendingWarnings([warning].compactMap { $0 }, to: candidate)
        } catch {
            if Task.isCancelled || cancelled.withLock({ $0 }) { throw CancellationError() }
            // DEC-063: an audit problem never blocks the notule; it becomes a line in the warning section.
            let finding = (error as? NotuleAuditError)?.finding ?? NotuleAudit.uncheckedContentWarning
            return NotuleAudit.appendingWarnings([warning, finding].compactMap { $0 }, to: candidate)
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
