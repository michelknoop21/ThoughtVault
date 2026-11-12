import Foundation

private let logger = AppLog(category: "PersonalCorrections")

struct PersonalCorrection: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var canonical: String = ""
    var variants: [String] = [""]
    var scope: String? = nil
    var enabled: Bool = true
    /// Short explanation for the minutes AI (max 200 characters). Absent in version 1 files.
    var note: String? = nil
    enum CodingKeys: String, CodingKey { case id, canonical, variants, scope, enabled, note }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(canonical, forKey: .canonical)
        try values.encode(variants, forKey: .variants); try values.encode(scope, forKey: .scope)
        try values.encode(enabled, forKey: .enabled); try values.encodeIfPresent(note, forKey: .note)
    }
}
struct CorrectionDocument: Codable, Sendable {
    var version = 2
    var entries: [PersonalCorrection] = []
    /// Suggestions the user rejected, so they are not offered again.
    var dismissed: [String] = []
    init(entries: [PersonalCorrection] = [], dismissed: [String] = []) { self.entries = entries; self.dismissed = dismissed }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        entries = try values.decode([PersonalCorrection].self, forKey: .entries)
        dismissed = try values.decodeIfPresent([String].self, forKey: .dismissed) ?? []
    }
}
/// A directory person as seen by the minutes AI.
struct PersonContext: Sendable {
    var name: String
    var role: String
    var organization: String
    var responsibilities: [String]
    var aliases: [String]
}
enum PersonalCorrections {
    static var url: URL {
        AppEnvironment.supportDirectory.appendingPathComponent("ThoughtVault/personal-corrections.json")
    }
    /// For the minutes path: an unreadable glossary (e.g. a newer file version) must not
    /// block the minutes, so it is logged and treated as empty.
    static func loadOrEmpty(at path: URL = url) -> [PersonalCorrection] {
        do { return try load(from: path) } catch {
            logger.error("Glossary unreadable, minutes continue without it: \(LogRedact.mask(error.localizedDescription))")
            return []
        }
    }
    static func load(from path: URL = url) throws -> [PersonalCorrection] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let document = try JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: path))
        try validate(document)
        return document.entries
    }
    static func save(_ entries: [PersonalCorrection], to path: URL = url) throws {
        let document = CorrectionDocument(entries: entries, dismissed: (try? JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: path)))?.dismissed ?? [])
        try validate(document)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: path, options: .atomic)
    }
    /// Rejected suggestion keys; empty when the file is missing or unreadable.
    static func dismissed(at path: URL = url) -> [String] {
        (try? JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: path)))?.dismissed ?? []
    }
    /// Records a rejected suggestion key so it is not offered again. Entries are kept.
    @MainActor
    static func addDismissed(_ key: String, to path: URL = url) throws {
        let current = FileManager.default.fileExists(atPath: path.path)
            ? try JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: path)) : CorrectionDocument()
        guard !current.dismissed.contains(key) else { return }
        let document = CorrectionDocument(entries: current.entries, dismissed: current.dismissed + [key])
        try validate(document)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: path, options: .atomic)
    }
    /// Upserts `entry` and saves; the stored version it replaces is kept in ContextHistory
    /// under `source`. Returns the saved entries.
    @MainActor
    @discardableResult
    static func saveRecording(_ entry: PersonalCorrection, source: String, to path: URL = url) throws -> [PersonalCorrection] {
        let entries = try load(from: path)
        let next = upsert(entries, entry: entry)
        try validate(CorrectionDocument(entries: next))
        // upsert appends the saved entry last and may merge into an existing entry with
        // the same term; record both old versions.
        let saved = next.last
        for old in entries where (old.id == entry.id || old.id == saved?.id) && old != saved {
            try ContextHistory.record(kind: .term, itemId: old.id, source: source, snapshot: old)
        }
        try save(next, to: path)
        return next
    }
    /// Removes an entry; its last state is kept in ContextHistory so `restore` can bring it back.
    @MainActor
    static func delete(id: String, source: String, to path: URL = url) throws {
        let entries = try load(from: path)
        guard let old = entries.first(where: { $0.id == id }) else { return }
        try ContextHistory.record(kind: .term, itemId: id, source: source, snapshot: old)
        try save(entries.filter { $0.id != id }, to: path)
    }
    /// Puts an earlier version of a glossary entry back as a new version.
    @MainActor
    static func restore(_ entry: HistoryEntry, to path: URL = url) throws {
        try saveRecording(JSONDecoder().decode(PersonalCorrection.self, from: Data(entry.snapshotJSON.utf8)), source: "herstel", to: path)
    }
    static func validate(_ document: CorrectionDocument) throws {
        func invalid(_ message: String) -> NSError { NSError(domain: "PersonalCorrections", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        guard document.version == 1 || document.version == 2 else { throw invalid("Onbekend woordenlijstformaat.") }
        var ids = Set<String>()
        let valid = validTerm
        for entry in document.entries {
            guard !entry.id.isEmpty, ids.insert(entry.id).inserted, valid(entry.canonical), entry.scope != "", (entry.note?.utf16.count ?? 0) <= 200, entry.note?.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n<>")) == nil else { throw invalid("Vul een correcte term in (maximaal 120 tekens) en houd de toelichting onder 200 tekens, zonder regeleinden of haakjes.") }
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
    static func validTerm(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 120 && text.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n<>")) == nil
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
    /// Case-insensitive whole-word match, same boundaries as text().
    static func containsWord(_ word: String, in text: String) -> Bool {
        text.range(of: #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: word) + #"(?![\p{L}\p{N}_])"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func contextBudget(for provider: NotulenProvider) -> Int { provider == .appleIntelligence ? 1200 : 6000 }

    /// Glossary and people block for the minutes AI. `maxCharacters` limits the lines, not the fixed header.
    /// Order: lines matching the transcript, then lines for `profileId`, then the newest.
    /// Role and organization only go along with `includeRoles` (the suggestion step): in the minutes
    /// prompt, models copied them into the notule without the transcript saying them.
    static func contextBlock(entries: [PersonalCorrection], people: [PersonContext], transcript: String, profileId: String?, maxCharacters: Int, extraTerms: [String] = [], includeRoles: Bool = false) -> String {
        // Word-boundary, case-insensitive match, same boundaries as text().
        func found(_ names: [String]) -> Bool {
            names.contains {
                let n = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !n.isEmpty && containsWord(n, in: transcript)
            }
        }
        func joined(_ parts: [String]) -> String { parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ") }
        var candidates: [(line: String, rank: Int)] = []
        // Entries are appended on upsert, so the last one is the newest.
        for entry in active(entries, profileId: profileId).reversed() {
            let variants = entry.variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var line = "- " + entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            if !variants.isEmpty { line += " (ook gehoord als: \(variants.joined(separator: ", ")))" }
            if let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { line += ": " + note }
            candidates.append((line, found([entry.canonical] + variants) ? 0 : (profileId != nil && entry.scope == profileId ? 1 : 2)))
        }
        for person in people {
            var line = "- " + person.name
            let detail = includeRoles ? joined([person.role, person.organization]) : joined(person.aliases)
            if !detail.isEmpty { line += includeRoles ? " (\(detail))" : " (ook gehoord als: \(detail))" }
            let tasks = person.responsibilities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !tasks.isEmpty { line += ", taken: " + tasks.joined(separator: "; ") }
            candidates.append((line, found([person.name] + person.aliases) ? 0 : 2))
        }
        // Extra terms (context note) go last, skipping anything already covered.
        var covered = Set<String>()
        for entry in active(entries, profileId: profileId) { covered.insert(entry.canonical.lowercased()); entry.variants.forEach { covered.insert($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) } }
        for person in people { covered.insert(person.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        for term in extraTerms.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !term.isEmpty && covered.insert(term.lowercased()).inserted {
            candidates.append(("- " + term, 3))
        }
        var lines: [String] = [], used = 0
        for candidate in candidates.enumerated().sorted(by: { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }).map(\.element) {
            guard used + candidate.line.count + 1 <= maxCharacters else { continue }
            lines.append(candidate.line); used += candidate.line.count + 1
        }
        guard !lines.isEmpty else { return "" }
        return "\n\nWoordenboek en personen (juiste spelling en betekenis; corrigeer verkeerd herkende varianten stil, voeg geen feiten toe; noem een functie of organisatie alleen als het transcript die noemt; koppel een actie alleen aan een persoon die het transcript noemt):\n" + lines.joined(separator: "\n")
    }

    /// Call-site helper: adds the directory people and the provider budget.
    @MainActor
    static func contextBlock(entries: [PersonalCorrection], transcript: String, profileId: String?, provider: NotulenProvider, includeRoles: Bool = false) -> String {
        let people = PersonDirectoryService.shared.directoryPeople().map {
            PersonContext(name: $0.name, role: $0.role, organization: $0.organization, responsibilities: $0.responsibilities, aliases: $0.aliases)
        }
        return contextBlock(entries: entries, people: people, transcript: transcript, profileId: profileId, maxCharacters: contextBudget(for: provider),
                            extraTerms: VaultFolderStore.readContextNote().map { VaultFolderStore.parseTerms(fromNote: $0) } ?? [], includeRoles: includeRoles)
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
