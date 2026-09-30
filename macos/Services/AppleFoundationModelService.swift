// AppleFoundationModelService.swift
// ThoughtVault
//
// Notule generation with Apple's on-device Foundation Models (macOS/iOS 26+).

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "LLMService")

// MARK: - AppleFoundationModelService

#if canImport(FoundationModels)
import FoundationModels

/// LLM service implementation using Apple's on-device Foundation Models framework.
/// Requires macOS 26+ or iOS 26+.
@available(macOS 26, iOS 26, *)
final class AppleFoundationModelService: LLMService, @unchecked Sendable {

    // The on-device model's context window (4,096 tokens today) is shared by
    // instructions, prompt AND output (~3-4 chars/token). Character budgets scale
    // with the window the system reports instead of a hardcoded size.
    private static var contextTokens: Int { SystemLanguageModel.default.contextSize }
    private static var maxChunkCharacters: Int { contextTokens * 6_000 / 4_096 }
    private static var maxFinalTranscriptCharacters: Int { contextTokens * 5_000 / 4_096 }

    /// Compact format guidance instead of the profile's full HTML template —
    /// the real templates (4-10k chars) alone would overflow the context window.
    private static let compactTemplate = """
    Gebruik h1 voor een specifieke titel, h2 voor de secties en p/ul/li voor de inhoud.
    Laat secties weg wanneer de transcriptie er geen concrete inhoud voor bevat.
    """

    // MARK: - Availability

    var isAvailable: Bool {
        get async { Self.unavailabilityReason == nil }
    }

    // MARK: - Generate Notulen

    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {

        // Refuse early with a clear reason rather than letting LanguageModelSession
        // fail opaquely when Apple Intelligence is off, unsupported, or still loading.
        if let reason = Self.unavailabilityReason {
            throw LLMError.generationFailed(reason)
        }

        // Compress long transcriptions until they fit the final request.
        // ponytail: max 3 reduce-passes; genoeg voor uren transcript (6000^n groei).
        var processedTranscription = transcription
        var passes = 0
        while processedTranscription.count > Self.maxFinalTranscriptCharacters, passes < 3 {
            logger.info("AppleFoundationModelService: transcript \(processedTranscription.count) chars, reduce pass \(passes + 1)")
            processedTranscription = try await summarizeInChunks(processedTranscription)
            passes += 1
        }

        let instructions = systemPrompt.isEmpty
            ? "Je bent een professionele notulist die vergaderingen nauwkeurig samenvat in het Nederlands."
            : systemPrompt

        // The character budget is an estimate; when the model still reports a
        // context overflow, compress once more and retry within the same pass cap.
        while true {
            let userContent = buildNotuleUserContent(
                notulePrompt: notulePrompt,
                transcription: processedTranscription,
                outputTemplate: Self.compactTemplate
            )
            do {
                return try await streamNotule(instructions: instructions, prompt: userContent, onProgress: onProgress)
            } catch {
                guard let overflow = Self.contextOverflow(error) else { throw error }
                guard passes < 3 else {
                    let detail = overflow.tokens.map { " (\($0) van \(overflow.limit ?? Self.contextTokens) tokens)" } ?? ""
                    throw LLMError.generationFailed("Transcriptie te lang voor Apple Intelligence\(detail). Kies een andere notuleaanbieder.")
                }
                logger.info("AppleFoundationModelService: context overflow \(overflow.tokens ?? -1)/\(overflow.limit ?? -1), extra reduce pass")
                processedTranscription = try await summarizeInChunks(processedTranscription)
                passes += 1
            }
        }
    }

    private func streamNotule(
        instructions: String,
        prompt: String,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        var fullText = ""
        var lastReportedLength = 0

        // Stream the response token by token; onProgress receives each new chunk
        for try await snapshot in session.streamResponse(to: prompt) {
            fullText = snapshot.content
            let newChunk = String(fullText.dropFirst(lastReportedLength))
            if !newChunk.isEmpty {
                onProgress(newChunk)
                lastReportedLength = fullText.count
            }
        }

        if fullText.isEmpty {
            throw LLMError.emptyResponse
        }

        return fullText
    }

    /// Token count and limit of a context-overflow error, or nil for any other
    /// error. The detailed error type exists from macOS/iOS 27; on 26 only the
    /// (now deprecated) generation error signals the overflow, without counts.
    private static func contextOverflow(_ error: Error) -> (tokens: Int?, limit: Int?)? {
        if #available(macOS 27, iOS 27, *),
           case LanguageModelError.contextSizeExceeded(let info) = error {
            return (info.tokenCount, info.contextSize)
        }
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
            return (nil, nil)
        }
        return nil
    }

    // MARK: - Chunked Summarization

    private func summarizeInChunks(_ text: String) async throws -> String {
        let chunks = splitIntoChunks(text, maxChars: Self.maxChunkCharacters)
        var summaries: [String] = []

        let summaryInstructions = "Je bent een assistent die transcripties samenvat. Bewaar alle belangrijke informatie, namen, besluiten en actiepunten."

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            logger.info("AppleFoundationModelService: summarizing chunk \(index + 1)/\(chunks.count)")
            let session = LanguageModelSession(instructions: summaryInstructions)
            let response = try await session.respond(
                to: "Vat dit deel van de transcriptie samen:\n\n\(chunk)"
            )
            summaries.append(response.content)
        }

        return summaries.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private func splitIntoChunks(_ text: String, maxChars: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        let sentences = text.components(separatedBy: ". ")

        for sentence in sentences {
            let candidate = current.isEmpty ? sentence : current + ". " + sentence
            if candidate.count > maxChars && !current.isEmpty {
                chunks.append(current)
                current = sentence
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return hardSplitOversizedChunks(chunks.isEmpty ? [text] : chunks, maxChars: maxChars)
    }
}

// MARK: - Apple Intelligence availability

@available(macOS 26, iOS 26, *)
extension AppleFoundationModelService {
    /// Single source of truth for whether on-device Apple Intelligence can run.
    /// `nil` means ready; otherwise a user-facing Dutch reason it cannot.
    /// Consumed by `isAvailable`, the generation guard, and SettingsView's status note.
    static var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Schakel Apple Intelligence in via Systeeminstellingen."
        case .unavailable(.deviceNotEligible):
            return "Dit apparaat ondersteunt Apple Intelligence niet."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence-model wordt nog gedownload. Probeer later opnieuw."
        case .unavailable:
            return "Apple Intelligence is momenteel niet beschikbaar."
        }
    }
}

#endif
