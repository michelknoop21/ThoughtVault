import AVFoundation
import Foundation
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
#endif

private let log = OSLog(subsystem: "com.buildmind.ThoughtVault", category: "RecordingVM")

// MARK: - RecordingViewModel

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - Published State

    var recordingState: RecordingState = .idle
    var updateInstalling = false
    private var pendingRegenerations = 0
    var updateIsBusy: Bool {
        switch recordingState {
        case .idle, .error: return activeTasks.contains { $0.status.isActive } || isProcessingQueue || !localProcessingTasks.isEmpty || pendingRegenerations > 0
        default: return true
        }
    }
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

    // MARK: - Agenda Seed

    /// The calendar event linked to the current (or most recent) recording.
    /// Set at recording start sites in ContentView; cleared after attendees are captured.
    var activeMeeting: CalendarEvent? = nil

    /// Attendee emails captured from activeMeeting when stopAndUpload completes.
    /// The View layer observes this to trigger SeedReviewSheet after recordingState settles.
    var pendingSeedAttendees: [String]? = nil

    /// Directory person IDs manually selected for the current recording. Used for
    /// ad-hoc meetings with no calendar link so they still get a deelnemerslijst.
    /// Reset after each recording is dispatched.
    var selectedParticipantIDs: [String] = []
    /// "Snelle notitie" typed during the current recording; kept across pause/resume
    /// and stored with the audio file on stop (QuickNoteStore).
    var quickNote: String = ""

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
            // Both sources use AudioEnvelopeProcessor at 30 Hz. Align their
            // newest samples in case one history has not filled up yet.
            let sys = Array(systemAudioCapture.audioLevels.suffix(audioRecorder.audioLevels.count))
            let mic = Array(audioRecorder.audioLevels.suffix(sys.count))
            return zip(mic, sys).map(max)
#else
            return audioRecorder.audioLevels
#endif
        }
    }

#if DEBUG
    /// Envelope pipeline diagnostics for the DEBUG waveform overlay.
    var meterDebugText: String {
#if os(macOS)
        switch selectedMode {
        case .microphone: audioRecorder.meterDebugText
        case .systemAudio: systemAudioCapture.meterDebugText
        case .combined: audioRecorder.meterDebugText + " | " + systemAudioCapture.meterDebugText
        }
#else
        audioRecorder.meterDebugText
#endif
    }
#endif

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

    /// Whether the app is configured to process everything locally (no server).
    var isLocalMode: Bool { ProcessingMode.isLocalMode }

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
    /// Status-polling tasks that take over when an SSE stream permanently fails.
    private var pollingFallbackTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var uploadTask: Task<Void, Never>?
    @ObservationIgnored
    private var localProcessingTasks: [String: Task<Void, Never>] = [:]
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
            await loadDefaultProfile(savedId: UserDefaults.standard.string(forKey: "defaultProfile") ?? "")
            await checkFeatures()
        }
    }

    deinit {
        liveTranscriptionTask?.cancel()
        for task in pendingRemovalTasks.values { task.cancel() }
        for task in localProcessingTasks.values { task.cancel() }
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
        await loadDefaultProfile(savedId: UserDefaults.standard.string(forKey: "defaultProfile") ?? "")
    }

    private func loadDefaultProfile(savedId: String) async {
        var profiles: [Profile]
        if isLocalMode {
            // Fully offline: use the built-in profiles, no server call.
            profiles = LocalProfileStore.choices()
        } else {
            do {
                let remote = try await APIService.shared.getProfiles()
                profiles = Profile.currentChoices(remote)
            } catch {
                os_log("[RecordingVM] Could not load profiles from API, using defaults: %{public}@", log: .default, type: .error, error.localizedDescription)
                profiles = Profile.defaults
            }
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
        guard recordingState == .idle, !updateInstalling else { return }
        recordingState = .preparing
        audioMixFallbackOccurred = false

        // Only microphone/combined capture needs the microphone permission.
        if selectedMode != .systemAudio {
            await audioRecorder.requestPermission()
            guard audioRecorder.hasPermission else {
                recordingState = .error("Microfoontoestemming geweigerd. Geef toegang via Instellingen.")
                return
            }
        }

        do {
            switch selectedMode {
            case .microphone:
                try await audioRecorder.startRecording()

            case .systemAudio:
#if os(macOS)
                try await systemAudioCapture.startCapture()
                PermissionManager.shared.recordSystemAudioResult(nil)
#else
                try await audioRecorder.startRecording()
#endif

            case .combined:
#if os(macOS)
                // Capture system audio via Core Audio and microphone via AVAudioRecorder.
                // The existing microphone pipeline remains separate.
                _ = try await systemAudioCapture.startCapture(includeMicrophone: false)
                PermissionManager.shared.recordSystemAudioResult(nil)
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
                PermissionManager.shared.recordSystemAudioResult(error)
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
        // Reserve the transition before suspending: widget, page and MCP may race.
        recordingState = .stopping

        os_log("[RecordingVM] stopAndUpload: state=%{public}@, profile=%{public}@", log: log, type: .info, "\(recordingState)", selectedProfile?.name ?? "nil")

        // Capture attendees before clearing activeMeeting (D-07 / T-02-06).
        // Signal is set after recordingState settles to .idle so the View layer
        // presents the sheet only when the UI is ready (Pitfall 3 avoidance).
        let capturedAttendees = activeMeeting?.attendees ?? []
        activeMeeting = nil

        // Resolve the participant list (self + calendar attendees + manual picks)
        // before any early return so every dispatch path can carry it (D-B).
        let participants = PersonDirectoryService.shared.resolveParticipants(
            attendeeEmails: capturedAttendees,
            manualIDs: selectedParticipantIDs
        )
        selectedParticipantIDs = []

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

        QuickNoteStore.save(quickNote, audioFilename: url.lastPathComponent)
        quickNote = ""

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

        // Signal the View layer to present SeedReviewSheet after recordingState settles.
        // capturedAttendees is non-empty only when the recording was linked to a meeting.
        if !capturedAttendees.isEmpty {
            await MainActor.run {
                pendingSeedAttendees = capturedAttendees
            }
        }

        await dispatchProcessing(url: url, profile: profile, participants: participants)
    }

    /// Routes a finished audio file (live recording or imported) through the same
    /// local / on-device / cloud / offline decision used by stopAndUpload.
    func dispatchProcessing(url: URL, profile: Profile, participants: [Participant]) async {
        // Fully local mode: transcribe + generate notulen on-device, no server needed.
        if isLocalMode {
            os_log("[RecordingVM] dispatchProcessing: path=local", log: log, type: .info)
            await processLocally(url: url, profileId: profile.id, participants: participants)
            return
        }

        // Decide upload path
        if networkMonitor.isConnected {
#if os(macOS)
            // Core Audio produces float32 PCM that SFSpeechRecognizer cannot reliably
            // process. For systemAudio and combined modes, always use cloud transcription.
            let canUseOnDevice = preferOnDeviceTranscription && onDeviceTranscriptionAvailable
                && selectedMode == .microphone
#else
            let canUseOnDevice = preferOnDeviceTranscription && onDeviceTranscriptionAvailable
#endif
            if canUseOnDevice {
                os_log("[RecordingVM] dispatchProcessing: path=onDevice", log: log, type: .info)
                await transcribeOnDeviceThenUpload(url: url, profileId: profile.id, participants: participants)
            } else {
                os_log("[RecordingVM] dispatchProcessing: path=cloud", log: log, type: .info)
                await uploadFile(url, profileId: profile.id, participants: participants)
            }
        } else {
            os_log("[RecordingVM] dispatchProcessing: path=offline", log: log, type: .info)
            await handleOfflineRecording(url: url)
        }
    }

    /// Imports an external audio file (iPhone voice memo, dictaphone), copies it into
    /// the persistent Recordings directory and runs it through the standard pipeline.
    /// The picked URL is security-scoped (from .fileImporter).
    func importAudioFile(_ pickedURL: URL) async {
        guard !updateInstalling else { return }
        let accessed = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessed { pickedURL.stopAccessingSecurityScopedResource() } }

        guard let profile = selectedProfile else {
            await MainActor.run {
                recordingState = .error("Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.")
            }
            return
        }

        // Copy into Recordings/ → stable path for localAudioPath and "Opgeslagen opnames".
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let dest = recordingsDir
            .appendingPathComponent("import_\(Int(Date().timeIntervalSince1970))_\(pickedURL.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: pickedURL, to: dest)
        } catch {
            os_log("[RecordingVM] importAudioFile: copy failed: %{public}@", log: log, type: .error, error.localizedDescription)
            await MainActor.run {
                recordingState = .error("Kon het audiobestand niet importeren.")
            }
            return
        }

        let participants = PersonDirectoryService.shared.resolveParticipants(
            attendeeEmails: [],
            manualIDs: selectedParticipantIDs
        )
        selectedParticipantIDs = []

        loadSavedRecordings()
        await dispatchProcessing(url: dest, profile: profile, participants: participants)
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
            activeMeeting = nil
            quickNote = ""
        }
    }

    // MARK: - Upload

    func uploadFile(_ url: URL, profileId: String, participants: [Participant] = []) async {
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
                    usePremium: usePremium,
                    participants: participants
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

    func transcribeOnDeviceThenUpload(url: URL, profileId: String, participants: [Participant] = []) async {
        await MainActor.run {
            isLiveTranscribing = true
            liveTranscriptText = ""
            recordingState = .uploading
        }

        do {
            var fullTranscription = ""

            try LocalTranscriberFactory.validateAudioFile(at: url)
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
                profileId: profileId,
                participants: participants
            )

            saveLocalAudioPath(url: url, taskId: task.taskId)   // links the quick note
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

    /// Transcribes audio locally and generates minutes with the selected AI provider,
    /// then stores the result locally. No ThoughtVault backend is contacted.
    /// Runs on a detached Task so the MainActor stays responsive and the user can cancel.
    func processLocally(url: URL, profileId: String, participants: [Participant] = []) async {
        guard !updateInstalling else { return }
        let profile = availableProfiles.first { $0.id == profileId }
            ?? Profile.defaults.first { $0.id == profileId }
            ?? selectedProfile
            ?? Profile.defaults[0]

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

        // Run on a detached Task so the MainActor stays responsive. The task
        // reference is stored for cancellation.
        localProcessingTasks[localId] = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.processLocallyWorker(url: url, localId: localId, profile: profile, participants: participants)
        }
    }

    /// Worker that does the actual transcription + notule generation. Runs off the
    /// MainActor on a detached Task. All @MainActor state updates go through Task hops.
    private func processLocallyWorker(url: URL, localId: String, profile: Profile, participants: [Participant]) async {
        // 1. Local transcription
        let transcription: String
        do {
            try Task.checkCancellation()
            try LocalTranscriberFactory.validateAudioFile(at: url)
            let transcriber = LocalTranscriberFactory.make()
            transcription = try await transcriber.transcribe(url: url) { [weak self] fraction in
                Task { @MainActor in
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    self.updateTask(localId, status: .transcribing,
                                     progress: 0.15 + fraction * 0.35)
                }
            }
            guard Self.hasUsableTranscription(transcription) else {
                throw LLMError.generationFailed("Geen bruikbare spraak herkend. Controleer de opname en probeer opnieuw.")
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            await MainActor.run { self.cancelLocalTaskCleanup(localId) }
            return
        } catch {
            os_log("[RecordingVM] processLocally transcription failed: %{public}@", log: log, type: .error, error.localizedDescription)
            await MainActor.run {
                self.updateTask(localId, status: .error, errorMessage: error.localizedDescription)
                self.localProcessingTasks.removeValue(forKey: localId)
                // The recording itself is safe in Documents/Recordings — offer it
                // under "Opgeslagen opnames" so the user has a retry route.
                self.loadSavedRecordings()
                self.lastFailedRecording = self.savedRecordings.first { $0.filename == url.lastPathComponent }
            }
            return
        }

        try? await Task.sleep(for: .milliseconds(100))
        try? Task.checkCancellation()

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
        record.participants = participants
        do {
            try LocalTranscriptStore.shared.save(record)
        } catch {
            os_log("[RecordingVM] processLocally save failed: %{public}@", log: log, type: .error, error.localizedDescription)
            await MainActor.run {
                self.updateTask(localId, status: .error, errorMessage: "Opslaan mislukt: \(error.localizedDescription)")
                self.localProcessingTasks.removeValue(forKey: localId)
            }
            return
        }

        await MainActor.run {
            self.setTaskTranscription(localId, transcription)
            self.updateTask(localId, status: .generatingLocal, progress: TaskStatus.generatingLocal.progress)
            self.isGeneratingLocally = true
            self.localGenerationProgress = 0
            self.saveLocalAudioPath(url: url, taskId: localId)
            self.loadSavedRecordings()
        }

        // 3. Local notule generation via the configured provider.
        let providerRaw = UserDefaults.standard.string(forKey: "notulenProvider") ?? NotulenProvider.platformDefault.rawValue
        var provider = NotulenProvider(rawValue: providerRaw) ?? .ollama
        if provider == .cloud { provider = .ollama }   // cloud is meaningless offline

        do {
            try Task.checkCancellation()
            let service = LLMServiceFactory.service(for: provider, serverURL: "")
            let html = try await service.generateNotulen(
                transcription: transcription,
                systemPrompt: profile.systemPrompt ?? "",
                notulePrompt: QuickNoteStore.promptBlock(QuickNoteStore.note(audioFilename: url.lastPathComponent))
                    + Self.injectParticipants(into: profile.notulePrompt ?? "", participants: participants)
                    + PersonalVocabulary.promptInstruction(),
                outputTemplate: profile.template
            ) { [weak self] chunk in
                Task { @MainActor in
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    self.appendTaskNotuleHtml(localId, chunk)
                }
            }
            try Task.checkCancellation()

            let datedHtml = Self.injectDate(into: Self.stripCodeFences(html), date: record.createdAt)
            guard Self.hasUsableNotule(datedHtml) else {
                throw LLMError.generationFailed("De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.")
            }
            let title = NotuleTitleExtractor.extract(from: datedHtml) ?? fallback
            try LocalTranscriptStore.shared.finalizeNotule(taskId: localId, html: datedHtml, title: title, style: profile.minutesStyle)

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

    /// Cancels an in-progress local processing task (transcription or notule generation).
    func cancelLocalProcessing(_ taskId: String) {
        localProcessingTasks[taskId]?.cancel()
        localProcessingTasks.removeValue(forKey: taskId)
        cancelLocalTaskCleanup(taskId)
    }

    /// Marks a cancelled task as error and cleans up.
    private func cancelLocalTaskCleanup(_ taskId: String) {
        updateTask(taskId, status: .error, errorMessage: "Geannuleerd door gebruiker.")
        isGeneratingLocally = false
    }

    /// Regenerates the notule for an already-stored local record using its saved
    /// transcription and the given profile — entirely on-device. Returns the new
    /// HTML and title so the open detail view can stay in sync with SwiftData.
    func regenerateNotuleLocally(taskId: String, profileId: String) async throws -> (html: String, title: String) {
        guard !updateInstalling else { throw LLMError.generationFailed("De app wordt bijgewerkt. Probeer na de herstart opnieuw.") }
        pendingRegenerations += 1
        defer { pendingRegenerations -= 1 }
        guard let record = LocalTranscriptStore.shared.record(forTaskId: taskId) else {
            throw LocalStoreError.recordNotFound
        }
        let profile = availableProfiles.first { $0.id == profileId }
            ?? Profile.defaults.first { $0.id == profileId }
            ?? selectedProfile
            ?? Profile.defaults[0]

        var provider = NotulenProvider(rawValue: UserDefaults.standard.string(forKey: "notulenProvider") ?? NotulenProvider.platformDefault.rawValue) ?? .ollama
        if provider == .cloud { provider = .ollama }

        let service = LLMServiceFactory.service(for: provider, serverURL: "")
        let html = try await service.generateNotulen(
            transcription: record.rawTranscription,
            systemPrompt: profile.systemPrompt ?? "",
            notulePrompt: QuickNoteStore.promptBlock(QuickNoteStore.note(forTranscriptId: taskId))
                + Self.injectParticipants(into: profile.notulePrompt ?? "", participants: record.participants)
                + PersonalVocabulary.promptInstruction(),
            outputTemplate: profile.template
        ) { _ in }

        let datedHtml = Self.injectDate(into: Self.stripCodeFences(html), date: record.createdAt)
        guard Self.hasUsableNotule(datedHtml) else {
            throw LLMError.generationFailed("De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.")
        }
        let title = NotuleTitleExtractor.extract(from: datedHtml) ?? record.title
        try LocalTranscriptStore.shared.finalizeNotule(taskId: taskId, html: datedHtml, title: title, style: profile.minutesStyle)
        return (record.notuleHtml ?? datedHtml, title)
    }

    /// Removes the markdown code fences some models wrap around their HTML output.
    /// The cloud backend strips these server-side; on-device generation needs the
    /// same guard because the prompt discourages fences but cannot prevent them.
    nonisolated static func hasUsableTranscription(_ text: String) -> Bool {
        let spoken = text.replacingOccurrences(
            of: "\\b(ruis|stilte|onverstaanbaar|muziek|applaus|gelach)\\b",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return spoken.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= 10
            && text.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: "^(geen transcriptie|transcriptie ontbreekt|onvoldoende transcriptie)[.!\\s]*$", options: [.regularExpression, .caseInsensitive]) == nil
    }

    nonisolated static func hasUsableNotule(_ html: String) -> Bool {
        let visible = html
            .replacingOccurrences(of: "<(style|script|template)\\b[^>]*>[\\s\\S]*?</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard visible.unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count >= 20 else { return false }
        guard visible.range(of: "\\[[^\\]]+\\]", options: .regularExpression) == nil else { return false }
        return visible.range(of: "geen transcriptie|transcriptie ontbreekt|onvoldoende transcriptie", options: [.regularExpression, .caseInsensitive]) == nil
    }

    private static func stripCodeFences(_ html: String) -> String {
        var text = html.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "^```(?:html)?\\s*\\n?", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\\n?```\\s*$", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces the {{DATE}} template placeholder with a localized date. The cloud
    /// backend fills this server-side; for on-device generation the app does it.
    private static func injectDate(into html: String, date: Date) -> String {
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
    private static func injectParticipants(into notulePrompt: String, participants: [Participant]) -> String {
        let block = participants.notulePromptBlock
        if notulePrompt.contains("{{PARTICIPANTS}}") {
            return notulePrompt.replacingOccurrences(of: "{{PARTICIPANTS}}", with: block)
        }
        guard !block.isEmpty else { return notulePrompt }
        return block + "\n\n" + notulePrompt
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
        guard activeTasks[idx].status.isActive else { return }
        activeTasks[idx].rawTranscription = text
    }

    private func appendTaskNotuleHtml(_ id: String, _ chunk: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        guard activeTasks[idx].status.isActive else { return }
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
            if item.retryCount >= QueuedItem.maxRetries {
                let filename: String
                switch item {
                case .audio(let url, _, _): filename = url.lastPathComponent
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
            case .audio(let url, _, _):
                // Awaitable upload, mirroring the .text branch below. The previous
                // code called uploadFile(), which spawns a detached Task and returns
                // before the upload finishes — so the recordingState check always saw
                // .idle and every queued item was removed regardless of outcome
                // (failures silently dropped, retry-count branch dead). Calling the
                // API directly here lets us await the real result.
                let tempId = "upload-\(UUID().uuidString)"
                await MainActor.run {
                    self.addTask(TranscriptTask(
                        id: tempId,
                        taskId: tempId,
                        filename: url.lastPathComponent,
                        status: .uploading,
                        progress: 0
                    ))
                }
                do {
                    let task = try await APIService.shared.uploadAudio(
                        fileURL: url,
                        profileId: profileId,
                        usePremium: usePremium
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.updateTask(tempId, status: .uploading, progress: progress)
                        }
                    }
                    await MainActor.run {
                        self.activeTasks.removeAll { $0.id == tempId }
                        self.addTask(task)
                    }
                    if !task.taskId.isEmpty {
                        await startSSEStream(for: task.taskId)
                    }
                    saveLocalAudioPath(url: url, taskId: task.taskId)
                    offlineQueue.removeItem(item)
                } catch {
                    os_log("[RecordingVM] Offline queue item upload failed, incrementing retry count: %{public}@", log: .default, type: .error, error.localizedDescription)
                    await MainActor.run { self.activeTasks.removeAll { $0.id == tempId } }
                    let updated = item.incrementingRetryCount()
                    offlineQueue.replaceItem(item, with: updated)
                }
            case .text(let transcription, let pid, _, _):
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
        #if os(macOS)
        NSWorkspace.shared.open(dir)
        #endif
        // ponytail: iOS has no "reveal in Finder"; folder is reachable via Files app share sheet elsewhere.
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
        // System audio capture runs alongside microphone capture in combined mode.
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
                        // SSE gave up (max reconnects) — fall back to polling so
                        // the task never stays "processing" forever.
                        self.startPollingFallback(taskId: taskId)
                    }
                }
            }

            await MainActor.run { self.sseClients[taskId] = client }
            client.connect()

        } catch {
            os_log("[RecordingVM] Could not start SSE stream for task %{public}@: %{public}@", log: .default, type: .error, taskId, error.localizedDescription)
        }
    }

    /// Polls task status every 15s after SSE has permanently failed, feeding
    /// results through the normal SSE event path. Stops on a terminal state or
    /// after 40 attempts (~10 min), marking the task as failed so it never
    /// hangs in "processing".
    private func startPollingFallback(taskId: String) {
        guard pollingFallbackTasks[taskId] == nil else { return }
        pollingFallbackTasks[taskId] = Task { @MainActor in
            defer { pollingFallbackTasks.removeValue(forKey: taskId) }
            for _ in 0..<40 {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                if let task = try? await APIService.shared.getTaskStatus(taskId: taskId) {
                    handleSSEEvent(task)
                    if task.status == .completed || task.status == .error { return }
                }
            }
            // Give up: surface a failed state instead of an eternal spinner.
            if let index = activeTasks.firstIndex(where: { $0.taskId == taskId }) {
                var task = activeTasks[index]
                task.status = .error
                task.errorMessage = "Verbinding met de server verloren. Controleer later of de notule alsnog is aangemaakt."
                handleSSEEvent(task)
            }
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
            scheduleRemoval(of: updatedTask.taskId)
        }

        // Auto-export a freshly-completed cloud notule to Obsidian (no-op when
        // disabled). Cloud notulen embed participants server-side, so none are
        // passed here.
        if updatedTask.status == .completed,
           ObsidianService.isEnabled,
           let html = updatedTask.notuleHtml, !html.isEmpty {
            let title = NotuleTitleExtractor.extract(from: html)
                ?? (updatedTask.filename as NSString).deletingPathExtension
            ObsidianService.tryExportDetached(
                title: title,
                html: html,
                date: updatedTask.createdAt ?? Date(),
                participants: [],
                profileName: updatedTask.profileId,
                profileId: updatedTask.profileId,
                tags: updatedTask.tags
            )
        }
    }

    /// Removes a finished (completed/error) task from the active list after a short
    /// delay so the user briefly sees the final state. Shared by the SSE path and
    /// the fully-local processing path.
    private func scheduleRemoval(of taskId: String) {
        pendingRemovalTasks[taskId]?.cancel()
        pendingRemovalTasks[taskId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self.removeTask(taskId)
            self.pendingRemovalTasks.removeValue(forKey: taskId)
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
        if !activeTasks[idx].status.isActive, activeTasks[idx].status != status {
            return
        }
        activeTasks[idx].status = status
        if let progress { activeTasks[idx].progress = progress }
        if let errorMessage { activeTasks[idx].errorMessage = errorMessage }

        // Local processing reports completion through updateTask (not SSE), so the
        // auto-removal must be scheduled here too. Failures are deliberately left
        // standing until the user dismisses them — a 3s window is not enough to
        // read (let alone act on) an error.
        if status == .completed {
            scheduleRemoval(of: activeTasks[idx].taskId)
        }
    }

    // MARK: - Feature Flags

    func checkFeatures() async {
        // Feature flags come from the backend; skip entirely in local mode.
        guard !isLocalMode else { return }
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
                    os_log("[RecordingVM] Could not create mix format, using mic only", log: log, type: .error)
                    return micURL
                }

                let totalFrames = max(micFile.length, sysFile.length)

                // Stream in 10s chunks with reusable buffers: loading both files
                // whole costs hundreds of MB per hour and risks an OOM kill.
                let chunkFrames: AVAudioFrameCount = 16_000 * 10
                guard totalFrames > 0,
                      let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
                      let sysBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
                      let mixBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
                else {
                    os_log("[RecordingVM] Could not allocate mix buffers, using mic only", log: log, type: .error)
                    return micURL
                }

                let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Recordings")
                try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                let outputURL = recordingsDir
                    .appendingPathComponent("combined_\(Int(Date().timeIntervalSince1970)).wav")
                // Write 16kHz mono Int16 PCM — the same on-disk format as every other
                // writer in the app (AudioRecorder, AudioChunker, AudioPreConverter).
                // `format` above stays Float32 for the mixing buffers; AVAudioFile
                // encodes to Int16 on write.
                let diskSettings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 16_000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: diskSettings)

                var framesWritten: AVAudioFramePosition = 0
                while framesWritten < totalFrames {
                    let remaining = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), totalFrames - framesWritten))

                    micBuffer.frameLength = 0
                    if micFile.framePosition < micFile.length {
                        try micFile.read(into: micBuffer, frameCount: remaining)
                    }
                    sysBuffer.frameLength = 0
                    if sysFile.framePosition < sysFile.length {
                        try sysFile.read(into: sysBuffer, frameCount: remaining)
                    }

                    guard let micData = micBuffer.floatChannelData?[0],
                          let sysData = sysBuffer.floatChannelData?[0],
                          let mixData = mixBuffer.floatChannelData?[0] else {
                        os_log("[RecordingVM] Audio mixing failed: nil channel data, using mic only", log: log, type: .error)
                        return micURL
                    }

                    mixBuffer.frameLength = remaining
                    for i in 0..<Int(remaining) {
                        let micSample: Float = i < Int(micBuffer.frameLength) ? micData[i] : 0
                        let sysSample: Float = i < Int(sysBuffer.frameLength) ? sysData[i] : 0
                        // Element-wise magnitude-max: pick the louder source at each sample, preserving its sign
                        let sample = abs(micSample) >= abs(sysSample) ? micSample : sysSample
                        mixData[i] = max(-1.0, min(1.0, sample))
                    }

                    try outputFile.write(from: mixBuffer)
                    framesWritten += AVAudioFramePosition(remaining)
                }

                let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let outSize = (attrs?[.size] as? Int64) ?? 0
                os_log("[RecordingVM] Audio mix OK — mic %.1fs (%lld frames), system %.1fs (%lld frames) → %lld frames, %lld bytes Int16 at %{public}@",
                       log: log, type: .info,
                       Double(micFile.length) / micFile.processingFormat.sampleRate, micFile.length,
                       Double(sysFile.length) / sysFile.processingFormat.sampleRate, sysFile.length,
                       framesWritten, outSize, outputURL.path)

                return outputURL

            } catch {
                os_log("[RecordingVM] Audio mix failed: %{public}@, using mic only", log: log, type: .error, error.localizedDescription)
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
#endif
}
