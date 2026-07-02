// ObsidianService.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Writes notulen to an Obsidian vault through the Obsidian Local REST API
// plugin: PUT /vault/{path} with a Bearer key and `text/markdown` body. The
// plugin serves HTTPS on 127.0.0.1 with a self-signed certificate, so TLS
// validation is accepted for the loopback host only (see LoopbackTrustDelegate).

import Foundation
import OSLog

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

    enum ObsidianError: LocalizedError {
        case missingConfig
        case badStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingConfig:
                return "Vul eerst de Obsidian base-URL, vault-pad en API-sleutel in."
            case .badStatus(let code, let detail):
                return "Obsidian gaf status \(code)\(detail.isEmpty ? "" : ": \(detail)")."
            }
        }
    }

    // MARK: - Connection test

    /// GET / with the Bearer key; succeeds when the plugin reports `authenticated:true`.
    func testConnection() async -> Result<Void, Error> {
        guard !apiKey.isEmpty, let url = URL(string: baseURL + "/") else {
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

    /// Convenience over a (non-Sendable) record: reads its fields on the MainActor,
    /// then performs the network export with value types only.
    @MainActor
    func export(_ record: TranscriptRecord) async throws {
        let title = record.title
        let html = record.notuleHtml
        let date = record.createdAt
        let participants = record.participants
        let profileName = record.profileName
        let tags = record.tags
        try await export(
            title: title, html: html, date: date,
            participants: participants, profileName: profileName, tags: tags
        )
    }

    func export(
        title: String,
        html: String,
        date: Date,
        participants: [Participant],
        profileName: String?,
        tags: [String]
    ) async throws {
        guard !apiKey.isEmpty, !vaultPath.isEmpty else { throw ObsidianError.missingConfig }

        let filename = Self.fileName(title: title, date: date)
        let rawPath = vaultPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + filename
        let encodedPath = rawPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: baseURL + "/vault/" + encodedPath) else {
            throw ObsidianError.missingConfig
        }

        let body = Self.frontmatter(
            title: title, date: date, participants: participants,
            profileName: profileName, tags: tags
        ) + htmlToMarkdown(html) + "\n"

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
    }

    /// Single auto-export entry point: no-op when disabled, fails silently with a
    /// log so it never blocks the processing pipeline. Reads the (non-Sendable)
    /// record on the MainActor and hands only value types to the detached task.
    @MainActor
    static func autoExport(_ record: TranscriptRecord) {
        guard isEnabled else { return }
        let title = record.title
        let html = record.notuleHtml
        let date = record.createdAt
        let participants = record.participants
        let profileName = record.profileName
        let tags = record.tags

        // Prefer the file-based vault folder when configured — it is the only path
        // that works on iOS and needs no REST plugin running.
        if VaultFolderStore.isConfigured {
            let filename = Self.fileName(title: title, date: date)
            let markdown = Self.frontmatter(
                title: title, date: date, participants: participants,
                profileName: profileName, tags: tags
            ) + htmlToMarkdown(html) + "\n"
            if !VaultFolderStore.writeNote(filename: filename, markdown: markdown) {
                logger.error("Auto-export naar Obsidian-map mislukt")
            }
            return
        }

        let service = ObsidianService()
        Task.detached {
            do {
                try await service.export(
                    title: title, html: html, date: date,
                    participants: participants, profileName: profileName, tags: tags
                )
            } catch {
                logger.error("Auto-export naar Obsidian mislukt: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Builders

    /// `{yyyy-MM-dd}-{kebab-title}.md`, matching the vault's note-naming convention.
    static func fileName(title: String, date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let slug = slugify(title)
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
        tags: [String]
    ) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        func yaml(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }

        var lines = ["---"]
        lines.append("type: notulen")
        lines.append("title: \(yaml(title))")
        lines.append("date: \(df.string(from: date))")
        if !participants.isEmpty {
            lines.append("participants:")
            for p in participants {
                let role = p.role.trimmingCharacters(in: .whitespaces)
                lines.append("  - " + (role.isEmpty ? p.name : "\(p.name) (\(role))"))
            }
        }
        let allTags = (["notule"] + tags).map { $0.replacingOccurrences(of: ",", with: " ") }
        lines.append("tags: [\(allTags.joined(separator: ", "))]")
        if let profileName, !profileName.isEmpty {
            lines.append("profile: \(yaml(profileName))")
        }
        lines.append("source: TranscriptStudio")
        lines.append("---")
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

// MARK: - LoopbackTrustDelegate

/// Accepts the self-signed server certificate for 127.0.0.1 / localhost only;
/// every other host falls through to default validation.
private final class LoopbackTrustDelegate: NSObject, URLSessionDelegate, Sendable {
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
