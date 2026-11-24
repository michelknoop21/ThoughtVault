import Foundation

private let log = AppLog(category: "RecordingVM")

extension RecordingViewModel {
    nonisolated static func supportFailureMessage(_ error: Error) -> String {
        switch error {
        case APIError.httpError(let status, _, _): return "Serverfout (HTTP \(status))."
        case APIError.decodingError: return "Fout bij verwerken van serverrespons."
        case LLMError.generationFailed: return "Generatie mislukt."
        case let review as NotuleReviewError: return review.supportReason ?? "Inhoudscontrole mislukt."
        default: return error.localizedDescription
        }
    }

    /// Short codes for the app's fully static failure sentences; any other shown text is logged as its mask.
    private nonisolated static let staticMessageCodes: [String: String] = [
        "Microfoontoestemming geweigerd. Geef toegang via Instellingen.": "mic-denied",
        "Opname is leeg of te kort om te verwerken.": "recording-empty",
        "Opname is te kort (minimaal 3 seconden). Probeer opnieuw.": "recording-too-short",
        "Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.": "no-profile",
        "Geannuleerd door gebruiker.": "cancelled-by-user",
        "Kon het audiobestand niet importeren.": "import-failed",
        "Transcriptie is leeg. Probeer het opnieuw.": "transcript-empty",
    ]

    nonisolated static func failureDiagnostic(shown: String, error: Error?) -> FailureDiagnostic {
        FailureDiagnostic(code: staticMessageCodes[shown] ?? LogRedact.mask(shown),
                          descriptor: error.map(LogRedact.describe) ?? "none")
    }

    func recordingFailed(_ error: Error, cancelled: Bool = false) {
        guard !cancelled else { recordingState = .idle; return }
        recordingFailureSupportMessage = Self.supportFailureMessage(error)
        recordingFailureError = error
        recordingState = .error(error.localizedDescription)
    }

    func recordingStateDidChange(from previous: RecordingState) {
        let supportMessage = recordingFailureSupportMessage
        let failure = recordingFailureError
        recordingFailureSupportMessage = nil
        recordingFailureError = nil
        if case .error(let message) = recordingState, previous != recordingState {
            reportFailure(stage: .opnemen, shown: message, support: supportMessage ?? message, error: failure)
        }
        syncSessionStage()
    }

    func taskDidChange(from previous: TaskStatus, to status: TaskStatus, message: String?,
                       shown: String? = nil, failure: Error? = nil) {
        if status == .error, previous != .error {
            reportFailure(stage: SupportViewModel.stage(afterFailureOf: previous),
                          shown: shown ?? message ?? "", support: message ?? "", error: failure)
        }
        syncSessionStage()
    }

    /// One log line per failure the user sees, at the state change, then the support hook.
    private func reportFailure(stage: SupportStage, shown: String, support: String, error: Error?) {
        let diagnostic = Self.failureDiagnostic(shown: shown, error: error)
        log.warning("Failure shown: stage=\(stage.rawValue) \(diagnostic.logText)")
        lastFailureDiagnostic = diagnostic
        onFailure?(stage, support)
    }

    func logSettings(trigger: String) {
        DiagnosticLog.logSettings(trigger: trigger, recordingMode: selectedMode, liveTranscription: preferOnDeviceTranscription)
    }

    /// Logs engine progress once at 25, 50 and 75 percent per task.
    func logTranscriptionProgress(_ id: String, _ fraction: Double) {
        let quarter = min(3, Int(fraction * 4))
        guard quarter > loggedTranscriptionQuarter[id, default: 0] else { return }
        loggedTranscriptionQuarter[id] = quarter
        log.info("Local transcription progress task=\(LogRedact.mask(id)) pct=\(quarter * 25)")
    }

    func syncSessionStage() {
        let stage: SupportStage?
        switch recordingState {
        case .preparing, .recording, .paused, .stopping, .uploading: stage = .opnemen
        case .idle, .error:
            stage = activeTasks.last(where: { $0.status.isActive })
                .map { SupportViewModel.stage(afterFailureOf: $0.status) }
        }
        AppLog.setSessionStage(stage?.rawValue)
    }
}
