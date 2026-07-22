// SettingsSyncService.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Mirrors the notule-provider settings between UserDefaults and the iCloud
// key-value store so configuring Ollama Cloud on the Mac makes it work on the
// iPhone without retyping anything. The API key itself syncs via iCloud
// Keychain (see KeychainService.synchronizableKeys).
//
// Existing code keeps reading plain UserDefaults; this service only mirrors.
// Both directions write only on an actual difference, which prevents
// notification ping-pong loops without any state flags.

import Foundation

// NSObject: required for selector-based NotificationCenter observers.
// @unchecked Sendable: no mutable state; the stores are thread-safe.
final class SettingsSyncService: NSObject, @unchecked Sendable {
    static let shared = SettingsSyncService()

    private static let keys = ["notulenProvider", "ollamaURL", "ollamaModel"]

    private let store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    private override init() {}

    func start() {
        // Pull first so freshly-installed devices adopt the iCloud values
        // before any local write could push defaults back up.
        store.synchronize()
        pull(keys: Self.keys)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChangedExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
    }

    // MARK: - Pull (iCloud -> UserDefaults)

    @objc private func storeChangedExternally(_ notification: Notification) {
        let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? Self.keys
        pull(keys: changed.filter { Self.keys.contains($0) })
    }

    private func pull(keys: [String]) {
        for key in keys {
            guard let cloudValue = store.string(forKey: key) else { continue }
            if defaults.string(forKey: key) != cloudValue {
                defaults.set(cloudValue, forKey: key)
            }
        }
    }

    // MARK: - Push (UserDefaults -> iCloud)

    @objc private func defaultsChanged() {
        for key in Self.keys {
            guard let localValue = defaults.string(forKey: key) else { continue }
            if store.string(forKey: key) != localValue {
                store.set(localValue, forKey: key)
            }
        }
    }
}
