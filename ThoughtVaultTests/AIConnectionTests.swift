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
