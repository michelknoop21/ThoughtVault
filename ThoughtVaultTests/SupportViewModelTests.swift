import Foundation
import XCTest
@testable import ThoughtVault

final class SupportViewModelTests: XCTestCase {
    @MainActor
    private func fixture() -> (SupportViewModel, SupportRelay, UserDefaults, URLSession, URL, String) {
        let suite = "SupportViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appending(path: suite)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SupportStub.self]
        let session = URLSession(configuration: configuration)
        SupportStub.reset()
        SupportStub.handler { _, _ in throw URLError(.notConnectedToInternet) }
        let relay = SupportRelay(baseURL: URL(string: "https://example.com/support")!, session: session,
                                 defaults: UserDefaults(suiteName: suite)!, keychain: KeychainService(serviceIdentifier: suite), outbox: directory, logTail: { _ in "" })
        // Leave identity absent: automatic flush cannot create real Keychain credentials.
        return (SupportViewModel(relay: relay, defaults: defaults), relay, defaults, session, directory, suite)
    }

    private func cleanup(_ defaults: UserDefaults, _ session: URLSession, _ directory: URL, _ suite: String) {
        session.invalidateAndCancel()
        KeychainService(serviceIdentifier: suite).delete(for: SupportIdentity.secretKey)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor func testSessionStartupConsumesPreviousCrashOnlyOnce() throws {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        _ = AppLog.beginSession(in: directory)
        AppLog.setSessionStage("transcriberen", in: directory)
        XCTAssertFalse(vm.hasBegunSession)
        XCTAssertEqual(vm.beginSessionIfNeeded(in: directory), .crashed(stage: "transcriberen"))
        XCTAssertTrue(vm.hasBegunSession)
        AppLog.setSessionStage("opnemen", in: directory)
        XCTAssertNil(vm.beginSessionIfNeeded(in: directory))
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "session.open"), encoding: .utf8), "opnemen")
    }

    @MainActor func testCleanStartupDoesNotReportCrashOnRootRestart() {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        XCTAssertEqual(vm.beginSessionIfNeeded(in: directory), .clean)
        XCTAssertNil(vm.beginSessionIfNeeded(in: directory))
    }

    @MainActor func testBackgroundBeforeStartupLeavesNoFalseCrashMarker() {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        _ = AppLog.beginSession(in: directory)
        AppLog.setSessionStage("transcriberen", in: directory)
        vm.reconcileSession(isBackground: true, in: directory)
        let previous = vm.beginSessionIfNeeded(in: directory)
        // Startup reconciles the current background phase even without another scene event.
        vm.reconcileSession(isBackground: true, in: directory)
        XCTAssertEqual(previous, .crashed(stage: "transcriberen"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "session.open").path))
        XCTAssertEqual(AppLog.beginSession(in: directory), .clean)
    }

    @MainActor func testStartupBeforeBackgroundLeavesNoFalseCrashMarker() {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        XCTAssertEqual(vm.beginSessionIfNeeded(in: directory), .clean)
        vm.reconcileSession(isBackground: false, in: directory)
        AppLog.setSessionStage("opnemen", in: directory)
        vm.reconcileSession(isBackground: true, in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "session.open").path))
        XCTAssertEqual(AppLog.beginSession(in: directory), .clean)
    }

    @MainActor func testActiveBeforeStartupPreservesCapturedCrashAndRestoresCurrentStage() throws {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        _ = AppLog.beginSession(in: directory)
        AppLog.setSessionStage("notule", in: directory)
        vm.reconcileSession(isBackground: false, in: directory)
        let previous = vm.beginSessionIfNeeded(in: directory)
        vm.reconcileSession(isBackground: false, in: directory)
        AppLog.setSessionStage("opnemen", in: directory)
        XCTAssertEqual(previous, .crashed(stage: "notule"))
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "session.open"), encoding: .utf8), "opnemen")
        XCTAssertNil(vm.beginSessionIfNeeded(in: directory))
    }

    func testFingerprintIgnoresDigits() {
        let first = "WhisperKit-model laden duurde langer dan 120 s (code 3)"
        let second = "WhisperKit-model laden duurde langer dan 90 s (code 17)"
        XCTAssertEqual(SupportViewModel.fingerprint(stage: .transcriberen, error: first), "7ea3d39b266b6289")
        XCTAssertEqual(SupportViewModel.fingerprint(stage: .transcriberen, error: second), "7ea3d39b266b6289")
        XCTAssertEqual(SupportViewModel.fingerprint(stage: .notule, error: first), "63e4d3d1c415c47c")
    }

    func testFingerprintUsesRawErrorBeforeRedaction() {
        XCTAssertNotEqual(SupportViewModel.fingerprint(stage: .opnemen, error: "anna@example.com"),
                          SupportViewModel.fingerprint(stage: .opnemen, error: LogRedact.scrub("anna@example.com")))
    }

    func testUserInstructionsAreNotReported() {
        for message in ["Microfoontoestemming geweigerd. Geef toegang via Instellingen.",
                        "Opname is leeg of te kort om te verwerken.",
                        "Opname is te kort (minimaal 3 seconden). Probeer opnieuw.",
                        "Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.",
                        "Geannuleerd door gebruiker."] {
            XCTAssertFalse(SupportViewModel.shouldReport(message), message)
        }
        XCTAssertTrue(SupportViewModel.shouldReport("Kon het audiobestand niet importeren."))
    }

    func testStageFromPreviousStatus() {
        XCTAssertEqual(SupportViewModel.stage(afterFailureOf: .generatingLocal), .notule)
        XCTAssertEqual(SupportViewModel.stage(afterFailureOf: .transcribing), .transcriberen)
        XCTAssertEqual(SupportViewModel.stage(afterFailureOf: .uploading), .transcriberen)
    }

    @MainActor func testRecordingErrorTransitionReportsOnce() {
        let vm = RecordingViewModel()
        var calls: [(SupportStage, String)] = []
        vm.onFailure = { calls.append(($0, $1)) }
        vm.recordingState = .error("Kon het audiobestand niet importeren.")
        vm.recordingState = .error("Kon het audiobestand niet importeren.")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, .opnemen)
    }

    @MainActor func testUpdateTaskErrorReportsStageOfPreviousStatus() {
        let vm = RecordingViewModel()
        var calls: [(SupportStage, String)] = []
        vm.onFailure = { calls.append(($0, $1)) }
        let task = TranscriptTask(taskId: UUID().uuidString, status: .generatingLocal)
        vm.addTask(task)
        vm.updateTask(task.id, status: .error, errorMessage: "Notule mislukt")
        vm.updateTask(task.id, status: .error, errorMessage: "Notule mislukt")
        XCTAssertEqual(calls.map(\.0), [.notule])
        XCTAssertEqual(calls.first?.1, "Notule mislukt")
    }

    @MainActor func testSessionStageFollowsActiveTask() throws {
        _ = AppLog.beginSession()
        defer { AppLog.endSession() }
        let vm = RecordingViewModel()
        let task = TranscriptTask(taskId: UUID().uuidString, status: .transcribing)
        vm.addTask(task)
        vm.updateTask(task.id, status: .transcribing)
        let marker = AppLog.directory.appending(path: "session.open")
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "transcriberen")
        vm.updateTask(task.id, status: .completed)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "")
        vm.recordingState = .preparing
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "opnemen")
        vm.recordingState = .idle
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "")
    }

    @MainActor func testAutoReportScrubsShownMessage() async {
        let (vm, relay, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        await vm.report(stage: .opnemen, shown: "Bestand niet gevonden: Klant.m4a", error: "Bestand niet gevonden: Klant.m4a")
        let report = await relay.pendingReports().first
        XCTAssertEqual(report?.kind, "auto")
        XCTAssertEqual(report?.category, .bug)
        XCTAssertEqual(report?.stage, "opnemen")
        XCTAssertEqual(report?.shownMessage, "Bestand niet gevonden: k-cc794b")
        XCTAssertEqual(report?.errorText, "Bestand niet gevonden: k-cc794b")
        XCTAssertEqual(report?.fingerprint?.count, 16)
    }

    @MainActor func testAutoReportScrubsBeforeTruncating() async {
        let (vm, relay, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        let shown = String(repeating: "x", count: 4_995) + " anna@example.com"
        await vm.report(stage: .opnemen, shown: shown, error: shown)
        let report = await relay.pendingReports().first
        XCTAssertEqual(report?.shownMessage, String(LogRedact.scrub(shown).prefix(5_000)))
        XCTAssertEqual(report?.errorText, String(LogRedact.scrub(shown).prefix(2_000)))
    }

    @MainActor func testAutoReportOffSkipsAutomaticReports() async {
        let (vm, relay, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        XCTAssertTrue(vm.isAutoReportEnabled)
        defaults.set(false, forKey: SupportIdentity.autoReportKey)
        await vm.report(stage: .notule, shown: "Notule mislukt", error: "Notule mislukt")
        await vm.reportCrash(runningStage: nil)
        let reports = await relay.pendingReports()
        XCTAssertTrue(reports.isEmpty)
    }

    @MainActor func testCrashReportUsesRunningStage() async {
        let (vm, relay, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        await vm.reportCrash(runningStage: .transcriberen)
        await vm.reportCrash(runningStage: nil)
        let reports = await relay.pendingReports()
        XCTAssertEqual(reports.map(\.stage), ["transcriberen", "crash"])
        XCTAssertEqual(reports.map(\.errorText), ["gestopt tijdens transcriberen", "onverwacht gestopt"])
    }

    @MainActor func testManualReportStillQueuesWhenAutomaticReportsAreOff() async {
        let (vm, relay, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        defaults.set(false, forKey: SupportIdentity.autoReportKey)
        let outcome = await vm.submit(category: .question, description: "Mijn vraag")
        XCTAssertEqual(outcome, .queued)
        let reports = await relay.pendingReports()
        XCTAssertEqual(reports.first?.shownMessage, "Mijn vraag")
        XCTAssertEqual(reports.first?.kind, "manual")
        XCTAssertNil(reports.first?.fingerprint)
    }

    @MainActor func testCancelLocalTaskDoesNotQueueAutomaticReport() async {
        let (support, relay, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        let recording = RecordingViewModel()
        var message: String?
        recording.onFailure = { _, shown in message = shown }
        let task = TranscriptTask(taskId: UUID().uuidString, status: .transcribing)
        recording.addTask(task)
        recording.cancelLocalTaskCleanup(task.id)
        XCTAssertEqual(message, "Geannuleerd door gebruiker.")
        await support.report(stage: .transcriberen, shown: message ?? "", error: message ?? "")
        let reports = await relay.pendingReports()
        XCTAssertTrue(reports.isEmpty)
    }

    @MainActor func testTerminalTaskCannotBeRestartedByLateUpdate() {
        let vm = RecordingViewModel()
        let task = TranscriptTask(taskId: UUID().uuidString, status: .transcribing)
        vm.addTask(task)
        vm.cancelLocalTaskCleanup(task.id)
        vm.updateTask(task.id, status: .generatingLocal)
        XCTAssertEqual(vm.activeTasks.first?.status, .error)
    }
    @MainActor func testSSEErrorReportsOnceAndPreservesTaskPayload() {
        let vm = RecordingViewModel()
        let task = TranscriptTask(taskId: UUID().uuidString, status: .generatingLocal)
        vm.addTask(task)
        var stages: [SupportStage] = []
        vm.onFailure = { stage, _ in stages.append(stage) }
        var updated = task
        updated.status = .error
        updated.errorMessage = "Notule mislukt"
        updated.rawTranscription = "LOCAL-TRANSCRIPT"
        vm.handleSSEEvent(updated)
        vm.handleSSEEvent(updated)
        XCTAssertEqual(stages, [.notule])
        XCTAssertEqual(vm.activeTasks.first?.rawTranscription, "LOCAL-TRANSCRIPT")
    }

    @MainActor func testTicketReadFailuresPreserveExistingState() async {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        let ticket = SupportTicket(id: "c1", ref: "TV-1", status: "OPEN", category: "BUG",
                                   description: "Test", unread: true, createdAt: Date(), updatedAt: nil, lastMessage: nil)
        let message = SupportMessage(id: "m1", body: "Test", senderRole: "ADMIN", createdAt: Date())
        vm.unreadCount = 2
        vm.tickets = [ticket]
        vm.thread = [message]
        await vm.refreshUnread()
        await vm.loadTickets()
        await vm.openThread(ticket)
        XCTAssertEqual(vm.unreadCount, 2)
        XCTAssertEqual(vm.tickets, [ticket])
        XCTAssertEqual(vm.thread, [message])
    }

    @MainActor func testSubmitPassesSentAndFailedOutcomes() async throws {
        let (vm, _, defaults, session, directory, suite) = fixture()
        defer { cleanup(defaults, session, directory, suite) }
        defaults.set("Test", forKey: SupportIdentity.nameKey)
        defaults.set("test@example.com", forKey: SupportIdentity.emailKey)
        SupportStub.handler { request, _ in
            .init(status: 201, text: request.url?.lastPathComponent == "installations" ? "{}"
                  : #"{"ticketId":"c1","ref":"TV-1","repeated":false,"count":1}"#)
        }
        let sent = await vm.submit(category: .bug, description: "Test")
        guard case .sent(let result) = sent else { return XCTFail("Expected sent") }
        XCTAssertEqual(result?.ticketId, "c1")
        SupportStub.handler { _, _ in .init(status: 422, text: "{}") }
        let failed = await vm.submit(category: .bug, description: "Test")
        XCTAssertEqual(failed, .failed)
    }

    @MainActor func testSafeSupportMessageKeepsLocalReviewDetail() {
        let vm = RecordingViewModel()
        let task = TranscriptTask(taskId: UUID().uuidString, status: .generatingLocal)
        vm.addTask(task)
        var reported: String?
        vm.onFailure = { _, message in reported = message }
        vm.updateTask(task.id, status: .error, errorMessage: "De notule mist broninformatie: PRIVATE-TRANSCRIPT",
                      supportMessage: "Inhoudscontrole bron T1: missing")
        XCTAssertTrue(vm.activeTasks.first?.errorMessage?.contains("PRIVATE-TRANSCRIPT") == true)
        XCTAssertEqual(reported, "Inhoudscontrole bron T1: missing")
    }

    func testTypedRemoteErrorsKeepLocalAdviceAndUseSafeSupportText() {
        let error = APIError.httpError(422, "PRIVATE-TRANSCRIPT", "INVALID_REQUEST")
        XCTAssertEqual(error.localizedDescription, "PRIVATE-TRANSCRIPT")
        XCTAssertEqual(error.errorCode, "INVALID_REQUEST")
        XCTAssertEqual(RecordingViewModel.supportFailureMessage(error), "Serverfout (HTTP 422).")
        let generation = LLMError.generationFailed("PRIVATE-TRANSCRIPT")
        XCTAssertTrue(generation.localizedDescription.contains("PRIVATE-TRANSCRIPT"))
        XCTAssertEqual(RecordingViewModel.supportFailureMessage(generation), "Generatie mislukt.")
        XCTAssertEqual(RecordingViewModel.supportFailureMessage(LLMError.serverError(429)), LLMError.serverError(429).localizedDescription)
    }

    @MainActor func testSSEFailureDoesNotReportRemoteBody() {
        let vm = RecordingViewModel()
        let task = TranscriptTask(taskId: UUID().uuidString, status: .generatingLocal)
        vm.addTask(task)
        var reported: String?
        vm.onFailure = { _, message in reported = message }
        var updated = task
        updated.status = .error
        updated.errorMessage = "PRIVATE-TRANSCRIPT"
        vm.handleSSEEvent(updated)
        XCTAssertEqual(reported, "Verwerking op de server mislukt.")
        XCTAssertEqual(vm.activeTasks.first?.errorMessage, "PRIVATE-TRANSCRIPT")
    }


    @MainActor func testRecordingAPIFailurePreservesLocalErrorAndReportsSafeMetadataOnce() {
        let vm = RecordingViewModel()
        let error = APIError.httpError(422, "Ongeldige transcriptie: PRIVATE-INHOUD", "INVALID_TRANSCRIPT")
        var calls: [(SupportStage, String)] = []
        vm.onFailure = { calls.append(($0, $1)) }
        // The same helper is used by the uploadTranscriptionText catch.
        vm.recordingFailed(error)
        vm.recordingFailed(error)
        XCTAssertEqual(vm.recordingState, .error(error.localizedDescription))
        XCTAssertEqual(error.errorCode, "INVALID_TRANSCRIPT")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, .opnemen)
        XCTAssertEqual(calls.first?.1, "Serverfout (HTTP 422).")
        XCTAssertFalse(calls.first?.1.contains("PRIVATE-INHOUD") ?? true)
        XCTAssertNil(vm.recordingFailureSupportMessage)
        // A later ordinary transition must not reuse the transient override.
        vm.recordingState = .error("Kon het audiobestand niet importeren.")
        XCTAssertEqual(calls.last?.1, "Kon het audiobestand niet importeren.")
    }

    @MainActor func testCancelledOnDeviceUploadDoesNotReportFailure() {
        let vm = RecordingViewModel()
        var calls = 0
        vm.onFailure = { _, _ in calls += 1 }
        vm.recordingState = .uploading
        vm.recordingFailed(APIError.httpError(422, "PRIVATE-INHOUD", nil), cancelled: true)
        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(vm.recordingFailureSupportMessage)
    }

    @MainActor func testRecordingDecoderFailureDoesNotReportResponseText() {
        let vm = RecordingViewModel()
        var reported: String?
        vm.onFailure = { _, message in reported = message }
        let underlying = NSError(domain: "decoder", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "PRIVATE-INHOUD"])
        let error = APIError.decodingError(underlying)
        vm.recordingFailed(error)
        XCTAssertEqual(vm.recordingState, .error(error.localizedDescription))
        XCTAssertTrue(error.localizedDescription.contains("PRIVATE-INHOUD"))
        XCTAssertEqual(reported, "Fout bij verwerken van serverrespons.")
    }

    @MainActor func testThreadSnapshotsKeepIndependentCentersAndRejectLateRequests() {
        let a = SupportMessage(id: "a", body: "A", senderRole: "ADMIN", createdAt: Date())
        let b = SupportMessage(id: "b", body: "B", senderRole: "ADMIN", createdAt: Date())
        var first = SupportThreadSnapshot()
        var second = SupportThreadSnapshot()
        let firstA = first.begin(ticketID: "A")
        let secondB = second.begin(ticketID: "B")
        second.complete([b], ticketID: "B", request: secondB)
        first.complete([a], ticketID: "A", request: firstA)
        XCTAssertEqual(first.ticketID, "A")
        XCTAssertEqual(first.messages, [a])
        XCTAssertEqual(second.ticketID, "B")
        XCTAssertEqual(second.messages, [b])
        let oldA = first.begin(ticketID: "A")
        let nextB = first.begin(ticketID: "B")
        XCTAssertTrue(first.messages.isEmpty)
        first.complete([b], ticketID: "B", request: nextB)
        first.complete([a], ticketID: "A", request: oldA)
        XCTAssertEqual(first.messages, [b])
        let oldB = first.begin(ticketID: "B")
        let newB = first.begin(ticketID: "B")
        first.complete([a], ticketID: "B", request: oldB)
        XCTAssertEqual(first.messages, [b])
        first.complete([b], ticketID: "B", request: newB)
    }

    @MainActor func testThreadSnapshotPreservesSameTicketOfflineAndClearsNewTicket() {
        let message = SupportMessage(id: "a", body: "A", senderRole: "ADMIN", createdAt: Date())
        var state = SupportThreadSnapshot()
        let first = state.begin(ticketID: "A")
        state.complete([message], ticketID: "A", request: first)
        let refresh = state.begin(ticketID: "A")
        state.complete(nil, ticketID: "A", request: refresh)
        XCTAssertEqual(state.messages, [message])
        let next = state.begin(ticketID: "B")
        state.complete(nil, ticketID: "B", request: next)
        XCTAssertEqual(state.ticketID, "B")
        XCTAssertTrue(state.messages.isEmpty)
    }

}
