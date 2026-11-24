import Foundation
import Observation
import CryptoKit

struct LibraryEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var name: String
    var kind: String // folder, smart, label
    var labelIDs: [String] = []
    var description = ""
    var automatic = false
    var deleted = false
    var modified = Date()
}

struct NoteOrganization: Codable, Equatable, Sendable {
    var folderID: String?
    var automaticLabelIDs: [String] = []
    var suppressedLabelIDs: [String] = []
}

@MainActor @Observable
final class LibraryOrganization {
    static let shared = LibraryOrganization(url: AppEnvironment.supportDirectory.appending(path: "ThoughtVault/library.json"))
    nonisolated static let syncID = "thoughtvault-library-organization-v1"
    static let didChange = Notification.Name("LibraryOrganizationDidChange")
    private(set) var entries: [LibraryEntry] = []
    private(set) var error: String?
    private let url: URL

    init(url: URL) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                entries = try JSONDecoder().decode([LibraryEntry].self, from: Data(contentsOf: url))
                try Self.validate(entries)
            }
        } catch { self.error = error.localizedDescription }
    }

    var folders: [LibraryEntry] { entries.filter { !$0.deleted && $0.kind == "folder" } }
    var smartFolders: [LibraryEntry] { entries.filter { !$0.deleted && $0.kind == "smart" } }
    var labels: [LibraryEntry] { entries.filter { !$0.deleted && $0.kind == "label" } }

    static func validate(_ entries: [LibraryEntry]) throws {
        guard Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ["folder", "smart", "label"].contains($0.kind) }) else {
            throw NotuleSyncError.invalidData
        }
    }

    private func persist(_ next: [LibraryEntry]) throws {
        guard error == nil else { throw NotuleSyncError.invalidData }
        try Self.validate(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        entries = next
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private static func labelID(_ name: String) -> String {
        "label-" + SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func save(_ entry: LibraryEntry) throws {
        var entry = entry
        entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.kind == "label", !entries.contains(where: { $0.id == entry.id }) {
            entry.id = Self.labelID(entry.name)
            guard !labels.contains(where: { $0.name == entry.name }) else { throw NotuleSyncError.invalidData }
        }
        entry.modified = Date()
        if entry.kind == "smart", entry.labelIDs.isEmpty { throw NotuleSyncError.invalidData }
        try persist(entries.filter { $0.id != entry.id } + [entry])
    }

    func remove(_ entry: LibraryEntry) throws {
        var removed = entry
        removed.deleted = true
        try save(removed)
    }

    func adoptLabels(_ names: [String]) throws {
        var next = entries
        for name in Set(names).sorted() where !labels.contains(where: { $0.name == name }) {
            next.append(LibraryEntry(id: Self.labelID(name), name: name, kind: "label"))
        }
        if next != entries { try persist(next) }
    }

    func merge(_ incoming: [LibraryEntry]) throws {
        try Self.validate(incoming)
        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for entry in incoming {
            if let current = merged[entry.id] {
                // Stable tie-break makes two offline edits converge on both devices.
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                if entry.modified < current.modified { continue }
                if entry.modified == current.modified,
                   try encoder.encode(entry).lexicographicallyPrecedes(encoder.encode(current)) { continue }
            }
            merged[entry.id] = entry
        }
        let next = merged.values.sorted { $0.id < $1.id }
        if next != entries.sorted(by: { $0.id < $1.id }) { try persist(next) }
    }

    func matches(_ selection: String, folderID: String?, tags: [String]) -> Bool {
        if selection == "all" { return true }
        let folder = folders.first { $0.id == folderID }
        if selection == "unfiled" { return folder == nil }
        if let smart = smartFolders.first(where: { $0.id == selection }) {
            return labels.contains { smart.labelIDs.contains($0.id) && tags.contains($0.name) }
        }
        return folder?.id == selection
    }
}
