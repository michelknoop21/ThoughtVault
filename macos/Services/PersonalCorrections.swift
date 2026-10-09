import Foundation

struct PersonalCorrection: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var canonical: String = ""
    var variants: [String] = [""]
    var scope: String? = nil
    var enabled: Bool = true
    enum CodingKeys: String, CodingKey { case id, canonical, variants, scope, enabled }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(canonical, forKey: .canonical)
        try values.encode(variants, forKey: .variants); try values.encode(scope, forKey: .scope)
        try values.encode(enabled, forKey: .enabled)
    }
}
struct CorrectionDocument: Codable, Sendable {
    var version = 1
    var entries: [PersonalCorrection] = []
}
enum PersonalCorrections {
    static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ThoughtVault/personal-corrections.json")
    }
    static func load(from path: URL = url) throws -> [PersonalCorrection] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let document = try JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: path))
        try validate(document)
        return document.entries
    }
    static func save(_ entries: [PersonalCorrection], to path: URL = url) throws {
        let document = CorrectionDocument(entries: entries)
        try validate(document)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: path, options: .atomic)
    }
    static func validate(_ document: CorrectionDocument) throws {
        func invalid(_ message: String) -> NSError { NSError(domain: "PersonalCorrections", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        guard document.version == 1 else { throw invalid("Onbekend woordenlijstformaat.") }
        var ids = Set<String>()
        func valid(_ text: String) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 120 && text.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n<>")) == nil
        }
        for entry in document.entries {
            guard !entry.id.isEmpty, ids.insert(entry.id).inserted, valid(entry.canonical), !entry.variants.isEmpty, entry.scope != "" else { throw invalid("Vul een correcte term en minstens één variant in (maximaal 120 tekens).") }
            var variants = Set<String>()
            for variant in entry.variants {
                let key = variant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard valid(variant), key != entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), variants.insert(key).inserted else { throw invalid("Een variant moet afwijken van de correcte term en mag niet dubbel voorkomen.") }
                for other in document.entries where other.id != entry.id && other.enabled && entry.enabled {
                    if entry.scope == nil || other.scope == nil || entry.scope == other.scope {
                        guard !other.variants.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) else { throw invalid("Deze variant heeft al een regel binnen dit bereik.") }
                    }
                }
            }
        }
    }
    static func upsert(_ entries: [PersonalCorrection], entry: PersonalCorrection) -> [PersonalCorrection] {
        let previous = entries.first { $0.id != entry.id && $0.scope == entry.scope && $0.canonical.lowercased() == entry.canonical.lowercased() }
        var updated = entry
        updated.id = previous?.id ?? entry.id
        var seen = Set<String>()
        updated.variants = ((previous?.variants ?? []) + entry.variants).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { seen.insert($0.lowercased()).inserted }
        return entries.filter { $0.id != entry.id && $0.id != previous?.id } + [updated]
    }
    static func active(_ entries: [PersonalCorrection], profileId: String?) -> [PersonalCorrection] {
        entries.filter { $0.enabled && ($0.scope == nil || $0.scope == profileId) }
    }
    static func prompt(_ entries: [PersonalCorrection], profileId: String?) -> String {
        let rules = active(entries, profileId: profileId).prefix(30)
        return rules.isEmpty ? "" : "\n\nGoedgekeurde spellingcorrecties (geen nieuwe feiten):\n" + rules.map { "\($0.variants.joined(separator: ", ")) -> \($0.canonical)" }.joined(separator: "\n")
    }
    static func text(_ text: String, entries: [PersonalCorrection], profileId: String?, html: Bool = false) -> String {
        var replacements: [String: String] = [:]
        for entry in active(entries, profileId: profileId) {
            for variant in entry.variants { replacements[variant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard !replacements.isEmpty else { return text }
        let alternatives = replacements.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"&(?:#\d+|#x[\da-f]+|[a-z]+);|(?:https?://|www\.)[^\s<>]+|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}|`[^`]*`|(?<![\p{L}\p{N}_])(?:"# + alternatives + #")(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text), let canonical = replacements[String(text[range]).lowercased()], let outputRange = Range(match.range, in: result) else { continue }
            let matched = String(text[range])
            if matched.hasPrefix("&") || matched.hasPrefix("`") || matched.contains("@") || matched.lowercased().hasPrefix("http://") || matched.lowercased().hasPrefix("https://") || matched.lowercased().hasPrefix("www.") { continue }
            let replacement = html ? escape(canonical) : canonical
            result.replaceSubrange(outputRange, with: replacement)
        }
        return result
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    static func html(_ html: String, entries: [PersonalCorrection], profileId: String?) -> String {
        let pattern = #"<!--[\s\S]*?-->|</?[A-Za-z!](?:"[^"]*"|'[^']*'|[^'">])*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let tagRegex = try! NSRegularExpression(pattern: #"^<\s*(/?)\s*(script|style|code|pre|a)\b"#, options: .caseInsensitive)
        var stack: [String] = []
        var result = "", cursor = html.startIndex
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let content = String(html[cursor..<range.lowerBound])
            result += stack.isEmpty ? text(content, entries: entries, profileId: profileId, html: true) : content
            let tag = String(html[range]); result += tag
            if let parsed = tagRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)), let nameRange = Range(parsed.range(at: 2), in: tag) {
                let name = String(tag[nameRange]).lowercased()
                if parsed.range(at: 1).length > 0 { if stack.last == name { stack.removeLast() } }
                else if stack.isEmpty && !tag.hasSuffix("/>") { stack.append(name) }
            }
            cursor = range.upperBound
        }
        let tail = String(html[cursor...])
        return result + (stack.isEmpty ? text(tail, entries: entries, profileId: profileId, html: true) : tail)
    }
}
