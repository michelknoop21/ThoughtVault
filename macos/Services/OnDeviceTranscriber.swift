import Foundation
import Speech
import OSLog
import os
#if os(iOS)
import UIKit
#endif

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "OnDeviceTranscriber")

// MARK: - OnDeviceTranscriber

/// On-device speech recognition using Apple's Speech framework with Dutch locale.
/// Handles both full-file transcription and live microphone transcription during recording.
@MainActor @Observable
final class OnDeviceTranscriber {

    static let shared = OnDeviceTranscriber()

    // MARK: - Observable State

    var isTranscribing: Bool = false

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer?
    /// File transcription and live recognition each own their task: stopping one must never cancel the other.
    private var recognitionTask: SFSpeechRecognitionTask?
    private var liveRecognitionTask: SFSpeechRecognitionTask?
    /// Bumped on every start and stop; callbacks of a replaced session compare and drop their results.
    private var liveSession = 0
    private var audioEngine: AVAudioEngine?
    private var liveRequest: SFSpeechAudioBufferRecognitionRequest?

    // MARK: - Init

    private init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "nl-NL"))
    }

    // MARK: - Availability

    /// Returns true if SFSpeechRecognizer is available and supports on-device recognition.
    func isAvailable() -> Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }

    /// Returns true if on-device transcription is viable given current device state.
    /// Checks battery level (not low power mode) and available disk space (>100 MB).
    func isViable() -> Bool {
        guard isAvailable() else { return false }

        // Check for Low Power Mode on iOS
        #if os(iOS)
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            logger.info("OnDeviceTranscriber: not viable — Low Power Mode active")
            return false
        }
        #endif

        // Check disk space: require at least 100 MB free
        let requiredBytes: Int64 = 100 * 1024 * 1024
        if let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ), let freeSpace = attrs[.systemFreeSize] as? Int64 {
            if freeSpace < requiredBytes {
                logger.info("OnDeviceTranscriber: not viable — insufficient disk space (\(freeSpace) bytes free)")
                return false
            }
        }

        return true
    }

    // MARK: - Permission

    /// Requests speech recognition authorization from the user.
    func requestPermission() async {
        await withCheckedContinuation { continuation in
            // TCC invokes this on a background queue; @Sendable prevents
            // MainActor inference which would trap under Swift 6 (SIGTRAP).
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                switch status {
                case .authorized:
                    logger.info("OnDeviceTranscriber: speech recognition authorized")
                case .denied:
                    logger.warning("OnDeviceTranscriber: speech recognition denied")
                case .restricted:
                    logger.warning("OnDeviceTranscriber: speech recognition restricted")
                case .notDetermined:
                    logger.info("OnDeviceTranscriber: speech recognition not determined")
                @unknown default:
                    break
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Full-File Transcription

    /// Transcribes an audio file at the given URL and returns the full transcription text.
    /// Uses on-device recognition where available, falls back to server if needed.
    func transcribe(url: URL) async throws -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriberError.permissionDenied
        }

        isTranscribing = true
        logger.info("OnDeviceTranscriber: starting file transcription for \(url.lastPathComponent)")

        // Runs on MainActor when the function exits (normal return or thrown
        // timeout). Cancelling the recognition task here stops the orphaned
        // SFSpeechRecognitionTask left running when the watchdog fires.
        defer {
            recognitionTask?.cancel()
            recognitionTask = nil
            isTranscribing = false
        }

        let vocabulary = PersonalVocabulary.terms()

        // Watchdog: SFSpeechRecognizer can hang indefinitely on files it cannot
        // handle (never calls back). A timeout Task races the recognition callback
        // via a single-resume guard, so the caller always gets a result or error.
        let didResume = OSAllocatedUnfairLock(initialState: false)
        let watchdog = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        return try await withCheckedThrowingContinuation { continuation in
            let resumeOnce: @Sendable (Result<String, Error>) -> Void = { result in
                let first = didResume.withLock { resumed -> Bool in
                    if resumed { return false }
                    resumed = true
                    return true
                }
                guard first else { return }
                watchdog.withLock { $0?.cancel() }
                continuation.resume(with: result)
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            // Bias recognition toward known names/terms (custom vocabulary, people directory).
            request.contextualStrings = vocabulary

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    logger.error("OnDeviceTranscriber: transcription error — \(error.localizedDescription)")
                    resumeOnce(.failure(TranscriberError.recognitionFailed(error.localizedDescription)))
                    return
                }

                if let result = result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    logger.info("OnDeviceTranscriber: transcription complete — \(text.count) characters")
                    if text.isEmpty {
                        resumeOnce(.failure(TranscriberError.emptyResult))
                    } else {
                        resumeOnce(.success(text))
                    }
                }
            }

            // ponytail: on timeout we resume with an error; the orphaned SFSpeech
            // task's later callback hits the single-resume guard and is ignored.
            watchdog.withLock {
                $0 = Task {
                    try? await Task.sleep(for: .seconds(180))
                    guard !Task.isCancelled else { return }
                    resumeOnce(.failure(TranscriberError.recognitionFailed(
                        "Time-out: spraakherkenning reageerde niet binnen 3 minuten."
                    )))
                }
            }
        }
    }

    // MARK: - Live Transcription

    /// Starts live transcription from the microphone during active recording.
    /// Calls `onPartialResult` with each intermediate result as speech is recognized.
    func startLiveTranscription(
        onPartialResult: @Sendable @escaping (String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriberError.permissionDenied
        }

        // Stop any existing session first
        stopLiveTranscription()

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        // Bias recognition toward known names/terms (custom vocabulary, people directory).
        request.contextualStrings = PersonalVocabulary.terms()

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // The tap fires on AVAudioEngine's realtime queue, not MainActor. Mark the
        // closure @Sendable so it doesn't inherit this @MainActor class's isolation
        // (which would trap under Swift 6 strict concurrency). Appending to the
        // request is thread-safe.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.liveRequest = request

        liveSession += 1
        let session = liveSession
        logger.info("OnDeviceTranscriber: live transcription started")

        liveRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard self != nil else { return }

            if let error = error {
                let nsError = error as NSError
                guard !Self.isBenignLiveError(nsError) else { return }
                logger.error("OnDeviceTranscriber: live recognition error — \(error.localizedDescription)")
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard self?.liveSession == session else { return }
                    onError?(message)
                }
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    guard self?.liveSession == session else { return }
                    onPartialResult(text)
                }
            }
        }
    }

    /// Terminal results that are not failures: cancellation (301, 216) and "no speech
    /// detected" (1110, 203), e.g. a silent start. They must not show up as errors.
    nonisolated static func isBenignLiveError(_ error: NSError) -> Bool {
        [203, 216, 301, 1110].contains(error.code)
    }

    /// Stops the active live transcription session and cleans up resources.
    func stopLiveTranscription() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        liveRequest?.endAudio()
        liveRequest = nil

        liveRecognitionTask?.cancel()
        liveRecognitionTask = nil
        liveSession += 1

        logger.info("OnDeviceTranscriber: live transcription stopped")
    }
}

// MARK: - LiveTranscriptionPolicy

/// When live recognition may run and what the recording screen says when it does not.
enum LiveTranscriptionPolicy {

    /// Live recognition taps the microphone with its own AVAudioEngine next to the
    /// AVAudioRecorder, in microphone and combined mode alike. System-audio-only
    /// recordings have no microphone to listen to.
    static func supports(mode: RecordingMode) -> Bool {
        #if os(macOS)
        return mode != .systemAudio
        #else
        return true
        #endif
    }

    /// Why no live text appears, or nil when live recognition is (or is about to be)
    /// running and "Ik luister..." is the honest answer.
    static func statusText(preferred: Bool, available: Bool, mode: RecordingMode, error: String?) -> String? {
        guard preferred else { return "Opname loopt (live tekst staat uit)" }
        guard available else { return "Opname loopt (live tekst niet beschikbaar)" }
        guard supports(mode: mode) else { return "Opname loopt (geen live tekst bij alleen systeemgeluid)" }
        if let error { return "Live tekst gestopt: \(error)" }
        return nil
    }
}

// MARK: - TranscriberError

enum TranscriberError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied
    case recognitionFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "On-device spraakherkenning is niet beschikbaar op dit apparaat."
        case .permissionDenied:
            return "Toestemming voor spraakherkenning is geweigerd. Geef toegang via Instellingen."
        case .recognitionFailed(let message):
            return "Transcriptie mislukt: \(message)"
        case .emptyResult:
            return "De transcriptie bevat geen tekst. Controleer of de opname audio bevat."
        }
    }
}
