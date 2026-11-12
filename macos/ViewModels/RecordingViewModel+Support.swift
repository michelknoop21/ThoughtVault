import Foundation

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

    func recordingFailed(_ error: Error, cancelled: Bool = false) {
        guard !cancelled else { recordingState = .idle; return }
        recordingFailureSupportMessage = Self.supportFailureMessage(error)
        recordingState = .error(error.localizedDescription)
    }

    func recordingStateDidChange(from previous: RecordingState) {
        let supportMessage = recordingFailureSupportMessage
        recordingFailureSupportMessage = nil
        if case .error(let message) = recordingState, previous != recordingState {
            onFailure?(.opnemen, supportMessage ?? message)
        }
        syncSessionStage()
    }

    func taskDidChange(from previous: TaskStatus, to status: TaskStatus, message: String?) {
        if status == .error, previous != .error {
            onFailure?(SupportViewModel.stage(afterFailureOf: previous), message ?? "")
        }
        syncSessionStage()
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
