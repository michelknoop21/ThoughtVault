import Foundation

/// Transcript list search. Mirrors windows TranscriptsList.tsx: one trimmed query,
/// substring match (nl-NL lowercase, no diacritic folding) on any of the fields.
enum TranscriptSearch {
    static func matches(_ query: String, title: String, transcript: String, notuleHtml: String, tags: [String]) -> Bool {
        let locale = Locale(identifier: "nl_NL")
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: locale)
        if q.isEmpty { return true }
        let notule = HTMLPlainText.from(notuleHtml)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return ([title, transcript, notule] + tags).contains { $0.lowercased(with: locale).contains(q) }
    }
}
