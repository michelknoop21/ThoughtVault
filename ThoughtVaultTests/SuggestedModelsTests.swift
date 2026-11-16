import XCTest
@testable import ThoughtVault

final class SuggestedModelsTests: XCTestCase {

    func testSuggestionsStayWithinTheCap() {
        for provider in [NotulenProvider.openAI, .anthropic] {
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
}
