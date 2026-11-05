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
