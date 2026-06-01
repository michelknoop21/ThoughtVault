// NotuleTitleExtractor.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Extracts a descriptive title from generated notule HTML. Swift port of the
// backend's `_extract_title_from_html` so locally generated notulen get the same
// titles the server produced (instead of generic words or section headings).

import Foundation

enum NotuleTitleExtractor {

    private static let genericTitles: Set<String> = [
        "notule", "notulen", "vergadering", "meeting", "gespreksverslag",
        "verslag", "samenvatting", "tl;dr", "tldr",
    ]

    private static let sectionWords: Set<String> = [
        "gespreksverslag", "actiepunten", "samenvatting", "context",
        "conclusie", "agenda", "deelnemers", "besluitenlijst",
        "kernargumenten", "kernpunten", "key takeaways", "takeaways",
        "hoofdpunten", "besluiten", "vervolgstappen", "inleiding",
        "introductie", "achtergrond", "discussie", "toelichting",
        "analyse", "resultaten", "aanbevelingen", "bijlagen",
        "thema", "onderwerp", "overzicht", "tl;dr", "tldr",
    ]

    /// Returns a descriptive title from the HTML, or nil if none qualifies.
    /// Strategies: descriptive heading (h1-h4) → TL;DR/summary paragraph → first
    /// substantial paragraph. Generic words and section headings are skipped.
    static func extract(from html: String) -> String? {
        // Strategy 1: first descriptive heading (h1–h4)
        for match in regexMatches(#"<(h[1-4])[^>]*>(.*?)</\1>"#, in: html, group: 2) {
            let title = clean(match)
            if isDescriptive(title) { return String(title.prefix(80)) }
        }

        // Strategy 2: TL;DR / summary box — extract the following <p> content
        let tldrPattern = #"(?:tl;?dr|samenvatting|in het kort)[^<]*</(?:h2|h3|strong|b|div|span)>[^<]*<p[^>]*>(.*?)</p>"#
        if let tldr = regexMatches(tldrPattern, in: html, group: 1).first {
            let summary = clean(tldr)
            if summary.count > 20 {
                let sentence = firstSentence(summary)
                if sentence.count > 10 { return String(sentence.prefix(80)) }
            }
        }

        // Strategy 3: first <p> with substantial text
        for match in regexMatches(#"<p[^>]*>(.*?)</p>"#, in: html, group: 1) {
            let text = clean(match)
            if text.count > 30 && !text.hasPrefix("📅") {
                let sentence = firstSentence(text)
                if sentence.count > 10 { return String(sentence.prefix(80)) }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func clean(_ input: String) -> String {
        var text = input
        text = replace(#"<[^>]+>"#, in: text, with: "")        // strip tags
        text = replace(#"\[.*?\]"#, in: text, with: "")         // strip [bracketed]
        text = replace(#"[\x{1F300}-\x{1F9FF}\x{2600}-\x{27BF}]+"#, in: text, with: "") // emoji
        text = replace(#"^\d+\.\s*"#, in: text.trimmingCharacters(in: .whitespacesAndNewlines), with: "") // leading "1. "
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, char) in entities { text = text.replacingOccurrences(of: entity, with: char) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDescriptive(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .trimmingCharacters(in: .whitespaces)
        if text.count < 6 || text.hasPrefix("[") { return false }
        if genericTitles.contains(lower) || sectionWords.contains(lower) { return false }
        let words = lower.split(separator: " ").map(String.init)
        if words.count <= 2 && words.contains(where: { sectionWords.contains($0.trimmingCharacters(in: CharacterSet(charactersIn: ":"))) }) {
            return false
        }
        return true
    }

    private static func firstSentence(_ text: String) -> String {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        return (parts.first ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regexMatches(_ pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
