import XCTest
import Network
@testable import ThoughtVault

@MainActor
final class McpRouterTests: XCTestCase {
    private func router() throws -> McpRouter { McpRouter(catalogue: try McpCatalogue.bundled(), version: "test") }

    private func object(_ line: String?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(line).utf8)) as? [String: Any])
    }

    /// `expected` must be a deep subset of `actual`.
    private func assertSubset(_ expected: Any, _ actual: Any?, _ path: String, file: StaticString = #filePath, line: UInt = #line) {
        switch expected {
        case let map as [String: Any]:
            guard let actualMap = actual as? [String: Any] else { return XCTFail("\(path): expected object", file: file, line: line) }
            for (key, value) in map { assertSubset(value, actualMap[key], "\(path).\(key)", file: file, line: line) }
        case let list as [Any]:
            guard let actualList = actual as? [Any], actualList.count == list.count else {
                return XCTFail("\(path): expected \(list.count) items, got \(String(describing: actual))", file: file, line: line)
            }
            for (index, value) in list.enumerated() { assertSubset(value, actualList[index], "\(path)[\(index)]", file: file, line: line) }
        default:
            XCTAssertEqual(expected as? NSObject, actual as? NSObject, path, file: file, line: line)
        }
    }

    func testSharedProtocolFixtures() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "protocol-fixtures", withExtension: "json"))
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let router = try router()
        for case let fixture as [String: Any] in try XCTUnwrap(fixtures["cases"] as? [Any]) {
            let name = fixture["name"] as? String ?? "?"
            let request = try JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["request"]))
            let reply = await router.handle(String(decoding: request, as: UTF8.self), allowWrite: fixture["allowWrite"] as? Bool ?? false) { _, _ in
                throw McpToolError.message("handler must not run in protocol fixtures")
            }
            if fixture["expect"] is NSNull {
                XCTAssertNil(reply, name)
                continue
            }
            let response = try object(reply)
            if let expected = fixture["expect"] { assertSubset(expected, response, name) }
            if let names = fixture["expectToolNames"] as? [String] {
                let tools = (response["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
                XCTAssertEqual(tools.map { $0["name"] as? String ?? "" }, names, name)
                XCTAssertTrue(tools.allSatisfy { $0["scope"] == nil && $0["destructive"] == nil && $0["annotations"] != nil }, name)
            }
            if let destructive = fixture["expectDestructive"] as? [String] {
                let tools = (response["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
                let marked = tools.filter { ($0["annotations"] as? [String: Any])?["destructiveHint"] as? Bool == true }
                XCTAssertEqual(marked.map { $0["name"] as? String ?? "" }, destructive, name)
            }
        }
    }

    func testUnparseableLineIsParseError() async throws {
        let reply = try await router().handle("{nope", allowWrite: false) { _, _ in Data() }
        let error = try XCTUnwrap(try object(reply)["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
    }

    func testEveryCatalogueToolHasAHandler() async throws {
        for tool in try McpCatalogue.bundled().tools {
            do { _ = try await McpTools(recordingVM: nil).call(tool.name, [:]) } catch {
                XCTAssertFalse(error.localizedDescription.hasPrefix("Onbekende tool"), tool.name)
            }
        }
    }

    func testListGetAndUpdateNote() async throws {
        let store = LocalTranscriptStore.shared
        let old = TranscriptRecord(title: "Overleg dakdragers", rawTranscription: String(repeating: "abcdefghij", count: 300),
                                   notuleHtml: "<h1>Notule</h1><p>Besluit: offerte sturen.</p>", tags: ["klant"],
                                   createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let new = TranscriptRecord(title: "Weekstart", rawTranscription: "Agenda", createdAt: Date())
        try store.save(old)
        try store.save(new)
        let tools = McpTools(recordingVM: nil)

        let found = try await tools.call("list_notes", ["query": "dakdragers"])
        XCTAssertEqual(found["total"] as? Int, 1)
        let dated = try await tools.call("list_notes", ["to": "2023-11-15"])
        XCTAssertEqual((dated["notes"] as? [[String: Any]])?.map { $0["id"] as? String }, [old.taskId])

        let note = try await tools.call("get_note", ["id": old.taskId, "max_chars": 1000])
        let transcript = try XCTUnwrap(note["transcript"] as? [String: Any])
        XCTAssertEqual((transcript["text"] as? String)?.count, 1000)
        XCTAssertEqual(transcript["next_offset"] as? Int, 1000)
        XCTAssertEqual(transcript["total_chars"] as? Int, 3000)
        XCTAssertTrue((note["notule"] as? String ?? "").contains("Besluit"))

        let revision = try XCTUnwrap(note["revision"] as? String)
        let updated = try await tools.call("update_note", ["id": old.taskId, "revision": revision, "title": "Dakdragers, offerte"])
        XCTAssertNotEqual(updated["revision"] as? String, revision)
        let reread = try await tools.call("get_note", ["id": old.taskId, "include_transcript": false])
        XCTAssertEqual(updated["revision"] as? String, reread["revision"] as? String, "returned revision must allow the next update")
        do {
            _ = try await tools.call("update_note", ["id": old.taskId, "revision": reread["revision"] as Any, "title": "X", "folder_id": "no-such-folder"])
            XCTFail("unknown folder accepted")
        } catch {
            XCTAssertEqual(store.record(forTaskId: old.taskId)?.title, "Dakdragers, offerte", "nothing written before the folder check")
        }
        let before = store.allRecords().count
        do { _ = try await tools.call("create_note", ["title": "Dubbel?", "folder_id": "no-such-folder"]); XCTFail("unknown folder accepted") } catch {}
        XCTAssertEqual(store.allRecords().count, before, "a rejected create must not save a note")
        XCTAssertEqual(store.record(forTaskId: old.taskId)?.title, "Dakdragers, offerte")
        do {
            _ = try await tools.call("update_note", ["id": old.taskId, "revision": revision, "title": "Te laat"])
            XCTFail("stale revision accepted")
        } catch {
            XCTAssertEqual(store.record(forTaskId: old.taskId)?.title, "Dakdragers, offerte")
        }
        try store.delete(taskId: old.taskId)
        try store.delete(taskId: new.taskId)
    }

    func testTranscribeRecordingRejectsPaths() async {
        for name in ["../Local.store", "/etc/hosts", ".hidden"] {
            do { _ = try await McpTools(recordingVM: nil).call("transcribe_recording", ["filename": name]); XCTFail(name) } catch {
                XCTAssertTrue(error.localizedDescription.hasPrefix("Opname niet gevonden"), "\(name): \(error.localizedDescription)")
            }
        }
    }

    func testTokenAndLineLimits() {
        XCTAssertTrue(McpServer.tokenMatches("abc", "abc"))
        XCTAssertFalse(McpServer.tokenMatches("abd", "abc"))
        XCTAssertFalse(McpServer.tokenMatches("", ""))
        XCTAssertEqual(McpServer.randomToken().count, 64)
        let reader = McpLineReader()
        XCTAssertEqual(reader.append(Data("a\nb".utf8), limit: 10), ["a"])
        XCTAssertEqual(reader.append(Data("c\n".utf8), limit: 10), ["bc"])
        XCTAssertNil(reader.append(Data(repeating: 0x41, count: 11), limit: 10))
    }

    /// The real listener in the sandboxed app host: token first, then JSON-RPC over loopback.
    func testListenerAnswersOverLoopback() async throws {
        let suite = "McpRouterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: McpServer.enabledKey)
        defaults.set(false, forKey: McpServer.allowWriteKey)
        let server = McpServer()
        server.apply(defaults: defaults)
        defer { server.stop(); defaults.removePersistentDomain(forName: suite) }
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: McpServer.fileURL.path) { try await Task.sleep(for: .milliseconds(100)) }
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: McpServer.fileURL)) as? [String: Any])
        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: UInt16(XCTUnwrap(file["port"] as? Int))))
        let token = try XCTUnwrap(file["token"] as? String)

        let reply = try await exchange(port: port, lines: [token, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#])
        let names = ((try object(reply)["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names?.first, "list_notes")
        XCTAssertFalse(names?.contains("update_note") ?? true, "write tools listed while writing is off")

        let refused = try? await exchange(port: port, lines: ["wrong", #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#])
        XCTAssertNil(refused ?? nil)
        // No newline within a token's length: dropped before it can buffer more.
        let flood = try? await exchange(port: port, lines: [String(repeating: "x", count: 4096)])
        XCTAssertNil(flood ?? nil)
        // Token and first request in one packet, the request longer than the token limit, still served.
        let long = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_notes","arguments":{"query":""# + String(repeating: "q", count: 600) + #""}}}"#
        let served = try await exchange(port: port, lines: [token, long])
        XCTAssertEqual(try object(served)["id"] as? Int, 2)

        // Switching off ends a session that is already connected.
        let connection = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        connection.start(queue: .main)
        connection.send(content: Data((token + "\n").utf8), completion: .idempotent)
        try await Task.sleep(for: .milliseconds(200))
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        connection.send(content: Data(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#.utf8 + [0x0A]), completion: .idempotent)
        let afterStop: String? = await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, _, _ in
                continuation.resume(returning: data.flatMap { $0.isEmpty ? nil : String(decoding: $0, as: UTF8.self) })
            }
        }
        connection.cancel()
        XCTAssertNil(afterStop, "a connected client still got an answer after switching off")

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: McpServer.fileURL.path))
    }

    private func exchange(port: NWEndpoint.Port, lines: [String]) async throws -> String? {
        let connection = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        connection.start(queue: .main)
        defer { connection.cancel() }
        connection.send(content: Data(lines.map { $0 + "\n" }.joined().utf8), completion: .idempotent)
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, _, _ in
                        continuation.resume(returning: data.map { String(decoding: $0, as: UTF8.self) })
                    }
                }
            }
            group.addTask { try await Task.sleep(for: .seconds(3)); return nil }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
