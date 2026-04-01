import AppKit
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "AuthViewModel")

// MARK: - Notification Name

extension Notification.Name {
    /// Posted by APIService (or any layer that receives an HTTP 401) to signal
    /// that the current auth token has been rejected by the server.
    static let authDidInvalidate = Notification.Name("authDidInvalidate")
}

// MARK: - AuthViewModel

@MainActor
@Observable
final class AuthViewModel {

    // MARK: - Published State

    var isAuthenticated: Bool = false
    var currentUser: TSUserInfo?
    var isLoading: Bool = false
    var errorMessage: String?
    var requiresTwoFactor: Bool = false
    var tempToken: String?
    var showForceUpdate: Bool = false

    // MARK: - AppStorage

    @ObservationIgnored
    @AppStorage("userEmail") var userEmail: String = ""

    // MARK: - Private

    /// Timestamp of the most recent successful login, used to apply a grace
    /// period before acting on auth-invalidation notifications.
    private var loginTimestamp: Date?
    @ObservationIgnored
    private var authObserverTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        checkAuthState()
        startAuthInvalidationObserver()
        startWakeObserver()
    }

    deinit {
        authObserverTask?.cancel()
    }

    // MARK: - Auth State

    /// Restores the authenticated session from the Keychain on app launch.
    /// Validates the token against the backend but never auto-logouts on failure.
    func checkAuthState() {
        if let token = KeychainService.shared.load(for: "authToken"), !token.isEmpty {
            isAuthenticated = true
            logger.info("Auth state restored from Keychain.")

            // Validate token in background — never logout on failure
            Task {
                do {
                    _ = try await APIService.shared.getProfiles()
                    logger.info("Token validated against backend.")
                } catch {
                    logger.warning("Token validation failed: \(error.localizedDescription) — user stays authenticated.")
                    // Show non-disruptive message if needed — the user stays logged in
                }
            }
        } else {
            isAuthenticated = false
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        requiresTwoFactor = false
        tempToken = nil

        do {
            let response = try await APIService.shared.login(email: email, password: password)

            if response.requiresTwoFactor == true, let tt = response.tempToken {
                // 2FA is required — hold state for the verification step
                requiresTwoFactor = true
                tempToken = tt
                userEmail = email
                isLoading = false
                return
            }

            // Standard login: persist token and mark authenticated
            let token = response.token ?? ""
            guard !token.isEmpty else {
                errorMessage = "Geen token ontvangen van de server."
                isLoading = false
                return
            }
            KeychainService.shared.save(token, for: "authToken")

            // Save biometric token opportunistically so Face ID / Touch ID
            // can be offered on next launch.
            if BiometricService.shared.isEnabled {
                do {
                    try await BiometricService.shared.saveTokenWithBiometrics(token)
                } catch {
                    logger.error("Failed to save biometric token: \(error.localizedDescription)")
                }
            }

            let userInfo: TSUserInfo?
            do {
                userInfo = try await APIService.shared.getCurrentUser()
            } catch {
                logger.error("Failed to fetch current user after login: \(error.localizedDescription)")
                userInfo = nil
            }

            currentUser = userInfo
            userEmail = email
            loginTimestamp = Date()
            isAuthenticated = true
            isLoading = false

            logger.info("Login succeeded for \(email, privacy: .private).")

        } catch {
            isLoading = false
            errorMessage = dutchErrorMessage(for: error)
            logger.error("Login failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Two-Factor Verification

    func verifyTwoFactor(code: String) async {
        guard let tt = tempToken else {
            errorMessage = "Ongeldige sessie. Log opnieuw in."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await APIService.shared.verifyTwoFactor(username: userEmail, tempToken: tt, code: code)

            let token = response.token ?? ""
            guard !token.isEmpty else {
                errorMessage = "Geen token ontvangen van de server."
                isLoading = false
                return
            }
            KeychainService.shared.save(token, for: "authToken")

            if BiometricService.shared.isEnabled {
                do {
                    try await BiometricService.shared.saveTokenWithBiometrics(token)
                } catch {
                    logger.error("Failed to save biometric token after 2FA: \(error.localizedDescription)")
                }
            }

            let userInfo: TSUserInfo?
            do {
                userInfo = try await APIService.shared.getCurrentUser()
            } catch {
                logger.error("Failed to fetch current user after 2FA: \(error.localizedDescription)")
                userInfo = nil
            }

            currentUser = userInfo
            userEmail = userInfo?.email ?? userEmail
            loginTimestamp = Date()
            isAuthenticated = true
            requiresTwoFactor = false
            tempToken = nil
            isLoading = false

            logger.info("Two-factor verification succeeded.")

        } catch {
            isLoading = false
            errorMessage = dutchErrorMessage(for: error)
            logger.error("Two-factor verification failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Biometric Login

    func loginWithBiometrics() async {
        guard BiometricService.shared.isEnabled else {
            errorMessage = "Biometrisch inloggen is niet ingeschakeld."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
#if os(macOS)
            // macOS requires passing the authenticated LAContext explicitly to
            // access the Keychain item that is protected by biometry.
            let (success, context) = try await BiometricService.shared.authenticateWithContext()
            guard success else {
                isLoading = false
                errorMessage = "Biometrische verificatie mislukt."
                return
            }
            guard let token = try await BiometricService.shared.loadBiometricToken(context: context),
                  !token.isEmpty else {
                isLoading = false
                errorMessage = "Geen biometrisch token gevonden. Log eerst in met e-mail en wachtwoord."
                return
            }
#else
            // iOS handles biometric prompting automatically via Keychain ACL.
            let success = try await BiometricService.shared.authenticate()
            guard success else {
                isLoading = false
                errorMessage = "Biometrische verificatie mislukt."
                return
            }
            guard let token = try await BiometricService.shared.loadBiometricToken(),
                  !token.isEmpty else {
                isLoading = false
                errorMessage = "Geen biometrisch token gevonden. Log eerst in met e-mail en wachtwoord."
                return
            }
#endif

            KeychainService.shared.save(token, for: "authToken")

            let userInfo: TSUserInfo?
            do {
                userInfo = try await APIService.shared.getCurrentUser()
            } catch {
                logger.error("Failed to fetch current user after biometric login: \(error.localizedDescription)")
                userInfo = nil
            }
            currentUser = userInfo
            loginTimestamp = Date()
            isAuthenticated = true
            isLoading = false

            logger.info("Biometric login succeeded.")

        } catch {
            isLoading = false
            errorMessage = dutchErrorMessage(for: error)
            logger.error("Biometric login error: \(error.localizedDescription)")
        }
    }

    // MARK: - Logout

    func logout() {
        KeychainService.shared.delete(for: "authToken")
        // Keep the biometric token so Face ID / Touch ID login works on next launch.
        // Only remove it when the user explicitly disables biometric login in Settings.

        isAuthenticated = false
        currentUser = nil
        requiresTwoFactor = false
        tempToken = nil
        errorMessage = nil
        loginTimestamp = nil

        logger.info("User logged out.")
    }

    // MARK: - Error Localisation

    /// Returns a Dutch error message suitable for display to the user.
    /// APIError and URLValidationError already provide Dutch descriptions;
    /// for other errors a generic fallback is used.
    private func dutchErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        if let urlError = error as? URLValidationError {
            return urlError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Geen internetverbinding. Controleer je netwerk en probeer het opnieuw."
            case .timedOut:
                return "De server reageert niet. Probeer het later opnieuw."
            case .cannotFindHost, .cannotConnectToHost:
                return "Kan geen verbinding maken met de server."
            default:
                return "Netwerkfout. Probeer het later opnieuw."
            }
        }
        return "Er is een onverwachte fout opgetreden. Probeer het opnieuw."
    }

    // MARK: - Auth Invalidation Observer

    /// Listens for `.authDidInvalidate` notifications using Swift Concurrency's
    /// `NotificationCenter.notifications(named:)` API.
    ///
    /// IMPORTANT: Never auto-logout. The user stays authenticated until they
    /// explicitly log out. Auth errors are logged but do not trigger logout,
    /// preventing recording loss during transient 401 responses.
    private func startAuthInvalidationObserver() {
        authObserverTask = Task { [weak self] in
            // IMPORTANT: Use notifications(named:) — NOT notifications(for:)
            // Swift's async NotificationCenter API requires the `named:` label.
            for await _ in NotificationCenter.default.notifications(named: .authDidInvalidate) {
                guard let self else { return }

                // Log the event but never logout — token stays in Keychain
                logger.warning("Auth invalidation received — ignoring, user stays authenticated. Token will be retried automatically.")
            }
        }
    }

    // MARK: - Wake Observer

    /// Re-validates the auth token after system wake from sleep.
    /// If the token is no longer valid, the 401 retry in APIService will handle
    /// transient issues. We never auto-logout here.
    private func startWakeObserver() {
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                guard let self, isAuthenticated else { continue }
                logger.info("System wake — validating auth token")
                do {
                    _ = try await APIService.shared.getProfiles()
                    logger.info("Token still valid after wake.")
                } catch {
                    logger.warning("Token validation failed after wake: \(error.localizedDescription) — user stays authenticated.")
                }
            }
        }
    }
}
