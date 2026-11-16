import XCTest
@testable import ThoughtVault

final class SuggestedModelsTests: XCTestCase {

    func testSuggestionsStayWithinTheCap() {
        for provider in [NotulenProvider.openAI, .anthropic, .openRouter] {
            let suggested = SuggestedModels.suggested(for: provider)
            XCTAssertFalse(suggested.isEmpty)
            for model in suggested {
                XCTAssertTrue(SuggestedModels.isAllowed(model, provider: provider), model)
            }
        }
    }

    func testMeteredProvidersBlockExpensiveAndUnknownModels() {
        XCTAssertFalse(SuggestedModels.isAllowed("claude-opus-5-5", provider: .anthropic))
        XCTAssertFalse(SuggestedModels.isAllowed("gpt-5.6-sol", provider: .openAI))
        XCTAssertFalse(SuggestedModels.isAllowed("unknown-model", provider: .openAI))
        XCTAssertTrue(SuggestedModels.isAllowed("claude-sonnet-4-6", provider: .anthropic))  // exactly on the cap
        XCTAssertTrue(SuggestedModels.isAllowed("anthropic/claude-sonnet-5-5", provider: .openAICompatible))
    }

    func testLocalAndFlatRateProvidersAreNotCapped() {
        XCTAssertTrue(SuggestedModels.isAllowed("anything", provider: .ollama))
        XCTAssertTrue(SuggestedModels.isAllowed("anything", provider: .ollamaCloud))
        XCTAssertTrue(SuggestedModels.isAllowed("anything", provider: .lmStudio))
    }

    func testChoicesDropCurrentModelAboveTheCap() {
        let choices = SuggestedModels.choices(for: .anthropic, current: "claude-opus-5-5", available: ["claude-haiku-4-5"])
        XCTAssertEqual(choices, ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-haiku-4-5"])
    }

    func testReportedPerTokenPricesAreConvertedAndCapped() {
        let cheap = SuggestedModels.pricePerToken(prompt: "0.000002", completion: "0.00001")
        XCTAssertEqual(cheap?.input ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(cheap?.output ?? 0, 10, accuracy: 0.0001)
        XCTAssertTrue(SuggestedModels.isAllowed("x/new-model", provider: .openAICompatible, reportedPrice: cheap))

        let expensive = SuggestedModels.pricePerToken(prompt: "0.000005", completion: "0.000025")
        XCTAssertFalse(SuggestedModels.isAllowed("x/big-model", provider: .openAICompatible, reportedPrice: expensive))
        XCTAssertNil(SuggestedModels.pricePerToken(prompt: "-1", completion: "-1"))
        XCTAssertNil(SuggestedModels.pricePerToken(prompt: nil, completion: "0.1"))
    }

    func testReportedModelListKeepsOnlyPricedModels() {
        let prices = SuggestedModels.reportedPrices([
            ["id": "vendor/cheap", "pricing": ["prompt": "0.000001", "completion": "0.000002"]],
            ["id": "vendor/costly", "pricing": ["prompt": "0.00001", "completion": "0.00005"]],
            ["id": "vendor/variable", "pricing": ["prompt": "-1", "completion": "-1"]],
        ])
        XCTAssertEqual(Set(prices.keys), ["vendor/cheap", "vendor/costly"])
        let choices = SuggestedModels.choices(for: .openRouter, current: "", available: prices.keys.sorted(), prices: prices)
        XCTAssertTrue(choices.contains("vendor/cheap"))
        XCTAssertFalse(choices.contains("vendor/costly"))
        XCTAssertEqual(choices.first, "mistralai/mistral-large-4-0")
    }

    /// Ids from the routed provider's public model list (November 2026), kept here so the test needs no network.
    private static let routedListFixture: Set<String> = [
        "mistralai/mistral-large-4-0", "anthropic/claude-sonnet-5.5", "anthropic/claude-haiku-5.5",
        "anthropic/claude-opus-5.5", "anthropic/claude-fable-5.2", "openai/gpt-5.6-terra",
        "openai/gpt-5.6-luna", "openai/gpt-5.6-sol",
    ]

    func testSuggestedRoutedIdsExistInTheProviderList() {
        for model in SuggestedModels.suggested(for: .openRouter) {
            XCTAssertNotNil(model.range(of: #"^[a-z0-9-]+/[a-z0-9.:-]+$"#, options: .regularExpression), model)
            XCTAssertTrue(Self.routedListFixture.contains(model), model)
        }
    }

    func testDottedAndDashedVersionsShareAPrice() {
        XCTAssertEqual(SuggestedModels.price(of: "anthropic/claude-sonnet-5.5"), SuggestedModels.price(of: "claude-sonnet-5-5"))
        XCTAssertFalse(SuggestedModels.isAllowed("anthropic/claude-opus-5.5", provider: .openRouter))
        XCTAssertFalse(SuggestedModels.isAllowed("openai/gpt-5.6-sol", provider: .openRouter))
        XCTAssertTrue(SuggestedModels.isAllowed("openai/gpt-5.6-luna", provider: .openRouter))
    }

    /// The model used for a request comes from `currentModel`; a stored model above the cap must not reach it.
    func testStoredModelAboveTheCapIsNotUsed() {
        let key = "openRouterModel"
        let original = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }
        UserDefaults.standard.set("anthropic/claude-opus-5", forKey: key)
        XCTAssertEqual(SuggestedModels.currentModel(for: .openRouter), "mistralai/mistral-large-4-0")
        XCTAssertEqual(SuggestedModels.capNotice(for: .openRouter),
                       "anthropic/claude-opus-5 valt boven de prijsgrens, daarom is mistralai/mistral-large-4-0 gebruikt.")
        UserDefaults.standard.set("openai/gpt-5.6-luna", forKey: key)
        XCTAssertEqual(SuggestedModels.currentModel(for: .openRouter), "openai/gpt-5.6-luna")
        XCTAssertNil(SuggestedModels.capNotice(for: .openRouter))
    }

    /// A custom endpoint is usually self-hosted: an unknown price is fine, a known price above the cap is refused.
    func testCompatibleEndpointRefusesOnlyAKnownPriceAboveTheCap() {
        XCTAssertTrue(SuggestedModels.isAllowed("eigen-llama-70b", provider: .openAICompatible))
        XCTAssertTrue(SuggestedModels.isAllowed("gpt-5.6-terra", provider: .openAICompatible))
        XCTAssertFalse(SuggestedModels.isAllowed("gpt-5.6-sol", provider: .openAICompatible))
        XCTAssertNil(SuggestedModels.refusal(for: "eigen-llama-70b", provider: .openAICompatible))
        let refusal = SuggestedModels.refusal(for: "gpt-5.6-sol", provider: .openAICompatible)
        XCTAssertEqual(refusal, "gpt-5.6-sol valt boven de prijsgrens en is niet gebruikt. Kies een goedkoper model bij Instellingen > Verwerking.")
        // Providers with suggestions fall back instead of refusing.
        XCTAssertNil(SuggestedModels.refusal(for: "anthropic/claude-opus-5", provider: .openRouter))
        XCTAssertFalse(SuggestedModels.isAllowed("vendor/unknown", provider: .openRouter))
    }

    func testRememberedPricesArePerProviderAndEndpointAndExpire() throws {
        let suite = "reported-prices-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let cheap = ModelPrice(input: 1, output: 2)
        SuggestedModels.rememberReported(["vendor/x": cheap], provider: .openRouter, baseURL: "https://a.example/v1",
                                         at: t0, defaults: defaults)
        XCTAssertEqual(SuggestedModels.rememberedPrice(of: "vendor/x", provider: .openRouter, baseURL: "https://a.example/v1",
                                                       now: t0.addingTimeInterval(86_400), defaults: defaults), cheap)
        XCTAssertNil(SuggestedModels.rememberedPrice(of: "vendor/x", provider: .openAICompatible, baseURL: "https://a.example/v1",
                                                     now: t0, defaults: defaults))
        XCTAssertNil(SuggestedModels.rememberedPrice(of: "vendor/x", provider: .openRouter, baseURL: "https://b.example/v1",
                                                     now: t0, defaults: defaults))
        XCTAssertNil(SuggestedModels.rememberedPrice(of: "vendor/x", provider: .openRouter, baseURL: "https://a.example/v1",
                                                     now: t0.addingTimeInterval(8 * 86_400), defaults: defaults))
    }
}
