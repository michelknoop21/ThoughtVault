import XCTest
@testable import ThoughtVault

final class ThoughtVaultTests: XCTestCase {
    func testModelsDecodable() throws {
        // Test that core models decode correctly.
        // The Transcript model uses "date" as the JSON key (via CodingKeys).
        let json = """
        {"id":"test-123","title":"Test vergadering","raw_transcription":"Dit is een test transcriptie.","notule_html":null,"tags":[],"date":"2026-03-04T12:00:00Z"}
        """.data(using: .utf8)!

        let transcript = try JSONDecoder().decode(Transcript.self, from: json)
        XCTAssertEqual(transcript.id, "test-123")
        XCTAssertEqual(transcript.title, "Test vergadering")
    }

    func testRegeneratedTaskReadsBackendResult() throws {
        let data = Data("""
        {"task_id":"regen-42","status":"completed","result":"<h1>Nieuwe notule</h1>"}
        """.utf8)
        let task = try JSONDecoder().decode(TranscriptTask.self, from: data)
        XCTAssertEqual(task.notuleHtml, "<h1>Nieuwe notule</h1>")
    }

    func testObsidianFilenameStaysStableWhenTitleChanges() {
        let date = Date(timeIntervalSince1970: 1_790_760_000)
        XCTAssertEqual(
            ObsidianService.fileName(title: "Eerste titel", date: date, noteID: "local-123"),
            ObsidianService.fileName(title: "Gewijzigde titel", date: date, noteID: "local-123")
        )
    }

    func testObsidianMarkdownCanBeReadInApp() {
        let html = markdownToNotuleHTML("# Besluit\n\n- Planning akkoord")
        XCTAssertTrue(html.contains("<h1>Besluit</h1>"))
        XCTAssertTrue(html.contains("<li>Planning akkoord</li>"))
    }

    func testTaskStatusProgress() {
        XCTAssertEqual(TaskStatus.pending.progress, 0.0)
        XCTAssertEqual(TaskStatus.completed.progress, 1.0)
        XCTAssertFalse(TaskStatus.completed.isActive)
        XCTAssertTrue(TaskStatus.transcribing.isActive)
    }

    func testUploadFailureReasonRetryability() {
        XCTAssertFalse(UploadFailureReason.fileTooLarge.isRetryable)
        XCTAssertTrue(UploadFailureReason.serverError(500).isRetryable)
        XCTAssertTrue(UploadFailureReason.unknown.isRetryable)
    }

    func testCompletedLocalNotuleNeedsTranscriptAndContent() {
        XCTAssertFalse(RecordingViewModel.hasUsableTranscription("..."))
        XCTAssertFalse(RecordingViewModel.hasUsableTranscription("Geen transcriptie."))
        XCTAssertFalse(RecordingViewModel.hasUsableTranscription("[ruis] ... (stilte) ... [onverstaanbaar]"))
        XCTAssertTrue(RecordingViewModel.hasUsableTranscription("We hebben de planning voor volgende week besproken."))
        XCTAssertFalse(RecordingViewModel.hasUsableNotule("<style>h1{color:red}</style><p>...</p>"))
        XCTAssertFalse(RecordingViewModel.hasUsableNotule("<h1>[Titel]</h1><p>[Samenvatting]</p>"))
        XCTAssertFalse(RecordingViewModel.hasUsableNotule("<p>Er is geen transcriptie aangeleverd.</p>"))
        XCTAssertTrue(RecordingViewModel.hasUsableNotule("<h2>Kernuitkomst</h2><p>De planning voor volgende week is besproken.</p>"))
    }

    @MainActor
    func testEditingMissingLocalRecordReportsFailure() {
        XCTAssertThrowsError(try LocalTranscriptStore.shared.updateNotule(taskId: "local-missing-record", html: "<p>Concept</p>"))
        XCTAssertThrowsError(try LocalTranscriptStore.shared.delete(taskId: "local-missing-record"))
    }

    @MainActor
    func testDisplayedNotuleUsesAppStyleAndDoesNotRepeatTitle() {
        let html = "<style>body{background:red}</style><header><h1>Planning</h1></header><p>De planning is besproken.</p>"
        let result = EditableHTMLWebView.preparedContent(html)
        XCTAssertFalse(result.contains("background:red"))
        XCTAssertFalse(result.contains("<h1>"))
        XCTAssertTrue(result.contains("De planning is besproken."))
        XCTAssertFalse(EditableHTMLWebView.preparedContent("<h1>Eerste</h1><h1>Tweede</h1><p>Tekst</p>").contains("<h1>"))
    }

    @MainActor
    func testEditingStyledNotulePreservesItsStylesAndOriginalTitle() {
        let original = "<style>.step{counter-increment:step}</style><h1>Handleiding</h1><section class=\"step\"><p>Oud</p></section>"
        let saved = restoreNotuleMarkup(original: original, editedBody: "<section class=\"step\"><p>Nieuw</p></section>")
        XCTAssertTrue(saved.contains("<style>.step{counter-increment:step}</style>"))
        XCTAssertTrue(saved.contains("<h1>Handleiding</h1>"))
        XCTAssertTrue(saved.contains("<p>Nieuw</p>"))
        XCTAssertFalse(saved.contains("<p>Oud</p>"))
    }
}

final class ProfileChoiceTests: XCTestCase {
    func testCurrentBuiltInsAndLocalCustomProfiles() throws {
        XCTAssertEqual(Profile.defaults.map(\.id), ["standaard", "executive", "projectoverleg", "klantgesprek", "een_op_een", "brainstorm", "promptnotitie"])
        let suite = "ProfileChoiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = Profile(id: "custom-1", name: "Eigen", notulePrompt: "Vat samen", isDefault: false)
        try LocalProfileStore.save(custom, defaults: defaults)
        XCTAssertEqual(LocalProfileStore.load(defaults: defaults), [custom])
        XCTAssertEqual(LocalProfileStore.choices(defaults: defaults).last?.id, custom.id)
        let choices = Profile.currentChoices([.zakelijk, custom])
        XCTAssertEqual(choices.map(\.id).prefix(7), Profile.defaults.map(\.id).prefix(7))
        XCTAssertEqual(choices.last?.id, custom.id)
        XCTAssertFalse(choices.dropFirst(7).contains { $0.id == "zakelijk" })
        let structured = Profile(id: "custom-2", name: "Eigen", template: "<h1>[Titel]</h1><section><h2>Context</h2><p>[Brongebonden inhoud]</p></section>", isDefault: false)
        XCTAssertEqual(structured.sectionNames, ["Context"])
        try LocalProfileStore.delete(id: custom.id, defaults: defaults)
        XCTAssertTrue(LocalProfileStore.load(defaults: defaults).isEmpty)
    }
}

@MainActor
final class SystemAudioPermissionTests: XCTestCase {
    func testUnavailableOutputRemainsNeutralAndStartFailureOffersRecovery() {
        let manager = PermissionManager.shared
        manager.systemAudioGranted = nil
        manager.recordSystemAudioResult(SystemAudioCaptureError.noOutputDevice)
        XCTAssertNil(manager.systemAudioGranted)
        manager.recordSystemAudioResult(SystemAudioCaptureError.coreAudio("opname", -1))
        XCTAssertEqual(manager.systemAudioGranted, false)
        manager.recordSystemAudioResult(nil)
        XCTAssertEqual(manager.systemAudioGranted, true)
        manager.systemAudioGranted = nil
    }
}

@MainActor
final class RestartTaskTests: XCTestCase {
    private func failedTask(audioPath: String?) -> TranscriptTask {
        TranscriptTask(id: "local-restart-test", taskId: "local-restart-test", filename: "x.wav",
                       status: .error, localAudioPath: audioPath, progress: 0, profileId: nil, createdAt: Date())
    }

    func testFailedTaskWithAudioOnDiskCanRestart() throws {
        let vm = RecordingViewModel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restart-\(UUID().uuidString).wav")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(vm.canRestartTask(failedTask(audioPath: url.path)))
    }

    func testFailedTaskWithoutRecordOrAudioCannotRestart() {
        let vm = RecordingViewModel()
        XCTAssertFalse(vm.canRestartTask(failedTask(audioPath: nil)))
        XCTAssertFalse(vm.canRestartTask(failedTask(audioPath: "/nonexistent/x.wav")))
    }

    func testOnlyFailedTasksCanRestart() throws {
        let vm = RecordingViewModel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restart-\(UUID().uuidString).wav")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var task = failedTask(audioPath: url.path)
        task.status = .completed
        XCTAssertFalse(vm.canRestartTask(task))
    }
}

final class LiveTranscriptionPolicyTests: XCTestCase {
    #if os(macOS)
    func testEveryModeListensToItsOwnSources() {
        XCTAssertEqual(LiveTranscriptionPolicy.sources(for: .microphone), [.microphone])
        XCTAssertEqual(LiveTranscriptionPolicy.sources(for: .systemAudio), [.system])
        XCTAssertEqual(LiveTranscriptionPolicy.sources(for: .combined), [.microphone, .system])
    }
    #endif

    func testLiveTextOfRestartedRequestsIsAppended() {
        XCTAssertEqual(OnDeviceTranscriber.joinLive("", "hallo"), "hallo")
        XCTAssertEqual(OnDeviceTranscriber.joinLive("hallo", "wereld"), "hallo wereld")
        XCTAssertEqual(OnDeviceTranscriber.joinLive("hallo", ""), "hallo")
    }

    func testBenignRecognitionEndsAreNotErrors() {
        for code in [203, 216, 301, 1110] {
            XCTAssertTrue(OnDeviceTranscriber.isBenignLiveError(NSError(domain: "kAFAssistantErrorDomain", code: code)), "code \(code)")
        }
        XCTAssertFalse(OnDeviceTranscriber.isBenignLiveError(NSError(domain: "kAFAssistantErrorDomain", code: 1101)))
        XCTAssertFalse(OnDeviceTranscriber.isBenignLiveError(NSError(domain: "kAFAssistantErrorDomain", code: 1107)))
    }

    func testStatusExplainsWhyThereIsNoLiveText() {
        func status(_ preferred: Bool = true, _ available: Bool = true, _ error: String? = nil) -> String? {
            LiveTranscriptionPolicy.statusText(preferred: preferred, available: available, error: error)
        }
        XCTAssertEqual(status(false), "Opname loopt (live tekst staat uit)")
        XCTAssertEqual(status(true, false), "Opname loopt (live tekst niet beschikbaar)")
        XCTAssertEqual(status(true, true, "Toestemming geweigerd"), "Live tekst gestopt: Toestemming geweigerd")
        // Running (or starting): no status, the screen shows "Ik luister..." and then the text.
        XCTAssertNil(status(true, true, nil))
    }
}

@MainActor
final class UpdateInstallationTests: XCTestCase {
    func testRecordingCannotStartDuringUpdateInstallation() async {
        let vm = RecordingViewModel()
        XCTAssertFalse(vm.updateIsBusy)
        vm.recordingState = .paused
        XCTAssertTrue(vm.updateIsBusy)
        vm.recordingState = .idle
        vm.updateInstalling = true
        await vm.startRecording()
        XCTAssertEqual(vm.recordingState, .idle)
    }
}
