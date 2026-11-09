import XCTest
@testable import ThoughtVault

final class HTMLPlainTextTests: XCTestCase {
    // Ported from windows/src/utils/__tests__/htmlToPlainText.test.ts
    func testSeparatesBlocksWithoutLeakingStyles() {
        let html = "<style>.x{color:red}</style><h2>Kern</h2><p>Een <strong>besluit</strong> &amp; actie.</p><h2>Acties</h2><p>Alex begint.<br>Maandag.</p><script>alert(1)</script>"
        XCTAssertEqual(HTMLPlainText.from(html), "Kern\nEen besluit & actie.\nActies\nAlex begint.\nMaandag.")
    }

    func testTableCellsAreTabSeparated() {
        let html = "<table><tr><th>Wie</th><th>Wat</th></tr><tr><td>Iris</td><td>Belt</td></tr></table>"
        // Trailing tab after the last cell is removed by the per-line trim.
        XCTAssertEqual(HTMLPlainText.from(html), "Wie\tWat\nIris\tBelt")
    }

    func testDecodesEntitiesOnce() {
        XCTAssertEqual(HTMLPlainText.from("&amp;lt;b&amp;gt;"), "&lt;b&gt;")
        XCTAssertEqual(HTMLPlainText.from("&#8364; 12.450"), "€ 12.450")
        XCTAssertEqual(HTMLPlainText.from("&#x20AC;"), "€")
    }

    func testDecodesCommonNamedEntities() {
        XCTAssertEqual(HTMLPlainText.from("&euro; 12.450"), "€ 12.450")
        XCTAssertEqual(HTMLPlainText.from("caf&eacute;"), "café")
        XCTAssertEqual(HTMLPlainText.from("&ldquo;ja&rdquo;"), "“ja”")
        XCTAssertEqual(HTMLPlainText.from("&hellip;"), "…")
        XCTAssertEqual(HTMLPlainText.from("&mdash;"), "—")
        XCTAssertEqual(HTMLPlainText.from("&Euml;"), "Ë")
        XCTAssertEqual(HTMLPlainText.from("a&shy;b"), "a\u{00AD}b")
        XCTAssertEqual(HTMLPlainText.from("&unknown;"), "&unknown;")
    }

    func testAmpersandEscapedEntityStaysLiteral() {
        XCTAssertEqual(HTMLPlainText.from("&amp;euro;"), "&euro;")
    }

    func testCollapsesBlankRuns() {
        XCTAssertEqual(HTMLPlainText.from("<p>A</p><p></p><p></p><p></p><p>B</p>"), "A\n\nB")
    }

    func testListItemsOnOwnLines() {
        XCTAssertEqual(HTMLPlainText.from("<ul><li>Een</li><li>Twee</li></ul>"), "Een\nTwee")
    }
}
