// VaultFolderStore.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// File-based Obsidian vault access. The user picks their vault folder once; we
// keep a security-scoped bookmark and then both READ a context note (names/terms
// fed into PersonalVocabulary) and WRITE notulen as Markdown files into it.
//
// This works identically on macOS and iOS (iCloud Drive or local vaults), unlike
// the Local REST API plugin which is only reachable on the desktop. When a folder
// is configured it becomes the auto-export target; otherwise ObsidianService's
// REST path stays in use (macOS only).

import Foundation
import CryptoKit

private let logger = AppLog(category: "VaultFolderStore")

enum VaultFolderStore {

    // Settings keys.
    static let bookmarkKey = "obsidianVaultBookmark"       // Data (security-scoped)
    static let folderNameKey = "obsidianVaultFolderName"   // String (display only)
    static let contextNoteKey = "obsidianContextNote"      // String, relative path
    static let defaultContextNote = "ThoughtVault/Context.md"

    /// Subfolder inside the vault to write notulen to; reuses the existing REST vault-path setting.
    static var notesSubfolder: String {
        (UserDefaults.standard.string(forKey: ObsidianService.vaultPathKey) ?? "Notulen")
            .trimmingCharacters(in: CharacterSet(charactersIn: " /"))
    }

    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var folderName: String {
        UserDefaults.standard.string(forKey: folderNameKey) ?? ""
    }

    // MARK: - Bookmark lifecycle

    /// Persist a security-scoped bookmark for the user-picked vault folder.
    /// The picked URL comes from `.fileImporter` and is already security-scoped.
    static func setFolder(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let data = try url.bookmarkData(options: [],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderNameKey)
    }

    /// Resolves the bookmark and runs `body` with the security scope active.
    /// Returns nil (and logs) when no folder is configured or the bookmark is unusable.
    /// The three failure points (resolve, scope, body) log distinctly; all of them return nil.
    static func withFolder<T>(_ body: (URL) throws -> T) -> T? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url: URL
        do {
            #if os(macOS)
            url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            url = try URL(resolvingBookmarkData: data, options: [],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
        } catch {
            logger.error("Vault-bookmark onbruikbaar: \(LogRedact.mask(error.localizedDescription)) step=resolve error=\(LogRedact.describe(error))")
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Kon security scope niet openen voor vault-map step=scope stale=\(stale)")
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale {
            logger.info("Vault-bookmark verouderd, wordt vernieuwd")
            try? setFolder(url)   // refresh the bookmark opportunistically
        }
        do {
            return try body(url)
        } catch {
            logger.error("Vault-bestand mislukt: \(LogRedact.mask(error.localizedDescription)) step=body reason=\(failureReason(error, at: nil)) error=\(LogRedact.describe(error))")
            return nil
        }
    }

    /// Reads a vault file as UTF-8; on failure logs why (missing, not downloaded from iCloud, permission) and returns nil.
    private static func readText(_ url: URL, what: String) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            let reason = failureReason(error, at: url)
            let line = "Vault-bestand niet gelezen what=\(what) reason=\(reason) error=\(LogRedact.describe(error))"
            if reason == "missing" { logger.info(line) } else { logger.warning(line) }
            return nil
        }
    }

    /// "missing", "not-downloaded" (iCloud placeholder), "permission-denied" or "other".
    static func failureReason(_ error: Error, at url: URL?) -> String {
        let ns = error as NSError
        let cocoa = ns.domain == NSCocoaErrorDomain
        if cocoa, [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code) { return "permission-denied" }
        if let url {
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
            if status == .notDownloaded || FileManager.default.fileExists(atPath: placeholder.path) { return "not-downloaded" }
        }
        if cocoa, [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(ns.code) { return "missing" }
        return "other"
    }

    // MARK: - Read context note

    /// Raw text of the configured context note, or nil when absent/unconfigured.
    static func readContextNote() -> String? {
        let rel = (UserDefaults.standard.string(forKey: contextNoteKey) ?? defaultContextNote)
            .trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !rel.isEmpty else { return nil }
        return withFolder { root in
            let fileURL = rel.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
            return readText(fileURL, what: "context-note")
        } ?? nil
    }

    /// Parses a context note into biasing terms. The note is expected to be a simple
    /// list (bullet lines and/or comma-separated); headers, frontmatter and long
    /// prose lines are skipped so only term-like tokens are kept.
    static func parseTerms(fromNote text: String) -> [String] {
        var out: [String] = []
        let lines = text.components(separatedBy: .newlines)

        // Skip a leading YAML frontmatter block (--- ... ---) so its keys don't leak in.
        var start = 0
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                start = end + 1
            }
        }

        for rawLine in lines[start...] {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
                line = String(line.dropFirst(bullet.count)); break
            }
            for token in line.components(separatedBy: ",") {
                let t = token.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && t.count <= 40 { out.append(t) }   // ponytail: skip prose sentences
            }
        }
        return out
    }

    // MARK: - Write note

    private static func syncKey(_ filename: String) -> String { "obsidianSync-\(filename)" }

    private static func digest(_ markdown: String) -> String {
        SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func readNote(filename: String) -> String? {
        withFolder { root in
            let dir = notesSubfolder.isEmpty ? root : root.appendingPathComponent(notesSubfolder, isDirectory: true)
            return readText(dir.appendingPathComponent(filename), what: "note")
        } ?? nil
    }

    static func acknowledgeImport(filename: String, markdown: String) {
        UserDefaults.standard.set(digest(markdown), forKey: syncKey(filename))
    }

    /// Writes Markdown into `{notesSubfolder}/{filename}` inside the vault, creating
    /// the subfolder if needed. `.externallyChanged` means the note was edited in
    /// Obsidian since the last sync and was left untouched; `.failed` is an I/O or
    /// access error.
    enum WriteOutcome { case written, externallyChanged, failed }

    @discardableResult
    static func writeNote(filename: String, markdown: String) -> WriteOutcome {
        let result: WriteOutcome? = withFolder { root in
            let dir = notesSubfolder.isEmpty ? root : root.appendingPathComponent(notesSubfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(filename)
            if let existing = try? String(contentsOf: fileURL, encoding: .utf8), existing != markdown {
                guard UserDefaults.standard.string(forKey: syncKey(filename)) == digest(existing) else {
                    logger.warning("Obsidian-notule is extern gewijzigd: \(LogRedact.mask(filename))")
                    return .externallyChanged
                }
            }
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            acknowledgeImport(filename: filename, markdown: markdown)
            return .written
        }
        return result ?? .failed
    }
}
