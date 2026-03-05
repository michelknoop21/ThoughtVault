import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
        let session = AVAudioSession.sharedInstance()
        let granted = await withCheckedContinuation { continuation in
            session.requestRecordPermission { granted in
                continuation.resume(returning: granted)
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

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw AudioRecorderError.failedToStart
            }
            self.audioRecorder = recorder
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            throw AudioRecorderError.failedToStart
        }

        await MainActor.run {
            self.currentRecordingURL = url
            self.isRecording = true
            self.isPaused = false
            self.duration = 0
            self.audioLevels = Array(repeating: 0, count: 60)
            self.errorMessage = nil
        }

        startTimers()
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        isPaused = false
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return currentRecordingURL }

        audioRecorder?.stop()
        finalizeTimers()

#if os(iOS)
        endBackgroundTask()
        deactivateAudioSession()
#endif

        let url = currentRecordingURL

        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
        }

        resetMetrics()

        // Validate minimum file size
        if let url, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64, size < Self.minimumValidFileSize {
            return nil
        }

        return url
    }

    // MARK: - Timers

    private func startTimers() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateMetering()
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder, !self.isPaused else { return }
            Task { @MainActor in
                self.duration = recorder.currentTime
            }
        }
    }

    private func finalizeTimers() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
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

        Task { @MainActor in
            var levels = self.audioLevels
            levels.removeFirst()
            levels.append(level)
            self.audioLevels = levels
        }
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
        return items.filter { $0.pathExtension.lowercased() == "wav" }
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
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AudioRecording") {
            [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
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
