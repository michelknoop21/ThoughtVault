import XCTest
import os
@testable import ThoughtVault

/// Gate M3 of the macOS GO report: the Windows content gate (6 audit cases, 3 fictional meetings)
/// against Ollama Cloud Kimi K2.6 through the production macOS services.
/// Opt-in: skipped unless the key is in the test environment. Run via scripts/run-m3-live-gate.sh.
final class M3LiveContentGateTests: XCTestCase {
    func testLiveContentGate() async throws {
        let key = ProcessInfo.processInfo.environment["TV_M3_OLLAMA_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw XCTSkip("M3 live gate is opt-in: set TEST_RUNNER_TV_M3_OLLAMA_KEY (see scripts/run-m3-live-gate.sh)")
        }
        let fixture = try M3Fixture.load()
        let evidence = M3Gate.evidenceDirectory()
        print("M3_EVIDENCE_DIR=\(evidence.path)")
        M3GateRecorder.start(cap: fixture.requestCap, transport: M3GateRecorder.live)
        defer { M3GateRecorder.stop() }

        let results = try await M3Gate(fixture: fixture, apiKey: key, evidence: evidence).run()
        for result in results {
            if result.actual == "transport_error" {
                XCTFail("\(result.name): transport error, not a content verdict.\(result.reason)")
            } else {
                XCTAssertTrue(result.pass, "\(result.name): expected \(result.expected), got \(result.actual) \(result.reason)")
            }
        }
        XCTAssertLessThanOrEqual(M3GateRecorder.requestCount, fixture.requestCap)
    }
}

/// Offline checks of the gate machinery: replaying the real Windows Kimi responses through the
/// macOS code must reproduce the Windows verdicts with byte-identical prompts.
final class M3LiveContentGateOfflineTests: XCTestCase {
    private let fakeKey = "m3-offline-fake-key"

    override func tearDown() {
        M3GateRecorder.stop()
        super.tearDown()
    }

    func testRedactionDropsCredentialHeaders() {
        let headers = ["Authorization": "Bearer x", "authorization": "y", "Proxy-Authorization": "z", "Cookie": "c",
                       "Content-Type": "application/json", "Accept": "text/event-stream"]
        XCTAssertEqual(M3GateRecorder.redacted(headers), ["Content-Type": "application/json", "Accept": "text/event-stream"])
        XCTAssertEqual(M3GateRecorder.redacted(nil), [:])
    }

    func testFixtureEncodesTheNineWindowsCases() throws {
        let fixture = try M3Fixture.load()
        XCTAssertEqual(fixture.baseURL, "https://ollama.com")
        XCTAssertEqual(fixture.model, "kimi-k2.6")
        XCTAssertEqual(fixture.auditCases.map(\.name), ["correcte_parafrase", "tweede_actie_ontbreekt", "tegenstrijdige_toestemming",
                                                        "verkeerd_budget", "voorwaarde_wordt_opdracht",
                                                        "opname10_ambigue_bron_numerieke_invulling"])
        XCTAssertEqual(fixture.auditCases.map(\.expectAccept), [true, false, false, false, false, false])
        XCTAssertTrue(fixture.auditCases.allSatisfy { $0.expectAccept == ($0.target == nil) })
        XCTAssertEqual(fixture.meetings.map(\.name), ["waddenspoor", "noorderlicht", "bibliotheek"])
        XCTAssertEqual(fixture.requestCap, 21)
    }

    func testSSEModelTextAndModelId() {
        let stream = Self.sse("{\"uncertain\":false}", model: "kimi-k2.6")
        XCTAssertEqual(M3GateRecorder.modelText(stream).text, "{\"uncertain\":false}")
        XCTAssertEqual(M3GateRecorder.modelText(stream).model, "kimi-k2.6")
    }

    func testWindowsResponsesReplayToTheSameVerdicts() async throws {
        let fixture = try M3Fixture.load()
        let queue = OSAllocatedUnfairLock(initialState: (fixture.auditCases.flatMap(\.windows) + fixture.meetings.flatMap(\.windows)).map(\.response))
        M3GateRecorder.start(cap: fixture.requestCap) { request in
            let next = queue.withLock { $0.isEmpty ? nil : $0.removeFirst() }
            guard let next else { throw URLError(.resourceUnavailable) }
            return (Self.ok(request), Self.sse(next, model: fixture.model))
        }
        let evidence = FileManager.default.temporaryDirectory.appending(path: "M3-offline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: evidence) }

        let results = try await M3Gate(fixture: fixture, apiKey: fakeKey, evidence: evidence).run()

        XCTAssertEqual(results.map(\.actual), ["accepted", "rejected", "rejected", "rejected", "rejected", "rejected",
                                               "accepted", "accepted", "accepted"])
        for result in results {
            XCTAssertTrue(result.pass, "\(result.name): \(result.actual) \(result.reason)")
            XCTAssertEqual(result.promptsMatchWindows, Array(repeating: true, count: result.calls), "\(result.name) prompt differs from Windows")
            XCTAssertEqual(result.model, "kimi-k2.6")
        }
        XCTAssertEqual(results.map(\.calls), [2, 2, 2, 2, 2, 1, 3, 3, 3])
        XCTAssertEqual(M3GateRecorder.requestCount, 20)
        XCTAssertTrue(queue.withLock { $0.isEmpty })

        // Evidence: one request and response per call plus a summary, and never the key.
        let files = try FileManager.default.contentsOfDirectory(atPath: evidence.path)
        XCTAssertEqual(files.count, 20 * 2 + 1)
        XCTAssertTrue(files.contains("summary.json"))
        XCTAssertTrue(files.contains("waddenspoor-1.request.json"))
        for file in files {
            let text = try String(contentsOf: evidence.appending(path: file), encoding: .utf8)
            XCTAssertFalse(text.contains(fakeKey), file)
            XCTAssertFalse(text.contains("Bearer"), file)
        }
    }

    /// An HTTP failure must surface as a transport error, never as the expected rejection.
    func testHTTPErrorIsATransportErrorNotARejection() async throws {
        let fixture = try M3Fixture.load()
        M3GateRecorder.start(cap: fixture.requestCap) { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!, Data("{}".utf8))
        }
        let evidence = FileManager.default.temporaryDirectory.appending(path: "M3-offline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: evidence) }

        let result = try await M3Gate(fixture: fixture, apiKey: fakeKey, evidence: evidence)
            .audit(fixture.auditCases[1])

        XCTAssertEqual(result.actual, "transport_error")
        XCTAssertFalse(result.pass)
        XCTAssertEqual(result.calls, 1)
        XCTAssertTrue(result.reason.contains("HTTP 500"), result.reason)
    }

    private static func ok(_ request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
    }

    /// The text as one OpenAI-style streamed chunk.
    private static func sse(_ text: String, model: String) -> Data {
        let chunk = ["model": model, "choices": [["index": 0, "delta": ["content": text]]]] as [String: Any]
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: chunk), as: UTF8.self)
        return Data("data: \(json)\n\ndata: [DONE]\n\n".utf8)
    }
}
