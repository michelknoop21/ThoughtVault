import Foundation

/// What the provider's public model list (GET /api/v1/models, no key) says about one model.
/// Same rule as windows/src/services/openRouterModels.ts.
struct OpenRouterModel: Equatable, Sendable {
    /// Thinks when the request names no reasoning: mandatory, default_enabled, or a default effort without a switch.
    var reasonsByDefault: Bool
    var lowEffort: Bool
    /// top_provider.max_completion_tokens
    var maxCompletionTokens: Int?

    /// Output cap for a model that thinks by default. Thinking and the reply share max_tokens, and the provider's
    /// notes for adaptive-thinking models name 64k as the size that worked for long turns; at 32k a 43k-character
    /// meeting ended truncated. Only generated tokens are billed, so the higher cap costs only when a model needs it.
    static let reasoningOutputTokens = 65_536

    static func parseList(_ data: Data) -> [String: OpenRouterModel] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return [:] }
        var models: [String: OpenRouterModel] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String else { continue }
            let reasoning = entry["reasoning"] as? [String: Any]
            let defaultEnabled = reasoning?["default_enabled"] as? Bool
            let reasons = reasoning != nil && (reasoning?["mandatory"] as? Bool == true || defaultEnabled == true
                || (defaultEnabled == nil && (reasoning?["default_effort"] as? String)?.isEmpty == false))
            let max = (entry["top_provider"] as? [String: Any])?["max_completion_tokens"] as? Int
            models[id] = OpenRouterModel(reasonsByDefault: reasons,
                                         lowEffort: (reasoning?["supported_efforts"] as? [String])?.contains("low") ?? false,
                                         maxCompletionTokens: (max ?? 0) > 0 ? max : nil)
        }
        return models
    }

    /// Request fields per model. An effort is only sent to a model that thinks anyway, because for any other model
    /// it switches thinking on. A model that only offers high or none keeps its default. Unknown model: the plain cap.
    static func requestFields(_ model: OpenRouterModel?, baseCap: Int) -> (maxTokens: Int, reasoning: [String: String]?) {
        let reasons = model?.reasonsByDefault == true
        let cap = reasons ? reasoningOutputTokens : baseCap
        return (min(cap, model?.maxCompletionTokens ?? cap), reasons && model?.lowEffort == true ? ["effort": "low"] : nil)
    }
}

/// The model list, fetched once per app session; a failed fetch is retried on the next request.
actor OpenRouterModelCatalog {
    static let shared = OpenRouterModelCatalog()
    static let listURL = URL(string: "https://openrouter.ai/api/v1/models")!

    private var models: [String: OpenRouterModel]?
    private var loading: Task<[String: OpenRouterModel]?, Never>?

    func model(_ id: String) async -> OpenRouterModel? {
        if let models { return models[id] }
        let task = loading ?? Task { await Self.fetch() }
        loading = task
        let result = await task.value
        loading = nil
        if models == nil { models = result }
        return result?[id]
    }

    private static func fetch() async -> [String: OpenRouterModel]? {
        var request = URLRequest(url: listURL)
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = root["data"] as? [[String: Any]] {
            SuggestedModels.rememberReported(SuggestedModels.reportedPrices(items), provider: .openRouter,
                                              baseURL: OpenAICompatibleLLMService.openRouterBaseURL)
        }
        let models = OpenRouterModel.parseList(data)
        return models.isEmpty ? nil : models
    }
}
