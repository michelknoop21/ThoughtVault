// QuickNoteStore.swift
// ThoughtVault
//
// Keeps the "Snelle notitie" typed during a recording with that recording.
// Stored per audio filename when the recording stops, so it survives every
// processing path (local, cloud, offline queue). A transcript finds its note
// through the existing `localAudio_<taskId>` path mapping.

import Foundation

enum QuickNoteStore {
    private static func key(_ audioFilename: String) -> String { "quickNote_\(audioFilename)" }

    /// Stores a trimmed note; an empty note stores nothing.
    static func save(_ note: String, audioFilename: String, defaults: UserDefaults = .standard) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: key(audioFilename))
    }

    static func note(audioFilename: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(audioFilename))
    }

    /// The note of the recording a transcript was made from, if any.
    static func note(forTranscriptId taskId: String, defaults: UserDefaults = .standard) -> String? {
        guard let path = defaults.string(forKey: "localAudio_\(taskId)") else { return nil }
        return note(audioFilename: URL(fileURLWithPath: path).lastPathComponent, defaults: defaults)
    }

    /// Prompt block for on-device notule generation: the note is context from
    /// the user, not part of the spoken transcript.
    static func promptBlock(_ note: String?) -> String {
        guard let note, !note.isEmpty else { return "" }
        return "NOTITIE VAN DE GEBRUIKER TIJDENS DE OPNAME (context, geen onderdeel van de transcriptie):\n\(note)\n\n"
    }
}
