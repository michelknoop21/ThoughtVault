// ProfileTemplates.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Loads the rich built-in profile prompts + HTML/CSS output templates (ported from
// the backend's profile_templates.py and bundled as ProfileTemplates.json) so locally
// generated notulen match the server's HTML quality.

import Foundation

enum ProfileTemplates {

    struct Entry: Decodable {
        let id: String
        let name: String
        let description: String?
        let icon: String?
        let systemPrompt: String?
        let notulePrompt: String?
        let template: String?
    }

    static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "ProfileTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }()

    static func entry(for id: String) -> Entry? {
        entries.first { $0.id == id }
    }
}
