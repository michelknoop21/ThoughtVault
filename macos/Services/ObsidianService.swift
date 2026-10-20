// ObsidianService.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Writes notulen to an Obsidian vault through the Obsidian Local REST API
// plugin: PUT /vault/{path} with a Bearer key and `text/markdown` body. The
// plugin serves HTTPS on 127.0.0.1 with a self-signed certificate, so TLS
// validation is accepted for the loopback host only (see LoopbackTrustDelegate).

import Foundation
import OSLog
import CryptoKit

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "ObsidianService")

struct ObsidianService: Sendable {

    // Settings keys. base-URL / vault-path / enable mirror @AppStorage in
    // SettingsView; the API key lives in the Keychain.
    static let enabledKey = "obsidianEnabled"
    static let baseURLKey = "obsidianBaseURL"
    static let vaultPathKey = "obsidianVaultPath"
    static let apiKeyKeychainKey = "obsidianApiKey"
    static let defaultBaseURL = "https://127.0.0.1:27124"

    private let baseURL: String
    private let vaultPath: String
    private let apiKey: String
    private let session: URLSession

    init(baseURL: String? = nil, vaultPath: String? = nil, apiKey: String? = nil) {
        let d = UserDefaults.standard
        var base = (baseURL ?? d.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }   // avoid `//` → 404
        self.baseURL = base
        self.vaultPath = (vaultPath ?? d.string(forKey: Self.vaultPathKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey ?? KeychainService.shared.load(for: Self.apiKeyKeychainKey) ?? ""
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: LoopbackTrustDelegate(),
            delegateQueue: nil
        )
    }

    /// Auto-export is on when the user enabled the integration in Settings.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private func localURL(_ path: String) -> URL? {
        guard let base = URL(string: baseURL),
              ["http", "https"].contains(base.scheme ?? ""),
              ["127.0.0.1", "localhost", "::1"].contains(base.host ?? ""),
              base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else { return nil }
        return URL(string: baseURL + path)
    }

    enum ObsidianError: LocalizedError {
        case missingConfig
        case badStatus(Int, String)
        case externallyChanged

        var errorDescription: String? {
            switch self {
            case .missingConfig:
                return "Vul eerst de Obsidian base-URL, vault-pad en API-sleutel in."
            case .badStatus(let code, let detail):
                return "Obsidian gaf status \(code)\(detail.isEmpty ? "" : ": \(detail)")."
            case .externallyChanged:
                return "Deze notule is gewijzigd in Obsidian. Haal die versie eerst op voordat je exporteert."
            }
        }
    }

    // MARK: - Connection test

    /// GET / with the Bearer key; succeeds when the plugin reports `authenticated:true`.
    func testConnection() async -> Result<Void, Error> {
        guard !apiKey.isEmpty, let url = localURL("/") else {
            return .failure(ObsidianError.missingConfig)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            // The plugin returns pretty-printed JSON (`"authenticated": true`), so
            // match whitespace-tolerantly rather than on an exact substring.
            let authenticated = body.range(
                of: "\"authenticated\"\\s*:\\s*true", options: .regularExpression
            ) != nil
            if (200..<300).contains(code) && authenticated {
                return .success(())
            }
            let detail = (200..<300).contains(code)
                ? "API-sleutel niet geaccepteerd"
                : (code == 401 ? "ongeldige API-sleutel" : "")
            return .failure(ObsidianError.badStatus(code, detail))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Export

    private static func syncKey(_ filename: String) -> String { "obsidianSync-\(filename)" }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func acknowledgeImport(filename: String, markdown: String) {
        if VaultFolderStore.isConfigured {
            VaultFolderStore.acknowledgeImport(filename: filename, markdown: markdown)
        } else {
            UserDefaults.standard.set(digest(markdown), forKey: syncKey(filename))
        }
    }

    private func noteURL(filename: String) -> URL? {
        let path = vaultPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + filename
        let encoded = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return localURL("/vault/" + encoded)
    }

    private func readRemote(filename: String) async throws -> String? {
        guard !apiKey.isEmpty, let url = noteURL(filename: filename) else { throw ObsidianError.missingConfig }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw ObsidianError.badStatus(status, "") }
        return String(data: data, encoding: .utf8)
    }

    static func readNote(title: String, date: Date, noteID: String) async throws -> (filename: String, markdown: String, html: String) {
        var filename = fileName(title: title, date: date, noteID: noteID)
        var markdown: String?
        if VaultFolderStore.isConfigured {
            markdown = VaultFolderStore.readNote(filename: filename)
        } else {
            markdown = try await ObsidianService().readRemote(filename: filename)
        }
        if markdown == nil {
            filename = fileName(title: title, date: date)
            if VaultFolderStore.isConfigured {
                markdown = VaultFolderStore.readNote(filename: filename)
            } else {
                markdown = try await ObsidianService().readRemote(filename: filename)
            }
        }
        guard let markdown else { throw ObsidianError.badStatus(404, "Notule niet gevonden") }
        return (filename, markdown, markdownToNotuleHTML(markdown))
    }

    /// Convenience over a (non-Sendable) record: reads its fields on the MainActor,
    /// then performs the network export with value types only.
    @MainActor
    func export(_ record: TranscriptRecord) async throws {
        let title = record.title
        let html = record.notuleHtml
        let date = record.createdAt
        let participants = record.participants
        let profileName = record.profileName
        let profileId = record.profileId
        let tags = record.tags
        try await export(
            title: title, html: html, date: date,
            participants: participants, profileName: profileName, profileId: profileId, tags: tags,
            noteID: record.taskId
        )
    }

    /// Static convenience for manual export from a local record. Prefers the
    /// file-based vault folder, falls back to REST. Throws on failure.
    @MainActor
    static func tryExport(_ record: TranscriptRecord) async throws {
        try await tryExport(
            title: record.title,
            html: record.notuleHtml,
            date: record.createdAt,
            participants: record.participants,
            profileName: record.profileName,
            profileId: record.profileId,
            tags: record.tags,
            noteID: record.taskId
        )
    }

    func export(
        title: String,
        html: String,
        date: Date,
        participants: [Participant],
        profileName: String?,
        profileId: String? = nil,
        tags: [String],
        noteID: String? = nil
    ) async throws {
        guard !apiKey.isEmpty, !vaultPath.isEmpty else { throw ObsidianError.missingConfig }

        let filename = Self.fileName(title: title, date: date, noteID: noteID)
        let rawPath = vaultPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + filename
        let encodedPath = rawPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = localURL("/vault/" + encodedPath) else {
            throw ObsidianError.missingConfig
        }

        let body = Self.frontmatter(
            title: title, date: date, participants: participants,
            profileName: profileName, profileId: profileId, tags: tags, noteID: noteID
        ) + htmlToMarkdown(html) + "\n"

        if let existing = try await readRemote(filename: filename), existing != body,
           UserDefaults.standard.string(forKey: Self.syncKey(filename)) != Self.digest(existing) {
            throw ObsidianError.externallyChanged
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("text/markdown", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ObsidianError.badStatus(code, String(data: data, encoding: .utf8) ?? "")
        }
        Self.acknowledgeImport(filename: filename, markdown: body)
    }

    /// Single auto-export entry point: no-op when disabled, fails silently with a
    /// log so it never blocks the processing pipeline. Reads the (non-Sendable)
    /// record on the MainActor and hands only value types to the detached task.
    @MainActor
    static func autoExport(_ record: TranscriptRecord) {
        guard isEnabled else { return }
        tryExportDetached(
            title: record.title,
            html: record.notuleHtml,
            date: record.createdAt,
            participants: record.participants,
            profileName: record.profileName,
            profileId: record.profileId,
            tags: record.tags,
            noteID: record.taskId
        )
    }

    /// Shared auto-export entry point used by both local and cloud notulen.
    /// Prefers the file-based vault folder (the only path that works on iOS),
    /// falls back to the REST API (desktop only). Runs on a detached task and
    /// logs failures silently.
    static func tryExportDetached(
        title: String,
        html: String,
        date: Date,
        participants: [Participant],
        profileName: String?,
        profileId: String? = nil,
        tags: [String],
        noteID: String? = nil
    ) {
        // Prefer the file-based vault folder when configured — it is the only path
        // that works on iOS and needs no REST plugin running.
        if VaultFolderStore.isConfigured {
            let filename = Self.fileName(title: title, date: date, noteID: noteID)
            let markdown = Self.frontmatter(
                title: title, date: date, participants: participants,
                profileName: profileName, profileId: profileId, tags: tags, noteID: noteID
            ) + htmlToMarkdown(html) + "\n"
            if VaultFolderStore.writeNote(filename: filename, markdown: markdown) != .written {
                logger.error("Export naar Obsidian-map mislukt")
            }
            return
        }

        let service = ObsidianService()
        Task.detached {
            do {
                try await service.export(
                    title: title, html: html, date: date,
                    participants: participants, profileName: profileName, profileId: profileId, tags: tags,
                    noteID: noteID
                )
            } catch {
                logger.error("Export naar Obsidian mislukt: \(error.localizedDescription)")
            }
        }
    }

    /// Synchronous export used by manual export buttons. Prefers the file-based
    /// vault folder (iOS-capable), falls back to the REST API. Throws on failure
    /// so the caller can surface an error to the user.
    @MainActor
    static func tryExport(
        title: String,
        html: String,
        date: Date,
        participants: [Participant],
        profileName: String?,
        profileId: String? = nil,
        tags: [String],
        noteID: String? = nil
    ) async throws {
        // Prefer the file-based vault folder when configured.
        if VaultFolderStore.isConfigured {
            let filename = Self.fileName(title: title, date: date, noteID: noteID)
            let markdown = Self.frontmatter(
                title: title, date: date, participants: participants,
                profileName: profileName, profileId: profileId, tags: tags, noteID: noteID
            ) + htmlToMarkdown(html) + "\n"
            switch VaultFolderStore.writeNote(filename: filename, markdown: markdown) {
            case .written: break
            case .externallyChanged: throw ObsidianError.externallyChanged
            case .failed: throw ObsidianError.badStatus(0, "Kon niet naar de vault-map schrijven")
            }
            return
        }

        // Fall back to the REST API (desktop only).
        try await ObsidianService().export(
            title: title, html: html, date: date,
            participants: participants, profileName: profileName, profileId: profileId, tags: tags,
            noteID: noteID
        )
    }

    // MARK: - Builders

    /// `{yyyy-MM-dd}-{kebab-title}.md`, matching the vault's note-naming convention.
    static func fileName(title: String, date: Date, noteID: String? = nil) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let slug = slugify(noteID ?? title)
        return slug.isEmpty ? "\(df.string(from: date))-notule.md" : "\(df.string(from: date))-\(slug).md"
    }

    /// Lowercase, hyphen-separated slug: keeps letters/digits, everything else
    /// becomes a single hyphen.
    static func slugify(_ s: String) -> String {
        let mapped = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var slug = String(mapped)
        slug = slug.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// YAML frontmatter block (kept in sync with the Windows side).
    static func frontmatter(
        title: String,
        date: Date,
        participants: [Participant],
        profileName: String?,
        profileId: String? = nil,
        tags: [String],
        noteID: String? = nil
    ) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        func yaml(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }

        // The "notitie" profile produces notes, not meeting minutes.
        let noteType = profileId == "notitie" ? "notitie" : "notulen"
        // For notes, tags start with the type; for notulen they start with "notule".
        let baseTag = profileId == "notitie" ? "notitie" : "notule"

        var lines = ["---"]
        lines.append("type: \(noteType)")
        if let noteID { lines.append("thoughtvault_id: \(yaml(noteID))") }
        lines.append("title: \(yaml(title))")
        lines.append("date: \(df.string(from: date))")
        if !participants.isEmpty {
            lines.append("participants:")
            for p in participants {
                let role = p.role.trimmingCharacters(in: .whitespaces)
                lines.append("  - " + (role.isEmpty ? p.name : "\(p.name) (\(role))"))
            }
        }
        let allTags = ([baseTag] + tags).map { $0.replacingOccurrences(of: ",", with: " ") }
        lines.append("tags: [\(allTags.joined(separator: ", "))]")
        if let profileName, !profileName.isEmpty {
            lines.append("profile: \(yaml(profileName))")
        }
        lines.append("source: ThoughtVault")
        lines.append("---")
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

// MARK: - LoopbackTrustDelegate

/// Accepts the self-signed server certificate for 127.0.0.1 / localhost only;
/// every other host falls through to default validation.
private final class LoopbackTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              ["127.0.0.1", "localhost"].contains(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
