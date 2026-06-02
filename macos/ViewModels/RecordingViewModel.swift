import AVFoundation
import Foundation
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
import ScreenCaptureKit
#endif

private let log = OSLog(subsystem: "nl.prezent.TranscriptStudio", category: "RecordingVM")

// MARK: - RecordingViewModel

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - Published State

    var recordingState: RecordingState = .idle
    var selectedMode: RecordingMode = .microphone
    var selectedProfile: Profile?
    var usePremium: Bool = false
    var availableProfiles: [Profile] = []
    var activeTasks: [TranscriptTask] = []
    var uploadProgress: Double = 0
    var liveTranscriptText: String = ""
    var isLiveTranscribing: Bool = false
    var localGenerationProgress: Double = 0
    var isGeneratingLocally: Bool = false
    var offlineStatusMessage: String?
    var lastFailedRecording: SavedRecording?
    var savedRecordings: [SavedRecording] = []
    var audioMixFallbackOccurred: Bool = false

    // YouTube transcription
    var isYouTubeEnabled: Bool = false
    var youtubeURL: String = ""
    var isSubmittingYouTube: Bool = false
    var youtubeError: String?
    // Google OAuth for YouTube
    var isGoogleConnected: Bool = false
    var googleUserEmail: String?
    var googleAuthError: String?
    var captionsNotAvailable: Bool = false

    // MARK: - Audio Properties (computed, @Observable-compatible)

    /// Combined audio levels from the active recorder(s). In combined mode the
    /// levels from both audioRecorder and systemAudioCapture are merged using
    /// element-wise max so the waveform reflects both audio sources.
    var audioLevels: [Float] {
        switch selectedMode {
        case .microphone:
            return audioRecorder.audioLevels
        case .systemAudio:
#if os(macOS)
            return systemAudioCapture.audioLevels
#else
            return audioRecorder.audioLevels
#endif
        case .combined:
#if os(macOS)
            let sys = systemAudioCapture.audioLevels
            let mic = audioRecorder.audioLevels
            let count = min(mic.count, sys.count)
            var merged = [Float](repeating: 0, count: count)
            for i in 0..<count {
                merged[i] = max(mic[i], sys[i])
            }
            return merged
#else
            return audioRecorder.audioLevels
#endif
        }
    }

    /// Duration from the primary active recorder.
    var duration: TimeInterval {
#if os(macOS)
        if selectedMode == .systemAudio || selectedMode == .combined {
            return systemAudioCapture.duration
        }
#endif
        return audioRecorder.duration
    }

    // MARK: - Services

    let audioRecorder = AudioRecorder()
#if os(macOS)
    let systemAudioCapture = SystemAudioCapture()
#endif
    let onDeviceTranscriber = OnDeviceTranscriber.shared
    let offlineQueue = OfflineQueue.shared

    var onDeviceTranscriptionAvailable: Bool {
        onDeviceTranscriber.isAvailable()
    }

    // MARK: - AppStorage

    @ObservationIgnored
    @AppStorage("preferOnDeviceTranscription") var preferOnDeviceTranscription = false

    @ObservationIgnored
    @AppStorage("processingMode") var processingModeRaw = ProcessingMode.local.rawValue

    /// Whether the app is configured to process everything locally (no server).
    var isLocalMode: Bool {
        (ProcessingMode(rawValue: processingModeRaw) ?? .local) == .local
    }

    // MARK: - SSE Clients

    var sseClients: [String: SSEClient] = [:]

    // MARK: - macOS Sleep Handling

#if os(macOS)
    var sleepInterruptedFileURL: URL?
    @ObservationIgnored
    nonisolated(unsafe) var sleepObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
#endif

    // MARK: - Private

    @ObservationIgnored
    private var isStartingLiveTranscription = false
    @ObservationIgnored
    private var liveTranscriptionTask: Task<Void, Never>?
    @ObservationIgnored
    private var pendingRemovalTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var uploadTask: Task<Void, Never>?
    private var isProcessingQueue = false
    private var networkMonitor = NetworkMonitor.shared

    // MARK: - Init

    init() {
        audioRecorder.onSilentFailure = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.recordingState = .error(error.localizedDescription)
            }
        }

        loadSavedRecordings()

#if os(macOS)
        setupSleepWakeObservers()
#endif

        // Load profiles from API (restore saved selection if available)
        Task {
            await loadDefaultProfile(savedId: UserDefaults.standard.string(forKey: "lastSelectedProfileId") ?? "")
            await checkFeatures()
        }
    }

    deinit {
        liveTranscriptionTask?.cancel()
        for task in pendingRemovalTasks.values { task.cancel() }
#if os(macOS)
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
#endif
    }

    // MARK: - Profile Loading

    /// Reload profiles from API. Call after login to fetch user-specific profiles.
    func reloadProfiles() async {
        await loadDefaultProfile(savedId: UserDefaults.standard.string(forKey: "lastSelectedProfileId") ?? "")
    }

    private func loadDefaultProfile(savedId: String) async {
        var profiles: [Profile]
        do {
            profiles = try await APIService.shared.getProfiles()
        } catch {
            os_log("[RecordingVM] Could not load profiles from API, using defaults: %{public}@", log: .default, type: .error, error.localizedDescription)
            profiles = Profile.defaults
        }

        if profiles.isEmpty {
            profiles = Profile.defaults
        }

        availableProfiles = profiles
        if let match = profiles.first(where: { $0.id == savedId }) {
            selectedProfile = match
        } else if let first = profiles.first {
            selectedProfile = first
        }
    }

    // MARK: - macOS Sleep / Wake

#if os(macOS)
    private func setupSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleWillSleep()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleDidWake()
            }
        }
    }

    private func handleWillSleep() {
        guard recordingState.isRecording else { return }
        os_log("[RecordingVM] System will sleep — stopping active recording", log: .default)
        // Capture the current file URL before stopping
        sleepInterruptedFileURL = audioRecorder.currentRecordingURL
        Task {
            await stopLiveTranscription()
            // Stop recorder synchronously via the sleep notification path
            _ = await audioRecorder.stopRecording()
#if os(macOS)
            let _ = await systemAudioCapture.stopCapture()
#endif
            await MainActor.run {
                self.recordingState = .idle
            }
        }
    }

    private func handleDidWake() {
        guard sleepInterruptedFileURL != nil else { return }
        os_log("[RecordingVM] System woke — interrupted recording file available for recovery", log: .default)
        // Load saved recordings so the user can find and reprocess the interrupted file
        loadSavedRecordings()
    }
#endif

    // MARK: - Recording Lifecycle

    func startRecording() async {
        guard recordingState == .idle else { return }

        await MainActor.run {
            recordingState = .preparing
            audioMixFallbackOccurred = false
        }

        // Request permissions
        await audioRecorder.requestPermission()
        guard audioRecorder.hasPermission else {
            await MainActor.run {
                recordingState = .error("Microfoontoestemming geweigerd. Geef toegang via Instellingen.")
            }
            return
        }

#if os(macOS)
        if selectedMode == .systemAudio || selectedMode == .combined {
            let hasScreenPermission = await ensureScreenCapturePermission()
            guard hasScreenPermission else {
                await MainActor.run {
                    recordingState = .error("Systeemaudio-toegang is vereist voor videocall-opname. Geef toegang in Systeeminstellingen > Privacy en beveiliging > Systeemaudio-opname, en herstart daarna de app.")
                }
                return
            }
        }
#endif

        do {
            switch selectedMode {
            case .microphone:
                try await audioRecorder.startRecording()

            case .systemAudio:
#if os(macOS)
                try await systemAudioCapture.startCapture()
#else
                try await audioRecorder.startRecording()
#endif

            case .combined:
#if os(macOS)
                // Capture system audio via ScreenCaptureKit and microphone via AVAudioRecorder.
                // This avoids relying on SCStream microphone output, which is not reliable
                // across all macOS versions/configurations.
                _ = try await systemAudioCapture.startCapture(includeMicrophone: false)
                try await audioRecorder.startRecording()
#else
                try await audioRecorder.startRecording()
#endif
            }

            await MainActor.run {
                recordingState = .recording
                #if os(macOS)
                sleepInterruptedFileURL = nil
                #endif
            }

            await startLiveTranscriptionIfEnabled()

        } catch {
#if os(macOS)
            if selectedMode == .systemAudio || selectedMode == .combined {
                _ = await systemAudioCapture.stopCapture()
            }
#endif
            _ = await audioRecorder.stopRecording()
            await MainActor.run {
                recordingState = .error(error.localizedDescription)
            }
        }
    }

    func pauseRecording() {
        guard case .recording = recordingState else { return }
#if os(macOS)
        if selectedMode != .systemAudio {
            audioRecorder.pauseRecording()
        }
        if selectedMode == .systemAudio || selectedMode == .combined {
            systemAudioCapture.pauseDurationTimer()
        }
#else
        audioRecorder.pauseRecording()
#endif
        recordingState = .paused
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil
        isLiveTranscribing = false
    }

    func resumeRecording() {
        guard case .paused = recordingState else { return }
#if os(macOS)
        if selectedMode != .systemAudio {
            audioRecorder.resumeRecording()
        }
        if selectedMode == .systemAudio || selectedMode == .combined {
            systemAudioCapture.resumeDurationTimer()
        }
#else
        audioRecorder.resumeRecording()
#endif
        recordingState = .recording
        Task { await startLiveTranscriptionIfEnabled() }
    }

    func stopAndUpload() async {
        guard recordingState == .recording || recordingState == .paused else { return }

        os_log("[RecordingVM] stopAndUpload: state=%{public}@, profile=%{public}@", log: log, type: .info, "\(recordingState)", selectedProfile?.name ?? "nil")

        await MainActor.run { recordingState = .stopping }
        await stopLiveTranscription()

        // Determine final audio URL
        let finalURL: URL?

#if os(macOS)
        switch selectedMode {
        case .microphone:
            _ = await systemAudioCapture.stopCapture()
            let micURL = await audioRecorder.stopRecording()
            finalURL = micURL
        case .systemAudio:
            let result = await systemAudioCapture.stopCapture()
            _ = await audioRecorder.stopRecording()
            finalURL = result.systemAudioURL
        case .combined:
            let result = await systemAudioCapture.stopCapture()
            let micURL = await audioRecorder.stopRecording()
            if let sys = result.systemAudioURL, let mic = micURL {
                let mixed = await mixAudioFiles(micURL: mic, systemURL: sys)
                if mixed == mic {
                    audioMixFallbackOccurred = true
                }
                finalURL = mixed
            } else {
                audioMixFallbackOccurred = true
                finalURL = result.systemAudioURL ?? micURL
            }
        }
#else
        let micURL = await audioRecorder.stopRecording()
        finalURL = micURL
#endif

        guard let url = finalURL else {
            await MainActor.run {
                recordingState = .error("Opname is leeg of te kort om te verwerken.")
            }
            return
        }

        // Validate file has actual audio content (16kHz mono 16-bit = ~32KB/sec, minimum 3 seconds)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        os_log("[RecordingVM] stopAndUpload: fileSize=%lld, network=%{public}@", log: log, type: .info, fileSize, networkMonitor.isConnected ? "connected" : "offline")
        if fileSize < 96_000 {
            os_log("[RecordingVM] Recording file too small (%lld bytes), likely too short", log: log, type: .error, fileSize)
            await MainActor.run {
                recordingState = .error("Opname is te kort (minimaal 3 seconden). Probeer opnieuw.")
            }
            return
        }

        guard let profile = selectedProfile else {
            await MainActor.run {
                recordingState = .error("Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.")
            }
            return
        }

        // Fully local mode: transcribe + generate notulen on-device, no server needed.
        if isLocalMode {
            os_log("[RecordingVM] stopAndUpload: path=local", log: log, type: .info)
            await processLocally(url: url, profileId: profile.id)
            return
        }

        // Decide upload path
        if networkMonitor.isConnected {
#if os(macOS)
            // ScreenCaptureKit produces float32 PCM that SFSpeechRecognizer cannot reliably
            // process. For systemAudio and combined modes, always use cloud transcription.
            let canUseOnDevice = preferOnDeviceTranscription && onDeviceTranscriptionAvailable
                && selectedMode == .microphone
#else
            let canUseOnDevice = preferOnDeviceTranscription && onDeviceTranscriptionAvailable
#endif
            if canUseOnDevice {
                os_log("[RecordingVM] stopAndUpload: path=onDevice", log: log, type: .info)
                await transcribeOnDeviceThenUpload(url: url, profileId: profile.id)
            } else {
                os_log("[RecordingVM] stopAndUpload: path=cloud", log: log, type: .info)
                await uploadFile(url, profileId: profile.id)
            }
        } else {
            os_log("[RecordingVM] stopAndUpload: path=offline", log: log, type: .info)
            await handleOfflineRecording(url: url)
        }
    }

    func cancelRecording() async {
        guard recordingState == .recording || recordingState == .paused else { return }

        await stopLiveTranscription()
#if os(macOS)
        let captureResult = await systemAudioCapture.stopCapture()
#endif
        _ = await audioRecorder.stopRecording()

        // Delete recording files
        if let url = audioRecorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
#if os(macOS)
        if let url = captureResult.systemAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = captureResult.microphoneURL {
            try? FileManager.default.removeItem(at: url)
        }
#endif

        await MainActor.run {
            recordingState = .idle
            uploadProgress = 0
        }
    }

    // MARK: - Upload

    func uploadFile(_ url: URL, profileId: String) async {
        os_log("[RecordingVM] uploadFile: starting for %{public}@", log: log, type: .info, url.lastPathComponent)

        // Create a temporary task so the upload is immediately visible in the task list
        let tempId = "upload-\(UUID().uuidString)"
        let pendingTask = TranscriptTask(
            id: tempId,
            taskId: tempId,
            filename: url.lastPathComponent,
            status: .uploading,
            progress: 0
        )

        await MainActor.run {
            addTask(pendingTask)
            recordingState = .idle
            lastFailedRecording = nil
        }

        uploadTask = Task {
            do {
                try Task.checkCancellation()

                let task = try await APIService.shared.uploadAudio(
                    fileURL: url,
                    profileId: profileId,
                    usePremium: usePremium
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.updateTask(tempId, status: .uploading, progress: progress)
                    }
                }

                try Task.checkCancellation()

                os_log("[RecordingVM] uploadFile: success, taskId=%{public}@", log: log, type: .info, task.taskId)

                await MainActor.run {
                    // Replace temp task with real server task
                    self.activeTasks.removeAll { $0.id == tempId }
                    self.addTask(task)
                }

                // Start SSE stream for server-side processing updates
                if !task.taskId.isEmpty {
                    await startSSEStream(for: task.taskId)
                }

                saveLocalAudioPath(url: url, taskId: task.taskId)
                loadSavedRecordings()

            } catch is CancellationError {
                os_log("[RecordingVM] Upload cancelled by user", log: log, type: .info)
                await MainActor.run {
                    self.activeTasks.removeAll { $0.id == tempId }
                }
            } catch let error as APIError {
                if RecordingViewModel.isAuthError(error) {
                    os_log("[RecordingVM] Auth error during upload — enqueuing to offline queue", log: .default, type: .info)
                    self.offlineQueue.enqueue(.audio(url: url))
                    await MainActor.run {
                        self.offlineStatusMessage = "Upload uitgesteld vanwege een sessiefout. De opname is opgeslagen en wordt automatisch opnieuw geprobeerd."
                    }
                }
                loadSavedRecordings()
                await MainActor.run {
                    self.updateTask(tempId, status: .error, errorMessage: error.localizedDescription)
                    self.lastFailedRecording = self.savedRecordings.first { $0.filename == url.lastPathComponent }
                }
                os_log("[RecordingVM] Upload failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            } catch {
                os_log("[RecordingVM] Upload failed (non-API): %{public}@", log: .default, type: .error, error.localizedDescription)
                loadSavedRecordings()
                await MainActor.run {
                    self.updateTask(tempId, status: .error, errorMessage: error.localizedDescription)
                    self.lastFailedRecording = self.savedRecordings.first { $0.filename == url.lastPathComponent }
                }
            }
        }

        // Don't await — upload runs in background
    }

    func cancelUpload(_ taskId: String? = nil) {
        if let taskId {
            activeTasks.removeAll { $0.id == taskId }
            if taskId.hasPrefix("upload-") {
                uploadTask?.cancel()
                uploadTask = nil
            }
        } else {
            // Cancel the current upload task (legacy call without ID)
            uploadTask?.cancel()
            uploadTask = nil
            activeTasks.removeAll { $0.id.hasPrefix("upload-") }
        }
    }

    // MARK: - On-Device Transcription

    func transcribeOnDeviceThenUpload(url: URL, profileId: String) async {
        await MainActor.run {
            isLiveTranscribing = true
            liveTranscriptText = ""
            recordingState = .uploading
        }

        do {
            var fullTranscription = ""

            let result = try await onDeviceTranscriber.transcribe(url: url)
            await MainActor.run {
                self.liveTranscriptText = result
                fullTranscription = result
            }

            await MainActor.run { isLiveTranscribing = false }

            guard !fullTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run {
                    recordingState = .error("Transcriptie is leeg. Probeer het opnieuw.")
                }
                return
            }

            // Upload transcription text to server
            let task = try await APIService.shared.uploadTranscriptionText(
                transcription: fullTranscription,
                profileId: profileId
            )

            await MainActor.run {
                self.addTask(task)
                recordingState = .idle
                liveTranscriptText = ""
            }

            await startSSEStream(for: task.taskId)
            loadSavedRecordings()

        } catch {
            await MainActor.run {
                isLiveTranscribing = false
                recordingState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Fully Local Processing

    /// Transcribes and generates notulen entirely on-device, then stores the result
    /// in the local SwiftData store. No backend server is contacted.
    func processLocally(url: URL, profileId: String) async {
        let profile = availableProfiles.first { $0.id == profileId }
            ?? Profile.defaults.first { $0.id == profileId }
            ?? selectedProfile
            ?? .zakelijk

        let localId = "local-\(UUID().uuidString)"
        let task = TranscriptTask(
            id: localId,
            taskId: localId,
            filename: url.lastPathComponent,
            status: .transcribing,
            localAudioPath: url.path,
            progress: TaskStatus.transcribing.progress,
            profileId: profile.id,
            createdAt: Date()
        )

        await MainActor.run {
            addTask(task)
            recordingState = .idle
            isLiveTranscribing = false
            liveTranscriptText = ""
        }

        // 1. Local transcription
        let transcription: String
        do {
            let transcriber = LocalTranscriberFactory.make()
            transcription = try await transcriber.transcribe(url: url) { [weak self] fraction in
                Task { @MainActor in
                    self?.updateTask(localId, status: .transcribing,
                                     progress: 0.15 + fraction * 0.35)
                }
            }
        } catch {
            os_log("[RecordingVM] processLocally transcription failed: %{public}@", log: log, type: .error, error.localizedDescription)
            updateTask(localId, status: .error, errorMessage: error.localizedDescription)
            return
        }

        // 2. Persist a partial record immediately so an expensive transcription is
        //    never lost if notule generation fails afterwards.
        let fallback = fallbackTitle(transcription: transcription, filename: url.lastPathComponent)
        let record = TranscriptRecord(
            id: localId,
            taskId: localId,
            title: fallback,
            filename: url.lastPathComponent,
            rawTranscription: transcription,
            notuleHtml: "",
            profileId: profile.id,
            profileName: profile.name,
            createdAt: Date(),
            localAudioPath: url.path,
            source: "local"
        )
        do {
            try LocalTranscriptStore.shared.save(record)
        } catch {
            os_log("[RecordingVM] processLocally save failed: %{public}@", log: log, type: .error, error.localizedDescription)
            updateTask(localId, status: .error, errorMessage: "Opslaan mislukt: \(error.localizedDescription)")
            return
        }

        setTaskTranscription(localId, transcription)
        updateTask(localId, status: .generatingLocal, progress: TaskStatus.generatingLocal.progress)
        isGeneratingLocally = true
        localGenerationProgress = 0
        saveLocalAudioPath(url: url, taskId: localId)
        loadSavedRecordings()

        // 3. Local notule generation via the configured provider.
        let providerRaw = UserDefaults.standard.string(forKey: "notulenProvider") ?? NotulenProvider.ollama.rawValue
        var provider = NotulenProvider(rawValue: providerRaw) ?? .ollama
        if provider == .cloud { provider = .ollama }   // cloud is meaningless offline

        do {
            let service = LLMServiceFactory.service(for: provider, serverURL: "")
            // Live preview is driven solely by ordered append chunks; the saved
            // record uses the authoritative return value (no final overwrite race).
            let html = try await service.generateNotulen(
                transcription: transcription,
                systemPrompt: profile.systemPrompt ?? "",
                notulePrompt: profile.notulePrompt ?? "",
                outputTemplate: profile.template
            ) { [weak self] chunk in
                Task { @MainActor in
                    self?.appendTaskNotuleHtml(localId, chunk)
                }
            }

            let title = NotuleTitleExtractor.extract(from: html) ?? fallback
            try LocalTranscriptStore.shared.finalizeNotule(taskId: localId, html: html, title: title)

            updateTask(localId, status: .completed, progress: 1.0)
            isGeneratingLocally = false
            localGenerationProgress = 1.0

        } catch {
            // Transcription is already saved; only the notule step failed.
            os_log("[RecordingVM] processLocally notule failed: %{public}@", log: log, type: .error, error.localizedDescription)
            isGeneratingLocally = false
            updateTask(localId, status: .error,
                       errorMessage: "Transcriptie opgeslagen, notule mislukt: \(error.localizedDescription)")
        }
    }

    /// Regenerates the notule for an already-stored local record using its saved
    /// transcription and the given profile — entirely on-device. Returns the new
    /// HTML and title so the open detail view can stay in sync with SwiftData.
    func regenerateNotuleLocally(taskId: String, profileId: String) async throws -> (html: String, title: String) {
        guard let record = LocalTranscriptStore.shared.record(forTaskId: taskId) else {
            throw LocalStoreError.recordNotFound
        }
        let profile = availableProfiles.first { $0.id == profileId }
            ?? Profile.defaults.first { $0.id == profileId }
            ?? selectedProfile
            ?? .zakelijk

        var provider = NotulenProvider(rawValue: UserDefaults.standard.string(forKey: "notulenProvider") ?? NotulenProvider.ollama.rawValue) ?? .ollama
        if provider == .cloud { provider = .ollama }

        let service = LLMServiceFactory.service(for: provider, serverURL: "")
        let html = try await service.generateNotulen(
            transcription: record.rawTranscription,
            systemPrompt: profile.systemPrompt ?? "",
            notulePrompt: profile.notulePrompt ?? "",
            outputTemplate: profile.template
        ) { _ in }

        let title = NotuleTitleExtractor.extract(from: html) ?? record.title
        try LocalTranscriptStore.shared.finalizeNotule(taskId: taskId, html: html, title: title)
        return (html, title)
    }

    /// Builds a fallback title from the transcription's first sentence or the filename.
    private func fallbackTitle(transcription: String, filename: String) -> String {
        let firstSentence = transcription
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstSentence.count >= 6 {
            return String(firstSentence.prefix(80))
        }
        return filename
    }

    private func setTaskTranscription(_ id: String, _ text: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        activeTasks[idx].rawTranscription = text
    }

    private func appendTaskNotuleHtml(_ id: String, _ chunk: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        activeTasks[idx].notuleHtml = (activeTasks[idx].notuleHtml ?? "") + chunk
    }

    // MARK: - Offline Recording

    func handleOfflineRecording(url: URL) async {
        offlineQueue.enqueue(.audio(url: url))

        await MainActor.run {
            recordingState = .idle
            offlineStatusMessage = "Geen verbinding. Opname opgeslagen en wordt automatisch geüpload zodra je weer online bent."
        }

        loadSavedRecordings()
    }

    // MARK: - Queue Processing

    func processQueueOnStartupIfNeeded() async {
        guard networkMonitor.isConnected else { return }
        guard !isProcessingQueue else { return }
        guard let profileId = selectedProfile?.id else { return }
        isProcessingQueue = true
        defer { isProcessingQueue = false }

        let queued = offlineQueue.items
        guard !queued.isEmpty else { return }

        await MainActor.run {
            offlineStatusMessage = "Versturen van \(queued.count) opgeslagen opname(s)..."
        }

        for item in queued {
            // Enforce max retry limit
            if item.retryCount >= 10 {
                let filename: String
                switch item {
                case .audio(let url, _): filename = url.lastPathComponent
                case .text: filename = "tekst-transcriptie"
                }
                offlineQueue.removeItem(item)
                await MainActor.run {
                    self.offlineStatusMessage = "Opname '\(filename)' kon na meerdere pogingen niet worden ge\u{00FC}pload. Ga naar Opgeslagen opnames om het handmatig opnieuw te proberen."
                }
                os_log("[RecordingVM] Offline queue item exceeded max retries, removed: %{public}@", log: .default, type: .error, filename)
                continue
            }

            switch item {
            case .audio(let url, _):
                let stateBefore = recordingState
                await uploadFile(url, profileId: profileId)
                // Only remove from queue if upload succeeded (state went back to idle without error)
                if case .error = recordingState {
                    os_log("[RecordingVM] Offline queue item upload failed, incrementing retry count", log: .default, type: .error)
                    let updated = item.incrementingRetryCount()
                    offlineQueue.replaceItem(item, with: updated)
                    await MainActor.run { recordingState = stateBefore }
                } else {
                    offlineQueue.removeItem(item)
                }
            case .text(let transcription, let pid, _):
                do {
                    let task = try await APIService.shared.uploadTranscriptionText(
                        transcription: transcription,
                        profileId: pid
                    )
                    await MainActor.run { self.addTask(task) }
                    await startSSEStream(for: task.taskId)
                    offlineQueue.removeItem(item)
                } catch {
                    os_log("[RecordingVM] Failed to process queued text item, incrementing retry: %{public}@", log: .default, type: .error, error.localizedDescription)
                    let updated = item.incrementingRetryCount()
                    offlineQueue.replaceItem(item, with: updated)
                }
            }
        }

        await MainActor.run { offlineStatusMessage = nil }
        loadSavedRecordings()
    }

    // MARK: - Reprocess Saved Recording

    func reprocessRecording(_ recording: SavedRecording, profileId: String, useOnDevice: Bool) async {
        os_log("[RecordingVM] reprocessRecording: %{public}@, onDevice=%{public}@", log: log, type: .info, recording.filename, useOnDevice ? "true" : "false")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Recordings").appendingPathComponent(recording.filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            await MainActor.run {
                recordingState = .error("Bestand niet gevonden: \(recording.filename)")
            }
            return
        }

        if isLocalMode {
            await processLocally(url: url, profileId: profileId)
        } else if useOnDevice && onDeviceTranscriptionAvailable {
            await transcribeOnDeviceThenUpload(url: url, profileId: profileId)
        } else {
            await uploadFile(url, profileId: profileId)
        }
    }

    // MARK: - Saved Recordings

    func loadSavedRecordings() {
        let urls = AudioRecorder.savedRecordingURLs()
        let fm = FileManager.default
        var recordings: [SavedRecording] = []

        for url in urls {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let created = attrs[.creationDate] as? Date,
                  let size = attrs[.size] as? Int64
            else { continue }

            recordings.append(SavedRecording(
                filename: url.lastPathComponent,
                date: created,
                fileSize: size
            ))
        }

        recordings.sort { $0.date > $1.date }

        Task { @MainActor in
            self.savedRecordings = recordings
        }
    }

    func openRecordingsFolder() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func deleteSavedRecording(_ recording: SavedRecording) {
        let urls = AudioRecorder.savedRecordingURLs()
        if let url = urls.first(where: { $0.lastPathComponent == recording.filename }) {
            try? FileManager.default.removeItem(at: url)
        }
        savedRecordings.removeAll { $0.id == recording.id }
    }

    func hasLocalAudio(for transcriptId: String) -> Bool {
        let key = "localAudio_\(transcriptId)"
        guard let path = UserDefaults.standard.string(forKey: key) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private func saveLocalAudioPath(url: URL, taskId: String) {
        let key = "localAudio_\(taskId)"
        UserDefaults.standard.set(url.path, forKey: key)
    }

    // MARK: - Live Transcription

    func startLiveTranscriptionIfEnabled() async {
        guard onDeviceTranscriptionAvailable, preferOnDeviceTranscription else { return }
#if os(macOS)
        // ScreenCaptureKit holds exclusive microphone access in systemAudio/combined mode.
        // Starting a second AVAudioEngine tap would conflict and produce no audio.
        guard selectedMode == .microphone else { return }
#endif

        // Prevent concurrent starts (e.g. rapid pause/resume)
        guard !isStartingLiveTranscription else { return }
        isStartingLiveTranscription = true
        defer { isStartingLiveTranscription = false }

        await MainActor.run {
            isLiveTranscribing = true
        }

        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.onDeviceTranscriber.startLiveTranscription { [weak self] partial in
                    Task { @MainActor in
                        self?.liveTranscriptText = partial
                    }
                }
            } catch {
                // Live transcription is best-effort; do not surface errors to the user
                os_log("[RecordingVM] Live transcription ended: %{public}@", log: .default, type: .info, error.localizedDescription)
            }

            self.isLiveTranscribing = false
        }
    }

    func stopLiveTranscription() async {
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil
        await MainActor.run {
            isLiveTranscribing = false
        }
    }

    // MARK: - SSE Streaming

    func startSSEStream(for taskId: String) async {
        // Avoid duplicate streams
        guard sseClients[taskId] == nil else { return }

        do {
            let (url, token) = try await APIService.shared.taskStreamInfo(taskId: taskId)

            // Re-check after suspension point to prevent duplicate streams
            guard sseClients[taskId] == nil else { return }

            let client = SSEClient(url: url, token: token)

            client.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .taskUpdate(let task):
                    Task { @MainActor in
                        self.handleSSEEvent(task)
                    }
                case .completed:
                    Task { @MainActor in
                        self.sseClients.removeValue(forKey: taskId)
                    }
                case .error(let error):
                    os_log("[RecordingVM] SSE error for task %{public}@: %{public}@", log: .default, type: .error, taskId, error.localizedDescription)
                    Task { @MainActor in
                        self.sseClients.removeValue(forKey: taskId)
                    }
                }
            }

            await MainActor.run { self.sseClients[taskId] = client }
            client.connect()

        } catch {
            os_log("[RecordingVM] Could not start SSE stream for task %{public}@: %{public}@", log: .default, type: .error, taskId, error.localizedDescription)
        }
    }

    func handleSSEEvent(_ updatedTask: TranscriptTask) {
        if let index = activeTasks.firstIndex(where: { $0.taskId == updatedTask.taskId }) {
            activeTasks[index] = updatedTask
        }

        // Reset recording state so user can start a new recording
        if updatedTask.status == .error, case .error = recordingState {
            recordingState = .idle
        }

        // Remove completed / error tasks from active list after a short delay
        if updatedTask.status == .completed || updatedTask.status == .error {
            let taskId = updatedTask.taskId
            pendingRemovalTasks[taskId]?.cancel()
            pendingRemovalTasks[taskId] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                self.removeTask(taskId)
                self.pendingRemovalTasks.removeValue(forKey: taskId)
            }
        }
    }

    // MARK: - Pending Task Recovery

    /// Checks the server for any active tasks and reconnects SSE streams so the
    /// user can see progress after an app restart.
    func checkPendingTasks() async {
        do {
            let active = try await APIService.shared.getActiveTasks()
            for task in active where task.status.isActive {
                addTask(task)
                await startSSEStream(for: task.taskId)
            }
            if !active.isEmpty {
                os_log("[RecordingVM] Recovered %d pending task(s)", log: log, type: .info, active.count)
            }
        } catch {
            os_log("[RecordingVM] Could not check pending tasks: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }

    // MARK: - Task Management

    func clearError() {
        guard case .error = recordingState else { return }
        recordingState = .idle
        lastFailedRecording = nil
    }

    func removeTask(_ taskId: String) {
        activeTasks.removeAll { $0.taskId == taskId }
        sseClients[taskId]?.disconnect()
        sseClients.removeValue(forKey: taskId)
    }

    func addTask(_ task: TranscriptTask) {
        // Avoid duplicates
        if !activeTasks.contains(where: { $0.taskId == task.taskId }) {
            activeTasks.append(task)
        }
    }

    func updateTask(_ id: String, status: TaskStatus, progress: Double? = nil, errorMessage: String? = nil) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        activeTasks[idx].status = status
        if let progress { activeTasks[idx].progress = progress }
        if let errorMessage { activeTasks[idx].errorMessage = errorMessage }
    }

    // MARK: - Feature Flags

    func checkFeatures() async {
        do {
            let features = try await APIService.shared.fetchFeaturesExtended()
            await MainActor.run {
                isYouTubeEnabled = features.youtube_transcription ?? false
            }
            // Configure GoogleAuthService with client ID from backend
            if let clientId = features.google_oauth_client_id_macos, !clientId.isEmpty {
                await GoogleAuthService.shared.configure(clientId: clientId)
            }
            // Check existing Google connection
            await checkGoogleConnection()
        } catch {
            os_log("[RecordingVM] Could not load features: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }

    // MARK: - YouTube Transcription

    func submitYouTubeURL() async {
        let url = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        guard let profile = selectedProfile else {
            youtubeError = "Geen profiel geselecteerd."
            return
        }

        await MainActor.run {
            isSubmittingYouTube = true
            youtubeError = nil
            captionsNotAvailable = false
        }

        do {
            // Get Google token if connected (for YouTube Captions API)
            let googleToken = await GoogleAuthService.shared.getValidToken()
            let task = try await APIService.shared.transcribeYouTube(
                url: url,
                profileId: profile.id,
                googleToken: googleToken
            )

            await MainActor.run {
                addTask(task)
                isSubmittingYouTube = false
                youtubeURL = ""
            }

            await startSSEStream(for: task.taskId)
        } catch {
            await MainActor.run {
                isSubmittingYouTube = false
                youtubeError = error.localizedDescription
            }
        }
    }

    // MARK: - Google OAuth

    func connectGoogle() async {
        googleAuthError = nil
        do {
            try await GoogleAuthService.shared.initiateAuth()
            let connected = await GoogleAuthService.shared.isConnected
            let email = await GoogleAuthService.shared.accountEmail
            await MainActor.run {
                isGoogleConnected = connected
                googleUserEmail = email
            }
        } catch {
            await MainActor.run {
                googleAuthError = error.localizedDescription
            }
        }
    }

    func disconnectGoogle() async {
        await GoogleAuthService.shared.disconnect()
        await MainActor.run {
            isGoogleConnected = false
            googleUserEmail = nil
        }
    }

    func checkGoogleConnection() async {
        let token = await GoogleAuthService.shared.getValidToken()
        let email = await GoogleAuthService.shared.accountEmail
        await MainActor.run {
            isGoogleConnected = token != nil
            googleUserEmail = email
        }
    }

    // MARK: - Audio Mixing (macOS Combined Mode)

#if os(macOS)
    /// Reads mic and system audio WAV files, mixes them at equal volume into a
    /// new temporary WAV file, and returns its URL.  Falls back to the mic file
    /// on any AVFoundation error so the upload always proceeds.
    private func mixAudioFiles(micURL: URL, systemURL: URL) async -> URL {
        return await Task.detached(priority: .userInitiated) {
            do {
                let micFile = try AVAudioFile(forReading: micURL)
                let sysFile = try AVAudioFile(forReading: systemURL)

                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 16_000,
                    channels: 1,
                    interleaved: false
                ) else {
                    os_log("[RecordingVM] Could not create mix format, using mic only", log: .default, type: .error)
                    return micURL
                }

                let micFrameCount = AVAudioFrameCount(micFile.length)
                let sysFrameCount = AVAudioFrameCount(sysFile.length)
                let totalFrames = max(micFrameCount, sysFrameCount)

                guard totalFrames > 0,
                      let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: micFrameCount),
                      let sysBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sysFrameCount),
                      let mixBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)
                else {
                    os_log("[RecordingVM] Could not allocate mix buffers, using mic only", log: .default, type: .error)
                    return micURL
                }

                try micFile.read(into: micBuffer)
                try sysFile.read(into: sysBuffer)

                mixBuffer.frameLength = totalFrames

                guard let micData = micBuffer.floatChannelData?[0],
                      let sysData = sysBuffer.floatChannelData?[0],
                      let mixData = mixBuffer.floatChannelData?[0] else {
                    os_log("[RecordingVM] Audio mixing failed: nil channel data, using mic only", log: .default, type: .error)
                    return micURL
                }

                for i in 0..<Int(totalFrames) {
                    let micSample: Float = i < Int(micBuffer.frameLength) ? micData[i] : 0
                    let sysSample: Float = i < Int(sysBuffer.frameLength) ? sysData[i] : 0
                    // Average mix at equal volume, clamp to [-1, 1]
                    mixData[i] = max(-1.0, min(1.0, (micSample + sysSample) * 0.5))
                }

                let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Recordings")
                try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                let outputURL = recordingsDir
                    .appendingPathComponent("combined_\(Int(Date().timeIntervalSince1970)).wav")
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                try outputFile.write(from: mixBuffer)

                return outputURL

            } catch {
                os_log("[RecordingVM] Audio mix failed: %{public}@, using mic only", log: .default, type: .error, error.localizedDescription)
                return micURL
            }
        }.value
    }
#endif

    // MARK: - Error Classification

    static func isNetworkError(_ error: Error) -> Bool {
        if let apiError = error as? APIError, case .networkError = apiError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    static func isAuthError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            if case .sessionExpired = apiError { return true }
            if case .httpError(let code, _, _) = apiError, code == 401 { return true }
        }
        return false
    }

    // MARK: - Helpers

#if os(macOS)
    private func ensureScreenCapturePermission() async -> Bool {
        // SCShareableContent automatically triggers the system permission prompt
        // on first use. On macOS 15+ this shows as "System Audio Recording" (not
        // "Screen Recording") when no .screen output is added to the stream.
        await systemAudioCapture.checkPermission()
        return systemAudioCapture.hasPermission
    }
#endif
}
