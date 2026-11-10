import CryptoKit
import Foundation
@testable import ThoughtVault

/// Inputs of gate M3, extracted from the Windows Kimi K2.6 evidence in
/// docs/qa/colleague-rollout-2026-11-09/content (see the fixture's `description`).
struct M3Fixture: Decodable, Sendable {
    /// One Windows request: message hashes plus the model text it received.
    struct Exchange: Decodable, Sendable { let systemSha256, userSha256, response: String }
    /// The targeted finding a rejection must contain, ported from modelcontrole-live-gate.ts.
    struct Target: Decodable, Sendable { let side, contains: String; let statuses: [String] }
    struct AuditCase: Decodable, Sendable {
        let name: String
        let expectAccept: Bool
        let source, html: String
        let target: Target?
        let windows: [Exchange]
    }
    struct Meeting: Decodable, Sendable { let name, source: String; let windows: [Exchange] }
    struct Prompts: Decodable, Sendable { let systemPrompt, notulePrompt: String }

    let baseURL, model: String
    let profile: Prompts
    let auditCases: [AuditCase]
    let meetings: [Meeting]

    /// Two audit requests per case and three per meeting at most; the gate never retries.
    var requestCap: Int { auditCases.count * 2 + meetings.count * 3 }

    static func load() throws -> M3Fixture {
        guard let url = Bundle(for: M3GateRecorder.self).url(forResource: "M3LiveContentGate", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(M3Fixture.self, from: Data(contentsOf: url))
    }
}

struct M3CaseResult: Encodable, Sendable {
    let kind: String
    let name: String
    let expected: String
    /// accepted, rejected (audit), review (meeting draft kept), generation_failed or transport_error.
    var actual = ""
    var reason = ""
    var model: String?
    var calls = 0
    var targetFinding: Bool?
    /// Per request: system and user message byte-identical to the Windows run.
    var promptsMatchWindows: [Bool] = []
    var html: String?
    var pass = false
    var finishedAt = ""
}

/// Runs the six audit cases and three meetings through the production macOS code.
/// Requests go through URLSession.shared, so `M3GateRecorder` must be started first.
struct M3Gate {
    let fixture: M3Fixture
    let apiKey: String
    let evidence: URL

    static func evidenceDirectory() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return FileManager.default.temporaryDirectory.appending(path: "M3-\(formatter.string(from: Date()))", directoryHint: .isDirectory)
    }

    func run() async throws -> [M3CaseResult] {
        let startedAt = Date().ISO8601Format()
        var results: [M3CaseResult] = []
        for testCase in fixture.auditCases { results.append(try await audit(testCase)) }
        for entry in fixture.meetings { results.append(try await meeting(entry)) }
        let summary = Summary(startedAt: startedAt, finishedAt: Date().ISO8601Format(), baseURL: fixture.baseURL,
                              requestedModel: fixture.model, requestCount: M3GateRecorder.requestCount,
                              requestCap: fixture.requestCap, pass: results.allSatisfy(\.pass), results: results)
        try write(try Self.encoder.encode(summary), to: "summary.json")
        return results
    }

    private var service: OpenAICompatibleLLMService {
        OpenAICompatibleLLMService(baseURL: fixture.baseURL, model: fixture.model, apiKey: apiKey)
    }

    /// Fixed source and notule through `auditSource` then `auditNotule`, one attempt each.
    func audit(_ testCase: M3Fixture.AuditCase) async throws -> M3CaseResult {
        M3GateRecorder.begin(testCase.name)
        let service = self.service
        let request: AuditRequest = { try await service.complete(system: $0, user: $1) }
        var result = M3CaseResult(kind: "audit", name: testCase.name, expected: testCase.expectAccept ? "accepted" : "rejected")
        var sourceAccepted = false
        var accepted = false
        do {
            // The source check only warns; auditNotule is the gate for every case.
            _ = try await NotuleAudit.auditSource(source: testCase.source, quickNote: "", request: request)
            sourceAccepted = true
            try await NotuleAudit.auditNotule(source: testCase.source, html: testCase.html, quickNote: "", request: request,
                                              requiredSentences: NotuleAudit.constraintSentences(testCase.source))
            accepted = true
        } catch {
            result.reason = error.localizedDescription
        }
        let exchanges = try record(&result, windows: testCase.windows)
        let transportOK = exchanges.allSatisfy(\.transportOK)
        result.actual = !transportOK ? "transport_error" : accepted ? "accepted" : "rejected"
        if !testCase.expectAccept { result.targetFinding = Self.targetFinding(testCase.target, exchanges) }
        // A transport failure is never a semantic rejection.
        result.pass = transportOK && result.calls == (sourceAccepted ? 2 : 1)
            && (testCase.expectAccept ? accepted : !accepted && result.targetFinding == true)
        return result
    }

    /// One generation plus both audits through NotuleGenerator; content is judged by a person.
    func meeting(_ meeting: M3Fixture.Meeting) async throws -> M3CaseResult {
        M3GateRecorder.begin(meeting.name)
        let profile = Profile(id: "standaard", name: "Standaard", systemPrompt: fixture.profile.systemPrompt,
                              notulePrompt: fixture.profile.notulePrompt, template: nil)
        // No context block: the user's own vocabulary and people must not reach the provider or the evidence.
        let generator = NotuleGenerator(service: service)
        var result = M3CaseResult(kind: "meeting", name: meeting.name, expected: "completed")
        do {
            result.html = try await generator.generate(transcription: meeting.source, profile: profile, participants: [],
                                                       quickNote: nil, createdAt: Date(), corrections: [])
            // DEC-063: problems are no longer thrown but shown in the warning section.
            result.actual = result.html?.contains("<h2>\(NotuleAudit.warningHeading)</h2>") == true ? "review" : "accepted"
        } catch {
            result.actual = "generation_failed"
            result.reason = error.localizedDescription
        }
        let transportOK = try record(&result, windows: meeting.windows).allSatisfy(\.transportOK)
        if !transportOK { result.actual = "transport_error" }
        result.pass = transportOK && result.calls <= 3
        return result
    }

    // MARK: Verdict

    /// Windows `target_semantic_finding`: the rejection must name the planted defect in a well-formed report.
    static func targetFinding(_ target: M3Fixture.Target?, _ exchanges: [M3GateRecorder.Exchange]) -> Bool {
        guard let target, let sourceReport = exchanges.first.flatMap(auditReport), isBool(sourceReport["uncertain"]) else { return false }
        guard exchanges.count == 2, let report = auditReport(exchanges[1]), let payload = auditPayload(exchanges[1]), isBool(report["uncertain"]),
              (report["source"] as? [Any])?.count == (payload["source"] as? [Any])?.count,
              (report["notes"] as? [Any])?.count == (payload["notes"] as? [Any])?.count
        else { return false }
        // An unclear source: the source check flags it and the notule audit rejects it as uncertain
        // (the same fallback as modelcontrole-live-gate.ts).
        if target.side == "sourceCheck" {
            return sourceReport["uncertain"] as? Bool == true && (report["uncertain"] as? Bool == true
                || (report["source"] as? [[String: Any]] ?? []).contains { $0["status"] as? String == "uncertain" })
        }
        guard let units = payload[target.side] as? [[String: Any]], let verdicts = report[target.side] as? [[String: Any]],
              let id = units.first(where: { ($0["text"] as? String)?.contains(target.contains) == true })?["id"] as? String
        else { return false }
        return verdicts.contains { $0["id"] as? String == id && target.statuses.contains($0["status"] as? String ?? "") }
    }

    private static func auditReport(_ exchange: M3GateRecorder.Exchange) -> [String: Any]? {
        (try? NotuleAudit.parseAuditResponse(M3GateRecorder.modelText(exchange.response).text)) as? [String: Any]
    }

    /// The unit JSON the audit sent, after the first line of the user message.
    private static func auditPayload(_ exchange: M3GateRecorder.Exchange) -> [String: Any]? {
        guard let user = messages(exchange)?.user, let newline = user.firstIndex(of: "\n") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(user[user.index(after: newline)...].utf8))) as? [String: Any]
    }

    private static func messages(_ exchange: M3GateRecorder.Exchange) -> (system: String, user: String)? {
        guard let body = try? JSONSerialization.jsonObject(with: exchange.body) as? [String: Any],
              let messages = body["messages"] as? [[String: Any]], messages.count == 2,
              let system = messages[0]["content"] as? String, let user = messages[1]["content"] as? String else { return nil }
        return (system, user)
    }

    /// `JSON.parse` boolean, not an NSNumber 0/1.
    private static func isBool(_ value: Any?) -> Bool {
        guard let value else { return false }
        return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Evidence

    private struct Summary: Encodable {
        let startedAt, finishedAt, baseURL, requestedModel: String
        let requestCount, requestCap: Int
        let pass: Bool
        let results: [M3CaseResult]
    }

    private struct RequestEvidence: Encodable {
        let url: String
        let method = "POST"
        let headers: [String: String]
        let body: String
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Writes this case's requests and raw responses and fills calls, model and prompt parity.
    private func record(_ result: inout M3CaseResult, windows: [M3Fixture.Exchange]) throws -> [M3GateRecorder.Exchange] {
        let exchanges = M3GateRecorder.exchanges(for: result.name)
        for (offset, exchange) in exchanges.enumerated() {
            let request = RequestEvidence(url: exchange.url, headers: exchange.headers,
                                          body: String(decoding: exchange.body, as: UTF8.self))
            try write(try Self.encoder.encode(request), to: "\(exchange.label).request.json")
            try write(exchange.error.map { Data("TRANSPORT ERROR: \($0)\n".utf8) } ?? exchange.response,
                      to: "\(exchange.label).response.txt")
            let sent = Self.messages(exchange)
            result.promptsMatchWindows.append(offset < windows.count && sent.map {
                Self.sha256($0.system) == windows[offset].systemSha256 && Self.sha256($0.user) == windows[offset].userSha256
            } == true)
            result.model = result.model ?? M3GateRecorder.modelText(exchange.response).model
            if let status = exchange.status, status != 200 { result.reason += " [HTTP \(status) on \(exchange.label)]" }
            if let error = exchange.error { result.reason += " [transport error on \(exchange.label): \(error)]" }
        }
        result.calls = exchanges.count
        result.finishedAt = Date().ISO8601Format()
        return exchanges
    }

    /// Refuses to write anything that contains the key.
    private func write(_ data: Data, to name: String) throws {
        guard apiKey.isEmpty || !String(decoding: data, as: UTF8.self).contains(apiKey) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "M3 evidence \(name) would contain the API key"])
        }
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try data.write(to: evidence.appending(path: name))
    }
}
