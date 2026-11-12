import XCTest
@testable import ThoughtVault

/// Answers every request with the next queued reply, or a short SSE answer when the queue is empty.
private final class ModelStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var queued: [(status: Int, headers: [String: String])] = []
    nonisolated(unsafe) static var failure: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        if let failure = Self.failure { return client!.urlProtocol(self, didFailWithError: failure) }
        let next = Self.queued.isEmpty ? (status: 200, headers: [:]) : Self.queued.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil,
                                                              headerFields: next.headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("data: {\"choices\":[{\"delta\":{\"content\":\"klaar\"}}]}\n\ndata: [DONE]\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Collects values from concurrent callers.
private final class Collected<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Value] = []
    var values: [Value] { lock.withLock { _values } }
    func append(_ value: Value) { lock.withLock { _values.append(value) } }
}

private let stubSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ModelStub.self]
    return URLSession(configuration: configuration)
}()

final class ModelRequestLogTests: XCTestCase {
    private let system = "Geheime systeeminstructie"
    private let user = "Transcriptie: Jan de Vries belt vrijdag de klant over het contract van 40.000 euro."

    override func setUp() {
        super.setUp()
        ModelStub.queued = []
        ModelStub.failure = nil
    }

    /// Runs `body` in `step` and returns the log lines it wrote.
    private func lines(step: ModelStep, _ body: @escaping @Sendable () async throws -> Void) async -> [String] {
        let lines = Collected<String>()
        await ModelRequestLog.$sink.withValue({ lines.append($0) }) {
            await ModelStep.$current.withValue(step) { try? await body() }
        }
        return lines.values
    }

    private func service() -> OpenAICompatibleLLMService {
        let service = OpenAICompatibleLLMService(baseURL: "http://localhost:11434", model: "test-model:7b", session: stubSession)
        service.rateLimitSleep = { _ in }
        return service
    }

    func testRequestLogsMetadataAndNoText() async {
        let service = service(), system = system, user = user
        let logged = await lines(step: ModelStep(.sentenceCheck, 12, of: 61)) {
            _ = try await service.complete(system: system, user: user)
        }
        XCTAssertEqual(logged.count, 2, "\(logged)")
        let head = "step=sentence-check 12/61 provider=local model=test-model:7b input_chars=\(system.utf16.count + user.utf16.count)"
        XCTAssertEqual(logged.first, "model request start \(head)")
        XCTAssertTrue(logged.last?.hasPrefix("model request end \(head) ms=") == true, "\(logged)")
        XCTAssertTrue(logged.last?.hasSuffix(" outcome=ok") == true, "\(logged)")
        // Only metadata leaves the device in a support report (DEC-064).
        for line in logged {
            for word in ["Geheime", "systeeminstructie", "Transcriptie", "Jan", "Vries", "klant", "40.000", "klaar", "11434"] {
                XCTAssertFalse(line.contains(word), "\"\(word)\" leaked: \(line)")
            }
        }
    }

    func testFailedRequestsNameTheirOutcome() async {
        let service = service(), system = system, user = user
        ModelStub.queued = [(503, [:])]
        let server = await lines(step: ModelStep(.draft)) { _ = try await service.complete(system: system, user: user) }
        XCTAssertTrue(server.last?.hasSuffix(" outcome=HTTP 503") == true, "\(server)")
        XCTAssertTrue(server.last?.contains("step=draft ") == true, "\(server)")

        ModelStub.failure = URLError(.timedOut)
        let timeout = await lines(step: ModelStep(.sourceCheck)) { _ = try await service.complete(system: system, user: user) }
        XCTAssertTrue(timeout.last?.hasSuffix(" outcome=timed out") == true, "\(timeout)")
    }

    func testRateLimitRetryIsLogged() async {
        let service = service(), system = system, user = user
        ModelStub.queued = [(429, ["Retry-After": "0"])]
        let logged = await lines(step: ModelStep(.coverage, 2, of: 3)) { _ = try await service.complete(system: system, user: user) }
        XCTAssertEqual(logged.count, 3, "\(logged)")
        XCTAssertTrue(logged[1].hasPrefix("model request retry step=coverage 2/3 after HTTP 429 wait_ms="), "\(logged)")
        XCTAssertTrue(logged[2].hasSuffix(" outcome=ok"), "\(logged)")
    }

    func testLongAuditCountsFinishedChecksAndNamesEachRequest() async throws {
        // Ten notule sentences preserve T391 to T400 of 401 source sentences: two coverage parts, ten checks.
        let source = (1...401).map { "Punt \($0) is besproken." }.joined(separator: " ")
        let html = "<p>" + (391...400).map { "Punt \($0) is besproken." }.joined(separator: " ") + "</p>"
        let steps = Collected<String>()
        let request: AuditRequest = { _, user in
            steps.append(ModelStep.current?.logLabel ?? "none")
            // Random delays make checks finish out of order.
            try await Task.sleep(nanoseconds: .random(in: 0...30_000_000))
            let body = user[user.index(after: user.firstIndex(of: "\n")!)...]
            let input = try JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: Any]
            let ids = { (key: String) in (input[key] as? [[String: String]] ?? []).map { $0["id"]! } }
            let reply: [String: Any]
            if user.hasPrefix("Inhoudsaudit deel") {
                reply = ["uncertain": false, "source": ids("source").map { id -> [String: Any] in
                    let number = Int(id.dropFirst()) ?? 0
                    return (391...400).contains(number) && id.hasPrefix("T")
                        ? ["id": id, "status": "covered", "evidence": ["N\(number - 390)"]]
                        : ["id": id, "status": "non_factual", "evidence": [String]()]
                }]
            } else {
                reply = ["uncertain": false, "notes": [["id": ids("notes")[0], "status": "supported", "evidence": ids("evidence")]]]
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self)
        }
        let progress = Collected<ModelStep>()
        try await NotuleAudit.auditNotule(source: source, html: html, quickNote: "", request: request,
                                          noteConcurrency: NotuleAudit.hostedAuditConcurrency, onProgress: { progress.append($0) })
        let coverage = progress.values.filter { $0.kind == .coverage }.map { "\($0.index!)/\($0.total!)" }
        XCTAssertEqual(coverage, ["0/2", "1/2", "2/2"])
        let checks = progress.values.filter { $0.kind == .sentenceCheck }.map { "\($0.index!)/\($0.total!)" }
        XCTAssertEqual(checks, (0...10).map { "\($0)/10" }, "the counter only rises and ends at the total")
        // The log names each request by its position, whatever order they finish in.
        XCTAssertEqual(Set(steps.values), Set(["coverage 1/2", "coverage 2/2"] + (1...10).map { "sentence-check \($0)/10" }))
        XCTAssertEqual(steps.values.count, 12)
        XCTAssertTrue(ModelStep(.sentenceCheck, 12, of: 61).displayLabel.contains("12"))
        XCTAssertTrue(ModelStep(.sentenceCheck, 12, of: 61).displayLabel.contains("61"))
    }
}
