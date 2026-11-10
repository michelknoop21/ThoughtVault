// ContextSuggestions.swift
// ThoughtVault
//
// After a notule is saved, one extra AI call proposes glossary terms and directory
// people from the conversation. Proposals are stored per recording until the user
// accepts or rejects them; nothing is added to the glossary automatically.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "ContextSuggestions")

extension Notification.Name {
    /// Posted on the main actor after suggestions for a recording were stored; `userInfo["taskId"]`.
    static let contextSuggestionsUpdated = Notification.Name("contextSuggestionsUpdated")
}

struct TermSuggestion: Codable, Hashable, Sendable {
    var heard: String
    var canonical: String
    var note: String

    init(heard: String, canonical: String, note: String) {
        self.heard = heard; self.canonical = canonical; self.note = note
    }
    /// AI output: missing or mistyped fields become empty.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        heard = values.lenient(.heard) ?? ""
        canonical = values.lenient(.canonical) ?? ""
        note = values.lenient(.note) ?? ""
    }
}

struct PersonSuggestion: Codable, Hashable, Sendable {
    var name: String
    var role: String
    var organization: String
    var responsibilities: [String]
    var topics: [String]
    var heardAs: [String]
    /// Directory person this suggestion updates; nil means a new person.
    var matchedPersonId: String?
    /// Directory people this suggestion could be when the name was ambiguous.
    var candidateIds: [String] = []

    init(name: String, role: String, organization: String, responsibilities: [String], topics: [String], heardAs: [String], matchedPersonId: String?, candidateIds: [String] = []) {
        self.name = name; self.role = role; self.organization = organization
        self.responsibilities = responsibilities; self.topics = topics; self.heardAs = heardAs
        self.matchedPersonId = matchedPersonId; self.candidateIds = candidateIds
    }
    /// AI output: missing or mistyped fields become empty.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = values.lenient(.name) ?? ""
        role = values.lenient(.role) ?? ""
        organization = values.lenient(.organization) ?? ""
        responsibilities = values.lenient(.responsibilities) ?? []
        topics = values.lenient(.topics) ?? []
        heardAs = values.lenient(.heardAs) ?? []
        matchedPersonId = values.lenient(.matchedPersonId)
        candidateIds = values.lenient(.candidateIds) ?? []
    }
}

struct ContextSuggestionSet: Codable, Equatable, Sendable {
    var terms: [TermSuggestion] = []
    var people: [PersonSuggestion] = []
    var isEmpty: Bool { terms.isEmpty && people.isEmpty }

    init(terms: [TermSuggestion] = [], people: [PersonSuggestion] = []) {
        self.terms = terms; self.people = people
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        terms = values.lenient(.terms) ?? []
        people = values.lenient(.people) ?? []
    }
}

extension TermSuggestion: Identifiable {
    var id: String { ContextSuggestions.dismissKey(for: .term(self)) }
}

extension PersonSuggestion: Identifiable {
    var id: String { ContextSuggestions.dismissKey(for: .person(self)) }
}

enum ContextSuggestionItem: Hashable, Sendable {
    case term(TermSuggestion)
    case person(PersonSuggestion)
}

private extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ key: Key) -> T? { (try? decodeIfPresent(T.self, forKey: key)) ?? nil }
}

enum ContextSuggestions {
    static let maxItems = 8
    static let maxTranscriptCharacters = 64_000

    /// Key stored in `CorrectionDocument.dismissed` when the user rejects a suggestion.
    static func dismissKey(for item: ContextSuggestionItem) -> String {
        switch item {
        case .term(let term): return "term:\(trim(term.heard))→\(trim(term.canonical))".lowercased()
        case .person(let person): return "person:\(trim(person.name))".lowercased()
        }
    }

    // MARK: - Parsing

    /// Turns the raw AI reply into checked suggestions. Never throws: anything unusable is dropped.
    /// The user is never suggested: a name equal to `selfNames` or `selfAliases` is dropped, a
    /// heardAs spelling only when it equals a self name (a bare first-name alias would otherwise
    /// drop everyone else with that first name).
    static func parse(_ raw: String, transcript: String, entries: [PersonalCorrection], dismissed: [String], selfNames: [String] = [], selfAliases: [String] = []) -> ContextSuggestionSet {
        // Reasoning models may prefix their answer with a think block that can contain braces.
        let raw = raw.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let decoded = try? JSONDecoder().decode(ContextSuggestionSet.self, from: Data(raw[start...end].utf8))
        else { return ContextSuggestionSet() }
        let rejected = Set(dismissed.map { $0.lowercased() })
        var known = Set<String>()
        for entry in entries { ([entry.canonical] + entry.variants).forEach { known.insert(trim($0).lowercased()) } }

        let ownNames = Set(selfNames.map { trim($0).lowercased() }.filter { !$0.isEmpty })
        let ownNamesAndAliases = ownNames.union(selfAliases.map { trim($0).lowercased() }.filter { !$0.isEmpty })

        // Plain loops, not lazy compactMap + prefix: a lazy collection re-runs its closure while
        // slicing, which would repeat the `seen` insert and drop valid items.
        var seen = Set<String>(), terms: [TermSuggestion] = [], people: [PersonSuggestion] = []
        // "a / b" in heard is several spellings in one item: one term per spelling found.
        for term in decoded.terms {
            for heard in term.heard.components(separatedBy: " / ") where terms.count < maxItems {
                let cleaned = TermSuggestion(heard: trim(heard), canonical: trim(term.canonical), note: noteText(term.note))
                let key = dismissKey(for: .term(cleaned))
                guard PersonalCorrections.validTerm(cleaned.heard), PersonalCorrections.validTerm(cleaned.canonical),
                      cleaned.heard.lowercased() != cleaned.canonical.lowercased(),
                      !known.contains(cleaned.canonical.lowercased()),
                      !rejected.contains(key), PersonalCorrections.containsWord(cleaned.heard, in: transcript),
                      seen.insert(key).inserted else { continue }
                terms.append(cleaned)
            }
        }
        for person in decoded.people where people.count < maxItems {
            let cleaned = PersonSuggestion(name: trim(person.name), role: trim(person.role), organization: trim(person.organization),
                                           responsibilities: list(person.responsibilities), topics: list(person.topics),
                                           heardAs: list(person.heardAs), matchedPersonId: nil)
            let key = dismissKey(for: .person(cleaned))
            guard !cleaned.name.isEmpty, !rejected.contains(key),
                  !ownNamesAndAliases.contains(cleaned.name.lowercased()),
                  !cleaned.heardAs.contains(where: { ownNames.contains($0.lowercased()) }),
                  seen.insert(key).inserted else { continue }
            people.append(cleaned)
        }
        return ContextSuggestionSet(terms: terms, people: people)
    }

    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func list(_ items: [String]) -> [String] { items.map(trim).filter { !$0.isEmpty } }

    /// A note valid for PersonalCorrection: one line, no angle brackets, at most 200 UTF-16 units.
    private static func noteText(_ text: String) -> String {
        var note = trim(text.components(separatedBy: CharacterSet(charactersIn: "\r\n<>")).joined(separator: " "))
        while note.utf16.count > 200 { note.removeLast() }
        return trim(note)
    }

    // MARK: - Storage

    /// Pending suggestions per task id. Under tests it resolves to a temp directory
    /// (AppEnvironment); tests still swap it and restore it afterwards.
    @MainActor static var url = PersonalCorrections.url.deletingLastPathComponent().appendingPathComponent("context-suggestions.json")

    /// Suggestions are disposable: an unreadable file counts as empty and is replaced on the next write.
    @MainActor private static func loadAll() -> [String: ContextSuggestionSet] {
        (try? JSONDecoder().decode([String: ContextSuggestionSet].self, from: Data(contentsOf: url))) ?? [:]
    }

    @MainActor static func load(taskId: String) -> ContextSuggestionSet? { loadAll()[taskId] }

    /// Replaces the suggestions for `taskId`; an empty set removes them.
    @MainActor static func save(_ set: ContextSuggestionSet, taskId: String) throws {
        var all = loadAll()
        let next = set.isEmpty ? nil : set
        guard all[taskId] != next else { return }
        all[taskId] = next
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(all).write(to: url, options: .atomic)
    }

    /// Removes one handled suggestion (matched on its dismiss key).
    @MainActor static func remove(taskId: String, item: ContextSuggestionItem) throws {
        guard var set = load(taskId: taskId) else { return }
        let key = dismissKey(for: item)
        set.terms.removeAll { dismissKey(for: .term($0)) == key }
        set.people.removeAll { dismissKey(for: .person($0)) == key }
        try save(set, taskId: taskId)
    }

    /// Remembers a rejected suggestion so it is not offered again.
    @MainActor static func dismiss(key: String, correctionsURL: URL = PersonalCorrections.url) throws {
        try PersonalCorrections.addDismissed(key, to: correctionsURL)
    }

    // MARK: - AI step

    /// The context step sends the whole transcript in one request, unchunked. A message well past a
    /// local model's chunk size would overflow its context and silently truncate the system prompt.
    static func fits(_ message: String, service: any LLMService) -> Bool {
        guard let local = service as? OpenAICompatibleLLMService else { return true }
        return message.count <= local.maxChunkCharacters + 8_000
    }

    /// Starts the suggestion call after the notule was saved. Fire and forget: failures are
    /// only logged. Skipped for Apple Intelligence, very long transcripts and under tests.
    static func runInBackground(taskId: String, transcript: String, participants: [Participant], profileId: String?, profileName: String, provider: NotulenProvider) {
        let provider: NotulenProvider = provider == .cloud ? .ollama : provider
        guard !AppEnvironment.isRunningTests, provider != .appleIntelligence,
              transcript.count <= maxTranscriptCharacters else { return }
        Task.detached(priority: .utility) {
            do {
                let (context, entries, dismissed, selfName, selfAliases) = await MainActor.run {
                    let entries = PersonalCorrections.loadOrEmpty()
                    let me = LocalTranscriptStore.shared.fetchSelfProfile()
                    return (PersonalCorrections.contextBlock(entries: entries, transcript: transcript, profileId: profileId, provider: provider, includeRoles: true),
                            entries, PersonalCorrections.dismissed(), me?.name ?? "", me?.aliases ?? [])
                }
                let message = userMessage(context: context, participants: participants, selfName: selfName, transcript: transcript)
                let service = LLMServiceFactory.service(for: provider, serverURL: "")
                guard fits(message, service: service) else {
                    logger.info("Context suggestions skipped: \(message.count) characters is too long for the local model")
                    return
                }
                let raw = try await service.complete(system: systemPrompt, user: message)
                let parsed = parse(raw, transcript: transcript, entries: entries, dismissed: dismissed, selfNames: [selfName], selfAliases: selfAliases)
                let set = try await MainActor.run {
                    // Matched people are filled in directly; only what needs the user is stored.
                    let set = PersonMatcher.link(parsed, taskId: taskId, profileName: profileName)
                    try save(set, taskId: taskId)
                    NotificationCenter.default.post(name: .contextSuggestionsUpdated, object: nil, userInfo: ["taskId": taskId])
                    return set
                }
                logger.info("Context suggestions: \(set.terms.count) terms, \(set.people.count) people")
            } catch {
                logger.error("Context suggestions failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static let systemPrompt = """
    Je helpt een persoonlijke woordenlijst en personenlijst bij te houden voor gespreksverslagen. \
    Je krijgt de bekende context, de naam van de gebruiker, de deelnemers en een automatisch herkende transcriptie. \
    Antwoord uitsluitend met één JSON-object, zonder uitleg en zonder code fences, in precies deze vorm:
    {"terms":[{"heard":"","canonical":"","note":""}],"people":[{"name":"","role":"","organization":"","responsibilities":[],"topics":[],"heardAs":[]}]}

    Regels:
    - terms zijn alleen eigennamen, organisaties, producten, merken, afkortingen of vakjargon die de gebruiker in een persoonlijke woordenlijst zou willen hebben en die de spraakherkenning waarschijnlijk verkeerd heeft verstaan.
    - Een gewoon Nederlands woord met een herkenningsfout is nooit een term.
    - heard is precies één letterlijke schrijfwijze zoals die in de transcriptie staat. Komt een term in meerdere schrijfwijzen voor, herhaal het item dan per schrijfwijze.
    - canonical is de juiste schrijfwijze. note is een korte toelichting van hooguit één zin.
    - Stel geen term voor die al in de bekende context staat.
    - people zijn alleen personen die in het gesprek met naam worden genoemd en een rol spelen. Laat personen zonder naam weg, zoals "mijn schoonvader". Stel de gebruiker zelf nooit voor.
    - Vul role, organization en responsibilities alleen in als dat in het gesprek expliciet wordt gezegd. Anders laat je ze leeg.
    - topics zijn de onderwerpen waar de persoon in dit gesprek bij betrokken is. heardAs bevat letterlijke schrijfwijzen van de naam uit de transcriptie.
    - Liever een paar zekere items dan veel twijfelachtige: hooguit 8 terms en 8 people.
    - Verzin geen feiten. Twijfel je, laat het item dan weg.
    - Voldoet er niets, antwoord dan met {"terms":[],"people":[]}.
    """

    static func userMessage(context: String, participants: [Participant], selfName: String, transcript: String) -> String {
        let people = participants.map { person in
            let detail = [person.role, person.organization].map(trim).filter { !$0.isEmpty }.joined(separator: ", ")
            return "- " + trim(person.name) + (detail.isEmpty ? "" : " (\(detail))")
        }
        return "Bekende context:\n" + (trim(context).isEmpty ? "(leeg)" : trim(context))
            + (trim(selfName).isEmpty ? "" : "\n\nGebruiker (niet voorstellen): " + trim(selfName))
            + "\n\nDeelnemers:\n" + (people.isEmpty ? "(niet opgegeven)" : people.joined(separator: "\n"))
            + "\n\nTranscriptie:\n" + transcript
    }
}
