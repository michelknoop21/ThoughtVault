// LocalTranscriber.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Abstraction over local (offline) speech-to-text engines so the app can transcribe
// without the backend server. Two implementations:
//   - WhisperKitTranscriber: CoreML Whisper, high quality (default when available)
//   - AppleSpeechTranscriber: Apple's SFSpeechRecognizer (zero-dependency fallback)

import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "LocalTranscriber")

// MARK: - PersonalVocabulary

/// Collects the user's known names and terms (own profile, people directory and the
/// free-text "Persoonlijke context" setting) so speech engines can be biased toward
/// the correct spellings (e.g. "Yinga" instead of "Jenga").
enum PersonalVocabulary {

    /// UserDefaults key for the free-text terms in Settings ("Yinga, Django, ...").
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

            var options = DecodingOptions(
                task: .transcribe,
                language: "nl"
            )

            // Bias recognition toward known names/terms via Whisper's initial prompt.
            let vocab = await MainActor.run { PersonalVocabulary.terms() }
            if !vocab.isEmpty, let tokenizer = pipe.tokenizer {
                let prompt = "Namen en termen: \(vocab.joined(separator: ", "))."
                options.promptTokens = tokenizer.encode(text: " " + prompt)
                    .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                options.usePrefillPrompt = true
            }

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
