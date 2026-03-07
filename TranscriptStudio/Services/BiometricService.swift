import Foundation
import LocalAuthentication
import Security
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "BiometricService")

// MARK: - Token Wrapper

/// Wraps an authentication token with an expiry date for time-limited biometric storage.
private struct TokenWrapper: Codable {
    let token: String
    let expiresAt: Date
}

enum BiometricType {
    case none
    case faceID
    case touchID
}

@Observable
final class BiometricService: @unchecked Sendable {
    static let shared = BiometricService()

    private let biometricServiceIdentifier = "nl.prezent.TranscriptStudio.biometric"
    private let biometricAccountKey = "biometricToken"

    @ObservationIgnored
    @AppStorage("biometricLoginEnabled") var isEnabled: Bool = false

    var availableType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    private init() {}

    // MARK: - Authentication

    /// Evaluate biometric policy and return success status.
    func authenticate() async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Gebruik wachtwoord"

        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Gebruik Face ID of Touch ID om in te loggen"
        )
    }

    /// Evaluate biometric policy and return both the success status and the authenticated LAContext.
    /// The returned context must be passed to `loadBiometricToken(context:)` on macOS to access
    /// Keychain items protected with `.biometryCurrentSet`.
    func authenticateWithContext() async throws -> (success: Bool, context: LAContext) {
        let context = LAContext()
        context.localizedFallbackTitle = "Gebruik wachtwoord"

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Gebruik Face ID of Touch ID om in te loggen"
        )
        return (success, context)
    }

    // MARK: - Token Storage

    /// Save an authentication token to the Keychain protected by biometric access control.
    /// The token is wrapped with a 24-hour expiry date.
    func saveTokenWithBiometrics(_ token: String) async throws {
        let wrapper = TokenWrapper(token: token, expiresAt: Date().addingTimeInterval(24 * 60 * 60))
        guard let data = try? JSONEncoder().encode(wrapper) else {
            throw BiometricError.invalidToken
        }

        // Remove any existing item first
        removeBiometricToken()

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            let errorMessage = accessError?.takeRetainedValue().localizedDescription ?? "Unknown error"
            logger.error("SecAccessControlCreateWithFlags failed: \(errorMessage)")
            throw BiometricError.accessControlCreationFailed(errorMessage)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: biometricServiceIdentifier,
            kSecAttrAccount: biometricAccountKey,
            kSecValueData: data,
            kSecAttrAccessControl: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("SecItemAdd (biometric) failed: \(status)")
            throw BiometricError.keychainError(status)
        }
    }

    /// Load the biometric-protected token. On iOS, the Keychain automatically prompts for
    /// biometric authentication via the access control flags. Use `loadBiometricToken(context:)`
    /// on macOS to pass the already-authenticated LAContext explicitly.
    ///
    /// Returns `nil` if the token has expired (24-hour TTL) and removes it from the Keychain.
    func loadBiometricToken() async throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: biometricServiceIdentifier,
            kSecAttrAccount: biometricAccountKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: {
                let ctx = LAContext()
                ctx.localizedReason = "Bevestig uw identiteit om in te loggen"
                return ctx
            }()
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data
        else {
            throw BiometricError.keychainError(status)
        }

        // Decode the TokenWrapper and check expiry
        guard let wrapper = try? JSONDecoder().decode(TokenWrapper.self, from: data) else {
            // Legacy token stored as plain string — treat as expired and remove
            logger.info("Biometric token is in legacy format, removing.")
            removeBiometricToken()
            return nil
        }

        if wrapper.expiresAt < Date() {
            logger.info("Biometric token expired, removing from Keychain.")
            removeBiometricToken()
            return nil
        }

        return wrapper.token
    }

    /// macOS-specific variant: passes an already-authenticated LAContext to the Keychain query,
    /// which is required because macOS does not automatically link the biometric session to
    /// subsequent Keychain operations the way iOS does.
    ///
    /// Returns `nil` if the token has expired (24-hour TTL) and removes it from the Keychain.
    func loadBiometricToken(context: LAContext) async throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: biometricServiceIdentifier,
            kSecAttrAccount: biometricAccountKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data
        else {
            throw BiometricError.keychainError(status)
        }

        // Decode the TokenWrapper and check expiry
        guard let wrapper = try? JSONDecoder().decode(TokenWrapper.self, from: data) else {
            // Legacy token stored as plain string — treat as expired and remove
            logger.info("Biometric token is in legacy format, removing.")
            removeBiometricToken()
            return nil
        }

        if wrapper.expiresAt < Date() {
            logger.info("Biometric token expired, removing from Keychain.")
            removeBiometricToken()
            return nil
        }

        return wrapper.token
    }

    /// Remove the biometric-protected token from the Keychain.
    func removeBiometricToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: biometricServiceIdentifier,
            kSecAttrAccount: biometricAccountKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum BiometricError: LocalizedError {
    case invalidToken
    case accessControlCreationFailed(String)
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Ongeld token formaat."
        case .accessControlCreationFailed(let msg):
            return "Toegangsbeheer aanmaken mislukt: \(msg)"
        case .keychainError(let status):
            return "Keychain fout (status \(status))."
        }
    }
}
