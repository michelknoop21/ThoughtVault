// QuickNoteStore.swift
// ThoughtVault
//
// Keeps the "Snelle notitie" typed during a recording with that recording.
// Stored per audio filename while editing and when the recording stops, surviving every
// processing path (local, cloud, offline queue). A transcript finds its note
// through the existing `localAudio_<taskId>` path mapping.

import Foundation

enum QuickNoteStore {
    private static func key(_ audioFilename: String) -> String { "quickNote_\(audioFilename)" }

    /// Stores a trimmed note; an empty processing retry leaves the saved note intact.
    static func save(_ note: String, audioFilename: String, defaults: UserDefaults = .standard) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: key(audioFilename))
    }

    static func saveDraft(_ note: String, audioFilename: String, defaults: UserDefaults = .standard) {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.removeObject(forKey: key(audioFilename))
        } else {
            save(note, audioFilename: audioFilename, defaults: defaults)
        }
    }

    static func note(audioFilename: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(audioFilename))
    }

    /// The note of the recording a transcript was made from, if any.
    static func note(forTranscriptId taskId: String, defaults: UserDefaults = .standard) -> String? {
        guard let path = defaults.string(forKey: "localAudio_\(taskId)") else { return nil }
        return note(audioFilename: URL(fileURLWithPath: path).lastPathComponent, defaults: defaults)
    }

    /// Prompt block for on-device notule generation: the note is context from the user,
    /// not part of the spoken transcript, and ends up rewritten as the last section.
    static func promptBlock(_ note: String?) -> String {
        guard let note, !note.isEmpty else { return "" }
        return """
        NOTITIE VAN DE GEBRUIKER TIJDENS DE OPNAME (context, geen onderdeel van de transcriptie):
        \(note)

        Sluit de notule af met een sectie <h2>Notities</h2>. Herschrijf de notitie daarin grammaticaal en stilistisch beter dan het origineel. Gebruik de rest van de notule als context (namen, termen, verwijzingen). Behoud elk punt uit de notitie en voeg niets nieuws toe.


        """
    }

    /// Guarantees the notule ends with a "Notities" section when the user typed a note:
    /// a section the model wrote stays as is, otherwise the raw note is appended.
    static func ensureNotesSection(_ html: String, note: String?) -> String {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return html }
        if html.range(of: "<h2[^>]*>\\s*Notities\\s*</h2>", options: [.regularExpression, .caseInsensitive]) != nil { return html }
        let escaped = note
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        let section = "<h2>Notities</h2><p>\(escaped)</p>"
        if let body = html.range(of: "</body>", options: [.backwards, .caseInsensitive]) {
            return html.replacingCharacters(in: body, with: section + "</body>")
        }
        return html + section
    }
}

/// Recording identity survives retries using the same audio-to-task mapping as quick notes.
struct RecordingIdentity: Codable, Equatable, Sendable {
    var title: String?
    var calendarID: String?
    var calendarTitle: String?
    var calendarStart: Date?
    var calendarURL: URL?

    static func load(audioFilename: String, defaults: UserDefaults = .standard) -> Self? {
        defaults.data(forKey: "recordingIdentity_" + audioFilename).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    func save(audioFilename: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "recordingIdentity_" + audioFilename) }
    }
    static func forTask(_ taskID: String) -> Self? {
        guard let path = UserDefaults.standard.string(forKey: "localAudio_" + taskID) else { return nil }
        return load(audioFilename: URL(fileURLWithPath: path).lastPathComponent)
    }
}

/// The App Store target is the macOS TestFlight build; do not expose the new workspace there.
enum RecordingFeatures {
    static var enabled: Bool {
#if os(macOS) && APP_STORE
        false
#else
        true
#endif
    }
}

struct QuickNoteDocument: Equatable {
    struct Item: Equatable { var text: String; var done: Bool }
    var notes: String
    var items: [Item]

    init(_ text: String) {
        var lines: [String] = []
        var items: [Item] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                items.append(Item(text: String(line.dropFirst(6)), done: line.hasPrefix("- [x] ")))
            } else { lines.append(line) }
        }
        notes = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        self.items = items
    }
    var text: String {
        ([notes] + items.map { "- [" + ($0.done ? "x" : " ") + "] " + $0.text.replacingOccurrences(of: "\n", with: " ") })
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    var html: String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let body = notes.isEmpty ? "" : "<p>" + escape(notes).replacingOccurrences(of: "\n", with: "<br>") + "</p>"
        let list = items.isEmpty ? "" : "<h3>Actiepunten uit het kladblok</h3><ul>" + items.map {
            "<li>" + ($0.done ? "☑ " : "☐ ") + escape($0.text) + "</li>"
        }.joined() + "</ul>"
        return "<!--thoughtvault-own-notes--><section data-thoughtvault-notes=\"true\"><hr><h2>Eigen notities</h2>" + body + list + "</section><!--/thoughtvault-own-notes-->"
    }
}

extension QuickNoteStore {
    static func withoutOwnNotes(_ html: String) -> String {
        html.replacingOccurrences(of: "<!--thoughtvault-own-notes-->[\\s\\S]*?<!--/thoughtvault-own-notes-->", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<section\\b[^>]*data-thoughtvault-notes=[\"']true[\"'][^>]*>[\\s\\S]*?</section>", with: "", options: [.regularExpression, .caseInsensitive])
    }
    static func exportHTML(_ html: String, note: String?, includeNotes: Bool) -> String {
        let clean = withoutOwnNotes(html)
        guard includeNotes else { return clean }
        // Preserve edits made to the saved section in the notule editor.
        if clean != html { return html }
        let section = note.map { QuickNoteDocument($0).html } ?? ""
        // Existing documents may contain the managed section without a local audio mapping (iCloud).
        guard !section.isEmpty else { return html }
        if let end = clean.range(of: "</body>", options: [.backwards, .caseInsensitive]) {
            return clean.replacingCharacters(in: end, with: section + "</body>")
        }
        return clean + section
    }
}
