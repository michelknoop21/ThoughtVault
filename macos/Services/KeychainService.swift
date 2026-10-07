import Foundation
import Security

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.buildmind.ThoughtVault"

    /// Keys that sync via iCloud Keychain so a Mac-configured credential is
    /// available on the iPhone (e.g. the Ollama Cloud API key).
    private static let synchronizableKeys: Set<String> = ["ollamaApiKey"]

    private init() {}

    // MARK: - Public API

    func save(_ value: String, for key: String) {
        guard load(for: key) != value else { return }
        guard let data = value.data(using: .utf8) else { return }

        // Upsert: delete existing item first, then add fresh
        delete(for: key)

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if Self.synchronizableKeys.contains(key) {
            // ThisDeviceOnly accessibility is incompatible with iCloud sync.
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            query[kSecAttrSynchronizable] = true
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            DebugLogger.shared.error("SecItemAdd failed for key '\(key)': \(status)", category: "Keychain")
        }
    }

    func load(for key: String) -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if Self.synchronizableKeys.contains(key) {
            // Any: finds both a pre-sync local item and a synced item.
            query[kSecAttrSynchronizable] = kSecAttrSynchronizableAny
        }

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
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key
        ]
        if Self.synchronizableKeys.contains(key) {
            // Any: wipes both the old local item and the synced item, so the
            // save() upsert never leaves a stale duplicate behind.
            query[kSecAttrSynchronizable] = kSecAttrSynchronizableAny
        }

        SecItemDelete(query as CFDictionary)
    }
}
