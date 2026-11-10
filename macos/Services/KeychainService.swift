import Foundation
import Security

enum KeychainError: LocalizedError, Equatable {
    case writeFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let status):
            return "De sleutel kon niet veilig worden opgeslagen (code \(status)). Probeer opnieuw of controleer de sleutelhanger."
        }
    }
}

final class KeychainService: Sendable {
    static let shared = KeychainService()

    /// Tests get their own keychain service so they never touch the user's real tokens.
    private let serviceIdentifier = AppEnvironment.isRunningTests ? "com.buildmind.ThoughtVault.tests" : "com.buildmind.ThoughtVault"

    /// Keys that sync via iCloud Keychain so a Mac-configured credential is
    /// available on the iPhone (e.g. the Ollama Cloud API key).
    private static let synchronizableKeys: Set<String> = ["ollamaApiKey", "openAIApiKey", "anthropicApiKey"]

    typealias AddFunction = @Sendable (CFDictionary) -> OSStatus
    typealias UpdateFunction = @Sendable (CFDictionary, CFDictionary) -> OSStatus

    private let add: AddFunction
    private let update: UpdateFunction

    /// The SecItem functions are injectable so tests can force write failures.
    init(
        add: @escaping AddFunction = { SecItemAdd($0, nil) },
        update: @escaping UpdateFunction = { SecItemUpdate($0, $1) }
    ) {
        self.add = add
        self.update = update
    }

    // MARK: - Public API

    /// Writes without deleting first, so a failed write keeps the previous value.
    func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let synced = Self.synchronizableKeys.contains(key)

        var match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: key
        ]
        // Exactly the synced variant: an existing pre-sync local item is not
        // updated in place (it would stay device-only) but replaced below.
        if synced { match[kSecAttrSynchronizable] = true }

        var status = update(match as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = match
            attributes[kSecValueData] = data
            // ThisDeviceOnly accessibility is incompatible with iCloud sync.
            attributes[kSecAttrAccessible] = synced
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = add(attributes as CFDictionary)
        }
        guard status == errSecSuccess else {
            DebugLogger.shared.error("Keychain write failed for key '\(key)': \(status)", category: "Keychain")
            throw KeychainError.writeFailed(status)
        }

        if synced {
            // Only after the new item exists: drop a stale pre-sync local variant.
            SecItemDelete([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: serviceIdentifier,
                kSecAttrAccount: key,
                kSecAttrSynchronizable: false
            ] as CFDictionary)
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
