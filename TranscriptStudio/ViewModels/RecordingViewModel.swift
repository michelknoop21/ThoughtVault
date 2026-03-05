import AVFoundation
import Foundation
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
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
    var availableProfiles: [Profile] = []
    var activeTasks: [TranscriptTask] = []
    var uploadProgress: Double = 0
    var liveTranscriptText: String = ""
    var isLiveTranscribing: Bool = false
    var localGenerationProgress: Double = 0
    var isGeneratingLocally: Bool = false
    var offlineStatusMessage: String?
    var lastFailedUploadURL: URL?
    var lastFailedUploadReason: UploadFailureReason?
    var savedRecordings: [SavedRecording] = []
    var showRetrySheet: Bool = false

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
            let mic = audioRecorder.audioLevels
            let sys = systemAudioCapture.audioLevels
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
        if selectedMode == .systemAudio {
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

    private var liveTranscriptionTask: Task<Void, Never>?
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

        // Restore profile from UserDefaults if available
        if let savedId = UserDefaults.standard.string(forKey: "lastSelectedProfileId") {
            Task {
                await loadDefaultProfile(savedId: savedId)
            }
        }
    }

    deinit {
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

    private func loadDefaultProfile(savedId: String) async {
        do {
            let profiles = try await APIService.shared.getProfiles()
            availableProfiles = profiles
            if let match = profiles.first(where: { $0.id == savedId }) {
                selectedProfile = match
            } else if let first = profiles.first {
                selectedProfile = first
            }
        } catch {
            os_log("[RecordingVM] Could not load profiles on init: %{public}@", log: .default, type: .error, error.localizedDescription)
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
            _ = await systemAudioCapture.stopCapture()
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

        await MainActor.run { recordingState = .preparing }

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
            await systemAudioCapture.checkPermission()
            guard systemAudioCapture.hasPermission else {
                await MainActor.run {
                    recordingState = .error("Schermopnamemachtiging vereist voor systeemaudio. Geef toegang via Systeeminstell.")
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
                // Start both recorders concurrently
                async let micStart: Void = audioRecorder.startRecording()
                async let sysStart: URL = systemAudioCapture.startCapture()
                _ = try await (micStart, sysStart)
#else
                try await audioRecorder.startRecording()
#endif
            }

            await MainActor.run {
                recordingState = .recording
                sleepInterruptedFileURL = nil
            }

            await startLiveTranscriptionIfEnabled()

        } catch {
            await MainActor.run {
                recordingState = .error(error.localizedDescription)
            }
        }
    }

    func pauseRecording() {
        guard case .recording = recordingState else { return }
        audioRecorder.pauseRecording()
#if os(macOS)
        // SystemAudioCapture does not support pause; let it continue running
#endif
        recordingState = .paused
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil
        isLiveTranscribing = false
    }

    func resumeRecording() {
        guard case .paused = recordingState else { return }
        audioRecorder.resumeRecording()
        recordingState = .recording
        Task { await startLiveTranscriptionIfEnabled() }
    }

    func stopAndUpload() async {
        guard recordingState == .recording || recordingState == .paused else { return }

        await MainActor.run { recordingState = .stopping }
        await stopLiveTranscription()

        let micURL = await audioRecorder.stopRecording()

#if os(macOS)
        let sysURL = await systemAudioCapture.stopCapture()
#endif

        // Determine final audio URL
        let finalURL: URL?

#if os(macOS)
        switch selectedMode {
        case .microphone:
            finalURL = micURL
        case .systemAudio:
            finalURL = sysURL
        case .combined:
            if let mic = micURL, let sys = sysURL {
                // Mix mic + system audio into a single file
                finalURL = await mixAudioFiles(micURL: mic, systemURL: sys)
            } else {
                finalURL = micURL ?? sysURL
            }
        }
#else
        finalURL = micURL
#endif

        guard let url = finalURL else {
            await MainActor.run {
                recordingState = .error("Opname is leeg of te kort om te verwerken.")
            }
            return
        }

        guard let profile = selectedProfile else {
            await MainActor.run {
                recordingState = .error("Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.")
            }
            return
        }

        // Decide upload path
        if networkMonitor.isConnected {
            if preferOnDeviceTranscription && onDeviceTranscriptionAvailable {
                await transcribeOnDeviceThenUpload(url: url, profileId: profile.id)
            } else {
                await uploadFile(url, profileId: profile.id)
            }
        } else {
            await handleOfflineRecording(url: url)
        }
    }

    func cancelRecording() async {
        guard recordingState == .recording || recordingState == .paused else { return }

        await stopLiveTranscription()
        _ = await audioRecorder.stopRecording()
#if os(macOS)
        _ = await systemAudioCapture.stopCapture()
#endif

        // Delete the recording file
        if let url = audioRecorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        await MainActor.run {
            recordingState = .idle
            uploadProgress = 0
        }
    }

    // MARK: - Upload

    func uploadFile(_ url: URL, profileId: String) async {
        await MainActor.run {
            recordingState = .uploading
            uploadProgress = 0
            lastFailedUploadURL = nil
            lastFailedUploadReason = nil
        }

        do {
            let task = try await APIService.shared.uploadAudio(
                fileURL: url,
                profileId: profileId
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.uploadProgress = progress
                }
            }

            await MainActor.run {
                self.addTask(task)
                recordingState = .idle
                uploadProgress = 0
            }

            // Save local audio path reference
            if !task.taskId.isEmpty {
                await startSSEStream(for: task.taskId)
            }

            // Persist local path for local audio playback
            saveLocalAudioPath(url: url, taskId: task.taskId)
            loadSavedRecordings()

        } catch let error as APIError {
            let reason = uploadFailureReason(from: error)
            await MainActor.run {
                self.lastFailedUploadURL = url
                self.lastFailedUploadReason = reason
                self.recordingState = .idle
                self.showRetrySheet = reason.isRetryable
                self.uploadProgress = 0
            }
            os_log("[RecordingVM] Upload failed: %{public}@", log: .default, type: .error, error.localizedDescription)
        } catch {
            await MainActor.run {
                self.lastFailedUploadURL = url
                self.lastFailedUploadReason = .unknown
                self.recordingState = .error(error.localizedDescription)
                self.uploadProgress = 0
            }
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

    // MARK: - Offline Recording

    func handleOfflineRecording(url: URL) async {
        offlineQueue.enqueue(.audio(url: url))

        await MainActor.run {
            recordingState = .idle
            offlineStatusMessage = "Geen verbinding. Opname opgeslagen en wordt geüpload zodra je weer online bent."
        }

        loadSavedRecordings()

        // Clear message after 5 seconds
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        await MainActor.run { offlineStatusMessage = nil }
    }

    // MARK: - Queue Processing

    func processQueueOnStartupIfNeeded() async {
        guard networkMonitor.isConnected else { return }
        guard let profileId = selectedProfile?.id else { return }

        let queued = offlineQueue.items
        guard !queued.isEmpty else { return }

        await MainActor.run {
            offlineStatusMessage = "Versturen van \(queued.count) opgeslagen opname(s)..."
        }

        for item in queued {
            switch item {
            case .audio(let url, _):
                await uploadFile(url, profileId: profileId)
                offlineQueue.removeItem(item)
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
                    os_log("[RecordingVM] Failed to process queued text item: %{public}@", log: .default, type: .error, error.localizedDescription)
                }
            }
        }

        await MainActor.run { offlineStatusMessage = nil }
        loadSavedRecordings()
    }

    // MARK: - Retry

    func retryLastFailedUpload() async {
        guard let url = lastFailedUploadURL,
              let profile = selectedProfile else { return }

        await MainActor.run {
            showRetrySheet = false
            lastFailedUploadURL = nil
            lastFailedUploadReason = nil
        }

        await uploadFile(url, profileId: profile.id)
    }

    // MARK: - Reprocess Saved Recording

    func reprocessRecording(_ recording: SavedRecording, profileId: String, useOnDevice: Bool) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Recordings").appendingPathComponent(recording.filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            await MainActor.run {
                recordingState = .error("Bestand niet gevonden: \(recording.filename)")
            }
            return
        }

        if useOnDevice && onDeviceTranscriptionAvailable {
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

        await MainActor.run {
            isLiveTranscribing = true
        }

        liveTranscriptionTask = Task {
            do {
                try await onDeviceTranscriber.startLiveTranscription { [weak self] partial in
                    Task { @MainActor in
                        self?.liveTranscriptText = partial
                    }
                }
            } catch {
                // Live transcription is best-effort; do not surface errors to the user
                os_log("[RecordingVM] Live transcription ended: %{public}@", log: .default, type: .info, error.localizedDescription)
            }

            Task { @MainActor in
                self.isLiveTranscribing = false
            }
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

        // Remove completed / error tasks from active list after a short delay
        if updatedTask.status == .completed || updatedTask.status == .error {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.removeTask(updatedTask.taskId)
                }
            }
        }
    }

    // MARK: - Task Management

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

                let micData = micBuffer.floatChannelData![0]
                let sysData = sysBuffer.floatChannelData![0]
                let mixData = mixBuffer.floatChannelData![0]

                for i in 0..<Int(totalFrames) {
                    let micSample: Float = i < Int(micBuffer.frameLength) ? micData[i] : 0
                    let sysSample: Float = i < Int(sysBuffer.frameLength) ? sysData[i] : 0
                    // Average mix at equal volume, clamp to [-1, 1]
                    mixData[i] = max(-1.0, min(1.0, (micSample + sysSample) * 0.5))
                }

                let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
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
            if case .httpError(let code, _) = apiError, code == 401 { return true }
        }
        return false
    }

    // MARK: - Helpers

    private func uploadFailureReason(from error: APIError) -> UploadFailureReason {
        switch error {
        case .sessionExpired:
            return .authExpired
        case .fileTooLarge:
            return .fileTooLarge
        case .httpError(let code, let message):
            if code == 401 { return .authExpired }
            if code == 422, let msg = message { return .validationError(msg) }
            return .serverError(code)
        case .networkError:
            return .unknown
        default:
            return .unknown
        }
    }
}

