import Foundation
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "LLMService")

// MARK: - LLMError

enum LLMError: LocalizedError {
    case providerUnavailable
    case serverError(Int)
    case generationFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "De AI-provider is niet beschikbaar."
        case .serverError(let code):
            return "Serverfout: statuscode \(code)."
        case .generationFailed(let message):
            return "Generatie mislukt: \(message)"
        case .emptyResponse:
            return "De AI-provider gaf een leeg antwoord."
        }
    }
}

// MARK: - LLMService Protocol

protocol LLMService: Sendable {

    /// Returns true if this provider is currently available for use.
    var isAvailable: Bool { get async }

    /// Generates meeting notes (notulen) from a transcription.
    ///
    /// - Parameters:
    ///   - transcription: The raw speech transcription text.
    ///   - systemPrompt: System-level instructions for the model persona.
    ///   - notulePrompt: User-level instructions describing the desired output format.
    ///   - outputTemplate: Optional HTML/Markdown template to structure the output.
    ///   - onProgress: Called with each streamed text chunk as it arrives.
    /// - Returns: The complete generated notulen as a string.
    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String
}

// MARK: - LLMServiceFactory

/// Creates the appropriate LLMService implementation based on the selected NotulenProvider.
class LLMServiceFactory {

    static func service(for provider: NotulenProvider, serverURL: String) -> any LLMService {
        switch provider {
        case .cloud:
            // Cloud uses APIService + n8n webhook, not a local LLM.
            // Return a no-op stub; cloud generation is handled server-side.
            return CloudLLMServiceStub()

        case .ollama:
            let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
            let baseURL = UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434"
            return OpenAICompatibleLLMService(baseURL: baseURL, model: model)

        case .lmStudio:
            let model = UserDefaults.standard.string(forKey: "lmStudioModel") ?? "local-model"
            let baseURL = UserDefaults.standard.string(forKey: "lmStudioURL") ?? "http://localhost:1234"
            return OpenAICompatibleLLMService(baseURL: baseURL, model: model)

        case .appleIntelligence:
            if #available(macOS 26, iOS 26, *) {
                return AppleFoundationModelService()
            } else {
                logger.warning("LLMServiceFactory: Apple Intelligence requested but OS version too low; falling back to stub")
                return CloudLLMServiceStub()
            }
        }
    }
}

// MARK: - CloudLLMServiceStub

/// Stub for cloud provider. Cloud generation is handled entirely server-side via n8n webhooks.
private struct CloudLLMServiceStub: LLMService {
    var isAvailable: Bool { true }

    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {
        throw LLMError.generationFailed("Cloud provider genereert notulen server-side via n8n.")
    }
}

// MARK: - OpenAICompatibleLLMService

/// LLM service implementation compatible with OpenAI-style chat completions API.
/// Works with both Ollama and LM Studio local servers.
/// Streams responses via Server-Sent Events and handles long transcriptions by chunking.
final class OpenAICompatibleLLMService: LLMService, @unchecked Sendable {

    private let baseURL: String
    private let model: String

    /// Maximum tokens a typical local model handles comfortably (conservative estimate).
    private static let maxChunkCharacters = 8_000

    init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            guard let url = URL(string: "\(baseURL)/api/tags").map({ $0 }) ??
                            URL(string: "\(baseURL)/v1/models") else { return false }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }

    // MARK: - Generate Notulen

    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {

        // If the transcription is long, summarize it in chunks first
        let processedTranscription: String
        if transcription.count > Self.maxChunkCharacters {
            logger.info("OpenAICompatibleLLMService: transcription is long (\(transcription.count) chars), chunking first")
            processedTranscription = try await summarizeInChunks(transcription)
        } else {
            processedTranscription = transcription
        }

        // Build the final prompt
        var userContent = "\(notulePrompt)\n\nTranscriptie:\n\(processedTranscription)"
        if let template = outputTemplate, !template.isEmpty {
            userContent += "\n\nGebruik dit outputformaat:\n\(template)"
        }

        return try await streamChatCompletion(
            systemPrompt: systemPrompt,
            userMessage: userContent,
            onProgress: onProgress
        )
    }

    // MARK: - Chunked Summarization

    private func summarizeInChunks(_ text: String) async throws -> String {
        let chunks = splitIntoChunks(text, maxChars: Self.maxChunkCharacters)
        var summaries: [String] = []

        for (index, chunk) in chunks.enumerated() {
            logger.info("OpenAICompatibleLLMService: summarizing chunk \(index + 1)/\(chunks.count)")
            let summary = try await streamChatCompletion(
                systemPrompt: "Je bent een assistent die transcripties samenvat. Bewaar alle belangrijke informatie, namen, besluiten en actiepunten.",
                userMessage: "Vat dit deel van de transcriptie samen:\n\n\(chunk)",
                onProgress: { _ in }  // No progress callbacks during intermediate summarization
            )
            summaries.append(summary)
        }

        return summaries.joined(separator: "\n\n")
    }

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

        return chunks.isEmpty ? [text] : chunks
    }

    // MARK: - SSE Streaming

    private func streamChatCompletion(
        systemPrompt: String,
        userMessage: String,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.generationFailed("Ongeldige server URL: \(baseURL)")
        }

        let requestBody: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw LLMError.generationFailed("Kon het verzoek niet serialiseren.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Ongeldig serverantwoord.")
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMError.serverError(httpResponse.statusCode)
        }

        var fullText = ""

        for try await line in asyncBytes.lines {
            // SSE lines start with "data: "
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst("data: ".count))

            // End of stream marker
            if data == "[DONE]" { break }

            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String
            else { continue }

            fullText += content
            onProgress(content)
        }

        if fullText.isEmpty {
            throw LLMError.emptyResponse
        }

        return fullText
    }
}

// MARK: - AppleFoundationModelService

#if os(macOS) || os(iOS)
import FoundationModels

/// LLM service implementation using Apple's on-device Foundation Models framework.
/// Requires macOS 26+ or iOS 26+.
@available(macOS 26, iOS 26, *)
final class AppleFoundationModelService: LLMService, @unchecked Sendable {

    private static let maxChunkCharacters = 12_000

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            // LanguageModelSession is available on all supported OS versions at compile time
            return true
        }
    }

    // MARK: - Generate Notulen

    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {

        // Chunk long transcriptions by summarizing them first
        let processedTranscription: String
        if transcription.count > Self.maxChunkCharacters {
            logger.info("AppleFoundationModelService: transcription is long (\(transcription.count) chars), chunking")
            processedTranscription = try await summarizeInChunks(transcription)
        } else {
            processedTranscription = transcription
        }

        var userContent = "\(notulePrompt)\n\nTranscriptie:\n\(processedTranscription)"
        if let template = outputTemplate, !template.isEmpty {
            userContent += "\n\nGebruik dit outputformaat:\n\(template)"
        }

        let instructions = systemPrompt.isEmpty
            ? "Je bent een professionele notulist die vergaderingen nauwkeurig samenvat in het Nederlands."
            : systemPrompt

        let session = LanguageModelSession(instructions: instructions)
        var fullText = ""
        var lastReportedLength = 0

        // Stream the response token by token; onProgress receives each new chunk
        for try await snapshot in session.streamResponse(to: userContent) {
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

    // MARK: - Chunked Summarization

    private func summarizeInChunks(_ text: String) async throws -> String {
        let chunks = splitIntoChunks(text, maxChars: Self.maxChunkCharacters)
        var summaries: [String] = []

        let summaryInstructions = "Je bent een assistent die transcripties samenvat. Bewaar alle belangrijke informatie, namen, besluiten en actiepunten."

        for (index, chunk) in chunks.enumerated() {
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

        return chunks.isEmpty ? [text] : chunks
    }
}

#endif
