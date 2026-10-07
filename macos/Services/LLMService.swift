import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "LLMService")

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
            return code == 401 || code == 403 ? "API-sleutel ontbreekt of is ongeldig (\(code))." : code == 404 ? "Model of AI-adres niet gevonden (404)." : "AI-serverfout: statuscode \(code)."
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
    let template = (outputTemplate ?? "").replacingOccurrences(
        of: "<style\\b[^>]*>[\\s\\S]*?</style>", with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    let contentRules = """

    Laatste inhoudsregels: volg de gekozen template en laat lege secties weg. Verzin geen feiten, besluiten, eigenaren of termijnen. Schrijf eenvoudige HTML zonder CSS, style-blok of code fences.
    """
    if notulePrompt.contains("{{TRANSCRIPTION}}") {
        // Substitute the trusted template first, then insert the untrusted
        // transcription last so its content can never trigger a placeholder swap.
        return notulePrompt
            .replacingOccurrences(of: "{{OUTPUT_TEMPLATE}}", with: template)
            .replacingOccurrences(of: "{{TRANSCRIPTION}}", with: transcription) + contentRules
    }
    var content = "\(notulePrompt)\n\nTranscriptie:\n\(transcription)"
    if !template.isEmpty {
        content += "\n\nGebruik dit outputformaat:\n\(template)"
    }
    return content + contentRules
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

        case .ollamaCloud:
            return OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: UserDefaults.standard.string(forKey: "ollamaCloudModel") ?? "", apiKey: KeychainService.shared.load(for: "ollamaApiKey"))
        case .openAICompatible:
            let selected = UserDefaults.standard.string(forKey: "selectedCloudAIConfiguration")
            guard let config = CloudAIConfiguration.load().first(where: { $0.id == selected }), URL(string: config.baseURL)?.scheme?.lowercased() == "https" else {
                return OpenAICompatibleLLMService(baseURL: "", model: "")
            }
            return OpenAICompatibleLLMService(baseURL: config.baseURL, model: config.model, apiKey: KeychainService.shared.load(for: config.keychainKey))
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
    var isAvailable: Bool { false }

    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {
        throw LLMError.providerUnavailable
    }
}

// MARK: - OpenAICompatibleLLMService

/// LLM service implementation compatible with OpenAI-style chat completions API.
/// Works with both Ollama and LM Studio local servers.
/// Streams responses via Server-Sent Events and handles long transcriptions by chunking.
final class OpenAICompatibleLLMService: LLMService, @unchecked Sendable {

    #if os(macOS)
    private let session = URLSession(configuration: .ephemeral, delegate: LocalLLMRedirectDelegate(), delegateQueue: nil)
    #else
    private let session = URLSession.shared
    #endif
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

    static func isAllowedEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value), url.host != nil, url.user == nil, url.password == nil else { return false }
        return url.scheme?.lowercased() == "https" || ProcessingMode.isLocalEndpoint(value)
    }

    private func endpoint(_ path: String) -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base + (base.hasSuffix("/v1") && path.hasPrefix("/v1/") ? String(path.dropFirst(3)) : path)
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
        guard Self.isAllowedEndpoint(baseURL) else { return false }
        guard let url = URL(string: endpoint(path)) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        applyAuth(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Attaches the bearer token only over HTTPS, so a cloud credential is never
    /// sent in the clear to a plain-HTTP endpoint.
    func applyAuth(to request: inout URLRequest) {
        guard let apiKey,
              request.url?.scheme?.lowercased() == "https" else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Model Discovery

    /// Fetches the available model names from the endpoint. Tries the OpenAI-compatible
    /// `/v1/models` first (works for Ollama local, Ollama Cloud and LM Studio), then
    /// falls back to Ollama's native `/api/tags`. Returns an empty array on failure.
    func fetchModels() async -> [String] { (try? await checkedModels()) ?? [] }

    func checkedModels() async throws -> [String] {
        guard Self.isAllowedEndpoint(baseURL) else { throw LLMError.generationFailed("Gebruik een geldig HTTPS-adres voor cloud-AI.") }
        for path in ["/v1/models", "/api/tags"] {
            guard let url = URL(string: endpoint(path)) else { throw LLMError.providerUnavailable }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            applyAuth(to: &request)
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LLMError.providerUnavailable }
            if response.statusCode == 404 && path == "/v1/models" { continue }
            guard response.statusCode == 200 else { throw LLMError.serverError(response.statusCode) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LLMError.providerUnavailable }
            if let items = json["data"] as? [[String: Any]] { return items.compactMap { $0["id"] as? String }.sorted() }
            if let items = json["models"] as? [[String: Any]] { return items.compactMap { $0["name"] as? String }.sorted() }
            throw LLMError.generationFailed("AI-provider gaf geen geldige modellenlijst.")
        }
        throw LLMError.providerUnavailable
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
            try Task.checkCancellation()
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

        return hardSplitOversizedChunks(chunks.isEmpty ? [text] : chunks, maxChars: maxChars)
    }

    // MARK: - SSE Streaming

    private func streamChatCompletion(
        systemPrompt: String,
        userMessage: String,
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {

        guard Self.isAllowedEndpoint(baseURL) else {
            throw LLMError.generationFailed("Gebruik HTTPS voor cloud-AI of een localhost-URL voor lokale AI.")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.generationFailed("Kies een notulemodel in Instellingen.") }
        guard let url = URL(string: endpoint("/v1/chat/completions")) else {
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
        // Idle timer (resets on every received byte). Generous on purpose: a
        // local model that cold-loads can take minutes before the first token,
        // and a premature timeout kills the whole notule generation.
        request.timeoutInterval = 300

        let (asyncBytes, response) = try await session.bytes(for: request)

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

/// Transcriptions without ". " separators produce one giant chunk that overflows
/// the model's context window (hang or empty output). Hard-split any chunk that
/// still exceeds maxChars.
func hardSplitOversizedChunks(_ chunks: [String], maxChars: Int) -> [String] {
    var result: [String] = []
    for chunk in chunks {
        var remainder = Substring(chunk)
        while remainder.count > maxChars {
            result.append(String(remainder.prefix(maxChars)))
            remainder = remainder.dropFirst(maxChars)
        }
        if !remainder.isEmpty { result.append(String(remainder)) }
    }
    return result
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

#if os(macOS)
private final class LocalLLMRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
