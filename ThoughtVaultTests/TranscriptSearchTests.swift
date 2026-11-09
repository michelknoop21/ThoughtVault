import XCTest
@testable import ThoughtVault

final class TranscriptSearchTests: XCTestCase {
    // Ported from windows/src/components/transcripts/__tests__/TranscriptsList.search.test.tsx
    private let notule = "<style>.hidden { color: red }</style><p>QA Windows 19 oktober</p><p>Bewerken gecontroleerd &amp; heropend.</p>"

    private func one(_ q: String) -> Bool {
        TranscriptSearch.matches(q, title: "Vergadering", transcript: "Alex doet de installatie", notuleHtml: notule, tags: ["Yinga"])
    }

    private func two(_ q: String) -> Bool {
        TranscriptSearch.matches(q, title: "Andere notule", transcript: "", notuleHtml: "", tags: [])
    }

    func testMatchesAcrossFieldsCaseInsensitive() {
        for q in ["  aLEX  ", "YINGA", "vergadering", "qa WINDOWS 19 oktober", "oktober Bewerken", "gecontroleerd & heropend"] {
            XCTAssertTrue(one(q), q)
            XCTAssertFalse(two(q), q)
        }
    }

    func testStyleTextIsNotSearchable() {
        XCTAssertFalse(one("color: red"))
        XCTAssertFalse(two("color: red"))
    }

    func testEmptyQueryMatchesAll() {
        XCTAssertTrue(one("   "))
        XCTAssertTrue(two(""))
    }
}
