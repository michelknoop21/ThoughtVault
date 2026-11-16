import XCTest
@testable import ThoughtVault

/// Answers every request with `body` and keeps the JSON body of each request.
private final class UsageStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var sent: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while case let read = stream.read(&buffer, maxLength: buffer.count), read > 0 { data.append(buffer, count: read) }
            stream.close()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { Self.sent.append(json) }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Collects log lines from concurrent callers.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    var values: [String] { lock.withLock { _values } }
    func append(_ value: String) { lock.withLock { _values.append(value) } }
}

private let stubSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageStub.self]
    return URLSession(configuration: configuration)
}()

final class UsageMeterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UsageStub.body = ""
        UsageStub.sent = []
    }

    /// Runs `body` with a fresh meter and a log sink; returns the totals and the log lines.
    private func metered(_ body: @escaping @Sendable () async throws -> Void) async -> (UsageMeter.Totals, [String]) {
        let meter = UsageMeter(), lines = Lines()
        await ModelRequestLog.$sink.withValue({ lines.append($0) }) {
            await UsageMeter.$current.withValue(meter) { try? await body() }
        }
        return (meter.totals, lines.values)
    }

    private func openAICompatible(_ baseURL: String) -> OpenAICompatibleLLMService {
        let service = OpenAICompatibleLLMService(baseURL: baseURL, model: "mistralai/mistral-large-4-0", apiKey: "k", session: stubSession)
        service.rateLimitSleep = { _ in }
        return service
    }

    // MARK: Providers

    private static func openRouterStream(usage: String) -> String {
        """
        : OPENROUTER PROCESSING

        data: {"choices":[{"index":0,"delta":{"content":"klaar"}}]}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":\(usage)}

        data: [DONE]

        """
    }

    func testOpenRouterFinalChunkWithCost() async {
        UsageStub.body = Self.openRouterStream(usage: #"{"prompt_tokens":1200,"completion_tokens":300,"total_tokens":1500,"completion_tokens_details":{"reasoning_tokens":40},"prompt_tokens_details":{"cached_tokens":0},"cost":0.0123}"#)
        let service = openAICompatible(OpenAICompatibleLLMService.openRouterBaseURL)
        let (totals, lines) = await metered { _ = try await service.complete(system: "s", user: "u") }
        XCTAssertEqual(totals.requests, 1)
        XCTAssertEqual(totals.requestsWithUnknownUsage, 0)
        XCTAssertEqual(totals.inputTokens, 1200)
        XCTAssertEqual(totals.outputTokens, 300)
        XCTAssertEqual(totals.reasoningTokens, 40)
        XCTAssertEqual(totals.costUSD ?? -1, 0.0123, accuracy: 1e-9)
        XCTAssertEqual(totals.model, "mistralai/mistral-large-4-0")
        XCTAssertTrue(lines.last?.contains(" in_tok=1200 out_tok=300 reason_tok=40 cost=0.012300 outcome=ok") == true, "\(lines)")
    }

    func testOpenRouterFinalChunkWithoutCostLeavesCostUnknown() async {
        UsageStub.body = Self.openRouterStream(usage: #"{"prompt_tokens":1200,"completion_tokens":300}"#)
        let service = openAICompatible(OpenAICompatibleLLMService.openRouterBaseURL)
        let (totals, lines) = await metered { _ = try await service.complete(system: "s", user: "u") }
        XCTAssertEqual(totals.inputTokens, 1200)
        XCTAssertEqual(totals.outputTokens, 300)
        XCTAssertNil(totals.costUSD)
        XCTAssertFalse(lines.last?.contains("cost=") == true, "\(lines)")
    }

    func testOpenAIFinalChunkWithEmptyChoices() async {
        UsageStub.body = """
        data: {"choices":[{"index":0,"delta":{"content":"klaar"},"finish_reason":null}],"usage":null}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":null}

        data: {"choices":[],"usage":{"prompt_tokens":50,"completion_tokens":7,"completion_tokens_details":{"reasoning_tokens":0}}}

        data: [DONE]

        """
        let service = openAICompatible(OpenAICompatibleLLMService.openAIBaseURL)
        let (totals, _) = await metered { _ = try await service.complete(system: "s", user: "u") }
        XCTAssertEqual(totals.requests, 1)
        XCTAssertEqual(totals.inputTokens, 50)
        XCTAssertEqual(totals.outputTokens, 7)
        XCTAssertNil(totals.costUSD, "OpenAI has no cost field")
    }

    func testStreamOptionsOnlyGoToOpenAI() async {
        UsageStub.body = "data: {\"choices\":[{\"delta\":{\"content\":\"klaar\"}}]}\n\ndata: [DONE]\n"
        for baseURL in [OpenAICompatibleLLMService.openAIBaseURL, OpenAICompatibleLLMService.openRouterBaseURL,
                        "http://localhost:11434", "https://ollama.com", "https://llm.example.com"] {
            let service = openAICompatible(baseURL)
            _ = await metered { _ = try await service.complete(system: "s", user: "u") }
        }
        XCTAssertEqual(UsageStub.sent.count, 5)
        XCTAssertEqual((UsageStub.sent[0]["stream_options"] as? [String: Any])?["include_usage"] as? Bool, true)
        for (index, body) in UsageStub.sent.enumerated().dropFirst() {
            XCTAssertNil(body["stream_options"], "\(body)")
            // OpenRouter (index 1) also asks for low reasoning effort.
            XCTAssertEqual(body.keys.sorted(), index == 1 ? ["max_tokens", "messages", "model", "reasoning", "stream"] : ["max_tokens", "messages", "model", "stream"])
        }
    }

    func testAnthropicStreamReadsStartAndCumulativeDelta() async {
        UsageStub.body = """
        event: message_start
        data: {"type":"message_start","message":{"id":"m","usage":{"input_tokens":2100,"output_tokens":1}}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"<p>Jan belt vrijdag.</p>"}}

        data: {"type":"message_delta","delta":{},"usage":{"output_tokens":40}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":85}}

        data: {"type":"message_stop"}

        """
        let service = AnthropicLLMService(model: "claude-test", apiKey: "k", session: stubSession)
        service.rateLimitSleep = { _ in }
        let (totals, _) = await metered {
            _ = try await service.generateNotulen(transcription: "Jan belt vrijdag.", systemPrompt: "s", notulePrompt: "p",
                                                  outputTemplate: nil, constraints: [], onProgress: { _ in })
        }
        XCTAssertEqual(totals.requests, 1)
        XCTAssertEqual(totals.inputTokens, 2100)
        XCTAssertEqual(totals.outputTokens, 85, "message_delta output is cumulative: the last one is the total")
        XCTAssertNil(totals.costUSD)
    }

    func testAnthropicPlainCompletionReadsUsage() async {
        UsageStub.body = #"{"content":[{"type":"text","text":"klaar"}],"stop_reason":"end_turn","usage":{"input_tokens":30,"output_tokens":4}}"#
        let service = AnthropicLLMService(model: "claude-test", apiKey: "k", session: stubSession)
        let (totals, _) = await metered { _ = try await service.complete(system: "s", user: "u") }
        XCTAssertEqual(totals.inputTokens, 30)
        XCTAssertEqual(totals.outputTokens, 4)
    }

    // MARK: Meter

    private static func request(_ kind: ModelStep.Kind, _ usage: TokenUsage?) async throws {
        try await ModelStep.$current.withValue(ModelStep(kind)) {
            try await ModelRequestLog.run(provider: "t", model: "m", system: "", user: "") {
                guard let usage else { throw URLError(.timedOut) }
                ModelRequestLog.report(usage)
            }
        }
    }

    func testMeterTotalsAcrossAsyncLetAndTaskGroup() async {
        let paid = TokenUsage(input: 100, output: 10, reasoning: 1, costUSD: 0.001)
        let (totals, _) = await metered {
            async let source: Void = Self.request(.sourceCheck, paid)
            try await Self.request(.draft, paid)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<8 { group.addTask { try? await Self.request(.sentenceCheck, paid) } }
            }
            try await source
        }
        XCTAssertEqual(totals.requests, 10)
        XCTAssertEqual(totals.requestsWithUnknownUsage, 0)
        XCTAssertEqual(totals.inputTokens, 1000)
        XCTAssertEqual(totals.outputTokens, 100)
        XCTAssertEqual(totals.reasoningTokens, 10)
        XCTAssertEqual(totals.costUSD ?? -1, 0.01, accuracy: 1e-9)
        XCTAssertEqual(totals.steps["sentence-check"], UsageMeter.StepTotals(requests: 8, inputTokens: 800, outputTokens: 80))
        XCTAssertEqual(totals.steps["draft"]?.requests, 1)
        XCTAssertEqual(totals.steps["source-check"]?.requests, 1)
    }

    func testOneRequestWithoutCostMakesTheCostUnknown() async {
        let (totals, _) = await metered {
            try await Self.request(.draft, TokenUsage(input: 100, output: 10, costUSD: 0.002))
            try await Self.request(.noteCheck, TokenUsage(input: 50, output: 5))
        }
        XCTAssertEqual(totals.requests, 2)
        XCTAssertEqual(totals.requestsWithUnknownUsage, 0)
        XCTAssertNil(totals.costUSD)
    }

    func testFailedRequestCountsWithUnknownUsage() async {
        let (totals, lines) = await metered {
            try await Self.request(.draft, TokenUsage(input: 100, output: 10, costUSD: 0.002))
            try await Self.request(.noteCheck, nil)
        }
        XCTAssertEqual(totals.requests, 2)
        XCTAssertEqual(totals.requestsWithUnknownUsage, 1)
        XCTAssertNil(totals.costUSD)
        XCTAssertTrue(lines.last?.hasSuffix("outcome=timed out") == true, "\(lines)")
    }

    // MARK: Ledger

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testLedgerAddsRunsPerMonth() throws {
        let suite = "UsageMeterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let known = UsageMeter.Totals(requests: 30, knownCostUSD: 0.05)
        let unknown = UsageMeter.Totals(requests: 4, knownCostUSD: 0.01, requestsWithoutCost: 1)

        UsageLedger.record(known, provider: .openRouter, notule: true, date: date("2026-11-03T12:00:00Z"), defaults: defaults)
        UsageLedger.record(known, provider: .openRouter, notule: true, date: date("2026-11-20T12:00:00Z"), defaults: defaults)
        UsageLedger.record(unknown, provider: .openRouter, notule: false, date: date("2026-11-21T12:00:00Z"), defaults: defaults)
        UsageLedger.record(UsageMeter.Totals(requests: 12), provider: .ollama, notule: true, date: date("2026-11-22T12:00:00Z"), defaults: defaults)
        UsageLedger.record(known, provider: .openRouter, notule: true, date: date("2026-12-02T12:00:00Z"), defaults: defaults)

        let months = UsageLedger.load(defaults)
        let november = try XCTUnwrap(months["2026-11"])
        XCTAssertEqual(november.notules, 3)
        XCTAssertEqual(november.requests, 76)
        XCTAssertEqual(november.costUSD, 0.10, accuracy: 1e-9)
        XCTAssertEqual(november.runsWithUnknownCost, 1, "a local run is free, not unknown")
        XCTAssertEqual(months["2026-12"], UsageLedger.Month(notules: 1, requests: 30, costUSD: 0.05, runsWithUnknownCost: 0))
        XCTAssertEqual(UsageLedger.previousMonthKey(date("2026-12-15T12:00:00Z")), "2026-11")
        XCTAssertEqual(UsageLedger.previousMonthKey(date("2027-01-15T12:00:00Z")), "2026-12")
    }

    // MARK: Footer

    private let html = "<h1>Overleg</h1><p>Jan belt vrijdag de klant.</p>"

    private func usage(_ provider: NotulenProvider, model: String, cost: Double?, skipped: String? = nil) -> NotuleUsage {
        NotuleUsage(provider: provider.rawValue, model: model, transcriptCharacters: 1000, notuleHtml: html, notuleSentences: 2,
                    totals: UsageMeter.Totals(requests: 33, knownCostUSD: cost ?? 0, requestsWithoutCost: cost == nil ? 1 : 0),
                    durationMs: 72_400, contentCheckSkipReason: skipped)
    }

    func testFooterPerProvider() {
        let length = "34 tekens \u{00B7} 6 woorden \u{00B7} 33 verzoeken \u{00B7} "
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.openRouter, model: "mistralai/mistral-large-4-0", cost: 0.0814)),
                       length + "ongeveer € 0,07 \u{00B7} 1 min 12 s \u{00B7} OpenRouter, mistral-large-4-0")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.openRouter, model: "mistralai/mistral-large-4-0", cost: 0.004)),
                       length + "minder dan € 0,01 \u{00B7} 1 min 12 s \u{00B7} OpenRouter, mistral-large-4-0")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.openAI, model: "gpt-5.6-terra", cost: nil)),
                       length + "kosten niet bekend in de app \u{00B7} 1 min 12 s \u{00B7} ChatGPT, gpt-5.6-terra")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.anthropic, model: "claude-sonnet-5-5", cost: nil)),
                       length + "kosten niet bekend in de app \u{00B7} 1 min 12 s \u{00B7} Claude, claude-sonnet-5-5")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.ollama, model: "llama3.1:8b", cost: nil)),
                       length + "gratis, op dit apparaat \u{00B7} 1 min 12 s \u{00B7} Ollama (lokaal), llama3.1:8b")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.appleIntelligence, model: "on-device", cost: nil)),
                       length + "gratis, op dit apparaat \u{00B7} 1 min 12 s \u{00B7} Apple Intelligence")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.ollamaCloud, model: "gpt-oss:120b", cost: nil)),
                       length + "via je Ollama-abonnement \u{00B7} 1 min 12 s \u{00B7} Ollama Cloud, gpt-oss:120b")
        XCTAssertEqual(UsageText.footer(html: html, usage: usage(.openRouter, model: "mistralai/mistral-large-4-0", cost: 0.0814, skipped: "Onvolledige inhoudscontrole")),
                       length + "ongeveer € 0,07 \u{00B7} 1 min 12 s \u{00B7} OpenRouter, mistral-large-4-0 \u{00B7} niet automatisch gecontroleerd")
    }

    func testFooterOfOldRecordShowsOnlyLength() {
        XCTAssertEqual(UsageText.footer(html: html, usage: nil), "34 tekens \u{00B7} 6 woorden")
        let long = "<p>" + String(repeating: "woord ", count: 1200) + "</p>"
        XCTAssertEqual(UsageText.footer(html: long, usage: nil), "7.199 tekens \u{00B7} 1.200 woorden")
    }

    func testMonthLine() {
        XCTAssertEqual(UsageText.month(UsageLedger.Month(notules: 41, requests: 1320, costUSD: 3.72, runsWithUnknownCost: 0)),
                       "41 notules \u{00B7} 1.320 verzoeken \u{00B7} ongeveer € 3,20")
        XCTAssertEqual(UsageText.month(UsageLedger.Month(notules: 1, requests: 1, costUSD: 0, runsWithUnknownCost: 0)),
                       "1 notule \u{00B7} 1 verzoek \u{00B7} geen kosten")
        XCTAssertEqual(UsageText.month(UsageLedger.Month(notules: 2, requests: 60, costUSD: 0, runsWithUnknownCost: 2)),
                       "2 notules \u{00B7} 60 verzoeken")
        XCTAssertEqual(UsageText.unknownCost(UsageLedger.Month(runsWithUnknownCost: 2)), "Van 2 verwerkingen zijn de kosten niet bekend in de app.")
        XCTAssertNil(UsageText.unknownCost(UsageLedger.Month()))
    }

    func testStoredUsageRoundTripsAndCountsAuditSentences() throws {
        let stored = usage(.openRouter, model: "mistralai/mistral-large-4-0", cost: 0.0814)
        XCTAssertEqual(NotuleUsage(json: stored.json), stored)
        XCTAssertNil(NotuleUsage(json: nil))
        XCTAssertEqual(NotuleAudit.noteSentenceCount("<h1>Overleg</h1><p>Jan belt vrijdag. De prijs is 15.000 euro! Klaar?</p>"), 4)
    }
}
