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
        XCTAssertEqual(report.shownMessage, "Verwerking mislukt tijdens notule.")
        XCTAssertEqual(report.errorText, report.shownMessage)
        XCTAssertEqual(report.clickPath.count, 30); XCTAssertTrue(report.clickPath.allSatisfy { $0.hasPrefix("k-") })
        XCTAssertLessThanOrEqual(report.shownMessage.count, 5_000)
        XCTAssertLessThanOrEqual(report.errorText.count, 2_000)
        XCTAssertEqual(fixture(shown: "anna@example.com").shownMessage, "anna@example.com")
    }

    func testAutomaticNormalizationIsIdempotentAndManualTextIsUnchanged() {
        for stage in ["opnemen", "transcriberen", "notule", "crash", "PRIVATE_TITLE"] {
            var report = automaticFixture(stage: stage)
            report.normalizeAutomatic()
            let boundedStage = SupportStage(rawValue: stage)?.rawValue ?? "crash"
            XCTAssertEqual(report.stage, boundedStage)
            XCTAssertEqual(report.shownMessage, "Verwerking mislukt tijdens \(boundedStage).")
            XCTAssertEqual(report.errorText, report.shownMessage)
            XCTAssertEqual(report.fingerprint, "0123456789abcdef")
            let normalized = report
            report.normalizeAutomatic()
            XCTAssertEqual(report, normalized)
        }
        for message in ["onverwacht gestopt", "gestopt tijdens opnemen", "gestopt tijdens transcriberen",
                        "gestopt tijdens notule", "gestopt tijdens crash"] {
            let stage = message == "onverwacht gestopt" ? "crash" : String(message.dropFirst("gestopt tijdens ".count))
            var report = automaticFixture(stage: stage, error: message)
            report.normalizeAutomatic()
            XCTAssertEqual(report.shownMessage, message)
            let normalized = report
            report.normalizeAutomatic()
            XCTAssertEqual(report, normalized)
        }
        var manual = fixture(shown: "PRIVATE_USER_TEXT anna@example.com")
        let original = manual
        manual.normalizeAutomatic()
        XCTAssertEqual(manual, original)
        XCTAssertEqual(SupportReport.make(kind: "auto", category: .bug, stage: "notule",
                                          shown: "PRIVATE_TITLE", error: "PRIVATE_TRANSCRIPT",
                                          fingerprint: "0123456789abcdef", clickPath: []).shownMessage,
                       "Verwerking mislukt tijdens notule.")
    }

    func testLegacyAutomaticOutboxIsNormalizedBeforeActualPost() async throws {
        reply()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = automaticFixture(error: #"{"error":"PRIVATE_TRANSCRIPT", "quote":"PRIVATE_NOTE"}"#)
        try SupportJSON.encoder.encode(report).write(to: directory.appending(path: "1-legacy.json"))
        await relay.flush()
        let json = SupportStub.json(1)
        XCTAssertEqual(json["kind"] as? String, "auto")
        XCTAssertEqual(json["stage"] as? String, "notule")
        XCTAssertEqual(json["shownMessage"] as? String, "Verwerking mislukt tijdens notule.")
        XCTAssertEqual(json["errorText"] as? String, "Verwerking mislukt tijdens notule.")
        XCTAssertEqual(json["fingerprint"] as? String, "0123456789abcdef")
        XCTAssertFalse(String(describing: json).contains("PRIVATE_"))
    }

    func testDisabledAutomaticQueueDropsWithoutIdentityAndKeepsManual() async throws {
        defaults.removeObject(forKey: SupportIdentity.emailKey)
        try await relay.enqueue(automaticFixture())
        try await relay.enqueue(fixture(shown: "PRIVATE_USER_TEXT"))
        defaults.set(false, forKey: SupportIdentity.autoReportKey)
        await relay.flush()
        let pending = await relay.pendingReports()
        XCTAssertEqual(pending.map(\.kind), ["manual"])
        do {
            try await relay.enqueue(automaticFixture())
            XCTFail("Disabled automatic reporting must reject storage")
        } catch { XCTAssertEqual(error as? SupportRelayError, .automaticReportingDisabled) }
        defaults.set("anna@example.com", forKey: SupportIdentity.emailKey)
        reply()
        await relay.flush()
        XCTAssertEqual(SupportStub.json(1)["kind"] as? String, "manual")
        XCTAssertEqual(SupportStub.json(1)["shownMessage"] as? String, "PRIVATE_USER_TEXT")
    }

    func testOptOutDuringRegistrationPreventsAutomaticPostAndPreservesManual() async throws {
        try await exerciseOptOutDuringRegistration(afterUnauthorized: false)
    }

    func testOptOutDuringUnauthorizedRegistrationPreventsAutomaticRetry() async throws {
        try await exerciseOptOutDuringRegistration(afterUnauthorized: true)
    }

    private func exerciseOptOutDuringRegistration(afterUnauthorized: Bool) async throws {
        try await relay.enqueue(automaticFixture())
        try await relay.enqueue(fixture(shown: "PRIVATE_USER_TEXT"))
        SupportStub.handler { request, index in
            if request.url?.lastPathComponent == "installations" {
                if !afterUnauthorized || index == 2 { self.defaults.set(false, forKey: SupportIdentity.autoReportKey) }
                return .init(status: 201, text: "{}")
            }
            return .init(status: afterUnauthorized && index == 1 ? 401 : 201, text: self.result)
        }
        await relay.flush()
        let reportIndexes = SupportStub.requests.indices.filter { SupportStub.requests[$0].url?.lastPathComponent == "reports" }
        XCTAssertEqual(reportIndexes.map { SupportStub.json($0)["kind"] as? String }, afterUnauthorized ? ["auto", "manual"] : ["manual"])
        let pending = await relay.pendingReports()
        XCTAssertTrue(pending.isEmpty)
    }

    func testOptOutDuringHeldLogTailPreventsAutomaticPost() async throws {
        try await exerciseOptOutDuringLogTail(limit: 1_048_576)
    }

    func testOptOutDuringHeld413LogTailPreventsAutomaticRetry() async throws {
        try await exerciseOptOutDuringLogTail(limit: 262_144)
    }

    func testConcurrentOptOutFlushCannotResurrectDeletedAutomaticReport() async throws {
        try await exerciseOptOutDuringLogTail(limit: 1_048_576, discardBeforeReenable: true)
    }

    func testConcurrentOptOutFlushCannotResurrectAutomaticReportAfterCleanupFailure() async throws {
        try await exerciseOptOutDuringLogTail(limit: 1_048_576, discardBeforeReenable: true, failCleanup: true)
    }

    func testConcurrentOptOutFlushPreventsDiscardedAutomatic413Retry() async throws {
        try await exerciseOptOutDuringLogTail(limit: 262_144, discardBeforeReenable: true)
    }

    private func exerciseOptOutDuringLogTail(limit: Int, discardBeforeReenable: Bool = false, failCleanup: Bool = false) async throws {
        let started = expectation(description: "automatic log tail suspended")
        let resume = expectation(description: "resume log tail")
        let held = OSAllocatedUnfairLock(initialState: false)
        relay = makeRelay(logTail: { size in
            let shouldHold = held.withLock { used in
                if size != limit || used { return false }
                used = true
                return true
            }
            if shouldHold {
                started.fulfill()
                await self.fulfillment(of: [resume], timeout: 5)
            }
            return "SAFE_LOG"
        })
        try await relay.enqueue(automaticFixture())
        let autoFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        if failCleanup { try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: autoFile.path) }
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: autoFile.path) }
        try await relay.enqueue(fixture(shown: "PRIVATE_USER_TEXT"))
        SupportStub.handler { request, index in
            .init(status: limit == 262_144 && index == 1 ? 413 : 201, text: self.result)
        }
        let flush = Task { await self.relay.flush() }
        await fulfillment(of: [started], timeout: 5)
        defaults.set(false, forKey: SupportIdentity.autoReportKey)
        if discardBeforeReenable {
            await relay.flush()
            XCTAssertEqual(FileManager.default.fileExists(atPath: autoFile.path), failCleanup)
            defaults.set(true, forKey: SupportIdentity.autoReportKey)
        }
        resume.fulfill()
        await flush.value
        let reportIndexes = SupportStub.requests.indices.filter { SupportStub.requests[$0].url?.lastPathComponent == "reports" }
        XCTAssertEqual(reportIndexes.map { SupportStub.json($0)["kind"] as? String }, limit == 262_144 ? ["auto", "manual"] : ["manual"])
        let pending = await relay.pendingReports()
        XCTAssertTrue(pending.isEmpty)
        if failCleanup {
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: autoFile.path)
            await relay.flush()
            XCTAssertFalse(FileManager.default.fileExists(atPath: autoFile.path))
        }
    }

    func testAcceptedAutomaticResponseRemainsSentAfterConcurrentDiscard() async throws {
        let started = expectation(description: "automatic request already started")
        let resume = DispatchSemaphore(value: 0)
        SupportStub.handler { request, _ in
            if request.url?.lastPathComponent == "reports" {
                started.fulfill()
                guard resume.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
            }
            return .init(status: 201, text: self.result)
        }
        let send = Task { await self.relay.send(self.automaticFixture()) }
        await fulfillment(of: [started], timeout: 5)
        defaults.set(false, forKey: SupportIdentity.autoReportKey)
        await relay.flush()
        defaults.set(true, forKey: SupportIdentity.autoReportKey)
        resume.signal()
        let outcome = await send.value
        XCTAssertEqual(outcome, .sent(.init(ticketId: "c1", ref: "TV-000001", repeated: false, count: 1, logAttached: false)))
        await relay.flush()
        XCTAssertEqual(SupportStub.paths.filter { $0 == "/support/reports" }.count, 1)
        let pending = await relay.pendingReports()
        XCTAssertTrue(pending.isEmpty)
    }

    func testAcceptedAutomaticResponseRemainsSentAfterOptOut() async throws {
        SupportStub.handler { request, _ in
            if request.url?.lastPathComponent == "reports" { self.defaults.set(false, forKey: SupportIdentity.autoReportKey) }
            return .init(status: 201, text: self.result)
        }
        let outcome = await relay.send(automaticFixture())
        XCTAssertEqual(outcome, .sent(.init(ticketId: "c1", ref: "TV-000001", repeated: false, count: 1, logAttached: false)))
        let pending = await relay.pendingReports()
        XCTAssertTrue(pending.isEmpty)
    }

    func testDisabledAutomaticCleanupFailureDoesNotSendAfterReenable() async throws {
        try await relay.enqueue(automaticFixture())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
        defaults.set(false, forKey: SupportIdentity.autoReportKey)
        await relay.flush()
        defaults.set(true, forKey: SupportIdentity.autoReportKey)
        reply()
        await relay.flush()
        XCTAssertTrue(SupportStub.requests.isEmpty)
        let pending = await relay.pendingReports()
        XCTAssertTrue(pending.isEmpty)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
        await relay.flush()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    private func automaticFixture(stage: String = "notule", error: String = "PRIVATE_TRANSCRIPT") -> SupportReport {
        var report = fixture(shown: "PRIVATE_TITLE")
        report.kind = "auto"
        report.stage = stage
        report.errorText = error
        report.fingerprint = "0123456789abcdef"
        return report
    }

    func testContactContractBoundaries() {
        let email = String(repeating: "a", count: 314) + "@b.com"
        XCTAssertTrue(SupportIdentity.isComplete(name: String(repeating: "n", count: 200), email: " " + email + " "))
        XCTAssertFalse(SupportIdentity.isComplete(name: String(repeating: "n", count: 201), email: email))
        XCTAssertFalse(SupportIdentity.isComplete(name: "Anna", email: "a" + email))
        XCTAssertTrue(SupportIdentity.isComplete(name: String(repeating: "e\u{301}", count: 100), email: email))
        XCTAssertFalse(SupportIdentity.isComplete(name: String(repeating: "e\u{301}", count: 101), email: email))
    }

    func testOverlongStoredIdentityHoldsQueueWithoutPosting() async throws {
        for key in [SupportIdentity.nameKey, SupportIdentity.emailKey] {
            defaults.set("Anna", forKey: SupportIdentity.nameKey)
            defaults.set("anna@example.com", forKey: SupportIdentity.emailKey)
            defaults.set(key == SupportIdentity.nameKey ? String(repeating: "n", count: 201) : String(repeating: "a", count: 315) + "@b.com", forKey: key)
            try await relay.enqueue(fixture())
            await relay.flush()
            XCTAssertTrue(SupportStub.paths.isEmpty)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        defaults.set("Anna", forKey: SupportIdentity.nameKey)
        defaults.set("anna@example.com", forKey: SupportIdentity.emailKey)
        reply(); await relay.flush()
        XCTAssertEqual(SupportStub.paths.filter { $0.hasSuffix("/reports") }.count, 2)
    }

    func testIdentityOverflowAfterLogAwaitHoldsReport() async throws {
        relay = makeRelay(logTail: { [self] _ in
            defaults.set(String(repeating: "n", count: 201), forKey: SupportIdentity.nameKey)
            return "LOG"
        })
        reply(); try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertFalse(SupportStub.paths.contains("/support/reports"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testIdentityOverflowDuringRegistrationHoldsReport() async throws {
        SupportStub.handler { [self] request, _ in
            if request.url?.lastPathComponent == "installations" {
                defaults.set(String(repeating: "a", count: 315) + "@b.com", forKey: SupportIdentity.emailKey)
            }
            return .init(status: 201, text: "{}")
        }
        try await relay.enqueue(fixture()); await relay.flush()
        XCTAssertEqual(SupportStub.paths, ["/support/installations"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testReplyLimitCountsUnicodeScalars() async throws {
        reply(status: 201)
        try await relay.sendMessage(ticketId: "c1", body: String(repeating: "e\u{301}", count: 2500))
        try await relay.sendMessage(ticketId: "c1", body: String(repeating: "x", count: 5000))
        let before = SupportStub.paths.count
        do {
            try await relay.sendMessage(ticketId: "c1", body: String(repeating: "e\u{301}", count: 2500) + "x")
            XCTFail("Oversized reply accepted")
        } catch { XCTAssertEqual(error as? SupportRelayError, .http(422)) }
        XCTAssertEqual(SupportStub.paths.count, before)
    }

    func testIdentityValidation() {
        XCTAssertTrue(SupportIdentity.isComplete(name: " Anna ", email: " anna@example.com "))
        for email in ["a@@example.com", "a@.com", "a@example.", "@example.com", "a b@example.com", "a@example"] {
            XCTAssertFalse(SupportIdentity.isValidEmail(email), email)
        }
        XCTAssertFalse(SupportIdentity.isComplete(name: "\n ", email: "a@example.com"))
    }

    func testEmailValidation() {
        XCTAssertTrue(SupportIdentity.isValidEmail("anna@example.com"))
        XCTAssertTrue(SupportIdentity.isValidEmail(" anna@example.com "))
        for email in ["anna@example", "anna example.com", "anna@@example.com"] {
            XCTAssertFalse(SupportIdentity.isValidEmail(email))
        }
    }

    func testGateShowsUntilIdentityComplete() {
        XCTAssertTrue(SupportIdentity.showsGate(name: "", email: "anna@example.com", arguments: []))
        XCTAssertTrue(SupportIdentity.showsGate(name: "Anna", email: "anna@", arguments: []))
        XCTAssertFalse(SupportIdentity.showsGate(name: " Anna ", email: " anna@example.com ", arguments: []))
    }

    func testDebugGateArguments() {
        let bypass = ["-TVDebugTab", "settings"]
        let force = ["-TVDebugOpen", "identity"]
        #if DEBUG
        XCTAssertFalse(SupportIdentity.showsGate(name: "", email: "", arguments: bypass))
        XCTAssertTrue(SupportIdentity.showsGate(name: "Anna", email: "anna@example.com", arguments: force))
        XCTAssertTrue(SupportIdentity.showsGate(name: "Anna", email: "anna@example.com", arguments: bypass + force))
        XCTAssertFalse(SupportIdentity.showsGate(name: "", email: "", arguments: ["-TVDebugOpen"]))
        #else
        XCTAssertTrue(SupportIdentity.showsGate(name: "", email: "", arguments: bypass))
        XCTAssertFalse(SupportIdentity.showsGate(name: "Anna", email: "anna@example.com", arguments: force))
        #endif
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
