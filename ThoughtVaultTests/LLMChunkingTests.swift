import XCTest
@testable import ThoughtVault

/// Answers every request of `stubSession` with `StubProtocol.reply` and records the sent body.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: Result<String, URLError> = .success("")
    nonisolated(unsafe) static var sentBody: [String: Any] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
            stream.close()
            Self.sentBody = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        switch Self.reply {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(let body):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

private let stubSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: configuration)
}()

final class LLMChunkingTests: XCTestCase {
    private func failure(_ body: () async throws -> String) async -> LLMError? {
        do { _ = try await body(); return nil } catch { return error as? LLMError }
    }

    func testModelRequestsHaveATotalTimeLimit() {
        // The idle timeout alone never fires while SSE keep-alive lines arrive.
        XCTAssertEqual(llmSession.configuration.timeoutIntervalForResource, 900)
    }

    func testTimeoutIsReportedAsTimeLimit() async {
        StubProtocol.reply = .failure(URLError(.timedOut))
        let service = OpenAICompatibleLLMService(baseURL: "http://localhost:11434", model: "m", session: stubSession)
        let error = await failure { try await service.complete(system: "s", user: "u") }
        guard case .timedOut? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(error!.localizedDescription.hasPrefix("Tijdslimiet bereikt"))
    }

    func testStreamSendsTheOutputCapAndRejectsATruncatedAnswer() async {
        StubProtocol.reply = .success("""
        data: {"choices":[{"delta":{"content":"{\\"uncertain\\":false"},"finish_reason":null}]}

        : keep-alive

        data: {"choices":[{"delta":{},"finish_reason":"length"}]}

        data: [DONE]

        """)
        let local = OpenAICompatibleLLMService(baseURL: "http://localhost:11434", model: "m", session: stubSession)
        let error = await failure { try await local.complete(system: "s", user: "u") }
        guard case .truncated? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(StubProtocol.sentBody["max_tokens"] as? Int, llmMaxOutputTokens)

        let openAI = OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.openAIBaseURL, model: "m", apiKey: "k", session: stubSession)
        _ = await failure { try await openAI.complete(system: "s", user: "u") }
        XCTAssertEqual(StubProtocol.sentBody["max_completion_tokens"] as? Int, llmMaxOutputTokens)
        XCTAssertNil(StubProtocol.sentBody["max_tokens"])
    }

    func testAnthropicRejectsAnAnswerCutOffAtMaxTokens() async {
        StubProtocol.reply = .success(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{\"uncertain\":false"}]}"#)
        let service = AnthropicLLMService(model: "m", apiKey: "k", session: stubSession)
        let error = await failure { try await service.complete(system: "s", user: "u") }
        guard case .truncated? = error else { return XCTFail("\(String(describing: error))") }
    }

    func testOllamaCloudUsesSingleRequestForMeetingButLocalModelsStayConservative() {
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "gpt-oss:120b").maxChunkCharacters, 64_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "mistral-large-4").maxChunkCharacters, 64_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "http://localhost:11434", model: "gpt-oss:120b").maxChunkCharacters, 8_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://other.example", model: "gpt-oss:120b").maxChunkCharacters, 8_000)
        XCTAssertEqual(OpenAICompatibleLLMService(baseURL: "https://ollama.com", model: "gpt-oss:120b", maxChunkCharacters: 9000).maxChunkCharacters, 9000)
    }

    func testHostedOpenAICompatibleProviderGetsLargeLimit() {
        var config = CloudAIConfiguration(id: "x", name: "OpenRouter")
        config.baseURL = "https://openrouter.ai/api"
        config.model = "mistralai/mistral-large"
        let service = OpenAICompatibleLLMService.hosted(config, apiKey: "k")
        XCTAssertEqual(service.maxChunkCharacters, 64_000)
        XCTAssertTrue(ContextSuggestions.fits(String(repeating: "a", count: 18_358), service: service))
        XCTAssertFalse(ContextSuggestions.fits(String(repeating: "a", count: 18_358),
                                               service: OpenAICompatibleLLMService(baseURL: "https://other.example", model: "m")))
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
