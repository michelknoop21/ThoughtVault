// LocalTranscriber.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Abstraction over local (offline) speech-to-text engines so the app can transcribe
// without the backend server. Two implementations:
//   - WhisperKitTranscriber: CoreML Whisper, high quality (default when available)
//   - AppleSpeechTranscriber: Apple's SFSpeechRecognizer (zero-dependency fallback)

import Foundation
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "LocalTranscriber")

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
}

// MARK: - AppleSpeechTranscriber

/// Wraps the existing `OnDeviceTranscriber` (SFSpeechRecognizer, Dutch locale).
struct AppleSpeechTranscriber: LocalTranscriber {

    func transcribe(url: URL, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        onProgress(0.05)
        let text = try await OnDeviceTranscriber.shared.transcribe(url: url)
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

    func transcribe(url: URL, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        do {
            onProgress(0.05)

            // Loads (and downloads on first use) the requested model variant.
            let config = WhisperKitConfig(model: model)
            let pipe = try await WhisperKit(config)

            onProgress(0.4)

            let options = DecodingOptions(
                task: .transcribe,
                language: "nl"
            )

            let results: [TranscriptionResult] = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
            onProgress(1.0)

            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { throw LocalTranscriberError.emptyResult }
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
#endif
