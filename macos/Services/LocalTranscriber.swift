// LocalTranscriber.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Abstraction over local (offline) speech-to-text engines so the app can transcribe
// without the backend server. Two implementations:
//   - WhisperKitTranscriber: CoreML Whisper, high quality (default when available)
//   - AppleSpeechTranscriber: Apple's SFSpeechRecognizer (zero-dependency fallback)

import Foundation
import AVFoundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "LocalTranscriber")

// MARK: - PersonalVocabulary

/// Collects the user's known names and terms (own profile, people directory and the
/// free-text "Persoonlijke context" setting) so speech engines can be biased toward
/// the correct spellings (e.g. "Michel" instead of "Migel").
enum PersonalVocabulary {

    /// UserDefaults key for the free-text terms in Settings ("Michel, Django, ...").
    static let defaultsKey = "personalVocabulary"

    // ponytail: cap terms to protect Whisper's 224-token prompt budget and
    // Apple Intelligence's 4k context window.
    private static let maxTerms = 30

    /// Distinct terms: custom terms + names/organizations of everyone in the
    /// on-device directory (incl. the self-profile). MainActor because the
    /// people directory lives in SwiftData's mainContext.
    @MainActor
    static func terms() -> [String] {
        var raw: [String] = []
        let custom = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        raw += (try? PersonalCorrections.load())?.filter { $0.enabled }.map { $0.canonical } ?? []
        raw += custom.components(separatedBy: CharacterSet(charactersIn: ",\n"))

        let context = LocalTranscriptStore.shared.container.mainContext
        if let people = try? context.fetch(FetchDescriptor<PersonProfile>()) {
            for p in people {
                raw.append(p.name)
                raw.append(p.organization)
            }
        }

        // Terms maintained in the linked Obsidian vault's context note.
        if let note = VaultFolderStore.readContextNote() {
            raw += VaultFolderStore.parseTerms(fromNote: note)
        }

        var seen = Set<String>()
        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(maxTerms)
            .map { $0 }
    }

    /// Short correction instruction appended to the notule prompt; empty when no terms.
    @MainActor
    static func promptInstruction() -> String {
        let all = terms()
        guard !all.isEmpty else { return "" }
        return "\n\nCorrecte spelling van namen en termen: \(all.joined(separator: ", ")). Corrigeer afwijkende spellingen hiervan in de transcriptie stilzwijgend."
    }
}

// MARK: - Audio Pre-conversion

/// Converts any audio file to 16kHz mono 16-bit PCM WAV — the format WhisperKit
/// handles most reliably. Imported files (m4a, mp3, 44.1kHz stereo) can otherwise
/// cause WhisperKit to silently hang during inference.
enum AudioPreConverter {

    static func convertToWav16k(_ url: URL) async throws -> URL {
        // ponytail: if already 16kHz mono WAV, skip conversion
        if isAlreadyWav16kMono(url) { return url }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preconv_\(UUID().uuidString).wav")

        let sourceFile = try AVAudioFile(forReading: url)
        let sourceFormat = sourceFile.processingFormat

        // On-disk format: 16kHz mono Int16 PCM WAV (what WhisperKit expects).
        // AVAudioFile(forWriting:settings:) with Int16 settings still exposes a
        // **Float32 non-interleaved** processingFormat — the file handles Int16
        // encoding internally on write. So the in-memory buffer must be Float32,
        // NOT Int16, otherwise AVAudioFile.write(from:) triggers a CoreAudio
        // CAAssertRtn → EXC_BREAKPOINT crash. This is the idiomatic AVAudioFile
        // pattern: always process in Float32, let the file handle disk encoding.
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
        // processingFormat is Float32 non-interleaved 16kHz mono — use this for buffers.
        let targetFormat = outputFile.processingFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw LocalTranscriberError.transcriptionFailed("Audio-conversie niet mogelijk voor dit formaat.")
        }

        let inputChunkSize = AVAudioFrameCount(max(4096, Int(sourceFormat.sampleRate)))
        let estimatedOutputChunkSize = AVAudioFrameCount(
            Double(inputChunkSize) * (targetFormat.sampleRate / sourceFormat.sampleRate) + 1024
        )
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputChunkSize),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedOutputChunkSize) else {
            throw LocalTranscriberError.transcriptionFailed("Kon audio-buffer niet aanmaken.")
        }

        var reachedEndOfStream = false
        while !reachedEndOfStream {
            // AVAudioFile.read throws a bare `nilError` (Foundation._GenericObjCError 0)
            // when framePosition already sits at EOF, so never issue that one extra
            // read: clamp to what is left and let an empty buffer drive the
            // converter's end-of-stream flush below.
            let framePosition = sourceFile.framePosition
            let framesRemaining = sourceFile.length - framePosition
            if framesRemaining > 0 {
                let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(inputChunkSize), framesRemaining))
                do {
                    try sourceFile.read(into: inputBuffer, frameCount: framesToRead)
                } catch {
                    throw LocalTranscriberError.transcriptionFailed(
                        "Lezen mislukt op frame \(framePosition) van \(sourceFile.length): \(error.localizedDescription)"
                    )
                }
            } else {
                inputBuffer.frameLength = 0
            }

            nonisolated(unsafe) let capturedInputBuffer = inputBuffer
            var didProvideInput = false
            while true {
                outputBuffer.frameLength = 0
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    if capturedInputBuffer.frameLength == 0 {
                        // Source exhausted: flush the converter's resampler tail.
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    if didProvideInput {
                        outStatus.pointee = .noDataNow
                        return nil
                    }

                    didProvideInput = true
                    outStatus.pointee = .haveData
                    return capturedInputBuffer
                }

                if status == .error || conversionError != nil {
                    throw LocalTranscriberError.transcriptionFailed(
                        "Audio-conversie mislukt: \(conversionError?.localizedDescription ?? "onbekend")"
                    )
                }

                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }

                if status == .endOfStream {
                    reachedEndOfStream = true
                    break
                }

                if status == .inputRanDry || status == .haveData {
                    break
                }
            }

            if inputBuffer.frameLength == 0 {
                reachedEndOfStream = true
            }
        }

        logger.info("Pre-converted \(url.lastPathComponent) → 16kHz mono WAV")
        return outputURL
    }

    /// Quick check: is this file already 16kHz mono 16-bit WAV?
    /// Must inspect `fileFormat` (what is on disk), not `processingFormat` — the
    /// latter is always Float32 regardless of the encoding, which made this check
    /// a tautology that let float32 WAVs through unconverted.
    private static func isAlreadyWav16kMono(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }
        guard let sourceFile = try? AVAudioFile(forReading: url) else { return false }
        let format = sourceFile.fileFormat
        return format.sampleRate == 16_000
            && format.channelCount == 1
            && format.commonFormat == .pcmFormatInt16
    }
}

// MARK: - Engine selection

enum LocalTranscriberEngine: String, CaseIterable, Identifiable, Sendable {
    case whisperKit
    case appleSpeech

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperKit:  return "WhisperKit (aanbevolen)"
        case .appleSpeech: return "Apple Spraakherkenning"
        }
    }
}

// MARK: - LocalTranscriberError

enum LocalTranscriberError: LocalizedError {
    case engineUnavailable(String)
    case transcriptionFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let name): return "Transcriptie-engine '\(name)' is niet beschikbaar."
        case .transcriptionFailed(let msg): return "Lokale transcriptie mislukt: \(msg)"
        case .emptyResult: return "De transcriptie was leeg."
        }
    }
}

// MARK: - LocalTranscriber protocol

protocol LocalTranscriber: Sendable {
    /// Transcribes an audio file fully locally and returns the text.
    /// - Parameter onProgress: coarse 0.0...1.0 progress (model download / transcription).
    func transcribe(url: URL, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String
}

// MARK: - Factory

enum LocalTranscriberFactory {

    /// Default WhisperKit model variant. Balances Dutch quality vs. download size.
    static let defaultWhisperModel = "openai_whisper-large-v3-v20240930_626MB"

    /// Builds the transcriber for the user's selected engine, falling back to
    /// Apple Speech when WhisperKit is not compiled in.
    static func make() -> any LocalTranscriber {
        let raw = UserDefaults.standard.string(forKey: "localTranscriber") ?? LocalTranscriberEngine.whisperKit.rawValue
        let engine = LocalTranscriberEngine(rawValue: raw) ?? .whisperKit

        switch engine {
        case .whisperKit:
            #if canImport(WhisperKit)
            let model = UserDefaults.standard.string(forKey: "whisperModel") ?? defaultWhisperModel
            return WhisperKitTranscriber(model: model)
            #else
            logger.warning("WhisperKit not compiled in; falling back to Apple Speech")
            return AppleSpeechTranscriber()
            #endif
        case .appleSpeech:
            return AppleSpeechTranscriber()
        }
    }

    /// A bare WAV/CAF header is a few hundred bytes; below this there is no audio.
    private static let minimumAudioBytes: Int64 = 1024

    /// Rejects a missing, empty or truncated recording before it reaches
    /// AVFoundation. Without this the user gets a raw OSStatus — a 0-byte or
    /// header-less file surfaces as `kAudioFileUnsupportedFileTypeError`
    /// ('typ?', 1954115647), which says nothing about what went wrong.
    static func validateAudioFile(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw LocalTranscriberError.transcriptionFailed(
                "Het audiobestand '\(url.lastPathComponent)' is niet meer aanwezig.")
        }
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64 else {
            throw LocalTranscriberError.transcriptionFailed(
                "De grootte van '\(url.lastPathComponent)' kon niet worden bepaald.")
        }
        guard size > minimumAudioBytes else {
            throw LocalTranscriberError.transcriptionFailed(
                "Het audiobestand '\(url.lastPathComponent)' is leeg of onvolledig (\(size) bytes).")
        }
    }
}

// MARK: - AppleSpeechTranscriber

/// Wraps the existing `OnDeviceTranscriber` (SFSpeechRecognizer, Dutch locale).
struct AppleSpeechTranscriber: LocalTranscriber {

    /// SFSpeechRecognizer reliably handles ~1 minute per request; longer files
    /// are split into chunks and transcribed sequentially.
    private static let maxSingleRequestDuration: TimeInterval = 55

    func transcribe(url: URL, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        onProgress(0.05)

        let text: String
        if let duration = AudioChunker.duration(of: url), duration > Self.maxSingleRequestDuration {
            let chunks = try await AudioChunker.chunk(url: url, chunkDuration: Self.maxSingleRequestDuration)
            defer { chunks.forEach { try? FileManager.default.removeItem(at: $0) } }
            var parts: [String] = []
            for (index, chunkURL) in chunks.enumerated() {
                let part = try await OnDeviceTranscriber.shared.transcribe(url: chunkURL)
                parts.append(part)
                onProgress(0.05 + 0.9 * (Double(index + 1) / Double(chunks.count)))
            }
            text = parts.joined(separator: " ")
        } else {
            text = try await OnDeviceTranscriber.shared.transcribe(url: url)
        }

        onProgress(1.0)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalTranscriberError.emptyResult }
        return trimmed
    }
}

// MARK: - WhisperKitTranscriber

#if canImport(WhisperKit)
import WhisperKit

/// CoreML Whisper transcription via WhisperKit. Downloads the model on first use.
final class WhisperKitTranscriber: LocalTranscriber, @unchecked Sendable {

    private let model: String

    init(model: String) {
        self.model = model
    }

    /// Best-effort check whether the WhisperKit model is already on disk
    /// (default HubApi download location). Only used to pick an init timeout.
    private static func isModelCached(_ model: String) -> Bool {
        let base = URL.documentsDirectory
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return false
        }
        return entries.contains { $0.contains(model) }
    }

    private struct UncheckedSendableBox<T>: @unchecked Sendable { let value: T }

    /// Runs `operation` with a hard timeout. On expiry the group is cancelled
    /// and a clear error is thrown instead of hanging forever.
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        errorMessage: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw LocalTranscriberError.transcriptionFailed(errorMessage)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func transcribe(url: URL, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        do {
            onProgress(0.02)

            // Pre-convert to 16kHz mono WAV — imported files (m4a/mp3/44.1kHz) can
            // otherwise silently hang WhisperKit during inference.
            let wavURL: URL
            do {
                wavURL = try await AudioPreConverter.convertToWav16k(url)
            } catch {
                // If conversion fails, try the original file — WhisperKit may still handle it.
                logger.warning("Pre-conversion failed (\(error.localizedDescription)), trying original file")
                wavURL = url
            }
            // The converted copy is a temp file of ~170 MB per recorded hour;
            // drop it once this transcription is done (success or failure).
            defer {
                if wavURL != url { try? FileManager.default.removeItem(at: wavURL) }
            }
            onProgress(0.06)

            // Loads (and downloads on first use) the requested model variant.
            // A stalled download would otherwise hang this await forever, so cap
            // it: generous when the model still needs downloading (626 MB),
            // short when it is already cached locally.
            let modelName = model
            let initTimeout: TimeInterval = Self.isModelCached(modelName) ? 60 : 300
            let pipe = try await Self.withTimeout(
                seconds: initTimeout,
                errorMessage: "Model laden duurde te lang (\(Int(initTimeout))s). Controleer je internetverbinding en probeer opnieuw."
            ) {
                // WhisperKit isn't Sendable; box it to cross the task-group boundary.
                UncheckedSendableBox(value: try await WhisperKit(WhisperKitConfig(model: modelName)))
            }.value

            onProgress(0.15)

            var options = DecodingOptions(
                task: .transcribe,
                language: "nl"
            )
            // VAD chunking: splits long audio into speech-bounded windows so large
            // files transcribe instead of hanging (WhisperKit handles this internally).
            options.chunkingStrategy = .vad

            // Bias recognition toward known names/terms via Whisper's initial prompt.
            let vocab = await MainActor.run { PersonalVocabulary.terms() }
            if !vocab.isEmpty, let tokenizer = pipe.tokenizer {
                let prompt = "Namen en termen: \(vocab.joined(separator: ", "))."
                options.promptTokens = tokenizer.encode(text: " " + prompt)
                    .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                options.usePrefillPrompt = true
            }

            onProgress(0.20)

            // Memory guardrail: WhisperKit loads the full file as a Float array
            // (~230 MB/hour). For very long recordings, split into 10-min chunks
            // and transcribe sequentially to keep peak memory bounded (iOS jetsam).
            let chunkThreshold: TimeInterval = 60 * 60
            let chunkLength: TimeInterval = 10 * 60

            var results: [TranscriptionResult] = []
            if let duration = AudioChunker.duration(of: wavURL), duration > chunkThreshold {
                let chunks = try await AudioChunker.chunk(url: wavURL, chunkDuration: chunkLength)
                defer { chunks.forEach { try? FileManager.default.removeItem(at: $0) } }
                for (index, chunkURL) in chunks.enumerated() {
                    let base = 0.20 + 0.75 * (Double(index) / Double(chunks.count))
                    let span = 0.75 / Double(chunks.count)
                    let chunkResults = try await pipe.transcribe(
                        audioPath: chunkURL.path,
                        decodeOptions: options,
                        callback: { [progress = pipe.progress] _ in
                            onProgress(min(0.95, base + span * progress.fractionCompleted))
                            return nil
                        }
                    )
                    results.append(contentsOf: chunkResults)
                }
            } else {
                results = try await pipe.transcribe(
                    audioPath: wavURL.path,
                    decodeOptions: options,
                    callback: { [progress = pipe.progress] _ in
                        onProgress(min(0.95, 0.20 + 0.75 * progress.fractionCompleted))
                        return nil
                    }
                )
            }
            onProgress(0.95)

            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { throw LocalTranscriberError.emptyResult }
            onProgress(1.0)
            logger.info("WhisperKit transcription complete — \(text.count) characters")
            return text
        } catch let error as LocalTranscriberError {
            throw error
        } catch {
            logger.error("WhisperKit failed: \(error.localizedDescription)")
            throw LocalTranscriberError.transcriptionFailed(error.localizedDescription)
        }
    }
}

// MARK: - WhisperKit Model Discovery

/// Fetches the list of available WhisperKit models for the dropdown in Settings.
/// Uses WhisperKit's recommendedModels API which reads the bundled device config.
enum WhisperKitModelDiscovery {

    /// Fetches recommended models from WhisperKit's registry. Returns nil on failure
    /// (offline, API not available) — the UI then shows the manual text field as fallback.
    static func fetchRecommendedModels() async -> [String]? {
        #if canImport(WhisperKit)
        // WhisperKit.recommendedModels() is synchronous (reads the bundled config).
        // It returns ModelSupport with a `default` model and a `supported` list.
        let support = WhisperKit.recommendedModels()
        var models = support.supported
        if !support.default.isEmpty && !models.contains(support.default) {
            models.insert(support.default, at: 0)
        }
        return models.isEmpty ? nil : models
        #else
        return nil
        #endif
    }
}
#endif
