// AnthropicLLMService.swift
// ThoughtVault
//
// Notule generation through the hosted Messages API with the user's own API
// key (Keychain). Uses the large context window directly: no chunking.

import Foundation

final class AnthropicLLMService: LLMService, @unchecked Sendable {

    static let baseURL = "https://api.anthropic.com"
    static let defaultModel = "claude-sonnet-5-5"
    private static let apiVersion = "2023-06-01"

    private let model: String
    private let apiKey: String?

    init(model: String, apiKey: String?) {
        self.model = model
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
        onProgress: @Sendable (String) -> Void
    ) async throws -> String {
        guard var request = request("/v1/messages") else {
            throw LLMError.generationFailed("Vul je API-sleutel in bij Instellingen > Verwerking.")
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "stream": true,
            "system": systemPrompt,
            "messages": [[
                "role": "user",
                "content": buildNotuleUserContent(notulePrompt: notulePrompt,
                                                  transcription: transcription,
                                                  outputTemplate: outputTemplate)
            ]]
        ]
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Ongeldig serverantwoord.")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw LLMError.generationFailed("API-sleutel geweigerd. Controleer de sleutel.") }
            throw LLMError.serverError(http.statusCode)
        }

        var fullText = ""
        for try await line in bytes.lines {
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
            case "error":
                let message = (json["error"] as? [String: Any])?["message"] as? String ?? "onbekende fout"
                throw LLMError.generationFailed(message)
            case "message_stop":
                break
            default:
                continue
            }
        }

        if fullText.isEmpty { throw LLMError.emptyResponse }
        return fullText
    }
}
