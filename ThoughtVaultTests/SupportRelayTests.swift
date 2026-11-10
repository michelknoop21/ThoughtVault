import Foundation
import os
import Security
import XCTest
@testable import ThoughtVault

final class SupportRelayTests: XCTestCase, @unchecked Sendable {
    private var defaults: UserDefaults!
    private var suite: String!
    private var keychain: KeychainService!
    private var directory: URL!
    private var session: URLSession!
    private var relay: SupportRelay!
    private let result = #"{"ticketId":"c1","ref":"TV-000001","repeated":false,"count":1,"logAttached":false}"#

    override func setUpWithError() throws {
        suite = "SupportRelayTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("Anna", forKey: SupportIdentity.nameKey)
        defaults.set("anna@example.com", forKey: SupportIdentity.emailKey)
        keychain = KeychainService(serviceIdentifier: "com.buildmind.ThoughtVault.tests.\(suite!)")
        directory = FileManager.default.temporaryDirectory.appending(path: "SupportRelayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SupportStub.self]
        session = URLSession(configuration: configuration)
        SupportStub.reset()
        relay = makeRelay()
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        keychain.delete(for: SupportIdentity.secretKey)
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) {
            let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for child in children { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: child.path) }
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func makeRelay(logTail: @escaping @Sendable (Int) async -> String = { _ in "LOG-AT-SEND" }) -> SupportRelay {
        SupportRelay(baseURL: URL(string: "https://example.com/support")!, session: session, defaults: defaults,
                     keychain: keychain, outbox: directory, logTail: logTail)
    }

    private func reply(status: Int = 201, body: String? = nil, headers: [String: String] = [:]) {
        let result = body ?? result
        SupportStub.handler { request, _ in
            .init(status: request.url?.lastPathComponent == "installations" ? 201 : status,
                  text: request.url?.lastPathComponent == "installations" ? "{}" : result, headers: headers)
        }
    }

    func testRegistersOnceAndSignsReports() async throws {
        reply()
        try await relay.enqueue(fixture()); await relay.flush()
        try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertEqual(SupportStub.paths, ["/support/installations", "/support/reports", "/support/reports"])
        let registration = SupportStub.json(0)
        let id = try XCTUnwrap(registration["installationId"] as? String)
        let secret = try XCTUnwrap(registration["secret"] as? String)
        XCTAssertEqual(id.count, 36); XCTAssertEqual(id, id.lowercased())
        XCTAssertEqual(secret.count, 43); XCTAssertFalse(secret.contains("="))
        XCTAssertEqual(SupportStub.requests[1].value(forHTTPHeaderField: "X-TV-Installation"), id)
        XCTAssertEqual(SupportStub.requests[1].value(forHTTPHeaderField: "X-TV-Secret"), secret)
        XCTAssertNil(defaults.string(forKey: SupportIdentity.secretKey))
        XCTAssertEqual(keychain.load(for: SupportIdentity.secretKey), secret)
        let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
    }

    func testLogAndIdentityAreReadAtSendAndNeverStored() async throws {
        reply()
        var report = fixture(); report.log = "PRIVATE-LOG"; report.name = "Old"; report.email = "old@example.com"
        try await relay.enqueue(report)
        let pending = await relay.pendingReports()
        XCTAssertNil(pending.first?.log); XCTAssertEqual(pending.first?.name, ""); XCTAssertEqual(pending.first?.email, "")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(try String(contentsOf: files[0], encoding: .utf8).contains("PRIVATE-LOG"))
        await relay.flush()
        XCTAssertEqual(SupportStub.json(1)["log"] as? String, "LOG-AT-SEND")
        XCTAssertEqual(SupportStub.json(1)["name"] as? String, "Anna")
        XCTAssertEqual(SupportStub.json(1)["email"] as? String, "anna@example.com")
    }

    func testOfflineSurvivesRelayRestartAndLaterSends() async throws {
        SupportStub.handler { _, _ in throw URLError(.notConnectedToInternet) }
        try await relay.enqueue(fixture()); await relay.flush()
        let pending = await relay.pendingReports(); XCTAssertEqual(pending.count, 1)
        relay = makeRelay(); reply(); await relay.flush()
        let after = await relay.pendingReports(); XCTAssertTrue(after.isEmpty)
    }

    func testRateLimitHonorsRetryAfterAcrossFlushAndRoutes() async throws {
        reply(status: 429, body: "{}", headers: ["Retry-After": "3600"])
        try await relay.enqueue(fixture()); try await relay.enqueue(fixture()); await relay.flush()
        await relay.flush()
        do { _ = try await relay.tickets(); XCTFail("Expected cooldown") }
        catch { XCTAssertEqual(error as? SupportRelayError, .http(429)) }
        XCTAssertEqual(SupportStub.paths.filter { $0 == "/support/reports" }.count, 1)
        let pending = await relay.pendingReports(); XCTAssertEqual(pending.count, 2)
    }

    func testTooLargeRetriesWithSmallLogThenDrops() async throws {
        relay = makeRelay(logTail: { String(repeating: "a", count: $0) })
        reply(status: 413, body: "{}")
        try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertEqual(SupportStub.paths.filter { $0 == "/support/reports" }.count, 2)
        XCTAssertEqual((SupportStub.json(1)["log"] as? String)?.utf8.count, 1_048_576)
        XCTAssertEqual((SupportStub.json(2)["log"] as? String)?.utf8.count, 262_144)
        let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
    }

    func testBadRequestDropsButServerErrorRetains() async throws {
        reply(status: 400, body: "{}")
        try await relay.enqueue(fixture()); await relay.flush()
        let dropped = await relay.pendingReports(); XCTAssertTrue(dropped.isEmpty)
        reply(status: 503, body: "{}")
        try await relay.enqueue(fixture()); await relay.flush()
        let retained = await relay.pendingReports(); XCTAssertEqual(retained.count, 1)
    }

    func testHeldUntilIdentityComplete() async throws {
        defaults.removeObject(forKey: SupportIdentity.emailKey)
        try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertTrue(SupportStub.paths.isEmpty)
        defaults.set("anna@example.com", forKey: SupportIdentity.emailKey)
        reply(); await relay.flush()
        let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
    }

    func testOutboxKeepsNewestFifty() async throws {
        for i in 0..<55 { try await relay.enqueue(fixture(shown: "fout \(i)")) }
        let pending = await relay.pendingReports()
        XCTAssertEqual(pending.count, 50); XCTAssertEqual(pending.first?.shownMessage, "fout 5")
        XCTAssertEqual(pending.last?.shownMessage, "fout 54")
    }

    func testUnauthorizedUsesSamePairAndConflictReplacesIt() async throws {
        let result = result
        SupportStub.handler { _, index in
            .init(status: [201, 401, 409, 201, 201][index], text: index == 4 ? result : "{}")
        }
        try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertEqual(SupportStub.paths, ["/support/installations", "/support/reports", "/support/installations",
                                           "/support/installations", "/support/reports"])
        XCTAssertEqual(SupportStub.json(0)["installationId"] as? String, SupportStub.json(2)["installationId"] as? String)
        XCTAssertEqual(SupportStub.json(0)["secret"] as? String, SupportStub.json(2)["secret"] as? String)
        XCTAssertNotEqual(SupportStub.json(2)["installationId"] as? String, SupportStub.json(3)["installationId"] as? String)
        XCTAssertNotEqual(SupportStub.json(2)["secret"] as? String, SupportStub.json(3)["secret"] as? String)
        XCTAssertEqual(SupportStub.requests[4].value(forHTTPHeaderField: "X-TV-Installation"), SupportStub.json(3)["installationId"] as? String)
    }

    func testConcurrentFlushSendsOnce() async throws {
        reply(); SupportStub.delay = 0.03
        try await relay.enqueue(fixture())
        async let first: Void = relay.flush(); async let second: Void = relay.flush()
        _ = await (first, second)
        XCTAssertEqual(SupportStub.paths.filter { $0 == "/support/reports" }.count, 1)
    }

    func testMissingLogAttachmentStillCountsAsSent() async throws {
        reply()
        let outcome = await relay.send(fixture())
        guard case .sent(let result) = outcome else { return XCTFail("Expected sent") }
        XCTAssertEqual(result?.logAttached, false)
        let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
    }

    func testSendPermanentRejectionsFailInsteadOfQueueing() async throws {
        for status in [400, 413] {
            reply(status: status, body: "{}")
            let outcome = await relay.send(fixture())
            XCTAssertEqual(outcome, .failed)
            let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
        }
    }

    func testSendStorageFailureFailsInsteadOfQueueing() async throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Not a directory".utf8).write(to: directory)
        let outcome = await relay.send(fixture())
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(SupportStub.requests.isEmpty)
    }

    func testRetentionCleanupFailureStillReturnsDurablyQueued() async throws {
        for _ in 0..<50 { try await relay.enqueue(fixture()) }
        let oldest = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.first)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: oldest.path)
        SupportStub.handler { _, _ in throw URLError(.notConnectedToInternet) }
        let outcome = await relay.send(fixture(shown: "Newest"))
        XCTAssertEqual(outcome, .queued)
        let pending = await makeRelay().pendingReports()
        XCTAssertEqual(pending.last?.shownMessage, "Newest")
    }

    func testSendMalformedAcceptanceIsSentWithoutReceipt() async throws {
        reply(body: "{}")
        let outcome = await relay.send(fixture())
        XCTAssertEqual(outcome, .sent(nil))
        await relay.flush()
        XCTAssertEqual(SupportStub.paths.filter { $0 == "/support/reports" }.count, 1)
        let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
    }

    func testSendOfflineIsDurablyQueued() async throws {
        SupportStub.handler { _, _ in throw URLError(.notConnectedToInternet) }
        let outcome = await relay.send(fixture())
        XCTAssertEqual(outcome, .queued)
        let pending = await makeRelay().pendingReports(); XCTAssertEqual(pending.count, 1)
    }

    func testAcceptedReportWithUnlinkFailureIsNotPostedTwice() async throws {
        let directory = try XCTUnwrap(directory)
        let result = result
        SupportStub.handler { request, _ in
            if request.url?.lastPathComponent == "installations" { return .init(status: 201, text: "{}") }
            let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
            return .init(status: 201, text: result)
        }
        let outcome = await relay.send(fixture())
        guard case .sent = outcome else { return XCTFail("Accepted report must be sent despite cleanup failure") }
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let pending = await relay.pendingReports(); XCTAssertTrue(pending.isEmpty)
        await relay.flush()
        XCTAssertEqual(SupportStub.paths.filter { $0 == "/support/reports" }.count, 1)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
        await relay.flush()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    func testFailedKeychainWriteRetainsQueueAndDoesNotRegister() async throws {
        let failing = KeychainService(serviceIdentifier: "com.buildmind.ThoughtVault.tests.\(suite!)-failure",
                                      add: { _ in errSecInteractionNotAllowed }, update: { _, _ in errSecInteractionNotAllowed })
        relay = SupportRelay(baseURL: URL(string: "https://example.com/support")!, session: session, defaults: defaults,
                             keychain: failing, outbox: directory, logTail: { _ in "" })
        try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertTrue(SupportStub.requests.isEmpty)
        let pending = await relay.pendingReports(); XCTAssertEqual(pending.count, 1)
    }

    func testTicketsAllowMissingUpdatedAtAndBothDateFormats() async throws {
        reply(status: 200, body: #"{"data":[{"id":"c1","ref":"TV-000001","status":"OPEN","category":"BUG","description":"x","unread":true,"createdAt":"2026-08-02T09:00:00Z","lastMessage":{"senderRole":"ADMIN","createdAt":"2026-08-02T10:00:00.000Z","excerpt":"Welke site?"}}]}"#)
        let tickets = try await relay.tickets()
        XCTAssertEqual(tickets.count, 1); XCTAssertNil(tickets.first?.updatedAt)
        XCTAssertEqual(tickets.first?.lastMessage?.excerpt, "Welke site?")
        XCTAssertEqual(tickets.first?.lastMessage?.createdAt.timeIntervalSince(tickets[0].createdAt), 3600)
    }

    func testThreadAndUnreadRoutes() async throws {
        SupportStub.handler { request, _ in
            if request.url?.lastPathComponent == "installations" { return .init(status: 201, text: "{}") }
            if request.url?.lastPathComponent == "unread-count" { return .init(status: 200, text: #"{"data":{"count":3}}"#) }
            if request.url?.path.contains("c2") == true { return .init(status: 404, text: "{}") }
            return .init(status: 200, text: #"{"data":[{"id":"m1","body":"Hoi","senderRole":"ADMIN","createdAt":"2026-08-02T10:00:00.000Z"}]}"#)
        }
        let messages = try await relay.messages(ticketId: "c1"); XCTAssertEqual(messages.first?.body, "Hoi")
        let count = try await relay.unreadCount(); XCTAssertEqual(count, 3)
        try await relay.sendMessage(ticketId: "c1", body: "Dank")
        XCTAssertEqual(SupportStub.requests.last?.httpMethod, "POST")
        XCTAssertEqual(SupportStub.json(SupportStub.requests.count - 1)["body"] as? String, "Dank")
        do { _ = try await relay.messages(ticketId: "c2"); XCTFail("Expected 404") }
        catch { XCTAssertEqual(error as? SupportRelayError, .http(404)) }
        let before = SupportStub.requests.count
        do { _ = try await relay.messages(ticketId: "../c1"); XCTFail("Expected invalid id") }
        catch { XCTAssertEqual(error as? SupportRelayError, .http(422)) }
        XCTAssertEqual(SupportStub.requests.count, before)
    }

    func testReportScrubsBeforeCappingAndPreservesManualText() {
        let email = String(repeating: "a", count: 90) + "@example.com"
        let report = SupportReport.make(kind: "auto", category: .bug, stage: "notule", shown: String(repeating: "x", count: 4_990) + " " + email,
                                        error: String(repeating: "x", count: 1_990) + " " + email, fingerprint: "0123456789abcdef",
                                        clickPath: Array(repeating: email, count: 35))
        XCTAssertFalse(report.shownMessage.contains(" a")); XCTAssertFalse(report.errorText.contains(" a"))
        XCTAssertEqual(report.clickPath.count, 30); XCTAssertTrue(report.clickPath.allSatisfy { $0.hasPrefix("k-") })
        XCTAssertLessThanOrEqual(report.shownMessage.count, 5_000)
        XCTAssertLessThanOrEqual(report.errorText.count, 2_000)
        XCTAssertEqual(fixture(shown: "anna@example.com").shownMessage, "anna@example.com")
    }

    func testIdentityValidation() {
        XCTAssertTrue(SupportIdentity.isComplete(name: " Anna ", email: " anna@example.com "))
        for email in ["a@@example.com", "a@.com", "a@example.", "@example.com", "a b@example.com", "a@example"] {
            XCTAssertFalse(SupportIdentity.isValidEmail(email), email)
        }
        XCTAssertFalse(SupportIdentity.isComplete(name: "\n ", email: "a@example.com"))
    }

    private func fixture(shown: String = "Fout") -> SupportReport {
        .make(kind: "manual", category: .bug, stage: "", shown: shown, error: "", fingerprint: nil, clickPath: [])
    }
}

final class SupportStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable { var status: Int; var text: String; var headers: [String: String] = [:] }
    typealias Handler = @Sendable (URLRequest, Int) throws -> Reply
    private struct State {
        var handler: Handler = { _, _ in throw URLError(.unsupportedURL) }
        var requests: [URLRequest] = []
        var bodies: [Data] = []
        var delay: TimeInterval = 0
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    static func reset() { state.withLock { $0 = State() } }
    static func handler(_ handler: @escaping Handler) { state.withLock { $0.handler = handler } }
    static var requests: [URLRequest] { state.withLock { $0.requests } }
    static var paths: [String] { requests.map { $0.url!.path } }
    static var delay: TimeInterval {
        get { state.withLock { $0.delay } }
        set { state.withLock { $0.delay = newValue } }
    }
    static func json(_ index: Int) -> [String: Any] {
        let data = state.withLock { $0.bodies[index] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // Intercept every request in this session: unexpected hosts must fail offline too.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.body(request)
        let (handler, index, delay) = Self.state.withLock {
            let index = $0.requests.count
            $0.requests.append(request); $0.bodies.append(body)
            return ($0.handler, index, $0.delay)
        }
        do {
            guard request.url?.host == "example.com" else { throw URLError(.unsupportedURL) }
            let reply = try handler(request, index)
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    private static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}
