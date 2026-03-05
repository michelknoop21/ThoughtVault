import Foundation
import AuthenticationServices
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "MicrosoftGraph")

// MARK: - CalendarProvider

enum CalendarProvider: String, Codable, CaseIterable {
    case apple
    case microsoft
}

// MARK: - MicrosoftGraphService

/// Handles Microsoft 365 OAuth (PKCE) and Graph API calendar access.
actor MicrosoftGraphService {

    static let shared = MicrosoftGraphService()

    // MARK: - Configuration

    private(set) var clientId: String?
    private(set) var tenantId: String?

    // MARK: - Token State

    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private(set) var tokenExpiry: Date?
    private(set) var accountEmail: String?

    var isConnected: Bool {
        accessToken != nil && accountEmail != nil
    }

    // MARK: - Constants

    private let scopes = ["User.Read", "Calendars.Read"]
    private let graphBase = "https://graph.microsoft.com/v1.0"
    private let redirectURI = "transcript-studio://auth/callback"

    // MARK: - PKCE State

    private var codeVerifier: String?

    // MARK: - Configuration

    func configure(clientId: String?, tenantId: String?) {
        self.clientId = clientId
        self.tenantId = tenantId
    }

    var isConfigured: Bool {
        clientId != nil && tenantId != nil &&
        !(clientId?.isEmpty ?? true) && !(tenantId?.isEmpty ?? true)
    }

    // MARK: - Fetch Config from Backend

    func fetchOAuthConfig() async {
        do {
            let settings = try await APIService.shared.getMySettings()
            self.clientId = settings.ms365_client_id
            self.tenantId = settings.ms365_tenant_id
            logger.info("OAuth config loaded: configured=\(self.isConfigured)")
        } catch {
            logger.error("Failed to fetch OAuth config: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Tokens from Backend

    func loadTokensFromBackend() async {
        do {
            let tokens = try await APIService.shared.getCalendarTokens()
            if let access = tokens.access_token, !access.isEmpty {
                self.accessToken = access
                self.refreshToken = tokens.refresh_token
                self.accountEmail = tokens.email
                if let expiry = tokens.token_expiry {
                    self.tokenExpiry = Date(timeIntervalSince1970: expiry)
                }
                logger.info("Calendar tokens loaded from backend for \(self.accountEmail ?? "unknown")")
            }
        } catch {
            logger.debug("No calendar tokens on backend: \(error.localizedDescription)")
        }
    }

    // MARK: - OAuth Flow

    @MainActor
    func initiateAuth() async throws {
        let service = MicrosoftGraphService.shared
        let clientId = await service.clientId
        let tenantId = await service.tenantId

        guard let clientId, let tenantId, !clientId.isEmpty, !tenantId.isEmpty else {
            throw MicrosoftGraphError.notConfigured
        }

        // Generate PKCE challenge
        let verifier = Self.generateCodeVerifier()
        let challenge = try Self.generateCodeChallenge(verifier: verifier)
        await service.setCodeVerifier(verifier)

        let state = UUID().uuidString

        var components = URLComponents(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: await service.redirectURI),
            URLQueryItem(name: "scope", value: await service.scopes.joined(separator: " ")),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            throw MicrosoftGraphError.invalidURL
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
                    continuation.resume(throwing: MicrosoftGraphError.authCancelled)
                }
            }

            // Present the auth session
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = AuthPresentationContext.shared
            session.start()
        }

        // Extract authorization code
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw MicrosoftGraphError.noAuthCode
        }

        // Exchange code for tokens
        try await service.exchangeCodeForTokens(code: code)
    }

    private func setCodeVerifier(_ verifier: String) {
        self.codeVerifier = verifier
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String) async throws {
        guard let clientId, let tenantId else {
            throw MicrosoftGraphError.notConfigured
        }
        guard let verifier = codeVerifier else {
            throw MicrosoftGraphError.missingVerifier
        }

        let tokenURL = URL(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "scope": scopes.joined(separator: " "),
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MicrosoftGraphError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        // Get user profile
        let email = try await fetchUserEmail(accessToken: tokenResponse.access_token)
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        self.accessToken = tokenResponse.access_token
        self.refreshToken = tokenResponse.refresh_token
        self.tokenExpiry = expiry
        self.accountEmail = email
        self.codeVerifier = nil

        // Save tokens to backend for cross-device sync
        try? await APIService.shared.saveCalendarTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token ?? "",
            tokenExpiry: expiry.timeIntervalSince1970,
            email: email
        )

        logger.info("Microsoft 365 connected for \(email)")
    }

    // MARK: - User Profile

    private func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(graphBase)/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let profile = try JSONDecoder().decode(GraphUserProfile.self, from: data)
        return profile.mail ?? profile.userPrincipalName ?? "unknown"
    }

    // MARK: - Calendar Events

    func getUpcomingEvents() async -> [CalendarEvent] {
        guard let token = accessToken else { return [] }

        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)
        let formatter = ISO8601DateFormatter()

        var components = URLComponents(string: "\(graphBase)/me/calendarView")!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: formatter.string(from: now)),
            URLQueryItem(name: "endDateTime", value: formatter.string(from: tomorrow)),
            URLQueryItem(name: "$top", value: "20"),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$select", value: "id,subject,start,end,onlineMeeting,organizer,attendees"),
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                // Token expired — disconnect
                await disconnect()
                return []
            }

            let graphResponse = try JSONDecoder().decode(GraphCalendarResponse.self, from: data)
            return graphResponse.value.compactMap { event in
                guard let startStr = event.start?.dateTime,
                      let endStr = event.end?.dateTime else { return nil }

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let startDate = isoFormatter.date(from: startStr + "Z") ?? Date()
                let endDate = isoFormatter.date(from: endStr + "Z") ?? Date()

                let joinURL = event.onlineMeeting?.joinUrl.flatMap { URL(string: $0) }
                let platform = detectPlatform(joinURL: joinURL)

                return CalendarEvent(
                    id: event.id,
                    title: event.subject ?? "Vergadering",
                    date: startDate,
                    endDate: endDate,
                    meetingURL: joinURL,
                    platform: platform,
                    calendarTitle: "Microsoft 365"
                )
            }
        } catch {
            logger.error("Failed to fetch Graph calendar events: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        accountEmail = nil

        try? await APIService.shared.deleteCalendarTokens()
        logger.info("Microsoft 365 disconnected")
    }

    // MARK: - Platform Detection

    private func detectPlatform(joinURL: URL?) -> MeetingPlatform {
        guard let host = joinURL?.host?.lowercased() else { return .other }
        if host.contains("teams.microsoft.com") { return .teams }
        if host.contains("zoom.us") { return .zoom }
        if host.contains("meet.google.com") { return .meet }
        return .other
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
            throw MicrosoftGraphError.invalidURL
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

enum MicrosoftGraphError: LocalizedError {
    case notConfigured
    case invalidURL
    case authCancelled
    case noAuthCode
    case missingVerifier
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Microsoft 365 is niet geconfigureerd door de beheerder."
        case .invalidURL: return "Ongeldige OAuth URL."
        case .authCancelled: return "Authenticatie geannuleerd."
        case .noAuthCode: return "Geen autorisatiecode ontvangen."
        case .missingVerifier: return "PKCE code verifier ontbreekt."
        case .tokenExchangeFailed: return "Token uitwisseling mislukt."
        }
    }
}

// MARK: - Presentation Context

@MainActor
private final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}

// MARK: - Graph API Response Models

private struct OAuthTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String?
}

private struct GraphUserProfile: Decodable {
    let mail: String?
    let userPrincipalName: String?
}

private struct GraphCalendarResponse: Decodable {
    let value: [GraphEvent]
}

private struct GraphEvent: Decodable {
    let id: String
    let subject: String?
    let start: GraphDateTime?
    let end: GraphDateTime?
    let onlineMeeting: GraphOnlineMeeting?
}

private struct GraphDateTime: Decodable {
    let dateTime: String?
    let timeZone: String?
}

private struct GraphOnlineMeeting: Decodable {
    let joinUrl: String?
}

// MARK: - CommonCrypto Import

import CommonCrypto
