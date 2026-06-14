// Participant.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// A meeting participant sent to the notule pipeline so the LLM can render an
// attendee list and attribute action points by name. Whisper has no diarisation,
// so this is NOT used to label individual utterances (zie notule-prompt regel).

import Foundation

// MARK: - Participant

struct Participant: Codable, Sendable, Hashable {
    var name: String
    var role: String
    var organization: String

    init(name: String, role: String = "", organization: String = "") {
        self.name = name
        self.role = role
        self.organization = organization
    }
}

// MARK: - Prompt block

extension Array where Element == Participant {

    /// Renders a Dutch "DEELNEMERS:" block (+ attribution instruction) for
    /// notule-prompt injection. Returns "" when empty so callers can no-op cleanly.
    /// Kept in sync with the backend's participants.build_participants_block.
    var notulePromptBlock: String {
        guard !isEmpty else { return "" }
        let lines = map { p -> String in
            let extras = [p.role, p.organization]
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: ", ")
            return extras.isEmpty ? "- \(p.name)" : "- \(p.name) (\(extras))"
        }
        let instruction = "Gebruik bovenstaande deelnemers in de notule: noem ze in een "
            + "deelnemerssectie en koppel actiepunten waar mogelijk aan de juiste persoon "
            + "op naam. Verzin geen deelnemers buiten deze lijst en wijs losse uitspraken "
            + "niet aan individuele sprekers toe."
        return "DEELNEMERS:\n" + lines.joined(separator: "\n") + "\n\n" + instruction
    }
}
