import Foundation

private let logger = AppLog(category: "LLMService")

// MARK: - LLMError

enum LLMError: LocalizedError {
    case providerUnavailable
    case serverError(Int)
    case generationFailed(String)
    case emptyResponse
    case timedOut
    case truncated

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "De AI-provider is niet beschikbaar."
        case .serverError(let code):
            if code == 429 {
                return "De AI-provider heeft een gebruikslimiet bereikt (429), ook na een nieuwe poging. Probeer het later opnieuw, verwerk minder opnames tegelijk of controleer je limiet bij de provider."
            }
            return "Serverfout: statuscode \(code)."
        case .generationFailed(let message):
            return "Generatie mislukt: \(message)"
        case .emptyResponse:
            return "De AI-provider gaf een leeg antwoord."
        case .timedOut:
            return "Tijdslimiet bereikt: de AI-provider gaf niet op tijd een volledig antwoord. Probeer het opnieuw of kies een sneller model."
        case .truncated:
            return "Het antwoord van de AI-provider is afgebroken omdat het de maximale lengte bereikte."
        }
    }
}

// MARK: - Request limits

/// Output cap per model request. The largest legitimate output is the single-request audit: one JSON item
/// of about 25 tokens per unit for up to 400 units, so about 10,000 tokens. A long notule draft is several
/// thousand. Reasoning models count their thinking against the same cap, hence 3x headroom.
let llmMaxOutputTokens = 32_768

/// Total time per model request, on top of the per-request idle timeout. SSE keep-alive lines reset the idle
/// timer, so without this a stalled stream never ends. 15 minutes covers a cold-loading local model plus a
/// long draft.
let llmRequestTimeLimit: TimeInterval = 900

let llmSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForResource = llmRequestTimeLimit
    return URLSession(configuration: configuration)
}()

/// URLSession reports the idle and the total time limit as `.timedOut`; name the cause instead.
func mappingTimeout<T>(_ body: () async throws -> T) async throws -> T {
    do { return try await body() } catch let error as URLError where error.code == .timedOut { throw LLMError.timedOut }
}

/// Wait before retrying an HTTP 429 when the provider sends no usable Retry-After.
let rateLimitDefaultWait: TimeInterval = 2
/// Longest Retry-After that is waited for; a provider asking more is reported as rate limiting right away.
let rateLimitMaxWait: TimeInterval = 30
let llmSleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }

/// Seconds to wait before retrying a 429: Retry-After as delta-seconds or HTTP date, else the default.
/// nil when the provider asks for more than `rateLimitMaxWait`.
func rateLimitWait(_ retryAfter: String?, now: Date = Date()) -> TimeInterval? {
    let value = retryAfter?.trimmingCharacters(in: .whitespaces) ?? ""
    let httpDate = DateFormatter()
    httpDate.locale = Locale(identifier: "en_US_POSIX")
    httpDate.timeZone = TimeZone(identifier: "GMT")
    httpDate.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let seconds = UInt(value).map(TimeInterval.init) ?? httpDate.date(from: value).map({ max(0, $0.timeIntervalSince(now)) })
    else { return rateLimitDefaultWait }
    return seconds <= rateLimitMaxWait ? seconds : nil
}

/// Sends a model request and retries it once on HTTP 429, after the provider's Retry-After plus up to one second
/// of jitter, so requests that were rate limited together do not collide again. The wait and the retry count
/// against the first attempt's `llmRequestTimeLimit`. When the wait is too long the 429 is returned unchanged, and
/// a second 429 is returned as well: the caller reports it. Cancellation during the wait throws CancellationError.
func sendRetryingRateLimit<T>(session: URLSession, sleep: @Sendable (TimeInterval) async throws -> Void,
                              _ send: (URLSession) async throws -> (T, URLResponse)) async throws -> (T, URLResponse) {
    let started = Date()
    let first = try await send(session)
    guard let http = first.1 as? HTTPURLResponse, http.statusCode == 429,
          let wait = rateLimitWait(http.value(forHTTPHeaderField: "Retry-After")).map({ $0 + .random(in: 0...1) })
    else { return first }
    let remaining = llmRequestTimeLimit - Date().timeIntervalSince(started) - wait
    guard remaining >= 1 else { return first }
    ModelRequestLog.retry(wait: wait)
    try await sleep(wait)
    // Same session settings, but only the time that is left.
    let configuration = session.configuration
    configuration.timeoutIntervalForResource = remaining
    let retrySession = URLSession(configuration: configuration)
    defer { retrySession.finishTasksAndInvalidate() }
    return try await send(retrySession)
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
    ///   - constraints: Source sentences the notule must keep; appended as a numbered block.
    ///   - onProgress: Called with each streamed text chunk as it arrives.
    /// - Returns: The complete generated notulen as a string.
    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        constraints: [String],
        onProgress: @Sendable (String) -> Void
    ) async throws -> String

    /// Plain, non-streamed completion (used by the audit and chunk summaries).
    func complete(system: String, user: String) async throws -> String
}

// MARK: - Prompt assembly

/// System prompt for the final notule request (port of Windows llm.ts).
func notuleSystemPrompt(_ profileSystemPrompt: String) -> String {
    "\(profileSystemPrompt)\n\nBrongetrouwheid gaat vóór beknoptheid en de template. \(NotuleAudit.factualityRules) Vermeld ieder expliciet vervallen tijdstip en iedere expliciete afwezigheid, ook als dat geen actie is. Als ergens geen besluit over uitvoering is genomen, behoud dat letterlijk als onbeslist; vraag niet hoe het uitgevoerd moet worden."
}

let chunkSummarySystemPrompt = "Je vat transcripties samen. Bewaar namen, feiten, besluiten, actiepunten, eigenaren en termijnen. Verzin niets. \(NotuleAudit.factualityRules)"
let chunkSummaryNotShorterMessage = "De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw."

/// Summarizes `text` chunk by chunk and repeats until it fits `limit`. Fails loudly
/// when a pass does not shrink the text, so it can never loop or silently truncate.
func summarizeUntilFits(
    _ text: String,
    limit: Int,
    split: (String, Int) -> [String],
    complete: (String, String) async throws -> String
) async throws -> String {
    var processed = text
    while processed.count > limit {
        var summaries: [String] = []
        let chunks = split(processed, limit)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            summaries.append(try await ModelStep.$current.withValue(ModelStep(.chunkSummary, index + 1, of: chunks.count)) {
                try await complete(chunkSummarySystemPrompt, "Vat dit deel compact samen:\n\n" + chunk)
            })
        }
        let joined = summaries.joined(separator: "\n\n")
        guard joined.count < processed.count else {
            throw LLMError.generationFailed(chunkSummaryNotShorterMessage)
        }
        processed = joined
    }
    return processed
}

/// Builds the user message for notule generation. Backend-style profiles embed
/// `{{TRANSCRIPTION}}` and `{{OUTPUT_TEMPLATE}}` placeholders in the notule prompt;
/// when present they are substituted in place. Otherwise the transcription and
/// template are appended (legacy inline profiles).
func buildNotuleUserContent(
    notulePrompt: String,
    transcription: String,
    outputTemplate: String?,
    constraints: [String] = []
) -> String {
    let template = (outputTemplate ?? "").replacingOccurrences(
        of: "<style\\b[^>]*>[\\s\\S]*?</style>", with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    // Byte-identical to the Windows closing rules (llm.ts buildUserContent).
    let contentRules = "\n\nLaatste inhoudsregels: volg de gekozen template en laat lege secties weg. Begin met één h1 die in 4 tot 10 woorden het doel of de uitkomst van het gesprek noemt; nooit alleen een genre-woord als Verslag, Notulen, Meeting, Gesprek of Overleg. Verzin geen feiten, besluiten, eigenaren of termijnen. \(NotuleAudit.factualityRules) Schrijf eenvoudige HTML zonder CSS, style-blok of code fences."
    let constraintBlock = constraints.isEmpty ? "" :
        "\n\nVerplicht te behouden bronzinnen (behoud de volledige betekenis, bedragen en voorwaarden bij het passende onderwerp, besluit of open punt; correcte parafrases mogen, tegenspraken nergens):\n"
        + constraints.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    if notulePrompt.contains("{{TRANSCRIPTION}}") {
        // Substitute the trusted template first, then insert the untrusted
        // transcription last so its content can never trigger a placeholder swap.
        return notulePrompt
            .replacingOccurrences(of: "{{OUTPUT_TEMPLATE}}", with: template)
            .replacingOccurrences(of: "{{TRANSCRIPTION}}", with: transcription) + contentRules + constraintBlock
    }
    var content = "\(notulePrompt)\n\nTranscriptie:\n\(transcription)"
    if !template.isEmpty {
        content += "\n\nGebruik dit outputformaat:\n\(template)"
    }
    return content + contentRules + constraintBlock
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

        case .openAI:
            guard provider.hasAPIKey else { return MissingAPIKeyLLMService(providerName: provider.studioNameForErrors) }
            let model = UserDefaults.standard.string(forKey: "openAIModel") ?? OpenAICompatibleLLMService.openAIDefaultModel
            // Large hosted context: chunk only truly huge transcripts.
            return OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.openAIBaseURL, model: model,
                                              apiKey: KeychainService.shared.load(for: "openAIApiKey"),
                                              maxChunkCharacters: 400_000)

        case .anthropic:
            guard provider.hasAPIKey else { return MissingAPIKeyLLMService(providerName: provider.studioNameForErrors) }
            let model = UserDefaults.standard.string(forKey: "anthropicModel") ?? AnthropicLLMService.defaultModel
            return AnthropicLLMService(model: model, apiKey: KeychainService.shared.load(for: "anthropicApiKey"))

        case .ollamaCloud:
            guard provider.hasAPIKey else { return MissingAPIKeyLLMService(providerName: provider.displayName) }
            return OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.ollamaCloudBaseURL,
                                              model: UserDefaults.standard.string(forKey: "ollamaCloudModel") ?? "",
                                              apiKey: KeychainService.shared.load(for: "ollamaApiKey"))

        case .openAICompatible:
            // The bearer token is only sent over HTTPS, so other schemes are refused up front.
            guard let config = CloudAIConfiguration.selected(), provider.hasAPIKey,
                  URL(string: config.baseURL)?.scheme?.lowercased() == "https" else {
                return MissingAPIKeyLLMService(providerName: provider.displayName)
            }
            return OpenAICompatibleLLMService.hosted(config, apiKey: KeychainService.shared.load(for: config.keychainKey))

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

// MARK: - MissingAPIKeyLLMService

/// A hosted provider is selected (or synced from another device) but no key is
/// stored on this device yet.
private struct MissingAPIKeyLLMService: LLMService {
    let providerName: String
    var isAvailable: Bool { false }

    func generateNotulen(
        transcription: String,
        systemPrompt: String,
        notulePrompt: String,
        outputTemplate: String?,
        constraints: [String],
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {
        throw LLMError.generationFailed("Geen API-sleutel voor \(providerName) op dit apparaat. Vul die in bij Instellingen > Verwerking.")
    }

    func complete(system: String, user: String) async throws -> String {
        throw LLMError.generationFailed("Geen API-sleutel voor \(providerName) op dit apparaat. Vul die in bij Instellingen > Verwerking.")
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
        constraints: [String],
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {
        throw LLMError.generationFailed("Cloud provider genereert notulen server-side via n8n.")
    }

    func complete(system: String, user: String) async throws -> String {
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

    static let openAIBaseURL = "https://api.openai.com"
    static let ollamaCloudBaseURL = "https://ollama.com"
    static let openAIDefaultModel = "gpt-5.6-terra"

    /// Transcript size above which it is summarized in chunks first. The default
    /// is what a typical local model handles comfortably (conservative estimate).
    let maxChunkCharacters: Int

    /// Test seam: replaces the network call behind `complete(system:user:)`.
    var completionOverride: (@Sendable (String, String) async throws -> String)?
    /// Test seam: the wait before retrying an HTTP 429.
    var rateLimitSleep = llmSleep
    private let session: URLSession

    /// Hosted (HTTPS) providers have a large context window; without the explicit limit the
    /// 8_000 local-model default would apply to any host other than ollama.com.
    static func hosted(_ config: CloudAIConfiguration, apiKey: String?) -> OpenAICompatibleLLMService {
        OpenAICompatibleLLMService(baseURL: config.baseURL, model: config.model, apiKey: apiKey, maxChunkCharacters: 64_000)
    }

    init(baseURL: String, model: String, apiKey: String? = nil, maxChunkCharacters: Int? = nil, session: URLSession = llmSession) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
        // Ollama Cloud models have at least 128K context; leave ample room for the profile and output.
        let ollamaCloud = URL(string: baseURL)?.scheme == "https"
            && URL(string: baseURL)?.host?.lowercased() == "ollama.com"
        self.maxChunkCharacters = maxChunkCharacters ?? (ollamaCloud ? 64_000 : 8_000)
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            await checkConnection() == .ready
        }
    }

    enum ConnectionStatus: Equatable {
        case ready
        case unreachable
        /// HTTPS server requires a key and none is configured.
        case keyMissing
        /// HTTPS server answered 401/403 to the configured key.
        case keyRejected
    }

    /// Reachability alone is not enough: Ollama Cloud lists models without a key but
    /// answers 401 on chat. HTTPS endpoints are therefore also probed on a protected
    /// endpoint, so a missing or wrong key shows up here instead of during generation.
    func checkConnection() async -> ConnectionStatus {
        // Try the OpenAI-compatible endpoint first, then fall back to Ollama's
        // native one. The previous `URL(...) ?? URL(...)` never fell back
        // because the first string always parses into a valid URL.
        var reachable = await endpointReturns200("/v1/models")
        if !reachable { reachable = await endpointReturns200("/api/tags") }
        guard reachable else { return .unreachable }
        guard URL(string: baseURL)?.scheme?.lowercased() == "https" else { return .ready }
        guard let status = await protectedEndpointStatus() else { return .unreachable }
        guard status == 401 || status == 403 else { return .ready }
        return apiKey == nil ? .keyMissing : .keyRejected
    }

    /// POSTs an empty body to chat completions: an authenticated caller gets a
    /// validation error (4xx other than 401/403), an unauthenticated one 401. No tokens are spent.
    private func protectedEndpointStatus() async -> Int? {
        guard let url = URL(string: endpoint("/v1/chat/completions")) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        applyAuth(to: &request)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    /// Accepts base URLs with or without a trailing `/v1`, as hosted providers document both.
    private func endpoint(_ path: String) -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base + (base.hasSuffix("/v1") && path.hasPrefix("/v1/") ? String(path.dropFirst(3)) : path)
    }

    private func endpointReturns200(_ path: String) async -> Bool {
        guard let url = URL(string: endpoint(path)) else { return false }
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
        guard let url = URL(string: endpoint("/v1/models")) else { return nil }
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
        guard let url = URL(string: endpoint("/api/tags")) else { return nil }
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
        constraints: [String],
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {

        // If the transcription is long, summarize it in chunks first
        let processedTranscription: String
        if transcription.count > maxChunkCharacters {
            logger.info("OpenAICompatibleLLMService: transcription is long (\(transcription.count) chars), chunking first")
            processedTranscription = try await summarizeInChunks(transcription)
        } else {
            processedTranscription = transcription
        }

        // Build the final prompt
        let userContent = buildNotuleUserContent(
            notulePrompt: notulePrompt,
            transcription: processedTranscription,
            outputTemplate: outputTemplate,
            constraints: constraints
        )

        return try await ModelRequestLog.run(provider: providerKind, model: model, system: systemPrompt, user: userContent) {
            try await mappingTimeout {
                try await streamChatCompletion(
                    systemPrompt: systemPrompt,
                    userMessage: userContent,
                    onProgress: onProgress
                )
            }
        }
    }

    // MARK: - Chunked Summarization

    func summarizeInChunks(_ text: String) async throws -> String {
        try await summarizeUntilFits(
            text,
            limit: maxChunkCharacters,
            split: { self.splitIntoChunks($0, maxChars: $1) },
            complete: { try await self.complete(system: $0, user: $1) }
        )
    }

    func complete(system: String, user: String) async throws -> String {
        if let completionOverride { return try await completionOverride(system, user) }
        return try await ModelRequestLog.run(provider: providerKind, model: model, system: system, user: user) {
            try await mappingTimeout { try await streamChatCompletion(systemPrompt: system, userMessage: user, onProgress: { _ in }) }
        }
    }

    /// Provider kind for the log, without the host of a self-configured endpoint.
    private var providerKind: String {
        let url = URL(string: baseURL)
        switch url?.host?.lowercased() {
        case "api.openai.com": return "openai"
        case "ollama.com": return "ollama-cloud"
        default: return url?.scheme?.lowercased() == "https" ? "hosted" : "local"
        }
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

        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.generationFailed("Kies een model bij Instellingen > Verwerking.")
        }
        guard let url = URL(string: endpoint("/v1/chat/completions")) else {
            throw LLMError.generationFailed("Ongeldige server URL: \(baseURL)")
        }

        // api.openai.com rejects `max_tokens` for newer models; local servers only know `max_tokens`.
        let capKey = URL(string: baseURL)?.host?.lowercased() == "api.openai.com" ? "max_completion_tokens" : "max_tokens"
        let requestBody: [String: Any] = [
            "model": model,
            "stream": true,
            capKey: llmMaxOutputTokens,
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
        // and a premature timeout kills the whole notule generation. `llmSession` bounds the total.
        request.timeoutInterval = 300

        let (asyncBytes, response) = try await sendRetryingRateLimit(session: session, sleep: rateLimitSleep) {
            try await $0.bytes(for: request)
        }

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
                  let first = choices.first
            else { continue }
            // A capped answer is incomplete; never parse it as a short one.
            if first["finish_reason"] as? String == "length" { throw LLMError.truncated }
            guard let delta = first["delta"] as? [String: Any],
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

// MARK: - Chunk helpers

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
