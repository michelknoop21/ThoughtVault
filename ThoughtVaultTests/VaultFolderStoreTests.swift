import XCTest
@testable import ThoughtVault

/// writeNote must tell a note edited in Obsidian (.externallyChanged) apart from an
/// I/O or access failure (.failed): callers show different messages for them.
/// The tests use a temp vault and restore the user's real vault settings afterwards.
final class VaultFolderStoreTests: XCTestCase {
    private let keys = [VaultFolderStore.bookmarkKey, VaultFolderStore.folderNameKey, ObsidianService.vaultPathKey,
                        ObsidianService.enabledKey, VaultFolderStore.contextNoteKey]
    private var saved: [String: Any] = [:]
    private var vault: URL!
    private let filename = "vaultfolderstore-test-note.md"

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        for key in keys { if let value = defaults.object(forKey: key) { saved[key] = value } }
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("vault-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defaults.set(true, forKey: ObsidianService.enabledKey)
        defaults.set("Context.md", forKey: VaultFolderStore.contextNoteKey)
        VaultFolderStore.resetLinkState()
        try VaultFolderStore.setFolder(vault)
        defaults.set("Notulen", forKey: ObsidianService.vaultPathKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys { if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.removeObject(forKey: "obsidianSync-\(filename)")
        try? FileManager.default.removeItem(at: vault)
        VaultFolderStore.resetLinkState()
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

    // MARK: - Switch and broken link

    private func writeContextNote() throws {
        try "- Michel\n- Prezent".write(to: vault.appendingPathComponent("Context.md"), atomically: true, encoding: .utf8)
    }

    func testSwitchOffNeverTouchesTheVault() throws {
        try writeContextNote()
        UserDefaults.standard.set(false, forKey: ObsidianService.enabledKey)

        XCTAssertNil(VaultFolderStore.readContextNote())
        XCTAssertFalse(VaultFolderStore.isConfigured)
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "x"), .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteURL.path))

        // An unusable bookmark is not even resolved while the switch is off.
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: VaultFolderStore.bookmarkKey)
        XCTAssertNil(VaultFolderStore.readContextNote())
        XCTAssertNil(VaultFolderStore.brokenStep)

        UserDefaults.standard.set(true, forKey: ObsidianService.enabledKey)
        try VaultFolderStore.setFolder(vault)
        XCTAssertEqual(VaultFolderStore.readContextNote(), "- Michel\n- Prezent")
    }

    func testUnresolvableBookmarkMarksLinkBrokenAndStopsVaultCalls() throws {
        try writeContextNote()
        let good = try XCTUnwrap(UserDefaults.standard.data(forKey: VaultFolderStore.bookmarkKey))
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: VaultFolderStore.bookmarkKey)

        XCTAssertNil(VaultFolderStore.readContextNote())
        XCTAssertEqual(VaultFolderStore.brokenStep, "resolve")

        // A working bookmark is not retried until the user picks again.
        UserDefaults.standard.set(good, forKey: VaultFolderStore.bookmarkKey)
        XCTAssertNil(VaultFolderStore.readContextNote())
        XCTAssertEqual(VaultFolderStore.writeNote(filename: filename, markdown: "x"), .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteURL.path))

        // A new pick clears the state and the vault works again.
        try VaultFolderStore.setFolder(vault)
        XCTAssertNil(VaultFolderStore.brokenStep)
        XCTAssertEqual(VaultFolderStore.readContextNote(), "- Michel\n- Prezent")
    }

    func testMissingNoteDoesNotMarkLinkBroken() {
        XCTAssertNil(VaultFolderStore.readContextNote())
        XCTAssertNil(VaultFolderStore.readNote(filename: "bestaat-niet.md"))
        XCTAssertNil(VaultFolderStore.brokenStep)
    }

    func testBrokenLinkExportThrowsVaultLinkBroken() async throws {
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: VaultFolderStore.bookmarkKey)
        do {
            try await ObsidianService.tryExport(title: "T", html: "<p>x</p>", date: Date(), participants: [],
                                                profileName: nil, tags: [], noteID: "vaultfolderstore-test")
            XCTFail("export should fail")
        } catch ObsidianService.ObsidianError.vaultLinkBroken {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testObsidianFolderCheck() throws {
        XCTAssertFalse(try VaultFolderStore.setFolder(vault))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        XCTAssertTrue(try VaultFolderStore.setFolder(vault))
    }
}
