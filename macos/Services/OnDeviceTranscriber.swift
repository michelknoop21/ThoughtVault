import Foundation
import Speech
import OSLog
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
    private var recognitionTask: SFSpeechRecognitionTask?
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

        defer { isTranscribing = false }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            // Bias recognition toward known names/terms (e.g. "Yinga", people directory).
            request.contextualStrings = PersonalVocabulary.terms()

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    logger.error("OnDeviceTranscriber: transcription error — \(error.localizedDescription)")
                    continuation.resume(throwing: TranscriberError.recognitionFailed(error.localizedDescription))
                    return
                }

                if let result = result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    logger.info("OnDeviceTranscriber: transcription complete — \(text.count) characters")
                    if text.isEmpty {
                        continuation.resume(throwing: TranscriberError.emptyResult)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }

    // MARK: - Live Transcription

    /// Starts live transcription from the microphone during active recording.
    /// Calls `onPartialResult` with each intermediate result as speech is recognized.
    func startLiveTranscription(onPartialResult: @Sendable @escaping (String) -> Void) async throws {
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
        // Bias recognition toward known names/terms (e.g. "Yinga", people directory).
        request.contextualStrings = PersonalVocabulary.terms()

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.liveRequest = request

        isTranscribing = true
        logger.info("OnDeviceTranscriber: live transcription started")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard self != nil else { return }

            if let error = error {
                let nsError = error as NSError
                if nsError.code != 301 {
                    logger.error("OnDeviceTranscriber: live recognition error — \(error.localizedDescription)")
                }
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    onPartialResult(text)
                }
            }
        }
    }

    /// Stops the active live transcription session and cleans up resources.
    func stopLiveTranscription() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        liveRequest?.endAudio()
        liveRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isTranscribing = false
        logger.info("OnDeviceTranscriber: live transcription stopped")
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
