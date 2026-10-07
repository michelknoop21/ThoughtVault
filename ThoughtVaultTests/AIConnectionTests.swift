import XCTest
@testable import ThoughtVault

final class AIConnectionTests: XCTestCase {
    func testStylingRejectsCSSInjectionAndInvalidNumbers() {
        var style = MinutesStyle()
        style.text_color = "red; background:url(https://evil)"
        XCTAssertThrowsError(try style.validate())
        style = MinutesStyle(); style.font = "url(file:///secret)"
        XCTAssertThrowsError(try style.validate())
        style = MinutesStyle(); style.size = .nan
        XCTAssertThrowsError(try style.validate())
    }

    func testStyleReplacesExistingCSSAndKeepsTables() throws {
        var style = MinutesStyle(); style.font = "Georgia"; style.orientation = "landscape"
        let html = try style.apply(to: "<style>body{color:red}</style><table><tr><td>Besluit</td></tr></table>")
        XCTAssertFalse(html.contains("color:red"))
        XCTAssertTrue(html.contains("Georgia"))
        XCTAssertTrue(html.contains("A4 landscape"))
        XCTAssertTrue(html.contains("<table>"))
    }

    func testMCPHTMLKeepsTextAndTablesWithoutExecutableMarkupOrResources() throws {
        let html = try MinutesStyle().apply(to: "<SCRIPT>steal()</SCRIPT><img src=file:///secret onerror=steal()><iframe src=https://example.invalid>remote</iframe><p onclick=steal() style='background:url(https://example.invalid)'>José</p><table><tr><td colspan=2>Besluit</td></tr></table>")
        XCTAssertTrue(html.contains("<p>José</p>"))
        XCTAssertTrue(html.contains("<table><tr><td>Besluit</td></tr></table>"))
        for forbidden in ["SCRIPT", "steal()", "<img", "<iframe", "onclick", "onerror", "file:", "https:"] { XCTAssertFalse(html.contains(forbidden)) }
    }

    func testProfileStylingSurvivesReload() throws {
        let defaults = UserDefaults(suiteName: "AIConnectionTests")!
        defer { defaults.removePersistentDomain(forName: "AIConnectionTests") }
        var profile = Profile.defaults[0]
        profile.id = "own"; profile.isDefault = false
        profile.minutesStyle = MinutesStyle(); profile.minutesStyle?.font = "Georgia"
        try LocalProfileStore.save(profile, defaults: defaults)
        XCTAssertEqual(LocalProfileStore.load(defaults: defaults).first?.minutesStyle?.font, "Georgia")
        XCTAssertEqual(Profile.defaults[0].isDefault, true)
    }

    func testMarkdownKeepsTableColumnsAndUnicode() {
        let markdown = htmlToMarkdown("<table><tr><th>Actie</th><th>Eigenaar</th></tr><tr><td>Start | stop</td><td>José</td></tr></table>")
        XCTAssertTrue(markdown.contains("| Actie | Eigenaar |"))
        XCTAssertTrue(markdown.contains("| --- | --- |"))
        XCTAssertTrue(markdown.contains("| Start \\| stop | José |"))
    }

    #if os(macOS)
    @MainActor func testLocalMCPInsideSignedAppHost() async throws {
        var ready = false
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let server = try LocalMCPServer(token: token, scopes: ["read"], handler: { _, _ in ["synthetic": true] }, onStatus: { ready = $0.contains("actief") })
        server.start()
        defer { server.stop() }
        for _ in 0..<50 {
            if ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ready)
        guard ready else { return }
        func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11218/mcp")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let initialized = try await call("initialize")
        XCTAssertEqual((initialized["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        let result = try await call("tools/call", ["name": "get_app_state", "arguments": [:]])
        let content = (result["result"] as? [String: Any])?["structuredContent"] as? [String: Any]
        XCTAssertEqual(content?["synthetic"] as? Bool, true)
        let denied = try await call("tools/call", ["name": "start_recording", "arguments": [:]])
        XCTAssertEqual((denied["result"] as? [String: Any])?["isError"] as? Bool, true)
    }
    #endif

    @MainActor func testRevisionDetectsManualEditsAndScopeCannotBeDowngraded() throws {
        let original: [String: Any] = ["title": "Meeting", "tags": ["work"], "minutes": "<p>Besluit</p>"]
        let revision = try AIConnectionViewModel.revision(original)
        var changed = original; changed["title"] = "Renamed"
        XCTAssertNotEqual(revision, try AIConnectionViewModel.revision(changed))
        XCTAssertEqual(AIConnectionViewModel.requiredScope("start_recording"), "record")
        XCTAssertEqual(AIConnectionViewModel.requiredScope("save_minutes"), "write")
        XCTAssertEqual(AIConnectionViewModel.requiredScope("get_transcript"), "read")
    }
}
