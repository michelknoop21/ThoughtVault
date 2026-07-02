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

// MARK: - Prompt assembly

/// Builds the user message for notule generation. Backend-style profiles embed
/// `{{TRANSCRIPTION}}` and `{{OUTPUT_TEMPLATE}}` placeholders in the notule prompt;
/// when present they are substituted in place. Otherwise the transcription and
/// template are appended (legacy inline profiles).
func buildNotuleUserContent(
    notulePrompt: String,
    transcription: String,
    outputTemplate: String?
) -> String {
    if notulePrompt.contains("{{TRANSCRIPTION}}") {
        // Substitute the trusted template first, then insert the untrusted
        // transcription last so its content can never trigger a placeholder swap.
        return notulePrompt
            .replacingOccurrences(of: "{{OUTPUT_TEMPLATE}}", with: outputTemplate ?? "")
            .replacingOccurrences(of: "{{TRANSCRIPTION}}", with: transcription)
    }
    var content = "\(notulePrompt)\n\nTranscriptie:\n\(transcription)"
    if let template = outputTemplate, !template.isEmpty {
        content += "\n\nGebruik dit outputformaat:\n\(template)"
    }
    return content
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
            // Optional API key (Keychain) enables Ollama Cloud (https://ollama.com).
            let apiKey = KeychainService.shared.load(for: "ollamaApiKey")
            return OpenAICompatibleLLMService(baseURL: baseURL, model: model, apiKey: apiKey)

        case .lmStudio:
            let model = UserDefaults.standard.string(forKey: "lmStudioModel") ?? "local-model"
            let baseURL = UserDefaults.standard.string(forKey: "lmStudioURL") ?? "http://localhost:1234"
            return OpenAICompatibleLLMService(baseURL: baseURL, model: model)

        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, *) {
                return AppleFoundationModelService()
            } else {
                logger.warning("LLMServiceFactory: Apple Intelligence requested but OS version too low; falling back to stub")
                return CloudLLMServiceStub()
            }
            #else
            logger.warning("LLMServiceFactory: Apple Intelligence not available on this SDK; falling back to stub")
            return CloudLLMServiceStub()
            #endif
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
    /// Optional bearer token. Set for hosted endpoints such as Ollama Cloud.
    private let apiKey: String?

    /// Maximum tokens a typical local model handles comfortably (conservative estimate).
    private static let maxChunkCharacters = 8_000

    init(baseURL: String, model: String, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.model = model
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            // Try the OpenAI-compatible endpoint first, then fall back to Ollama's
            // native one. The previous `URL(...) ?? URL(...)` never fell back
            // because the first string always parses into a valid URL.
            if await endpointReturns200("/v1/models") { return true }
            if await endpointReturns200("/api/tags") { return true }
            return false
        }
    }

    private func endpointReturns200(_ path: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)\(path)") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        applyAuth(to: &request)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Attaches the bearer token only over HTTPS, so a cloud credential is never
    /// sent in the clear to a plain-HTTP endpoint.
    private func applyAuth(to request: inout URLRequest) {
        guard let apiKey,
              request.url?.scheme?.lowercased() == "https" else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Model Discovery

    /// Fetches the available model names from the endpoint. Tries the OpenAI-compatible
    /// `/v1/models` first (works for Ollama local, Ollama Cloud and LM Studio), then
    /// falls back to Ollama's native `/api/tags`. Returns an empty array on failure.
    func fetchModels() async -> [String] {
        if let models = await fetchModelsOpenAI(), !models.isEmpty { return models }
        if let models = await fetchModelsOllamaTags(), !models.isEmpty { return models }
        return []
    }

    private func fetchModelsOpenAI() async -> [String]? {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        applyAuth(to: &request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]]
        else { return nil }
        return items.compactMap { $0["id"] as? String }.sorted()
    }

    private func fetchModelsOllamaTags() async -> [String]? {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        applyAuth(to: &request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["models"] as? [[String: Any]]
        else { return nil }
        return items.compactMap { $0["name"] as? String }.sorted()
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
        let userContent = buildNotuleUserContent(
            notulePrompt: notulePrompt,
            transcription: processedTranscription,
            outputTemplate: outputTemplate
        )

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
        applyAuth(to: &request)
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

#if canImport(FoundationModels)
import FoundationModels

/// LLM service implementation using Apple's on-device Foundation Models framework.
/// Requires macOS 26+ or iOS 26+.
@available(macOS 26, iOS 26, *)
final class AppleFoundationModelService: LLMService, @unchecked Sendable {

    // The on-device model has a 4,096-token context window shared by instructions,
    // prompt AND output (~3-4 chars/token). Keep every request's variable part small.
    private static let maxChunkCharacters = 6_000
    private static let maxFinalTranscriptCharacters = 5_000

    /// Compact output skeleton used instead of the profile's full HTML template —
    /// the real templates (4-10k chars) alone would overflow the context window.
    private static let compactTemplate = """
    <h1>[Titel]</h1>
    <p><em>[Datum] — [Deelnemers]</em></p>
    <h2>Samenvatting</h2>
    <p>...</p>
    <h2>Besproken punten</h2>
    <ul><li>...</li></ul>
    <h2>Besluiten</h2>
    <ul><li>...</li></ul>
    <h2>Actiepunten</h2>
    <ul><li>[Wie]: [Wat]</li></ul>
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

        let userContent = buildNotuleUserContent(
            notulePrompt: notulePrompt,
            transcription: processedTranscription,
            outputTemplate: Self.compactTemplate
        )

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
