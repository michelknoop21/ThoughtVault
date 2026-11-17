import XCTest
import SwiftData
@testable import ThoughtVault

@MainActor final class DocumentBrandingTests: XCTestCase {
    private func example() throws -> DocumentBranding {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Yinga", withExtension: "tvhuisstijl", subdirectory: "Document"))
        return try DocumentBranding.parse(String(contentsOf: url, encoding: .utf8))
    }

    func testLibraryRoundTripDefaultAndSnapshotsSurviveEditsAndRemoval() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "branding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "library.json")
        let store = DocumentBrandingStore(url: url)
        var style = try example()
        try store.save(DocumentBrandingLibrary(defaultId: style.id, styles: [style]))
        let applied = try XCTUnwrap(store.defaultSnapshot())
        style.name = "Aangepast"; style.revision += 1
        try store.save(DocumentBrandingLibrary(defaultId: style.id, styles: [style]))
        XCTAssertEqual(DocumentBrandingStore(url: url).library.styles.first?.name, "Aangepast")
        try store.save(DocumentBrandingLibrary())
        XCTAssertEqual(try DocumentBranding.parse(applied).name, "Yinga")
        XCTAssertEqual(try DocumentBranding.parse(applied).revision, 1)
        XCTAssertEqual(try DocumentBranding.parse(XCTUnwrap(store.defaultSnapshot())).id, "thoughtvault")
    }

    func testInvalidImportsAndUnreadableLibraryDoNotOverwriteFiles() throws {
        var style = try example()
        style.logo = "https://example.com/logo.png"
        XCTAssertThrowsError(try style.validate())
        style = try example(); style.schemaVersion = 2
        XCTAssertThrowsError(try style.validate())
        style = try example(); style.fontSize = .infinity
        XCTAssertThrowsError(try style.validate())
        let folder = FileManager.default.temporaryDirectory.appending(path: "branding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "library.json")
        try Data("broken".utf8).write(to: url)
        let store = DocumentBrandingStore(url: url)
        XCTAssertNotNil(store.error)
        XCTAssertThrowsError(try store.save(DocumentBrandingLibrary()))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }

    func testAppliedSnapshotSurvivesPortableSyncAndContentEditing() throws {
        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LocalTranscriptStore(container: container)
        let record = TranscriptRecord(id: "branded", title: "Overleg", notuleHtml: "<p>Besluit</p>")
        let snapshot = try example().json()
        record.documentBrandingJSON = snapshot
        try store.save(record)
        try store.updateNotule(taskId: record.taskId, html: "<p>Gewijzigd besluit</p>")
        XCTAssertEqual(record.documentBrandingJSON, snapshot)
        let payload = SyncedNotule(record)
        let decoded = try JSONDecoder().decode(SyncedNotule.self, from: payload.encoded())
        XCTAssertEqual(decoded.documentBrandingJSON, snapshot)
        XCTAssertEqual(record.asTranscript.documentBrandingJSON, snapshot)
        let data = try JSONEncoder().encode(record.asTranscript)
        XCTAssertEqual(try JSONDecoder().decode(Transcript.self, from: data).documentBrandingJSON, snapshot)
        let copy = TranscriptRecord(id: record.id, title: "")
        decoded.apply(to: copy)
        XCTAssertEqual(copy.documentBrandingJSON, snapshot)
        XCTAssertEqual(copy.notuleHtml, "<p>Gewijzigd besluit</p>")
    }
}
