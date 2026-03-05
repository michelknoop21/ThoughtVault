import Foundation
import Security

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let serviceIdentifier = "nl.prezent.TranscriptStudio"

    private init() {}

    // MARK: - Public API

    func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Upsert: delete existing item first, then add fresh
        delete(for: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainService] SecItemAdd failed for key '\(key)': \(status)")
        }
    }

    func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
