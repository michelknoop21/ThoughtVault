// SuggestedModels.swift
// ThoughtVault
//
// Curated notule models per provider and the price cap that keeps colleagues
// away from the expensive top tier.

import Foundation

/// List price in USD per million tokens.
struct ModelPrice: Equatable, Sendable {
    let input: Double
    let output: Double
}

enum SuggestedModels {

    /// Mid-tier ceiling: USD 3 per million input tokens and USD 15 per million output tokens.
    static let cap = ModelPrice(input: 3, output: 15)

    /// List prices of the hosted models the app knows (checked November 2026).
    static let knownPrices: [String: ModelPrice] = [
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50),
        "claude-haiku-4-5": ModelPrice(input: 1, output: 5),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10),
        "claude-sonnet-4-6": ModelPrice(input: 3, output: 15),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20),
        "claude-opus-5": ModelPrice(input: 5, output: 25),
        "claude-opus-4-8": ModelPrice(input: 5, output: 25),
        "claude-fable-5-2": ModelPrice(input: 8, output: 40),
        "claude-fable-5-1": ModelPrice(input: 10, output: 50),
        "gpt-5.6-luna": ModelPrice(input: 0.20, output: 1.20),
        "gpt-5.6-terra": ModelPrice(input: 2, output: 12),
        "gpt-5.6-sol": ModelPrice(input: 5, output: 30),
        "mistral-large-4-0": ModelPrice(input: 1.36, output: 4.18),
    ]

    /// The short list shown first in every model picker.
    static func suggested(for provider: NotulenProvider) -> [String] {
        switch provider {
        case .openRouter: return ["mistralai/mistral-large-4-0", "anthropic/claude-sonnet-5-5", "openai/gpt-5.6-terra"]
        case .anthropic: return ["claude-sonnet-5-5", "claude-haiku-5-5"]
        case .openAI: return ["gpt-5.6-terra", "gpt-5.6-luna"]
        case .ollamaCloud: return ["mistral-large-4", "gpt-oss:120b"]
        default: return []
        }
    }

    /// Providers that bill every token to the user's own API key.
    static func isMetered(_ provider: NotulenProvider) -> Bool {
        provider == .openAI || provider == .anthropic || provider == .openAICompatible || provider == .openRouter
    }

    /// Known price; a routed id such as `vendor/model` falls back to its last part.
    static func price(of model: String) -> ModelPrice? {
        knownPrices[model] ?? model.split(separator: "/").last.flatMap { knownPrices[String($0)] }
    }

    static func isWithinCap(_ price: ModelPrice) -> Bool {
        price.input <= cap.input && price.output <= cap.output
    }

    /// Metered providers only allow a model whose price is known (reported or listed) and within
    /// the cap; an unknown price counts as too expensive. Local and flat-rate providers are free.
    static func isAllowed(_ model: String, provider: NotulenProvider, reportedPrice: ModelPrice? = nil) -> Bool {
        guard isMetered(provider) else { return true }
        guard let price = reportedPrice ?? price(of: model) else { return false }
        return isWithinCap(price)
    }

    /// Picker choices: suggestions first, then the current and listed models that pass the cap.
    /// `prices` holds what the provider reported for its listed models.
    static func choices(for provider: NotulenProvider, current: String, available: [String] = [],
                        prices: [String: ModelPrice] = [:]) -> [String] {
        var seen = Set<String>()
        return (suggested(for: provider) + [current] + available).filter {
            !$0.isEmpty && isAllowed($0, provider: provider, reportedPrice: prices[$0]) && seen.insert($0).inserted
        }
    }

    /// A models endpoint that reports `pricing.prompt` / `pricing.completion` gives USD per token
    /// as strings; negative values mean variable pricing and count as unknown.
    static func pricePerToken(prompt: String?, completion: String?) -> ModelPrice? {
        guard let input = prompt.flatMap(Double.init), let output = completion.flatMap(Double.init),
              input >= 0, output >= 0 else { return nil }
        return ModelPrice(input: input * 1_000_000, output: output * 1_000_000)
    }

    /// The models a `/models` endpoint lists with the price it reports for each; nil when unreachable.
    static func fetchReportedPrices(baseURL: String, apiKey: String) async -> [String: ModelPrice]? {
        guard let url = URL(string: baseURL + "/models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }
        return reportedPrices(items)
    }

    /// Model id to reported price; a model without a usable price is left out.
    static func reportedPrices(_ items: [[String: Any]]) -> [String: ModelPrice] {
        var result: [String: ModelPrice] = [:]
        for item in items {
            guard let id = item["id"] as? String else { continue }
            let pricing = item["pricing"] as? [String: Any]
            result[id] = pricePerToken(prompt: pricing?["prompt"] as? String, completion: pricing?["completion"] as? String)
        }
        return result
    }

    // MARK: - Settings

    /// UserDefaults key that holds the model of `provider`; nil when the model is not a plain setting.
    static func modelKey(for provider: NotulenProvider) -> String? {
        switch provider {
        case .openAI: return "openAIModel"
        case .anthropic: return "anthropicModel"
        case .ollama: return "ollamaModel"
        case .ollamaCloud: return "ollamaCloudModel"
        case .lmStudio: return "lmStudioModel"
        case .openRouter: return "openRouterModel"
        default: return nil
        }
    }

    /// The provider local notule generation uses; the server setting falls back to the local default.
    static var currentProvider: NotulenProvider {
        let provider = NotulenProvider.configured()
        return provider == .cloud ? .ollama : provider
    }

    static func currentModel(for provider: NotulenProvider) -> String {
        if let key = modelKey(for: provider), let model = UserDefaults.standard.string(forKey: key), !model.isEmpty { return model }
        switch provider {
        case .openAI: return OpenAICompatibleLLMService.openAIDefaultModel
        case .anthropic: return AnthropicLLMService.defaultModel
        case .openRouter: return OpenAICompatibleLLMService.openRouterDefaultModel
        case .ollama: return "llama3.2"
        case .lmStudio: return "local-model"
        case .openAICompatible: return CloudAIConfiguration.selected()?.model ?? ""
        default: return ""
        }
    }
}
