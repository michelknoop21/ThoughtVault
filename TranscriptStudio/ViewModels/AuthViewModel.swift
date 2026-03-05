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
    }

    deinit {
        authObserverTask?.cancel()
    }

    // MARK: - Auth State

    /// Restores the authenticated session from the Keychain on app launch.
    func checkAuthState() {
        if let token = KeychainService.shared.load(for: "authToken"), !token.isEmpty {
            isAuthenticated = true
            logger.info("Auth state restored from Keychain.")
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
                try? await BiometricService.shared.saveTokenWithBiometrics(token)
            }

            let userInfo = try? await APIService.shared.getCurrentUser()

            currentUser = userInfo
            userEmail = email
            loginTimestamp = Date()
            isAuthenticated = true
            isLoading = false

            logger.info("Login succeeded for \(email, privacy: .private).")

        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
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
            let response = try await APIService.shared.verifyTwoFactor(tempToken: tt, code: code)

            let token = response.token ?? ""
            guard !token.isEmpty else {
                errorMessage = "Geen token ontvangen van de server."
                isLoading = false
                return
            }
            KeychainService.shared.save(token, for: "authToken")

            if BiometricService.shared.isEnabled {
                try? await BiometricService.shared.saveTokenWithBiometrics(token)
            }

            let userInfo = try? await APIService.shared.getCurrentUser()

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
            errorMessage = error.localizedDescription
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

            let userInfo = try? await APIService.shared.getCurrentUser()
            currentUser = userInfo
            loginTimestamp = Date()
            isAuthenticated = true
            isLoading = false

            logger.info("Biometric login succeeded.")

        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            logger.error("Biometric login error: \(error.localizedDescription)")
        }
    }

    // MARK: - Logout

    func logout() {
        KeychainService.shared.delete(for: "authToken")
        BiometricService.shared.removeBiometricToken()

        isAuthenticated = false
        currentUser = nil
        requiresTwoFactor = false
        tempToken = nil
        errorMessage = nil
        loginTimestamp = nil

        logger.info("User logged out.")
    }

    // MARK: - Auth Invalidation Observer

    /// Listens for `.authDidInvalidate` notifications using Swift Concurrency's
    /// `NotificationCenter.notifications(named:)` API.
    ///
    /// A 10-second grace period is applied after login to avoid a race condition
    /// where in-flight requests started just before login resolve with a stale
    /// token. Up to 3 failures within that window are tolerated before forcing
    /// logout.
    private func startAuthInvalidationObserver() {
        authObserverTask = Task { [weak self] in
            var recentFailureCount = 0

            // IMPORTANT: Use notifications(named:) — NOT notifications(for:)
            // Swift's async NotificationCenter API requires the `named:` label.
            for await _ in NotificationCenter.default.notifications(named: .authDidInvalidate) {
                guard let self else { return }

                // Apply grace period: ignore failures within 10 seconds of login
                if let loginTime = self.loginTimestamp,
                   Date().timeIntervalSince(loginTime) < 10 {
                    recentFailureCount += 1
                    if recentFailureCount <= 3 {
                        logger.debug("Auth invalidation within grace period (failure \(recentFailureCount)/3) — ignoring.")
                        continue
                    }
                } else {
                    // Reset counter outside of grace period
                    recentFailureCount = 0
                }

                logger.warning("Auth token invalidated by server — forcing logout.")
                self.logout()

                // Reset after a forced logout so subsequent logins start fresh
                recentFailureCount = 0
            }
        }
    }
}
