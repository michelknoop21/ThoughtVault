import XCTest
@testable import ThoughtVault

final class LLMChunkingTests: XCTestCase {
    func testHostedGPTOSSUsesSingleRequestForMeetingButLocalModelsStayConservative() {
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "gpt-oss:120b").maxChunkCharacters, 64_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "gpt-oss:120b-cloud").maxChunkCharacters, 64_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "http://localhost:11434", model: "gpt-oss:120b").maxChunkCharacters, 8_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "unknown").maxChunkCharacters, 8_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://other.example", model: "gpt-oss:120b").maxChunkCharacters, 8_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "gpt-oss:120b", maxChunkCharacters: 9000).maxChunkCharacters, 9000)
    }


    func testRateLimitFailureExplainsRetryAndKeepsOtherServerErrors() {
        XCTAssertTrue(LLMError.serverError(429).localizedDescription.contains("gebruikslimiet"))
        XCTAssertTrue(LLMError.serverError(429).localizedDescription.contains("later opnieuw"))
        XCTAssertEqual(LLMError.serverError(500).localizedDescription, "Serverfout: statuscode 500.")
    }

    func testHardSplitCapsChunksWithoutSentenceBreaks() {
        // Whisper output without ". " separators: one 50k-char blob.
        let blob = String(repeating: "a", count: 50_000)
        let result = hardSplitOversizedChunks([blob], maxChars: 6000)
        XCTAssertTrue(result.allSatisfy { $0.count <= 6000 })
        XCTAssertEqual(result.map(\.count).reduce(0, +), 50_000)
    }

    func testHardSplitLeavesSmallChunksUntouched() {
        let chunks = ["hello", "world"]
        XCTAssertEqual(hardSplitOversizedChunks(chunks, maxChars: 6000), chunks)
    }

    func testHardSplitDropsNothingOnExactBoundary() {
        let blob = String(repeating: "b", count: 12_000)
        let result = hardSplitOversizedChunks([blob], maxChars: 6000)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].count, 6000)
        XCTAssertEqual(result[1].count, 6000)
    }
}
