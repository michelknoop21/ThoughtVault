import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "APIService")

// MARK: - URL Validation Error

enum URLValidationError: LocalizedError {
    case httpsRequired
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .httpsRequired:
            return "De server URL moet HTTPS gebruiken voor een veilige verbinding."
        case .invalidURL:
            return "De opgegeven server URL is ongeldig."
        }
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String?, String?)  // statusCode, message, errorCode
    case decodingError(Error)
    case fileTooLarge
    case sessionExpired
    case networkError(Error)
    case localModeActive

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ongeldige serverrespons ontvangen."
        case .localModeActive:
            // Local mode makes no backend calls. Callers degrade to local data;
            // this message is a benign fallback and should not surface to the user.
            return "Lokale modus actief — geen serververbinding nodig."
        case .httpError(let code, let message, _):
            return message ?? "Serverfout (HTTP \(code))."
        case .decodingError(let error):
            return "Fout bij verwerken van serverrespons: \(error.localizedDescription)"
        case .fileTooLarge:
            return "Het bestand is te groot (maximaal 500 MB). Maak kortere opnames of comprimeer het bestand."
        case .sessionExpired:
            return "Je sessie is verlopen. Log opnieuw in om door te gaan."
        case .networkError:
            return "Kan geen verbinding maken met de server. Controleer je internetverbinding."
        }
    }

    /// Machine-readable error code from the backend, if available.
    var errorCode: String? {
        if case .httpError(_, _, let code) = self { return code }
        return nil
    }
}

// MARK: - Response Models (local API-only types)

struct TSUserInfo: Codable {
    let id: String
    let email: String
    let name: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case email = "username"
        case name
        case role
    }

    var displayName: String {
        name ?? email
    }

    var displayFirstName: String {
        if let name = name, let first = name.split(separator: " ").first {
            return String(first)
        }
        return email
    }
}


struct AdminUser: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let role: String
    let createdAt: String?
    let updatedAt: String?
    let lastLogin: String?
    let twofaEnabled: Bool?
    let noteCount: Int?
    let inviteCodeUsed: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email = "username"
        case name
        case role
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastLogin = "last_login"
        case twofaEnabled = "twofa_enabled"
        case noteCount = "note_count"
        case inviteCodeUsed = "invite_code_used"
    }
}

struct VersionCheckResponse: Codable {
    let minimumVersion: String?
    let currentVersion: String?
    let isSupported: Bool?

    enum CodingKeys: String, CodingKey {
        case minimumVersion = "minimum_version"
        case currentVersion = "current_version"
        case isSupported = "is_supported"
    }
}

// MARK: - APIService

actor APIService {
    static let shared = APIService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private var cachedBaseURL: URL?
    private var cachedRawURL: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
    }

    // MARK: - Configuration Helpers

    private func serverURL() -> String {
        // Read from UserDefaults (AppStorage key "serverURL")
        return UserDefaults.standard.string(forKey: "serverURL") ?? "https://n8n.prezent.nl/tstudio/api"
    }

    private func authToken() -> String? {
        return KeychainService.shared.load(for: "authToken")
    }

    private func validatedBaseURL() throws -> URL {
        var raw = serverURL()
        // Ensure trailing slash for correct relative URL resolution
        if !raw.hasSuffix("/") { raw += "/" }

        // Return cached URL if the raw string hasn't changed
        if raw == cachedRawURL, let cached = cachedBaseURL { return cached }

        guard let url = URL(string: raw) else {
            throw URLValidationError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw URLValidationError.httpsRequired
        }

        cachedBaseURL = url
        cachedRawURL = raw
        return url
    }

    // MARK: - Request Building

    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = "application/json",
        authenticated: Bool = true
    ) throws -> URLRequest {
        // Safety net: in local mode the app must never reach the AWS backend.
        // Every request funnels through here, so guarding it guarantees zero calls
        // even from paths that aren't individually local-mode aware.
        if ProcessingMode.isLocalMode {
            throw APIError.localModeActive
        }
        let base = try validatedBaseURL()
        // Strip leading slash so URL resolves relative to base path (not root)
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: relativePath, relativeTo: base) else {
            throw URLValidationError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body

        if let ct = contentType {
            req.setValue(ct, forHTTPHeaderField: "Content-Type")
        }

        if authenticated, let token = authToken() {
            req.setValue(token, forHTTPHeaderField: "X-User-Token")
        }

        return req
    }

    // MARK: - Response Handling

    private func perform<T: Decodable>(_ req: URLRequest, retries: Int = 2, retriedAuth: Bool = false) async throws -> T {
        do {
            let (data, response) = try await session.data(for: req)
            return try handleResponse(data: data, response: response)
        } catch APIError.sessionExpired where !retriedAuth {
            // Retry 401 once after 2s (transient server issues) — never auto-logout
            logger.warning("401 on \(req.url?.path ?? "?") — retrying in 2s")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await perform(req, retries: retries, retriedAuth: true)
        } catch let apiErr as APIError {
            throw apiErr
        } catch {
            // Retry transient network errors with exponential backoff
            if retries > 0 {
                let delay: UInt64 = retries == 2 ? 1_000_000_000 : 2_000_000_000
                try await Task.sleep(nanoseconds: delay)
                return try await perform(req, retries: retries - 1, retriedAuth: retriedAuth)
            }
            throw APIError.networkError(error)
        }
    }

    private func performVoid(_ req: URLRequest, retries: Int = 2, retriedAuth: Bool = false) async throws {
        do {
            let (data, response) = try await session.data(for: req)
            let _: EmptyResponse = try handleResponse(data: data, response: response)
        } catch APIError.sessionExpired where !retriedAuth {
            logger.warning("401 on \(req.url?.path ?? "?") — retrying in 2s")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await performVoid(req, retries: retries, retriedAuth: true)
        } catch let apiErr as APIError {
            throw apiErr
        } catch {
            if retries > 0 {
                let delay: UInt64 = retries == 2 ? 1_000_000_000 : 2_000_000_000
                try await Task.sleep(nanoseconds: delay)
                return try await performVoid(req, retries: retries - 1, retriedAuth: retriedAuth)
            }
            throw APIError.networkError(error)
        }
    }

    private func handleResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            throw APIError.sessionExpired
        }

        guard (200..<300).contains(http.statusCode) else {
            let (detail, errorCode) = extractErrorInfo(from: data)
            // If backend provides error_code + message, use it directly
            if errorCode != nil, let detail {
                throw APIError.httpError(http.statusCode, detail, errorCode)
            }
            // Fallback: map HTTP status codes to user-friendly Dutch messages
            let message: String
            switch http.statusCode {
            case 403:
                message = detail ?? "Geen toegang."
            case 404:
                message = detail ?? "Niet gevonden."
            case 413:
                throw APIError.fileTooLarge
            case 429:
                message = detail ?? "Te veel verzoeken. Probeer het later opnieuw."
            case 500...:
                message = detail ?? "Serverfout. Probeer het later opnieuw."
            default:
                message = detail ?? "Onverwachte fout (HTTP \(http.statusCode))."
            }
            throw APIError.httpError(http.statusCode, message, nil)
        }

        // Handle empty responses
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding error for \(T.self): \(error)")
            throw APIError.decodingError(error)
        }
    }

    private func extractErrorInfo(from data: Data) -> (message: String?, errorCode: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Non-JSON response (e.g. nginx HTML error page) — don't use as user-facing message
            let raw = String(data: data, encoding: .utf8)
            if let raw, raw.contains("<html") { return (nil, nil) }
            return (raw, nil)
        }
        // Structured error format: error_code + message from backend
        let errorCode = json["error_code"] as? String
        if errorCode != nil, let message = json["message"] as? String {
            return (message, errorCode)
        }
        // Fallback: try legacy formats (detail may be a string or dict)
        let message: String?
        if let detail = json["detail"] as? String {
            message = detail
        } else if let detailDict = json["detail"] as? [String: Any], let msg = detailDict["message"] as? String {
            // APIError wraps detail as {"error_code": ..., "message": ..., "detail": ...}
            return (msg, detailDict["error_code"] as? String)
        } else {
            message = json["message"] as? String ?? json["error"] as? String
        }
        return (message, errorCode)
    }

    // MARK: - Authentication

    func login(email: String, password: String) async throws -> LoginResponse {
        let body = try JSONEncoder().encode(["username": email, "password": password])
        let req = try request(path: "/auth/login", method: "POST", body: body, authenticated: false)
        return try await perform(req)
    }

    func verifyTwoFactor(username: String, tempToken: String, code: String) async throws -> LoginResponse {
        let payload = ["username": username, "temp_token": tempToken, "code": code]
        let body = try JSONEncoder().encode(payload)
        let req = try request(path: "/auth/login/verify-2fa", method: "POST", body: body, authenticated: false)
        return try await perform(req)
    }

    func getCurrentUser() async throws -> TSUserInfo {
        let req = try request(path: "/auth/me", method: "GET")
        return try await perform(req)
    }

    func logout() async {
        // Logout is client-side only: no server endpoint.
        KeychainService.shared.delete(for: "authToken")
    }

    // MARK: - Password & 2FA

    func changePassword(currentPassword: String, newPassword: String) async throws {
        let body = try JSONEncoder().encode([
            "current_password": currentPassword,
            "new_password": newPassword
        ])
        let req = try request(path: "/auth/change-password", method: "POST", body: body)
        try await performVoid(req)
    }

    func get2FAStatus() async throws -> TwoFAStatus {
        let req = try request(path: "/auth/2fa/status", method: "GET")
        return try await perform(req)
    }

    func setup2FA() async throws -> TwoFASetupResponse {
        let req = try request(path: "/auth/2fa/setup", method: "POST")
        return try await perform(req)
    }

    func verify2FASetup(code: String) async throws -> TwoFAVerifyResponse {
        let body = try JSONEncoder().encode(["code": code])
        let req = try request(path: "/auth/2fa/verify-setup", method: "POST", body: body)
        return try await perform(req)
    }

    func disable2FA(password: String) async throws {
        let body = try JSONEncoder().encode(["password": password])
        let req = try request(path: "/auth/2fa/disable", method: "POST", body: body)
        try await performVoid(req)
    }

    func regenerateBackupCodes() async throws -> TwoFAVerifyResponse {
        let req = try request(path: "/auth/2fa/regenerate-backup-codes", method: "POST")
        return try await perform(req)
    }

    func updateUserName(_ name: String) async throws {
        let body = try JSONEncoder().encode(["name": name])
        let req = try request(path: "/auth/update-name", method: "POST", body: body)
        try await performVoid(req)
    }

    // MARK: - Audio Upload

    func uploadAudio(
        fileURL: URL,
        profileId: String,
        usePremium: Bool = false,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptTask {
        // Enforce 500 MB limit (aligned with backend MAX_UPLOAD_SIZE)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        let maxBytes = 500 * 1024 * 1024
        if fileSize > maxBytes {
            throw APIError.fileTooLarge
        }

        let base = try validatedBaseURL()
        guard let url = URL(string: "transcribe", relativeTo: base) else {
            throw URLValidationError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let filename = fileURL.lastPathComponent

        // Build multipart body by streaming audio in chunks to a temp file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("upload_\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let outputStream = OutputStream(url: tempURL, append: false) else {
            throw APIError.invalidResponse
        }
        outputStream.open()
        defer { outputStream.close() }

        func writeString(_ s: String) {
            let data = Data(s.utf8)
            data.withUnsafeBytes { buffer in
                _ = outputStream.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
            }
        }

        // File part header
        writeString("--\(boundary)\r\n")
        writeString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        writeString("Content-Type: audio/wav\r\n\r\n")

        // Stream audio data in 64KB chunks
        guard let inputStream = InputStream(url: fileURL) else {
            throw APIError.invalidResponse
        }
        inputStream.open()
        defer { inputStream.close() }

        let chunkSize = 65_536
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: chunkSize)
            if bytesRead > 0 {
                outputStream.write(buffer, maxLength: bytesRead)
            } else {
                break
            }
        }

        writeString("\r\n")

        // Profile ID field
        writeString("--\(boundary)\r\n")
        writeString("Content-Disposition: form-data; name=\"profile_id\"\r\n\r\n")
        writeString("\(profileId)\r\n")

        // Premium model field
        writeString("--\(boundary)\r\n")
        writeString("Content-Disposition: form-data; name=\"use_premium\"\r\n\r\n")
        writeString("\(usePremium)\r\n")

        writeString("--\(boundary)--\r\n")
        outputStream.close()

        let tempSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path))?[.size] as? Int64 ?? 0
        logger.info("[APIService] uploadAudio: temp file size=\(tempSize)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = authToken() {
            req.setValue(token, forHTTPHeaderField: "X-User-Token")
        }

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        onProgress(0.0)
        logger.info("[APIService] uploadAudio: starting HTTP upload")
        let (data, response) = try await session.upload(for: req, fromFile: tempURL, delegate: delegate)
        onProgress(1.0)

        if let http = response as? HTTPURLResponse {
            logger.info("[APIService] uploadAudio: response status=\(http.statusCode)")
        }

        return try handleResponse(data: data, response: response)
    }

    // MARK: - Text Transcription Upload

    func uploadTranscriptionText(transcription: String, profileId: String, usePremium: Bool = false) async throws -> TranscriptTask {
        let payload: [String: Any] = ["transcription": transcription, "profile_id": profileId, "use_premium": usePremium]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try request(path: "/transcribe-text", method: "POST", body: body)
        return try await perform(req)
    }

    // MARK: - Features

    func fetchFeatures() async throws -> [String: Bool] {
        let req = try request(path: "/features", method: "GET", authenticated: false)
        return try await perform(req)
    }

    struct FeaturesResponse: Decodable {
        let youtube_transcription: Bool?
        let google_oauth_configured: Bool?
        let google_oauth_client_id_macos: String?
    }

    func fetchFeaturesExtended() async throws -> FeaturesResponse {
        let req = try request(path: "/features", method: "GET", authenticated: false)
        return try await perform(req)
    }

    // MARK: - YouTube Transcription

    struct YouTubeTranscribeResponse: Codable {
        let taskId: String
        let status: String
        let message: String?
        let sourceType: String?
        let sourceUrl: String?
        let extractedTitle: String?

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case status
            case message
            case sourceType = "source_type"
            case sourceUrl = "source_url"
            case extractedTitle = "extracted_title"
        }
    }

    func transcribeYouTube(url: String, profileId: String, googleToken: String? = nil) async throws -> TranscriptTask {
        let payload: [String: String] = ["url": url, "profile_id": profileId]
        let body = try JSONEncoder().encode(payload)
        var req = try request(path: "/transcribe-youtube", method: "POST", body: body)
        if let googleToken {
            req.setValue(googleToken, forHTTPHeaderField: "X-Google-Token")
        }
        return try await perform(req)
    }

    // MARK: - Task Streaming

    /// Returns the SSE stream URL and authentication token needed to connect to the task event stream.
    func taskStreamInfo(taskId: String) async throws -> (url: URL, token: String) {
        let base = try validatedBaseURL()
        guard let url = URL(string: "task/\(taskId)/stream", relativeTo: base) else {
            throw URLValidationError.invalidURL
        }
        let token = authToken() ?? ""
        return (url, token)
    }

    func getTaskStatus(taskId: String) async throws -> TranscriptTask {
        let req = try request(path: "/task/\(taskId)")
        return try await perform(req)
    }

    // MARK: - Transcripts

    func getTranscripts(
        search: String? = nil,
        tags: [String]? = nil
    ) async throws -> TranscriptsResponse {
        var components = URLComponents()
        components.queryItems = []
        if let search = search, !search.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }
        if let tags = tags, !tags.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        let queryString = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let req = try request(path: "/transcripts\(queryString)")
        return try await perform(req)
    }

    func getTranscript(taskId: String) async throws -> Transcript {
        let req = try request(path: "/transcripts/\(taskId)")
        let (data, response) = try await session.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.info("GET transcript \(taskId): HTTP \(statusCode), \(data.count) bytes")
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = json.keys.sorted().joined(separator: ", ")
            logger.info("Response keys: \(keys)")
            let notulePresent = json["notule_html"] != nil && !(json["notule_html"] as? String ?? "").isEmpty
            let resultPresent = json["result"] != nil && !(json["result"] as? String ?? "").isEmpty
            let rawPresent = json["raw_transcription"] != nil && !(json["raw_transcription"] as? String ?? "").isEmpty
            logger.info("Content: notule_html=\(notulePresent), result=\(resultPresent), raw_transcription=\(rawPresent)")
        }
        return try handleResponse(data: data, response: response)
    }

    func deleteTranscript(taskId: String) async throws {
        let req = try request(path: "/transcripts/\(taskId)", method: "DELETE")
        try await performVoid(req)
    }

    func updateTranscriptTitle(taskId: String, title: String) async throws {
        let body = try JSONEncoder().encode(["title": title])
        let req = try request(path: "/transcripts/\(taskId)", method: "PATCH", body: body)
        try await performVoid(req)
    }

    func updateTranscriptTags(taskId: String, tags: [String]) async throws {
        let body = try JSONEncoder().encode(["tags": tags])
        let req = try request(path: "/transcripts/\(taskId)", method: "PATCH", body: body)
        try await performVoid(req)
    }

    func updateNotuleHTML(taskId: String, html: String) async throws {
        let body = try JSONEncoder().encode(["notule_html": html])
        let req = try request(path: "/transcripts/\(taskId)", method: "PUT", body: body)
        try await performVoid(req)
    }

    /// Fetch linked notes for a transcript. Returns HTML string if available.
    func getTranscriptNotes(taskId: String) async throws -> String? {
        let req = try request(path: "/transcripts/\(taskId)/notes")
        let (data, response) = try await session.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let array = json as? [[String: Any]], let first = array.first {
                return first["html"] as? String ?? first["notule_html"] as? String
            }
            if let dict = json as? [String: Any] {
                return dict["html"] as? String ?? dict["notule_html"] as? String
            }
        }
        return nil
    }

    // MARK: - Notule Regeneration

    func regenerateNotule(taskId: String, profileId: String, usePremium: Bool = false) async throws -> TranscriptTask {
        let payload: [String: Any] = [
            "transcript_id": taskId,
            "profile_id": profileId,
            "use_premium": usePremium
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try request(path: "/transcripts/\(taskId)/regenerate", method: "POST", body: body)
        return try await perform(req)
    }

    // MARK: - Profiles

    func getProfiles() async throws -> [Profile] {
        let req = try request(path: "/profiles/accessible")
        let wrapper: ProfilesResponse = try await perform(req)
        return wrapper.profiles
    }

    private struct ProfilesResponse: Decodable {
        let profiles: [Profile]
    }

    func createProfile(
        name: String,
        systemPrompt: String,
        notulePrompt: String,
        template: String?
    ) async throws -> Profile {
        var payload: [String: String] = [
            "name": name,
            "systemPrompt": systemPrompt,
            "notulePrompt": notulePrompt,
            "description": name,
            "outputTemplate": template ?? ""
        ]
        if let template = template {
            payload["outputTemplate"] = template
        }
        let body = try JSONEncoder().encode(payload)
        let req = try request(path: "/profiles/me", method: "POST", body: body)
        let response: CreateProfileResponse = try await perform(req)
        return response.profile
    }

    private struct CreateProfileResponse: Decodable {
        let success: Bool
        let profile: Profile
    }

    func deleteProfile(id: String) async throws {
        let req = try request(path: "/profiles/me/\(id)", method: "DELETE")
        try await performVoid(req)
    }

    // MARK: - Settings

    struct MySettingsResponse: Decodable {
        let ms365_client_id: String?
        let ms365_tenant_id: String?
    }

    func getMySettings() async throws -> MySettingsResponse {
        let req = try request(path: "/settings/me")
        return try await perform(req)
    }

    // MARK: - Calendar Tokens

    struct CalendarTokensResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let token_expiry: Double?
        let email: String?
    }

    func getCalendarTokens() async throws -> CalendarTokensResponse {
        let req = try request(path: "/calendar/me")
        return try await perform(req)
    }

    func saveCalendarTokens(accessToken: String, refreshToken: String, tokenExpiry: Double, email: String) async throws {
        let payload: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "token_expiry": tokenExpiry,
            "email": email
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try request(path: "/calendar/me", method: "POST", body: body)
        try await performVoid(req)
    }

    func deleteCalendarTokens() async throws {
        let req = try request(path: "/calendar/me", method: "DELETE")
        try await performVoid(req)
    }

    // MARK: - Version Check

    func checkMinimumVersion() async throws -> Bool {
        let req = try request(path: "/version")
        let response: VersionCheckResponse = try await perform(req)
        return response.isSupported ?? true
    }

    // MARK: - Admin

    func getAdminUsers() async throws -> [AdminUser] {
        struct Wrapper: Decodable { let items: [AdminUser] }
        let req = try request(path: "/admin/users")
        let wrapper: Wrapper = try await perform(req)
        return wrapper.items
    }

    func deleteUser(id: String) async throws {
        let req = try request(path: "/admin/users/\(id)", method: "DELETE")
        try await performVoid(req)
    }

    func getAdminStats() async throws -> AdminStats {
        let req = try request(path: "/admin/metrics")
        return try await perform(req)
    }

    func createUser(email: String, password: String, name: String?, role: String) async throws {
        var payload: [String: String] = ["username": email, "password": password, "role": role]
        if let name = name, !name.isEmpty {
            payload["name"] = name
        }
        let body = try JSONEncoder().encode(payload)
        let req = try request(path: "/admin/users", method: "POST", body: body)
        try await performVoid(req)
    }

    func getAdminInvitations() async throws -> [AdminInvitation] {
        struct Wrapper: Decodable { let items: [AdminInvitation] }
        let req = try request(path: "/admin/invites")
        let wrapper: Wrapper = try await perform(req)
        return wrapper.items
    }

    func createInvitation(maxUses: Int, expiresHours: Int) async throws {
        let payload: [String: Int] = ["max_uses": maxUses, "expires_hours": expiresHours]
        let body = try JSONEncoder().encode(payload)
        let req = try request(path: "/admin/invites", method: "POST", body: body)
        try await performVoid(req)
    }

    func deleteInvitation(code: String) async throws {
        let req = try request(path: "/admin/invites/\(code)", method: "DELETE")
        try await performVoid(req)
    }

    func getAdminFeedback() async throws -> [AdminFeedback] {
        struct Wrapper: Decodable { let items: [AdminFeedback] }
        let req = try request(path: "/admin/feedback")
        let wrapper: Wrapper = try await perform(req)
        return wrapper.items
    }

    func updateAdminFeedback(id: String, status: String, response: String?) async throws {
        var payload: [String: String] = ["status": status]
        if let response = response {
            payload["admin_response"] = response
        }
        let body = try JSONEncoder().encode(payload)
        let req = try request(path: "/admin/feedback/\(id)", method: "PUT", body: body)
        try await performVoid(req)
    }

    func deleteAdminFeedback(id: String) async throws {
        let req = try request(path: "/admin/feedback/\(id)", method: "DELETE")
        try await performVoid(req)
    }

    func getAdminFeedbackPendingCount() async throws -> Int {
        struct CountResponse: Codable { let count: Int }
        let req = try request(path: "/admin/feedback/pending-count")
        let result: CountResponse = try await perform(req)
        return result.count
    }

    func getAdminErrors(
        limit: Int = 500,
        severity: String? = nil,
        userId: String? = nil,
        search: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil
    ) async throws -> [AdminError] {
        struct ErrorsWrapper: Decodable { let errors: [AdminError] }
        struct ItemsWrapper: Decodable { let items: [AdminError] }
        var components = URLComponents()
        components.path = "/admin/errors"
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let severity { queryItems.append(.init(name: "severity", value: severity)) }
        if let userId { queryItems.append(.init(name: "user_id", value: userId)) }
        if let search, !search.isEmpty { queryItems.append(.init(name: "search", value: search)) }
        if let startDate { queryItems.append(.init(name: "start_date", value: startDate)) }
        if let endDate { queryItems.append(.init(name: "end_date", value: endDate)) }
        components.queryItems = queryItems
        let path = components.string ?? "/admin/errors"
        let req = try request(path: path)
        let (data, response) = try await session.data(for: req)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8), nil)
        }
        let decoder = JSONDecoder()
        if let wrapper = try? decoder.decode(ErrorsWrapper.self, from: data) {
            return wrapper.errors
        }
        if let wrapper = try? decoder.decode(ItemsWrapper.self, from: data) {
            return wrapper.items
        }
        return (try? decoder.decode([AdminError].self, from: data)) ?? []
    }

    struct AdminSettingsResponse: Decodable {
        let webhookUrl: String?
        let notificationWebhookUrl: String?
        let ms365_client_id: String?
        let ms365_tenant_id: String?
        let google_oauth_client_id_macos: String?
        let google_oauth_client_id_windows: String?
        let youtube_max_duration_minutes: Int?
        let youtube_cookies_content: String?
        let youtube_extractor_args: String?
        let youtube_proxy: String?
    }

    func getAdminSettings() async throws -> AdminSettingsResponse {
        let req = try request(path: "/admin/settings")
        return try await perform(req)
    }

    func updateAdminSettings(
        ms365ClientId: String?,
        ms365TenantId: String?,
        googleOAuthClientIdMacos: String? = nil,
        googleOAuthClientIdWindows: String? = nil,
        youtubeMaxDurationMinutes: Int? = nil,
        youtubeCookiesContent: String? = nil,
        youtubeExtractorArgs: String? = nil,
        youtubeProxy: String? = nil
    ) async throws {
        var payload: [String: Any] = [:]
        if let clientId = ms365ClientId {
            payload["ms365_client_id"] = clientId
        }
        if let tenantId = ms365TenantId {
            payload["ms365_tenant_id"] = tenantId
        }
        if let gClientId = googleOAuthClientIdMacos {
            payload["google_oauth_client_id_macos"] = gClientId
        }
        if let gClientIdWin = googleOAuthClientIdWindows {
            payload["google_oauth_client_id_windows"] = gClientIdWin
        }
        if let ytMaxDuration = youtubeMaxDurationMinutes {
            payload["youtube_max_duration_minutes"] = ytMaxDuration
        }
        if let ytCookies = youtubeCookiesContent {
            payload["youtube_cookies_content"] = ytCookies
        }
        if let ytExtArgs = youtubeExtractorArgs {
            payload["youtube_extractor_args"] = ytExtArgs
        }
        if let ytProxy = youtubeProxy {
            payload["youtube_proxy"] = ytProxy
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try request(path: "/admin/settings", method: "POST", body: body)
        try await performVoid(req)
    }

    func resetUserPassword(id: String, newPassword: String) async throws {
        let payload = ["password": newPassword]
        let body = try JSONEncoder().encode(payload)
        let req = try request(path: "/admin/users/\(id)/password", method: "POST", body: body)
        try await performVoid(req)
    }

    func resetUser2FA(id: String) async throws {
        let req = try request(path: "/admin/users/\(id)/2fa/reset", method: "POST")
        try await performVoid(req)
    }

    func getAdminActivity(
        limit: Int = 500,
        userId: String? = nil,
        actionType: String? = nil,
        search: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil
    ) async throws -> [AdminActivity] {
        struct ActivitiesWrapper: Decodable { let activities: [AdminActivity] }
        struct ItemsWrapper: Decodable { let items: [AdminActivity] }
        var components = URLComponents()
        components.path = "/admin/activity"
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let userId { queryItems.append(.init(name: "user_id", value: userId)) }
        if let actionType { queryItems.append(.init(name: "action_type", value: actionType)) }
        if let search, !search.isEmpty { queryItems.append(.init(name: "search", value: search)) }
        if let startDate { queryItems.append(.init(name: "start_date", value: startDate)) }
        if let endDate { queryItems.append(.init(name: "end_date", value: endDate)) }
        components.queryItems = queryItems
        let path = components.string ?? "/admin/activity"
        let req = try request(path: path)
        let (data, response) = try await session.data(for: req)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8), nil)
        }
        let decoder = JSONDecoder()
        if let wrapper = try? decoder.decode(ActivitiesWrapper.self, from: data) {
            return wrapper.activities
        }
        if let wrapper = try? decoder.decode(ItemsWrapper.self, from: data) {
            return wrapper.items
        }
        return (try? decoder.decode([AdminActivity].self, from: data)) ?? []
    }

    // MARK: - Task Management

    /// Fetch active tasks for the current user.
    func getActiveTasks() async throws -> [TranscriptTask] {
        struct Wrapper: Decodable { let tasks: [TranscriptTask] }
        let req = try request(path: "/tasks/active")
        let wrapper: Wrapper = try await perform(req)
        return wrapper.tasks
    }

    /// Cancel an in-progress task.
    func cancelTask(taskId: String) async throws {
        let req = try request(path: "/task/\(taskId)/cancel", method: "POST")
        try await performVoid(req)
    }

    /// Delete a task (active or completed).
    func deleteTask(taskId: String) async throws {
        let req = try request(path: "/task/\(taskId)", method: "DELETE")
        try await performVoid(req)
    }
}

// MARK: - Helpers

private struct EmptyResponse: Codable {
    init() {}
    init(from decoder: Decoder) throws {}
}

// MARK: - SSE Notification

extension Notification.Name {
    /// Posted when an SSE client exhausts all reconnection attempts.
    static let sseConnectionFailed = Notification.Name("sseConnectionFailed")
}

// MARK: - SSEClient

/// Connects to a Server-Sent Events stream and delivers parsed events on a callback.
/// Implements automatic reconnection with exponential backoff up to 5 attempts.
final class SSEClient: @unchecked Sendable {
    enum SSEEvent {
        case taskUpdate(TranscriptTask)
        case error(Error)
        case completed
    }

    private let url: URL
    private let token: String
    private var dataTask: URLSessionDataTask?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var isStopped = false
    private var buffer = ""

    var onEvent: ((SSEEvent) -> Void)?

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    func connect() {
        isStopped = false
        reconnectAttempts = 0
        startStream()
    }

    func disconnect() {
        isStopped = true
        dataTask?.cancel()
        dataTask = nil
    }

    private func startStream() {
        guard url.scheme?.lowercased() == "https" else {
            logger.error("SSE connection refused: URL scheme is not HTTPS")
            onEvent?(.error(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-User-Token")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 300

        let session = URLSession(configuration: .default, delegate: SSEDelegate(client: self), delegateQueue: nil)
        dataTask = session.dataTask(with: request)
        dataTask?.resume()
    }

    fileprivate func handleData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Process complete SSE messages (separated by double newline)
        let messages = buffer.components(separatedBy: "\n\n")
        buffer = messages.last ?? ""

        for message in messages.dropLast() {
            parseMessage(message)
        }
    }

    private func parseMessage(_ message: String) {
        var eventType = "message"
        var dataLines: [String] = []

        for line in message.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                eventType = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let dataContent = String(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
                dataLines.append(dataContent)
            }
        }

        let jsonString = dataLines.joined(separator: "\n")
        guard !jsonString.isEmpty, let jsonData = jsonString.data(using: .utf8) else { return }

        // Handle terminal events
        if eventType == "done" || eventType == "completed" {
            onEvent?(.completed)
            return
        }

        // Attempt to decode as TranscriptTask
        do {
            let decoder = JSONDecoder()
            let task = try decoder.decode(TranscriptTask.self, from: jsonData)
            onEvent?(.taskUpdate(task))

            // Stop on terminal task states
            if task.status == .completed || task.status == .error {
                onEvent?(.completed)
            }
        } catch {
            logger.debug("SSE: Could not decode event data as TranscriptTask: \(error)")
        }
    }

    fileprivate func handleCompletion(error: Error?) {
        if isStopped { return }

        if let error = error {
            // Reconnect with exponential backoff
            if reconnectAttempts < maxReconnectAttempts {
                reconnectAttempts += 1
                let backoffSeconds = min(pow(2.0, Double(reconnectAttempts)), 16.0)
                logger.info("SSE: Reconnecting in \(backoffSeconds)s (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(backoffSeconds))
                    guard let self, !self.isStopped else { return }
                    self.startStream()
                }
            } else {
                logger.error("SSE: Max reconnect attempts reached.")
                NotificationCenter.default.post(name: .sseConnectionFailed, object: nil)
                onEvent?(.error(error))
            }
        } else {
            onEvent?(.completed)
        }
    }
}

// MARK: - UploadProgressDelegate

private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(min(fraction, 0.99))
    }
}

// MARK: - SSEDelegate

private class SSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var client: SSEClient?

    init(client: SSEClient) {
        self.client = client
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.handleData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        client?.handleCompletion(error: error)
    }
}
