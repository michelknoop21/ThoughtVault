import XCTest
import Security
@testable import ThoughtVault

final class KeychainServiceTests: XCTestCase {
    private let key = "keychainServiceTestsKey"
    private let failing: @Sendable (CFDictionary, CFDictionary) -> OSStatus = { _, _ in errSecInteractionNotAllowed }

    override func tearDown() {
        KeychainService.shared.delete(for: key)
        super.tearDown()
    }

    func testWriteFailureThrows() {
        let service = KeychainService(
            add: { _ in errSecInteractionNotAllowed },
            update: { _, _ in errSecInteractionNotAllowed }
        )
        XCTAssertThrowsError(try service.save("secret", for: key)) { error in
            XCTAssertEqual(error as? KeychainError, .writeFailed(errSecInteractionNotAllowed))
            XCTAssertEqual(
                error.localizedDescription,
                "De sleutel kon niet veilig worden opgeslagen (code \(errSecInteractionNotAllowed)). Probeer opnieuw of controleer de sleutelhanger."
            )
        }
    }

    func testFailedWriteKeepsPreviousValue() throws {
        try KeychainService.shared.save("v1", for: key)
        let service = KeychainService(add: { SecItemAdd($0, nil) }, update: failing)
        XCTAssertThrowsError(try service.save("v2", for: key))
        XCTAssertEqual(KeychainService.shared.load(for: key), "v1")
    }

    func testRoundTrip() throws {
        let keychain = KeychainService.shared
        try keychain.save("one", for: key)
        XCTAssertEqual(keychain.load(for: key), "one")
        try keychain.save("two", for: key)
        XCTAssertEqual(keychain.load(for: key), "two")
        keychain.delete(for: key)
        XCTAssertNil(keychain.load(for: key))
    }
}
