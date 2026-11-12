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
import Accelerate
import SwiftData

private let logger = AppLog(category: "LocalTranscriber")

// MARK: - PersonalVocabulary

/// Collects the user's known names and terms (own profile, people directory and the
/// free-text "Persoonlijke context" setting) so speech engines can be biased toward
/// the correct spellings (e.g. "Michel" instead of "Migel").
enum PersonalVocabulary {

    /// Legacy UserDefaults key for the free-text terms; only read by `migrateLegacyTerms`.
    static let defaultsKey = "personalVocabulary"

    // ponytail: cap terms to protect Whisper's 224-token prompt budget and
    // Apple Intelligence's 4k context window.
    private static let maxTerms = 30

    /// Distinct terms: custom terms + names/organizations of everyone in the
    /// on-device directory (incl. the self-profile). MainActor because the
    /// people directory lives in SwiftData's mainContext.
    @MainActor
    static func terms(profileId: String? = nil) -> [String] {
        var raw: [String] = []
        raw += PersonalCorrections.active((try? PersonalCorrections.load()) ?? [], profileId: profileId).map { $0.canonical }

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

    /// One-time move of the free-text "Persoonlijke context" terms into the Woordenlijst (no variants).
    static func migrateLegacyTerms(at path: URL = PersonalCorrections.url) throws {
        guard let legacy = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        var entries = try PersonalCorrections.load(from: path)
        let before = entries.count
        var known = Set(entries.map { $0.canonical.lowercased() })
        for term in legacy.components(separatedBy: CharacterSet(charactersIn: ",\n")).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !term.isEmpty {
            guard PersonalCorrections.validTerm(term) else { logger.info("Legacy term skipped during migration: \(LogRedact.mask(term))"); continue }
            if known.insert(term.lowercased()).inserted { entries.append(PersonalCorrection(canonical: term, variants: [])) }
        }
        if entries.count != before { try PersonalCorrections.save(entries, to: path) }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// MARK: - Audio Pre-conversion

/// Converts any audio file to 16kHz mono 16-bit PCM WAV — the format WhisperKit
/// handles most reliably. Imported files (m4a, mp3, 44.1kHz stereo) can otherwise
/// cause WhisperKit to silently hang during inference.
enum AudioPreConverter {

    /// Whole-file mean RMS that quiet recordings are boosted toward. Typical recordings
    /// sit around -26..-17 dBFS; a -41 dBFS meeting gave 3333 instead of 3260 words
    /// after boosting to this level.
    private static let targetRMSdB: Float = -23
    /// Upper bound on the boost so near-silent files don't turn noise into "speech".
    private static let maxGainDB: Float = 24

    static func convertToWav16k(_ url: URL) async throws -> URL {
        let gain = try normalizationGain(for: url)
        // ponytail: if already 16kHz mono WAV and loud enough, skip conversion
        if gain == 1, isAlreadyWav16kMono(url) { return url }

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
                    if gain != 1, let samples = outputBuffer.floatChannelData?[0] {
                        // ponytail: hard clip after the boost; a soft limiter if clipping hurts accuracy
                        var g = gain, lo: Float = -1, hi: Float = 1
                        let n = vDSP_Length(outputBuffer.frameLength)
                        vDSP_vsmul(samples, 1, &g, samples, 1, n)
                        vDSP_vclip(samples, 1, &lo, &hi, samples, 1, n)
                    }
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

        logger.info("Pre-converted \(LogRedact.mask(url.lastPathComponent)) → 16kHz mono WAV (gain \(gain))")
        return outputURL
    }

    /// Linear gain that lifts the file's mean RMS to `targetRMSdB`; 1 when it is
    /// already loud enough. Never attenuates. Reads the first channel only.
    static func normalizationGain(for url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let chunk: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return 1 }
        var sumSquares: Double = 0
        var count: Double = 0
        while file.framePosition < file.length {
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunk), file.length - file.framePosition))
            try file.read(into: buffer, frameCount: toRead)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { break }
            var s: Float = 0
            vDSP_svesq(samples, 1, &s, vDSP_Length(buffer.frameLength))
            sumSquares += Double(s)
            count += Double(buffer.frameLength)
        }
        return gain(forMeanSquare: count > 0 ? sumSquares / count : 0)
    }

    /// Pure gain rule, split out so it can be unit tested without audio files.
    static func gain(forMeanSquare meanSquare: Double) -> Float {
        guard meanSquare > 0 else { return 1 }
        let rmsDB = Float(10 * log10(meanSquare))
        let neededDB = min(targetRMSdB - rmsDB, maxGainDB)
        return neededDB > 1 ? powf(10, neededDB / 20) : 1
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
    case modelNotInstalled(String)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let name): return "Transcriptie-engine '\(name)' is niet beschikbaar."
        case .transcriptionFailed(let msg): return "Lokale transcriptie mislukt: \(msg)"
        case .emptyResult: return "De transcriptie was leeg."
        case .modelNotInstalled: return "Het spraakmodel is nog niet gedownload. Download het in Instellingen; de opname blijft bewaard."
        }
    }
}

// MARK: - LocalTranscriber protocol

protocol LocalTranscriber: Sendable {
    /// Transcribes an audio file fully locally and returns the text.
    /// - Parameter onProgress: coarse 0.0...1.0 progress (model download / transcription).
    func transcribe(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String
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

    func transcribe(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        onProgress(0.05)

        let text: String
        if let duration = AudioChunker.duration(of: url), duration > Self.maxSingleRequestDuration {
            let chunks = try await AudioChunker.chunk(url: url, chunkDuration: Self.maxSingleRequestDuration)
            defer { chunks.forEach { try? FileManager.default.removeItem(at: $0) } }
            var parts: [String] = []
            for (index, chunkURL) in chunks.enumerated() {
                let part = try await OnDeviceTranscriber.shared.transcribe(url: chunkURL, profileId: profileId)
                parts.append(part)
                onProgress(0.05 + 0.9 * (Double(index + 1) / Double(chunks.count)))
            }
            text = parts.joined(separator: " ")
        } else {
            text = try await OnDeviceTranscriber.shared.transcribe(url: url, profileId: profileId)
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

/// CoreML Whisper transcription via WhisperKit. Never downloads; the model must be installed (see WhisperModelStore).
final class WhisperKitTranscriber: LocalTranscriber, @unchecked Sendable {

    private let model: String
    /// Injectable so tests need no model on disk.
    private let isInstalled: @Sendable (String) -> Bool

    init(model: String, isInstalled: @escaping @Sendable (String) -> Bool = { WhisperModelStore.isInstalled($0) }) {
        self.model = model
        self.isInstalled = isInstalled
    }

    private struct UncheckedSendableBox<T>: @unchecked Sendable { let value: T }

    /// Cancels the operation on timeout; Core ML may finish loading before observing cancellation.
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

    func transcribe(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        // Never download implicitly mid-transcription; the user downloads in Settings.
        guard isInstalled(model) else { throw LocalTranscriberError.modelNotInstalled(model) }
        do {
            onProgress(0.02)

            // Pre-convert to 16kHz mono WAV — imported files (m4a/mp3/44.1kHz) can
            // otherwise silently hang WhisperKit during inference.
            let wavURL: URL
            do {
                wavURL = try await AudioPreConverter.convertToWav16k(url)
            } catch {
                // If conversion fails, try the original file — WhisperKit may still handle it.
                logger.warning("Pre-conversion failed (\(LogRedact.mask(error.localizedDescription))), trying original file")
                wavURL = url
            }
            // The converted copy is a temp file of ~170 MB per recorded hour;
            // drop it once this transcription is done (success or failure).
            defer {
                if wavURL != url { try? FileManager.default.removeItem(at: wavURL) }
            }
            onProgress(0.06)

            // Cached files can still require a slow first Core ML specialization.
            let modelName = model
            let initTimeout: TimeInterval = 300
            let pipe = try await Self.withTimeout(
                seconds: initTimeout,
                errorMessage: "Model gereedmaken duurde te lang (\(Int(initTimeout))s). Probeer opnieuw of kies een kleiner model."
            ) {
                // WhisperKit isn't Sendable; box it to cross the task-group boundary.
                // Load once before VAD workers can concurrently request the same models.
                UncheckedSendableBox(value: try await WhisperKit(WhisperKitConfig(model: modelName, modelFolder: WhisperModelStore.folder(for: modelName).path, load: true, download: false)))
            }.value

            onProgress(0.15)

            // WhisperKit 0.18 defaults already apply the OpenAI thresholds against silence and repetition (compression 2.4, logprob -1.0, no-speech 0.6).
            var options = DecodingOptions(
                task: .transcribe,
                language: "nl"
            )
            // VAD chunking: splits long audio into speech-bounded windows so large
            // files transcribe instead of hanging (WhisperKit handles this internally).
            options.chunkingStrategy = .vad

            // No vocabulary prompt: Whisper silently drops VAD windows when given
            // one (29-min meeting 3265 -> 0 words, 109 s test 291 -> 110). Names
            // are corrected afterwards via PersonalCorrections in NotuleGenerator.

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
            logger.error("WhisperKit failed: \(LogRedact.mask(error.localizedDescription))")
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
