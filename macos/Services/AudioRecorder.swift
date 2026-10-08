import AVFoundation
import Foundation
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let log = Logger(subsystem: "com.buildmind.ThoughtVault", category: "AudioRecorder")

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
    var audioLevels: [Float] = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
    var frequencyBands = Array(repeating: Float(0), count: AudioSpectrumProcessor.frequencies.count)
#if DEBUG
    /// Live pipeline diagnostics for the DEBUG waveform overlay.
    var meterDebugText: String = ""
#endif
    var currentRecordingURL: URL? = nil
    var errorMessage: String? = nil
    var hasPermission: Bool = false

    // MARK: - Callbacks

    /// Called when a silent/delegate error occurs that cannot be surfaced via throws.
    var onSilentFailure: ((AudioRecorderError) -> Void)?

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    /// Shared cross-platform amplitude envelope (dBFS → 0..1 scalar).
    private var envelope = AudioEnvelopeProcessor()
    private var spectrum = AudioSpectrumProcessor()
    private var spectrumFile: FileHandle?
    private var lastMeterDate: Date?
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
        await beginBackgroundTask()
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
                self.spectrumFile = try? FileHandle(forReadingFrom: url)
                self.spectrum = AudioSpectrumProcessor()
                self.frequencyBands = Array(repeating: 0, count: AudioSpectrumProcessor.frequencies.count)
                self.isRecording = true
                self.isPaused = false
                self.duration = 0
                self.recordingStartDate = Date()
                self.pausedAt = nil
                self.accumulatedPauseDuration = 0
                self.audioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
                self.envelope.reset()
                self.lastMeterDate = nil
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
        lastMeterDate = nil  // don't count paused time as envelope dt
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
            try? spectrumFile?.close()
            spectrumFile = nil
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
            self.meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / AudioEnvelopeConfig.publishRateHz, repeats: true) { [weak self] _ in
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

        // averagePower is already a dBFS mean-power measurement — deliberate
        // deviation from raw-PCM RMS so the recording path and combined mode
        // stay untouched (no second capture graph). Pipeline parity with
        // Windows is guaranteed at the envelope level via the shared fixture.
        let db = recorder.averagePower(forChannel: 0)
        let now = Date()
        let dt = lastMeterDate.map { now.timeIntervalSince($0) } ?? 1.0 / AudioEnvelopeConfig.publishRateHz
        lastMeterDate = now
        let level = envelope.process(db: db, dt: dt)
        // Read the existing mono Int16 writer; never open a second microphone capture graph.
        // ponytail: latency follows AVAudioRecorder flushes; use a shared PCM tap if hardware checks show visible lag.
        if let spectrumFile, let end = try? spectrumFile.seekToEnd(), end >= 4096 {
            do {
                try spectrumFile.seek(toOffset: end - 2048)
                if let data = try spectrumFile.read(upToCount: 2048) {
                    let samples = stride(from: 0, to: data.count - 1, by: 2).map { index in
                        Float(Int16(bitPattern: UInt16(data[index]) | UInt16(data[index + 1]) << 8)) / 32768
                    }
                    frequencyBands = spectrum.process(samples: samples, sampleRate: 16_000, dt: dt).map { $0 * envelope.lastGate }
                }
            } catch { frequencyBands = spectrum.process(samples: [0], sampleRate: 16_000, dt: dt) }
        }

#if DEBUG
        meterDebugText = String(format: "db %.1f  floor %.1f  gate %.2f  target %.2f  out %.3f  dt %.0fms",
                                db, envelope.noiseFloorDb, envelope.lastGate, envelope.lastTarget, level, dt * 1000)
#endif

        // Diagnostic logging every 5 seconds
        if now.timeIntervalSince(lastDiagnosticLog) >= 5.0 {
            lastDiagnosticLog = now
            log.info("[AudioRecorder] Metering — dB=\(db, format: .fixed(precision: 1)), floor=\(self.envelope.noiseFloorDb, format: .fixed(precision: 1)), level=\(level, format: .fixed(precision: 3)), duration=\(self.duration, format: .fixed(precision: 1))s")
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
            self.audioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
            self.envelope.reset()
            self.lastMeterDate = nil
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

    /// Keep source audio recoverable, but show a combined session only once.
    static func primaryRecordingURLs(from urls: [URL], defaults: UserDefaults = .standard) -> [URL] {
        urls.filter { url in
            guard let combinedPath = defaults.string(forKey: "combinedAudio_\(url.lastPathComponent)") else { return true }
            return !FileManager.default.fileExists(atPath: combinedPath)
        }
    }

    static func removeSourceIfMixIsComplete(sourceURL: URL, combinedURL: URL, expectedFrames: AVAudioFramePosition) throws -> Bool {
        guard sourceURL.standardizedFileURL != combinedURL.standardizedFileURL, expectedFrames > 0 else { return false }
        do {
            let mixed = try AVAudioFile(forReading: combinedURL)
            guard mixed.length == expectedFrames,
                  mixed.processingFormat.sampleRate == 16_000,
                  mixed.processingFormat.channelCount == 1,
                  let buffer = AVAudioPCMBuffer(pcmFormat: mixed.processingFormat, frameCapacity: 16_000 * 10)
            else { return false }
            var readFrames: AVAudioFramePosition = 0
            while readFrames < expectedFrames {
                try mixed.read(into: buffer, frameCount: AVAudioFrameCount(min(160_000, expectedFrames - readFrames)))
                guard buffer.frameLength > 0 else { return false }
                readFrames += AVAudioFramePosition(buffer.frameLength)
            }
        } catch {
            return false
        }
        try FileManager.default.removeItem(at: sourceURL)
        return true
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

    // AudioRecorder is a nonisolated class, so these run off the main thread.
    // UIApplication background-task APIs are main-actor-only — hop explicitly
    // instead of assuming isolation (assumeIsolated traps off the main thread).
    private func beginBackgroundTask() async {
        backgroundTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "AudioRecording") {
                [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        Task { @MainActor in
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
