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

#if os(macOS)
final class LocalDesktopTests: XCTestCase {
    @MainActor
    func testDesktopNeverRestoresAnAccount() {
        let vm = AuthViewModel()
        vm.checkAuthState()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNil(vm.currentUser)
        XCTAssertFalse(vm.isLoading)
    }

    func testCloudMigrationPreservesProviderAndOnboarding() {
        let name = "ThoughtVaultTests.LocalDesktop.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("cloud", forKey: "processingMode")
        defaults.set("cloud", forKey: "notulenProvider")
        defaults.set("https://ollama.com", forKey: "ollamaURL")
        defaults.set("my-local-model", forKey: "ollamaModel")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        ProcessingMode.configureLocalDesktop(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "processingMode"), "local")
        XCTAssertEqual(defaults.string(forKey: "notulenProvider"), "ollamaCloud")
        XCTAssertEqual(defaults.string(forKey: "ollamaURL"), "https://ollama.com")
        XCTAssertEqual(defaults.string(forKey: "ollamaModel"), "my-local-model")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
        defaults.set("lmStudio", forKey: "notulenProvider")
        ProcessingMode.configureLocalDesktop(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "notulenProvider"), "lmStudio")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
        for url in ["http://localhost:11434", "https://127.0.0.1:27124", "http://[::1]:1234"] {
            XCTAssertTrue(ProcessingMode.isLocalEndpoint(url))
        }
        for url in ["https://ollama.com", "http://localhost.evil.test", "http://user:secret@localhost", "file:///tmp/data"] {
            XCTAssertFalse(ProcessingMode.isLocalEndpoint(url))
        }
    }
}
#endif

final class CloudAIProviderTests: XCTestCase {
    func testCredentialsRequireHTTPSAndEndpointsHaveNoURLCredentials() {
        let service = OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "model", apiKey: "test-key")
        var secure = URLRequest(url: URL(string: "https://ollama.com/v1/models")!)
        service.applyAuth(to: &secure)
        XCTAssertEqual(secure.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        var insecure = URLRequest(url: URL(string: "http://localhost:11434/v1/models")!)
        service.applyAuth(to: &insecure)
        XCTAssertNil(insecure.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(OpenAICompatibleLLMService.isAllowedEndpoint("https://api.example.com/v1"))
        XCTAssertFalse(OpenAICompatibleLLMService.isAllowedEndpoint("http://api.example.com"))
        XCTAssertFalse(OpenAICompatibleLLMService.isAllowedEndpoint("https://user:secret@api.example.com"))
    }
    func testSeparateConfigurationsSurviveReload() {
        let suite = "CloudAIProviderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CloudAIConfiguration(name: "Eerste", baseURL: "https://first.example/v1", model: "one")
        let second = CloudAIConfiguration(name: "Tweede", baseURL: "https://second.example", model: "two")
        CloudAIConfiguration.save([first, second], defaults: defaults)
        XCTAssertEqual(CloudAIConfiguration.load(defaults: defaults), [first, second])
        XCTAssertNotEqual(first.keychainKey, second.keychainKey)
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
