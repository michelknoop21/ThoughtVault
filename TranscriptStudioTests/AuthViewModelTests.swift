// AuthViewModelTests.swift
// TranscriptStudioTests
// nl.prezent.TranscriptStudio

import Testing
import Foundation
@testable import TranscriptStudio

@Suite("AuthViewModel Tests")
struct AuthViewModelTests {

    // MARK: - Initial State

    @Test("Initial state is unauthenticated when no token in Keychain")
    @MainActor
    func initialStateUnauthenticated() {
        // Ensure no token exists before test (clean state)
        KeychainService.shared.delete(for: "authToken")

        let vm = AuthViewModel()

        #expect(vm.isAuthenticated == false)
        #expect(vm.currentUser == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.requiresTwoFactor == false)
        #expect(vm.tempToken == nil)
        #expect(vm.showForceUpdate == false)
    }

    @Test("Initial state is authenticated when token exists in Keychain")
    @MainActor
    func initialStateAuthenticatedFromKeychain() {
        // Pre-populate keychain
        KeychainService.shared.save("test-token-abc", for: "authToken")
        defer { KeychainService.shared.delete(for: "authToken") }

        let vm = AuthViewModel()

        #expect(vm.isAuthenticated == true)
    }

    // MARK: - Logout

    @Test("Logout clears authentication state and removes token from Keychain")
    @MainActor
    func logoutClearsState() {
        KeychainService.shared.save("test-token", for: "authToken")
        let vm = AuthViewModel()
        #expect(vm.isAuthenticated == true)

        vm.logout()

        #expect(vm.isAuthenticated == false)
        #expect(vm.currentUser == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.requiresTwoFactor == false)
        #expect(vm.tempToken == nil)

        // Token should be removed from Keychain
        let token = KeychainService.shared.load(for: "authToken")
        #expect(token == nil || token!.isEmpty)
    }

    @Test("Logout is idempotent — safe to call when already logged out")
    @MainActor
    func logoutIdempotent() {
        KeychainService.shared.delete(for: "authToken")
        let vm = AuthViewModel()
        #expect(vm.isAuthenticated == false)

        vm.logout()
        vm.logout()

        #expect(vm.isAuthenticated == false)
    }

    // MARK: - Error State

    @Test("Error message is cleared on new login attempt")
    @MainActor
    func errorMessageClearedOnLogin() async {
        let vm = AuthViewModel()
        vm.errorMessage = "Vorig foutbericht"

        // Trigger a login with invalid credentials (no network required — just check state clears)
        // We set an invalid URL so it fails quickly — errorMessage will be replaced, not nil
        let originalURL = UserDefaults.standard.string(forKey: "serverURL")
        UserDefaults.standard.set("https://localhost:1", forKey: "serverURL")
        defer {
            if let url = originalURL {
                UserDefaults.standard.set(url, forKey: "serverURL")
            } else {
                UserDefaults.standard.removeObject(forKey: "serverURL")
            }
        }

        await vm.login(email: "test@test.nl", password: "wachtwoord")

        // Error message should have changed (new error, not the old message)
        #expect(vm.errorMessage != "Vorig foutbericht")
        #expect(vm.isLoading == false)
    }

    // MARK: - 2FA State

    @Test("Two-factor state is reset on logout")
    @MainActor
    func twoFactorStateResetOnLogout() {
        let vm = AuthViewModel()
        vm.requiresTwoFactor = true
        vm.tempToken = "temp-token-xyz"

        vm.logout()

        #expect(vm.requiresTwoFactor == false)
        #expect(vm.tempToken == nil)
    }

    // MARK: - Auth Notification

    @Test("Auth invalidation notification posts without crashing")
    @MainActor
    func authInvalidationNotificationPosts() async {
        let vm = AuthViewModel()
        _ = vm // keep alive

        // Post the auth invalidation notification — should not crash
        NotificationCenter.default.post(name: .authDidInvalidate, object: nil)

        // Brief pause to allow async task to process
        try? await Task.sleep(for: .milliseconds(50))

        // If we reach here without crash, the test passes
        #expect(Bool(true))
    }

    @Test("authDidInvalidate notification name is correct string")
    func authInvalidateNotificationName() {
        #expect(Notification.Name.authDidInvalidate.rawValue == "authDidInvalidate")
    }
}
