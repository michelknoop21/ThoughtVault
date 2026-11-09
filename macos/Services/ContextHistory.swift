// ContextHistory.swift
// ThoughtVault
//
// Version history for the context sent to the minutes AI: directory people and
// glossary entries. Every change stores the state from before that change, so any
// earlier version can be restored. Kept on-device next to the glossary file.

import Foundation

enum HistoryKind: String, Codable { case person, term }

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let kind: HistoryKind
    let itemId: String
    let date: Date
    /// "handmatig", "gesprek:<taskId>", "voorstel:<taskId>" or "herstel".
    let source: String
    let snapshotJSON: String
}

/// Main-actor isolated: every read-modify-write of the history file runs serially there.
@MainActor
enum ContextHistory {
    static let maxPerItem = 50

    /// History file. Under tests it resolves to a temp directory (AppEnvironment); tests
    /// still swap it for their own file and restore it afterwards.
    static var url = PersonalCorrections.url.deletingLastPathComponent().appendingPathComponent("context-history.json")

    static func record<T: Encodable>(kind: HistoryKind, itemId: String, source: String, snapshot: T) throws {
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        var entries = try load()
        entries.append(HistoryEntry(id: UUID(), kind: kind, itemId: itemId, date: Date(), source: source, snapshotJSON: json))
        // Entries are appended in order, so the first matches are the oldest.
        var excess = entries.filter { $0.kind == kind && $0.itemId == itemId }.count - maxPerItem
        entries.removeAll { entry in
            guard excess > 0, entry.kind == kind, entry.itemId == itemId else { return false }
            excess -= 1
            return true
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    /// Versions of one item, newest first.
    static func versions(kind: HistoryKind, itemId: String) -> [HistoryEntry] {
        ((try? load()) ?? []).filter { $0.kind == kind && $0.itemId == itemId }.reversed()
    }

    /// Reads the history file; empty only when it does not exist. A read error throws,
    /// so the file is never overwritten. A file that does not decode is moved aside under
    /// a unique name (kept for recovery), so a damaged history never blocks edits.
    private static func load() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) { return entries }
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable-\(UUID().uuidString)"))
        return []
    }
}

/// The editable fields of a directory person, as stored in the history.
struct PersonSnapshot: Codable, Equatable {
    var name: String
    var role: String
    var organization: String
    var aliases: [String]
    var meetingTypes: [String]
    var expertiseTags: [String]
    var emails: [String]
    var isInternal: Bool?
    var responsibilities: [String]

    init(_ person: PersonProfile) {
        name = person.name
        role = person.role
        organization = person.organization
        aliases = person.aliases
        meetingTypes = person.meetingTypes
        expertiseTags = person.expertiseTags
        emails = person.emails
        isInternal = person.isInternal
        responsibilities = person.responsibilities
    }

    func apply(to person: PersonProfile) {
        person.name = name
        person.role = role
        person.organization = organization
        person.aliases = aliases
        person.meetingTypes = meetingTypes
        person.expertiseTags = expertiseTags
        person.emails = emails
        person.isInternal = isInternal
        person.responsibilities = responsibilities
    }
}
