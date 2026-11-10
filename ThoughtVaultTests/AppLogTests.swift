import XCTest
@testable import ThoughtVault

final class AppLogTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "AppLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func size(of name: String) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: dir.appending(path: name).path)[.size] as! Int
    }

    private func writeRotated(ageDays: Double) throws {
        let url = dir.appending(path: "thoughtvault.1.log")
        try Data("old\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ageDays * 24 * 60 * 60)], ofItemAtPath: url.path)
    }

    func testMaskIsStableShortToken() {
        XCTAssertEqual(LogRedact.mask("Overleg Jansen"), "k-08122f")
        XCTAssertEqual(LogRedact.mask("Overleg Jansen"), LogRedact.mask("Overleg Jansen"))
        XCTAssertEqual(LogRedact.mask("anna@example.com"), "k-f7d54c")
    }

    func testScrubMasksEmailPathAndMediaFilename() {
        XCTAssertEqual(LogRedact.scrub("Mail anna@example.com, file /Users/anna/Documents/Klant.m4a"),
                       "Mail k-f7d54c, file k-29040c")
        XCTAssertEqual(LogRedact.scrub("Bestand niet gevonden: Klant.m4a"), "Bestand niet gevonden: k-cc794b")
        XCTAssertEqual(LogRedact.scrub("POST https://thoughtvault.yinga.ai/support/reports 201"),
                       "POST https://thoughtvault.yinga.ai/support/reports 201")
    }

    func testRotatesAtTwoAndAHalfMegabytes() async throws {
        let file = LogFile(directory: dir)
        let line = String(repeating: "x", count: 999) + "\n"
        for _ in 0..<2_700 { await file.append(line) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "thoughtvault.1.log").path))
        XCTAssertLessThanOrEqual(try size(of: "thoughtvault.log"), 2_621_440)
        XCTAssertLessThanOrEqual(try size(of: "thoughtvault.1.log"), 2_621_440)
    }

    func testRotatedFileOlderThanSevenDaysIsRemovedAtStart() throws {
        try writeRotated(ageDays: 8)
        _ = LogFile(directory: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "thoughtvault.1.log").path))
        try writeRotated(ageDays: 6)
        _ = LogFile(directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "thoughtvault.1.log").path))
    }

    func testTailIsCappedAtOneMegabyteAndStartsAtALine() async {
        let file = LogFile(directory: dir)
        for i in 0..<3_000 { await file.append(String(format: "line-%04d ", i) + String(repeating: "é", count: 495) + "\n") }
        let tail = await file.tail(maxBytes: 1_048_576)
        XCTAssertLessThanOrEqual(tail.utf8.count, 1_048_576)
        XCTAssertTrue(tail.hasPrefix("line-"))
        XCTAssertTrue(tail.hasSuffix(String(repeating: "é", count: 495) + "\n"))
        XCTAssertTrue(tail.contains("line-2999 "))
    }

    func testSessionMarker() {
        XCTAssertEqual(AppLog.beginSession(in: dir), .clean)
        XCTAssertEqual(AppLog.beginSession(in: dir), .crashed(stage: nil))
        AppLog.setSessionStage("transcriberen", in: dir)
        XCTAssertEqual(AppLog.beginSession(in: dir), .crashed(stage: "transcriberen"))
        AppLog.endSession(in: dir)
        AppLog.setSessionStage("notule", in: dir)   // no marker: must not create one
        XCTAssertEqual(AppLog.beginSession(in: dir), .clean)
    }

    func testClickPathTakesLastThirtyMessagesCappedAtEightyChars() {
        var log = (0..<40).map { "2026-11-10T09:00:00Z INFO [Klikpad] Tab \($0)" }
        log.insert("2026-11-10T09:00:00Z ERROR [RecordingVM] other", at: 20)
        log.append("2026-11-10T09:00:01Z INFO [Klikpad] " + String(repeating: "a", count: 120))
        let path = AppLog.clickPath(in: log.joined(separator: "\n"))
        XCTAssertEqual(path.count, 30)
        XCTAssertEqual(path.first, "Tab 11")
        XCTAssertEqual(path.last?.count, 80)
    }

    func testAppLogWritesScrubbedLinesAndSkipsDebug() async {
        // AppLog.directory is AppEnvironment.supportDirectory/Logs: a per-run temp dir under XCTest.
        let log = AppLog(category: "Test")
        log.debug("debug-only")
        log.error("mislukt voor anna@example.com\nregel twee")
        await AppLog.flush()
        let tail = await AppLog.tail()
        XCTAssertTrue(tail.contains("ERROR [Test] mislukt voor k-f7d54c regel twee"))
        XCTAssertFalse(tail.contains("debug-only"))
        XCTAssertFalse(tail.contains("anna@"))
    }
}
