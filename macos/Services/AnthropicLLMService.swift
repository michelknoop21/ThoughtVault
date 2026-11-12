// AnthropicLLMService.swift
// ThoughtVault
//
// Notule generation through the hosted Messages API with the user's own API
// key (Keychain). Uses the large context window directly; only transcripts beyond `maxChunkCharacters` are chunked.

import Foundation

final class AnthropicLLMService: LLMService, @unchecked Sendable {

    static let baseURL = "https://api.anthropic.com"
    static let defaultModel = "claude-sonnet-5-5"
    private static let apiVersion = "2023-06-01"

    /// Claude models have >= 200K tokens of context; 150K characters (~40K tokens)
    /// leaves ample room for the profile, template and output.
    static let maxChunkCharacters = 150_000

    private let model: String
    private let apiKey: String?
    private let session: URLSession
    /// Test seam: the wait before retrying an HTTP 429.
    var rateLimitSleep = llmSleep

    init(model: String, apiKey: String?, session: URLSession = llmSession) {
        self.model = model
        self.session = session
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func request(_ path: String) -> URLRequest? {
        guard let apiKey, let url = URL(string: Self.baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
    }

    // MARK: - Availability / models

    var isAvailable: Bool {
        get async { !(await fetchModels().isEmpty) }
    }

    /// Model ids available to this key; empty when the key is missing or rejected.
    func fetchModels() async -> [String] {
        guard var request = request("/v1/models?limit=100") else { return [] }
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]]
        else { return [] }
        return items.compactMap { $0["id"] as? String }
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
        guard var request = request("/v1/messages") else {
            throw LLMError.generationFailed("Vul je API-sleutel in bij Instellingen > Verwerking.")
        }
        let transcription = try await summarizeUntilFits(
            transcription,
            limit: Self.maxChunkCharacters,
            split: { hardSplitOversizedChunks([$0], maxChars: $1) },
            complete: { try await self.complete(system: $0, user: $1) }
        )
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "stream": true,
            "system": systemPrompt,
            "messages": [[
                "role": "user",
                "content": buildNotuleUserContent(notulePrompt: notulePrompt,
                                                  transcription: transcription,
                                                  outputTemplate: outputTemplate,
                                                  constraints: constraints)
            ]]
        ]
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let fullText = try await mappingTimeout { () async throws -> String in
            let (bytes, response) = try await sendRetryingRateLimit(session: session, sleep: rateLimitSleep) {
                try await $0.bytes(for: request)
            }
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.generationFailed("Ongeldig serverantwoord.")
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 { throw LLMError.generationFailed("API-sleutel geweigerd. Controleer de sleutel.") }
                throw LLMError.serverError(http.statusCode)
            }

            var fullText = ""
            stream: for try await line in bytes.lines {
                guard line.hasPrefix("data: "),
                      let data = line.dropFirst(6).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                switch json["type"] as? String {
                case "content_block_delta":
                    if let delta = json["delta"] as? [String: Any], let text = delta["text"] as? String {
                        fullText += text
                        onProgress(text)
                    }
                case "message_delta":
                    // A capped answer is incomplete; never parse it as a short one.
                    if (json["delta"] as? [String: Any])?["stop_reason"] as? String == "max_tokens" { throw LLMError.truncated }
                case "error":
                    let message = (json["error"] as? [String: Any])?["message"] as? String ?? "onbekende fout"
                    throw LLMError.generationFailed(message)
                case "message_stop":
                    break stream
                default:
                    continue
                }
            }
            return fullText
        }

        if fullText.isEmpty { throw LLMError.emptyResponse }
        return fullText
    }

    // MARK: - Plain completion

    func complete(system: String, user: String) async throws -> String {
        guard var request = request("/v1/messages") else {
            throw LLMError.generationFailed("Vul je API-sleutel in bij Instellingen > Verwerking.")
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let (data, response) = try await mappingTimeout {
            try await sendRetryingRateLimit(session: session, sleep: rateLimitSleep) { try await $0.data(for: request) }
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Ongeldig serverantwoord.")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw LLMError.generationFailed("API-sleutel geweigerd. Controleer de sleutel.") }
            throw LLMError.serverError(http.statusCode)
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if json?["stop_reason"] as? String == "max_tokens" { throw LLMError.truncated }
        let blocks = json?["content"] as? [[String: Any]]
        let text = (blocks ?? []).compactMap { $0["text"] as? String }.joined()
        if text.isEmpty { throw LLMError.emptyResponse }
        return text
    }
}
