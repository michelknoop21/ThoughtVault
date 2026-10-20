import XCTest
@testable import ThoughtVault

/// writeNote must tell a note edited in Obsidian (.externallyChanged) apart from an
/// I/O or access failure (.failed): callers show different messages for them.
/// The tests use a temp vault and restore the user's real vault settings afterwards.
final class VaultFolderStoreTests: XCTestCase {
    private let keys = [VaultFolderStore.bookmarkKey, VaultFolderStore.folderNameKey, ObsidianService.vaultPathKey]
    private var saved: [String: Any] = [:]
    private var vault: URL!
    private let filename = "vaultfolderstore-test-note.md"

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        for key in keys { if let value = defaults.object(forKey: key) { saved[key] = value } }
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("vault-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try VaultFolderStore.setFolder(vault)
        defaults.set("Notulen", forKey: ObsidianService.vaultPathKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys { if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.removeObject(forKey: "obsidianSync-\(filename)")
        try? FileManager.default.removeItem(at: vault)
    }

    private var noteURL: URL { vault.appendingPathComponent("Notulen").appendingPathComponent(filename) }

    func testWritesNewNote() throws {
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "eerste"), .written)
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "eerste")
    }

    func testNoteEditedInObsidianIsExternallyChangedAndLeftUntouched() throws {
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "van ThoughtVault"), .written)
        try "bewerkt in Obsidian".write(to: noteURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "nieuwe export"), .externallyChanged)
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "bewerkt in Obsidian")
    }

    func testUnchangedNoteIsOverwritten() throws {
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "v1"), .written)
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "v2"), .written)
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "v2")
    }

    func testUnwritableFolderIsFailedNotExternallyChanged() throws {
        // A regular file where the notes subfolder should be makes createDirectory throw.
        try "blokkade".write(to: vault.appendingPathComponent("Notulen"), atomically: true, encoding: .utf8)
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "x"), .failed)
    }

    func testMissingVaultFolderIsFailed() {
        VaultFolderStore.clear()
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "x"), .failed)
    }
}
