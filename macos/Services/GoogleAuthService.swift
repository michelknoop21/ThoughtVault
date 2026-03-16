import Foundation
import AuthenticationServices
import OSLog
import CommonCrypto

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "GoogleAuth")

// MARK: - GoogleAuthService

/// Handles Google OAuth (PKCE) for YouTube captions access.
actor GoogleAuthService {

    static let shared = GoogleAuthService()

    // MARK: - Configuration

    private(set) var clientId: String?

    // MARK: - Token State

    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private(set) var tokenExpiry: Date?
    private(set) var accountEmail: String?

    var isConnected: Bool {
        accessToken != nil && accountEmail != nil
    }

    // MARK: - Constants

    nonisolated private let scopes = ["https://www.googleapis.com/auth/youtube.force-ssl"]
    nonisolated private let redirectURI = "transcript-studio://google/callback"

    // MARK: - PKCE State

    private var codeVerifier: String?
    private var oauthState: String?

    // MARK: - Init

    private init() {
        // Restore refresh token from Keychain on init
        if let saved = KeychainService.shared.load(for: "googleRefreshToken") {
            self.refreshToken = saved
        }
    }

    // MARK: - Configuration

    func configure(clientId: String?) {
        self.clientId = clientId
    }

    var isConfigured: Bool {
        clientId != nil && !(clientId?.isEmpty ?? true)
    }

    // MARK: - Fetch Config from Backend

    func fetchOAuthConfig() async {
        do {
            let features = try await APIService.shared.fetchFeaturesExtended()
            if let clientId = features.google_oauth_client_id_macos, !clientId.isEmpty {
                self.clientId = clientId
            }
        } catch {
            logger.error("Failed to fetch Google OAuth config: \(error.localizedDescription)")
        }
    }

    // MARK: - OAuth Flow

    @MainActor
    func initiateAuth() async throws {
        let service = GoogleAuthService.shared
        let clientId = await service.clientId

        guard let clientId, !clientId.isEmpty else {
            throw GoogleAuthError.notConfigured
        }

        // Generate PKCE challenge
        let verifier = Self.generateCodeVerifier()
        let challenge = try Self.generateCodeChallenge(verifier: verifier)
        await service.setCodeVerifier(verifier)

        let state = UUID().uuidString
        await service.setOAuthState(state)

        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw GoogleAuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: service.redirectURI),
            URLQueryItem(name: "scope", value: service.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            throw GoogleAuthError.invalidURL
        }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "transcript-studio"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleAuthError.authCancelled)
                }
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = GoogleAuthPresentationContext.shared
            session.start()
        }

        // Extract authorization code
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.noAuthCode
        }

        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        let expectedState = await service.oauthState
        if returnedState != expectedState {
            throw GoogleAuthError.invalidURL
        }

        // Exchange code for tokens
        try await service.exchangeCodeForTokens(code: code)
    }

    private func setCodeVerifier(_ verifier: String) {
        self.codeVerifier = verifier
    }

    private func setOAuthState(_ state: String) {
        self.oauthState = state
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String) async throws {
        guard let clientId else {
            throw GoogleAuthError.notConfigured
        }
        guard let verifier = codeVerifier else {
            throw GoogleAuthError.missingVerifier
        }

        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleAuthError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            logger.error("Token exchange failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw GoogleAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)

        // Fetch user email
        let email = try await fetchUserEmail(accessToken: tokenResponse.access_token)
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        self.accessToken = tokenResponse.access_token
        self.refreshToken = tokenResponse.refresh_token ?? self.refreshToken
        self.tokenExpiry = expiry
        self.accountEmail = email
        self.codeVerifier = nil
        self.oauthState = nil

        // Persist refresh token to Keychain
        if let refresh = self.refreshToken {
            KeychainService.shared.save(refresh, for: "googleRefreshToken")
        }

        logger.info("Google connected for \(email)")
    }

    // MARK: - User Profile

    private func fetchUserEmail(accessToken: String) async throws -> String {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else {
            throw GoogleAuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let userInfo = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
        return userInfo.email ?? "unknown"
    }

    // MARK: - Token Management

    /// Returns a valid access token, refreshing if needed.
    func getValidToken() async -> String? {
        // Check if current token is still valid (with 60s margin)
        if let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return accessToken
        }

        // Try to refresh
        if refreshToken != nil {
            do {
                try await refreshAccessToken()
                return accessToken
            } catch {
                logger.error("Token refresh failed: \(error.localizedDescription)")
            }
        }

        return nil
    }

    private func refreshAccessToken() async throws {
        guard let clientId, let refreshToken else {
            throw GoogleAuthError.notConfigured
        }

        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleAuthError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            logger.error("Token refresh failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw GoogleAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)

        self.accessToken = tokenResponse.access_token
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        // Google may issue a new refresh token
        if let newRefresh = tokenResponse.refresh_token {
            self.refreshToken = newRefresh
            KeychainService.shared.save(newRefresh, for: "googleRefreshToken")
        }

        logger.info("Google access token refreshed")
    }

    // MARK: - Disconnect

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        accountEmail = nil
        KeychainService.shared.delete(for: "googleRefreshToken")
        logger.info("Google disconnected")
    }

    // MARK: - PKCE Helpers

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateCodeChallenge(verifier: String) throws -> String {
        guard let data = verifier.data(using: .utf8) else {
            throw GoogleAuthError.invalidURL
        }
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Errors

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case invalidURL
    case authCancelled
    case noAuthCode
    case missingVerifier
    case tokenExchangeFailed
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google OAuth is niet geconfigureerd door de beheerder."
        case .invalidURL: return "Ongeldige OAuth URL."
        case .authCancelled: return "Authenticatie geannuleerd."
        case .noAuthCode: return "Geen autorisatiecode ontvangen."
        case .missingVerifier: return "PKCE code verifier ontbreekt."
        case .tokenExchangeFailed: return "Token uitwisseling mislukt."
        case .tokenRefreshFailed: return "Token vernieuwen mislukt. Log opnieuw in met Google."
        }
    }
}

// MARK: - Presentation Context

@MainActor
private final class GoogleAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #endif
    }
}

// MARK: - Google API Response Models

private struct GoogleTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String?
}

private struct GoogleUserInfo: Decodable {
    let email: String?
}
