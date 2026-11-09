import XCTest
import UniformTypeIdentifiers
@testable import ThoughtVault

final class ExportFileTests: XCTestCase {
    // Ported from windows/src/services/textExport.ts and its tests.
    func testFilenameReplacesForbiddenCharacters() {
        XCTAssertEqual(ExportFile.filename(title: "Overleg: Q3/Q4 <def>?", ext: "txt"), "Overleg_ Q3_Q4 _def__.txt")
        XCTAssertEqual(ExportFile.filename(title: "a\u{0007}b", ext: "md"), "a_b.md")
    }

    func testFilenameStripsTrailingDotsAndSpacesAndFallsBack() {
        XCTAssertEqual(ExportFile.filename(title: "Notulen.. ", ext: "pdf"), "Notulen.pdf")
        XCTAssertEqual(ExportFile.filename(title: "   ", ext: "txt"), "notulen.txt")
        XCTAssertEqual(ExportFile.filename(title: "...", ext: "txt"), "notulen.txt")
    }

    func testContentTypes() {
        XCTAssertEqual(ExportFile.contentType(ext: "md").preferredFilenameExtension, "md")
        XCTAssertEqual(ExportFile.contentType(ext: "txt"), .plainText)
        XCTAssertEqual(ExportFile.contentType(ext: "pdf"), .pdf)
        XCTAssertEqual(ExportFile.contentType(ext: "html"), .html)
    }

    func testTranscriptHTMLEscapesMarkup() {
        XCTAssertEqual(
            ExportFile.transcriptHTML("<script>a & b</script>\n\"x\" 'y'"),
            "&lt;script&gt;a &amp; b&lt;/script&gt;<br>&quot;x&quot; &#39;y&#39;")
    }

    func testContentSurvivesWriteByteIdentical() throws {
        let text = "Iris: € 12.450 — geen verhoging"
        for ext in ["txt", "md", "html"] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ExportFile.filename(title: "Overleg", ext: ext))
            try text.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertEqual(try Data(contentsOf: url), Data(text.utf8))
            XCTAssertEqual(url.lastPathComponent, "Overleg.\(ext)")
        }
    }
}
