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

    /// List prices of the hosted models the app knows (list prices checked November 2026).
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
        "gpt-5.6-sol": ModelPrice(input: 4, output: 20),
        "mistral-large-4-0": ModelPrice(input: 0.70, output: 2.10),
        "mistral-medium-3-5": ModelPrice(input: 1.50, output: 7.50),
        "mistral-small-2603": ModelPrice(input: 0.15, output: 0.60),
        "gpt-6-luna": ModelPrice(input: 0.10, output: 0.50),
        "gpt-6-sol": ModelPrice(input: 2, output: 10),
        "gpt-6.1-terra": ModelPrice(input: 1, output: 5),
        "gpt-6.1-sol": ModelPrice(input: 2, output: 10),
    ]

    /// The short list shown first in every model picker.
    static func suggested(for provider: NotulenProvider) -> [String] {
        switch provider {
        case .openRouter: return ["mistralai/mistral-large-4-0", "anthropic/claude-sonnet-5.5", "openai/gpt-6.1-terra"]
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

    /// Known price; a routed id such as `vendor/model` falls back to its last part, and a
    /// version written with a dot (`x-5.5`) also matches the dashed spelling (`x-5-5`).
    static func price(of model: String) -> ModelPrice? {
        let last = model.split(separator: "/").last.map(String.init) ?? model
        return [model, last, last.replacingOccurrences(of: ".", with: "-")].lazy.compactMap { knownPrices[$0] }.first
    }

    static func isWithinCap(_ price: ModelPrice) -> Bool {
        price.input <= cap.input && price.output <= cap.output
    }

    /// Metered providers only allow a model whose price is known (listed, or reported by that
    /// endpoint in the last week) and within the cap; an unknown price counts as too expensive,
    /// except on a custom OpenAI-compatible endpoint, which is usually self-hosted.
    /// Local and flat-rate providers are free.
    static func isAllowed(_ model: String, provider: NotulenProvider, reportedPrice: ModelPrice? = nil) -> Bool {
        guard isMetered(provider) else { return true }
        let remembered = { reportedPriceBaseURL(for: provider).flatMap { rememberedPrice(of: model, provider: provider, baseURL: $0) } }
        let prices = [reportedPrice, price(of: model), remembered()].compactMap { $0 }
        return prices.isEmpty ? provider == .openAICompatible : prices.allSatisfy(isWithinCap)
    }

    /// Picker choices: suggestions first, then the current and listed models that pass the cap.
    /// `prices` holds what the provider reported for its listed models. OpenRouter lists only what the
    /// key may use, so once its list is loaded a suggestion it does not contain is left out.
    static func choices(for provider: NotulenProvider, current: String, available: [String] = [],
                        prices: [String: ModelPrice] = [:]) -> [String] {
        var seen = Set<String>()
        let suggestions = provider == .openRouter && !available.isEmpty ? suggested(for: provider).filter(available.contains) : suggested(for: provider)
        return (suggestions + [current] + available).filter {
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
    /// OpenRouter's `/models/user` lists only what the key may use under the workspace's model access.
    static func fetchReportedPrices(provider: NotulenProvider, baseURL: String, apiKey: String) async -> [String: ModelPrice]? {
        guard let url = URL(string: baseURL + (provider == .openRouter ? "/models/user" : "/models")) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }
        let prices = reportedPrices(items)
        // Kept so a listed model chosen in settings stays allowed when the request is built later.
        rememberReported(prices, provider: provider, baseURL: baseURL)
        return prices
    }

    /// Why `model` is not sent at all: the provider does not allow it and has no suggestion to fall back to.
    static func refusal(for model: String, provider: NotulenProvider) -> String? {
        guard !isAllowed(model, provider: provider), suggested(for: provider).isEmpty else { return nil }
        return "\(model) valt boven de prijsgrens en is niet gebruikt. Kies een goedkoper model bij Instellingen > Verwerking."
    }

    static func requestRefusal(for model: String, baseURL: String) -> String? {
        let provider: NotulenProvider = OpenAICompatibleLLMService.providerKind(baseURL: baseURL) == "openrouter"
            ? .openRouter : .openAICompatible
        let priceBaseURL = provider == .openRouter ? OpenAICompatibleLLMService.openRouterBaseURL : baseURL
        let prices = [price(of: model), rememberedPrice(of: model, provider: provider, baseURL: priceBaseURL)].compactMap { $0 }
        guard prices.contains(where: { !isWithinCap($0) }) else { return nil }
        return "\(model) valt boven de prijsgrens en is niet gebruikt. Kies een goedkoper model bij Instellingen > Verwerking."
    }

    // MARK: - Reported prices

    /// Reported prices are kept per provider and endpoint, and trusted for a week.
    static let rememberedPriceMaxAge: TimeInterval = 7 * 24 * 3600
    private static let rememberedPricesKey = "reportedModelPricesByEndpoint"

    private static func priceScope(_ provider: NotulenProvider, _ baseURL: String) -> String { provider.rawValue + "|" + baseURL }

    /// The endpoint whose reported prices apply to `provider` now; nil when it reports none.
    private static func reportedPriceBaseURL(for provider: NotulenProvider) -> String? {
        switch provider {
        case .openRouter: return OpenAICompatibleLLMService.openRouterBaseURL
        case .openAICompatible: return CloudAIConfiguration.selected()?.baseURL
        default: return nil
        }
    }

    static func rememberReported(_ prices: [String: ModelPrice], provider: NotulenProvider, baseURL: String,
                                 at now: Date = Date(), defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: rememberedPricesKey) ?? [:]
        all[priceScope(provider, baseURL)] = ["at": now.timeIntervalSince1970,
                                              "prices": prices.mapValues { [$0.input, $0.output] }] as [String: Any]
        defaults.set(all, forKey: rememberedPricesKey)
    }

    static func rememberedPrice(of model: String, provider: NotulenProvider, baseURL: String,
                                now: Date = Date(), defaults: UserDefaults = .standard) -> ModelPrice? {
        guard let scope = defaults.dictionary(forKey: rememberedPricesKey)?[priceScope(provider, baseURL)] as? [String: Any],
              let at = scope["at"] as? Double, now.timeIntervalSince1970 - at <= rememberedPriceMaxAge,
              let price = (scope["prices"] as? [String: [Double]])?[model], price.count == 2 else { return nil }
        return ModelPrice(input: price[0], output: price[1])
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

    /// The model a notule request uses. A stored model that a metered provider does not allow
    /// (above the cap or without a known price) is replaced by the provider's first suggestion;
    /// `capNotice(for:)` says so in the task details.
    static func currentModel(for provider: NotulenProvider) -> String {
        let stored = storedModel(for: provider)
        guard !isAllowed(stored, provider: provider), let fallback = suggested(for: provider).first else { return stored }
        return fallback
    }

    /// Short notice when `currentModel(for:)` replaced or refused the stored model; nil otherwise.
    static func capNotice(for provider: NotulenProvider) -> String? {
        let stored = storedModel(for: provider), used = currentModel(for: provider)
        if let refusal = refusal(for: stored, provider: provider) { return refusal }
        return stored == used ? nil : "\(stored) valt boven de prijsgrens, daarom is \(used) gebruikt."
    }

    private static func storedModel(for provider: NotulenProvider) -> String {
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
