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
    /// Bumped on every start and stop; callbacks of a replaced session compare and drop their results.
    private var liveSession = 0
    private var audioEngine: AVAudioEngine?
    /// Per source: the current request lives in a box so audio threads keep appending while the request is replaced.
    nonisolated private let micBox = LiveRequestBox()
    nonisolated private let systemBox = LiveRequestBox()
    private var liveStreams: [LiveSource: LiveStream] = [:]
#if DEBUG
    private(set) var liveInputFormat = "-"
    private(set) var lastLiveError = "-"
    private(set) var liveFinalCount = 0
    /// Live recognition diagnostics for the DEBUG overlay of the recording screen.
    var liveDebugText: String {
        "live ondevice \(speechRecognizer?.supportsOnDeviceRecognition ?? false) fmt \(liveInputFormat) mic# \(liveStreams[.microphone]?.partials ?? 0) sys# \(liveStreams[.system]?.partials ?? 0) final \(liveFinalCount) err \(lastLiveError)"
    }
#endif

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
    func transcribe(url: URL, profileId: String? = nil) async throws -> String {
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

        let vocabulary = PersonalVocabulary.terms(profileId: profileId)

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

    /// Starts live transcription of the given sources during an active recording: the microphone
    /// through its own audio engine, system audio through buffers passed to `feedSystemAudio`.
    /// Each source recognizes on its own and restarts when Apple ends the request (silence, final).
    /// `onText` receives the full text of that source so far.
    func startLiveTranscription(
        sources: Set<LiveSource>,
        onText: @MainActor @Sendable @escaping (LiveSource, String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await requestPermission()
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriberError.permissionDenied
        }

        // Stop any existing session first
        stopLiveTranscription()
        liveSession += 1
        let session = liveSession

        if sources.contains(.microphone) {
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            let box = micBox
            // The tap fires on AVAudioEngine's realtime queue, not MainActor. Mark the
            // closure @Sendable so it doesn't inherit this @MainActor class's isolation
            // (which would trap under Swift 6 strict concurrency).
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable buffer, _ in
                box.append(buffer)
            }
            engine.prepare()
            try engine.start()
            audioEngine = engine
#if DEBUG
            liveInputFormat = "\(Int(recordingFormat.sampleRate))Hz/\(recordingFormat.channelCount)ch"
#endif
        }

        for source in sources {
            liveStreams[source] = LiveStream()
            beginRecognition(source, session: session, onText: onText, onError: onError)
        }
        logger.info("OnDeviceTranscriber: live transcription started (\(sources.count) source(s))")
    }

    /// Called from the system-audio capture queue with 16 kHz mono buffers.
    nonisolated func feedSystemAudio(_ buffer: AVAudioPCMBuffer) {
        systemBox.append(buffer)
    }

    private func beginRecognition(
        _ source: LiveSource,
        session: Int,
        onText: @MainActor @Sendable @escaping (LiveSource, String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?
    ) {
        guard liveSession == session, let recognizer = speechRecognizer, var stream = liveStreams[source] else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        // Bias recognition toward known names/terms (custom vocabulary, people directory).
        request.contextualStrings = PersonalVocabulary.terms()

        stream.generation += 1
        let generation = stream.generation
        stream.task?.cancel()
        (source == .microphone ? micBox : systemBox).replace(with: request)
        stream.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            Task { @MainActor [weak self] in
                self?.handle(source, session: session, generation: generation, text: text,
                             isFinal: isFinal, error: nsError, onText: onText, onError: onError)
            }
        }
        liveStreams[source] = stream
    }

    private func handle(
        _ source: LiveSource, session: Int, generation: Int, text: String?, isFinal: Bool, error: NSError?,
        onText: @MainActor @Sendable @escaping (LiveSource, String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?
    ) {
        guard liveSession == session, var stream = liveStreams[source], stream.generation == generation else { return }

        if let error {
            logger.debug("OnDeviceTranscriber: live \(String(describing: source)) ended — \(error.domain) \(error.code)")
#if DEBUG
            lastLiveError = "\(error.domain) \(error.code)"
#endif
            guard Self.isBenignLiveError(error) else {
                logger.error("OnDeviceTranscriber: live recognition error — \(error.localizedDescription)")
                onError?(error.localizedDescription)
                return
            }
            restart(source, session: session, stream: stream, pause: true, onText: onText, onError: onError)
            return
        }

        guard let text else { return }
        stream.partials += 1
        stream.shown = Self.joinLive(stream.committed, text)
        liveStreams[source] = stream
        onText(source, stream.shown)
        if isFinal {
#if DEBUG
            liveFinalCount += 1
#endif
            restart(source, session: session, stream: stream, pause: false, onText: onText, onError: onError)
        }
    }

    /// Apple ended the request (silence or final result): keep the text so far and listen again.
    private func restart(
        _ source: LiveSource, session: Int, stream: LiveStream, pause: Bool,
        onText: @MainActor @Sendable @escaping (LiveSource, String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?
    ) {
        var stream = stream
        stream.generation += 1 // drops late callbacks of the ended task
        stream.committed = stream.shown
        liveStreams[source] = stream
        Task { @MainActor [weak self] in
            // After a final result listen again at once (speech may be ongoing); after an error
            // wait briefly so a recognizer that ends immediately cannot spin.
            if pause { try? await Task.sleep(for: .seconds(1)) }
            self?.beginRecognition(source, session: session, onText: onText, onError: onError)
        }
    }

    nonisolated static func joinLive(_ committed: String, _ partial: String) -> String {
        committed.isEmpty ? partial : partial.isEmpty ? committed : committed + " " + partial
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

        micBox.replace(with: nil)
        systemBox.replace(with: nil)
        for stream in liveStreams.values { stream.task?.cancel() }
        liveStreams = [:]
        liveSession += 1

        logger.info("OnDeviceTranscriber: live transcription stopped")
    }
}

// MARK: - Live helpers

enum LiveSource: Hashable, Sendable { case microphone, system }

private struct LiveStream {
    var task: SFSpeechRecognitionTask?
    var generation = 0
    /// Text of earlier requests; each restart starts a new request, so it is prefixed to new partials.
    var committed = ""
    var shown = ""
    var partials = 0
}

/// Thread-safe slot for the current recognition request: audio threads append, the main actor swaps.
final class LiveRequestBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLockUnchecked { $0?.append(buffer) }
    }

    /// Replaces the request and ends the previous one.
    func replace(with request: SFSpeechAudioBufferRecognitionRequest?) {
        let old = lock.withLockUnchecked { slot -> SFSpeechAudioBufferRecognitionRequest? in
            defer { slot = request }
            return slot
        }
        old?.endAudio()
    }
}

// MARK: - LiveTranscriptionPolicy

/// When live recognition may run and what the recording screen says when it does not.
enum LiveTranscriptionPolicy {

    /// Which sources feed live recognition: the microphone through its own AVAudioEngine next to
    /// the AVAudioRecorder, system audio through the capture's converted buffers.
    static func sources(for mode: RecordingMode) -> Set<LiveSource> {
        #if os(macOS)
        switch mode {
        case .microphone: return [.microphone]
        case .systemAudio: return [.system]
        case .combined: return [.microphone, .system]
        }
        #else
        return [.microphone]
        #endif
    }

    /// Why no live text appears, or nil when live recognition is (or is about to be)
    /// running and "Ik luister..." is the honest answer.
    static func statusText(preferred: Bool, available: Bool, error: String?) -> String? {
        guard preferred else { return "Opname loopt (live tekst staat uit)" }
        guard available else { return "Opname loopt (live tekst niet beschikbaar)" }
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
