import AVFoundation
import Foundation
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let log = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "AudioRecorder")

// MARK: - Error

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case failedToStart
    case recordingInterrupted
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microfoontoestemming is geweigerd. Geef toegang via Instellingen."
        case .failedToStart:
            return "Kon de opname niet starten. Probeer het opnieuw."
        case .recordingInterrupted:
            return "De opname werd onderbroken door een telefoongesprek."
        case .emptyRecording:
            return "De opname is leeg of te kort om te verwerken."
        }
    }
}

// MARK: - AudioRecorder

@Observable
final class AudioRecorder: NSObject, @unchecked Sendable {

    // MARK: - Constants

    static let minimumValidFileSize: Int64 = 10_240 // 10 KB

    private static let recordingsDirectory = "Recordings"
    private static let cleanupAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    private static let orphanAge: TimeInterval = 60                   // 60 seconds

    // MARK: - Observable State

    var isRecording: Bool = false
    var isPaused: Bool = false
    var duration: TimeInterval = 0
    var audioLevels: [Float] = Array(repeating: 0, count: 60)
    var currentRecordingURL: URL? = nil
    var errorMessage: String? = nil
    var hasPermission: Bool = false

    // MARK: - Callbacks

    /// Called when a silent/delegate error occurs that cannot be surfaced via throws.
    var onSilentFailure: ((AudioRecorderError) -> Void)?

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private var lastDiagnosticLog: Date = .distantPast
    private var recordingStartDate: Date?
    private var pausedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0

#if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
#endif

    // MARK: - Init / Deinit

    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        meteringTimer?.invalidate()
        durationTimer?.invalidate()
    }

    // MARK: - Notifications

    private func setupNotifications() {
#if os(macOS)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
#elseif os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
#endif
    }

#if os(macOS)
    @objc private func handleWillSleep() {
        guard isRecording else { return }
        // Finalize WAV header by stopping cleanly before sleep.
        audioRecorder?.stop()
        finalizeTimers()
        isRecording = false
        isPaused = false
    }
#endif

#if os(iOS)
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            if isRecording {
                audioRecorder?.pause()
                isPaused = true
                onSilentFailure?(.recordingInterrupted)
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isPaused {
                    audioRecorder?.record()
                    isPaused = false
                }
            }
        @unknown default:
            break
        }
    }
#endif

    // MARK: - Permission

    func requestPermission() async {
#if os(iOS)
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { result in
                    continuation.resume(returning: result)
                }
            }
        }
        await MainActor.run { self.hasPermission = granted }
#elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            await MainActor.run { self.hasPermission = true }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { self.hasPermission = granted }
        default:
            await MainActor.run { self.hasPermission = false }
        }
#endif
    }

    // MARK: - Recording Lifecycle

    func startRecording() async throws {
        guard hasPermission else {
            throw AudioRecorderError.permissionDenied
        }

#if os(iOS)
        try configureAudioSession()
        beginBackgroundTask()
#endif

        let url = makeRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // AVAudioRecorder must be created and started on the main thread
        // to avoid dispatch_assert_queue failures in CoreAudio.
        try await MainActor.run {
            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.delegate = self
                recorder.isMeteringEnabled = true
                guard recorder.record() else {
                    log.error("[AudioRecorder] AVAudioRecorder.record() returned false for \(url.lastPathComponent)")
                    throw AudioRecorderError.failedToStart
                }
                self.audioRecorder = recorder
                self.currentRecordingURL = url
                self.isRecording = true
                self.isPaused = false
                self.duration = 0
                self.recordingStartDate = Date()
                self.pausedAt = nil
                self.accumulatedPauseDuration = 0
                self.audioLevels = Array(repeating: 0, count: 60)
                self.errorMessage = nil
                log.info("[AudioRecorder] Started recording to \(url.lastPathComponent) — 16kHz mono PCM")
            } catch let error as AudioRecorderError {
                throw error
            } catch {
                log.error("[AudioRecorder] Failed to create AVAudioRecorder: \(error.localizedDescription)")
                throw AudioRecorderError.failedToStart
            }
        }

        startTimers()
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        pausedAt = Date()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        isPaused = false
        if let pauseStart = pausedAt {
            accumulatedPauseDuration += Date().timeIntervalSince(pauseStart)
            pausedAt = nil
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return currentRecordingURL }

        // AVAudioRecorder.stop() must run on the main thread to match
        // the thread it was created/started on.
        await MainActor.run {
            audioRecorder?.stop()
            audioRecorder = nil  // Force dealloc to flush WAV header
            self.isRecording = false
            self.isPaused = false
            self.recordingStartDate = nil
            self.pausedAt = nil
            self.accumulatedPauseDuration = 0
        }
        finalizeTimers()

#if os(iOS)
        endBackgroundTask()
        deactivateAudioSession()
#endif

        let url = currentRecordingURL

        resetMetrics()

        // Log file size for diagnostics
        if let url, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            log.info("[AudioRecorder] Recording stopped — file size: \(size) bytes at \(url.lastPathComponent)")
            if size < Self.minimumValidFileSize {
                log.warning("[AudioRecorder] File too small (\(size) bytes < \(Self.minimumValidFileSize)), discarding")
                return nil
            }
        }

        return url
    }

    // MARK: - Timers

    private func startTimers() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateMetering()
            }
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartDate, !self.isPaused else { return }
                self.duration = Date().timeIntervalSince(start) - self.accumulatedPauseDuration
            }
        }
    }

    private func finalizeTimers() {
        DispatchQueue.main.async { [weak self] in
            self?.meteringTimer?.invalidate()
            self?.meteringTimer = nil
            self?.durationTimer?.invalidate()
            self?.durationTimer = nil
        }
    }

    // MARK: - Metering

    private func updateMetering() {
        guard let recorder = audioRecorder, isRecording, !isPaused else { return }
        recorder.updateMeters()

        let db = recorder.averagePower(forChannel: 0)
        let db60Floor: Float = -60.0
        let normalized: Float
        if db <= db60Floor {
            normalized = 0
        } else {
            normalized = pow((db - db60Floor) / 60.0, 0.6)
        }
        let level = max(0, min(1, normalized))

        // Diagnostic logging every 5 seconds
        let now = Date()
        if now.timeIntervalSince(lastDiagnosticLog) >= 5.0 {
            lastDiagnosticLog = now
            log.info("[AudioRecorder] Metering — dB=\(db, format: .fixed(precision: 1)), normalized=\(level, format: .fixed(precision: 3)), duration=\(self.duration, format: .fixed(precision: 1))s")
        }

        var levels = self.audioLevels
        levels.removeFirst()
        levels.append(level)
        self.audioLevels = levels
    }

    // MARK: - Reset

    func resetMetrics() {
        Task { @MainActor in
            self.duration = 0
            self.audioLevels = Array(repeating: 0, count: 60)
        }
    }

    // MARK: - File Management

    private func makeRecordingURL() -> URL {
        let dir = recordingsDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("recording_\(timestamp).wav")
    }

    private func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(Self.recordingsDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns all WAV URLs from the persistent Recordings directory.
    static func savedRecordingURLs() -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(recordingsDirectory)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        // ponytail: vaste extensielijst; uitbreiden als er een nieuw bronformaat opduikt.
        let audioExts: Set<String> = ["wav", "m4a", "mp3", "aiff", "caf"]
        return items.filter { audioExts.contains($0.pathExtension.lowercased()) }
    }

    /// Deletes recordings older than 7 days, protecting any URLs in the given set.
    static func cleanupOldRecordings(protecting protectedURLs: Set<URL>) {
        let cutoff = Date().addingTimeInterval(-cleanupAge)
        let fm = FileManager.default
        for url in savedRecordingURLs() {
            guard !protectedURLs.contains(url) else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let created = attrs[.creationDate] as? Date,
                  created < cutoff
            else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// Returns recording files older than 60 seconds that were not created in this session.
    func getOrphanedRecordings() -> [URL] {
        let cutoff = Date().addingTimeInterval(-Self.orphanAge)
        let fm = FileManager.default
        return Self.savedRecordingURLs().filter { url in
            // Exclude the active recording
            if let current = currentRecordingURL, url == current { return false }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let created = attrs[.creationDate] as? Date
            else { return false }
            return created < cutoff
        }
    }

    // MARK: - iOS Specifics

#if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginBackgroundTask() {
        let task = MainActor.assumeIsolated {
            UIApplication.shared.beginBackgroundTask(withName: "AudioRecording") {
                [weak self] in
                self?.endBackgroundTask()
            }
        }
        backgroundTask = task
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        MainActor.assumeIsolated {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
#endif
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.isRecording = false
                self.isPaused = false
                self.errorMessage = AudioRecorderError.failedToStart.errorDescription
            }
            finalizeTimers()
            onSilentFailure?(.failedToStart)
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.isPaused = false
            self.errorMessage = error?.localizedDescription ?? AudioRecorderError.failedToStart.errorDescription
        }
        finalizeTimers()
        onSilentFailure?(.failedToStart)
    }
}
