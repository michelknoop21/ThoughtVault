// PersonMatcher.swift
// ThoughtVault
//
// Links people suggested from a conversation to directory people. A clear match is
// filled in automatically (meeting type, topics, responsibilities); changes to role,
// organization or aliases are only ever proposed, never written.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "PersonMatcher")

enum MatchResult: Equatable {
    case existing(id: String)
    case ambiguous([String])
    case new
}

enum PersonMatcher {

    /// Directory people as match candidates. The self profile is never one.
    static func candidates(_ people: [PersonProfile]) -> [(id: String, snapshot: PersonSnapshot)] {
        people.filter { !$0.isSelf }.map { ($0.id, PersonSnapshot($0)) }
    }

    /// Exact name or alias first (the suggested name, plus heardAs spellings of more than one
    /// word); then a suggested name that is a bare first name links only when exactly one
    /// person has it. More than one candidate is `.ambiguous`. A one-word heardAs never links.
    static func match(_ s: PersonSuggestion, in people: [(id: String, snapshot: PersonSnapshot)]) -> MatchResult {
        let name = key(s.name)
        let spellings = Set(([name] + s.heardAs.map(key).filter { words($0).count > 1 }).filter { !$0.isEmpty })
        let exact = people.filter { !spellings.isDisjoint(with: names($0.snapshot)) }.map(\.id)
        if !exact.isEmpty { return result(exact) }
        guard words(name).count == 1 else { return .new }
        return result(people.filter { firstWord($0.snapshot.name) == name }.map(\.id))
    }

    /// Participants without a link whose name equals exactly one person's name or alias get that person's id.
    static func linked(_ participants: [Participant], to people: [(id: String, snapshot: PersonSnapshot)]) -> [Participant] {
        participants.map { participant in
            var participant = participant
            let ids = people.filter { names($0.snapshot).contains(key(participant.name)) }.map(\.id)
            if participant.personId == nil, ids.count == 1 { participant.personId = ids[0] }
            return participant
        }
    }

    /// Adds the meeting type, topics and responsibilities to the person (no duplicates,
    /// existing spelling kept) and returns what is left to propose: a different or new
    /// role or organization, and new spellings of the name. nil when nothing is left.
    @MainActor
    static func autoApply(_ s: PersonSuggestion, to id: String, profileName: String, taskId: String,
                          service: PersonDirectoryService = .shared) throws -> PersonSuggestion? {
        guard let person = service.directoryPeople().first(where: { $0.id == id }) else { return s }
        try service.update(person, source: "gesprek:\(taskId)") { p in
            p.meetingTypes = merged(p.meetingTypes, [profileName])
            p.expertiseTags = merged(p.expertiseTags, s.topics)
            p.responsibilities = merged(p.responsibilities, s.responsibilities)
        }
        let role = differs(s.role, from: person.role) ? trim(s.role) : ""
        let organization = differs(s.organization, from: person.organization) ? trim(s.organization) : ""
        var known = names(PersonSnapshot(person))
        // A bare first name is never proposed as an alias: it would bypass the first-name uniqueness check.
        let aliases = ((words(key(s.name)).count > 1 ? [s.name] : []) + s.heardAs).map(trim).filter { !$0.isEmpty && known.insert(key($0)).inserted }
        guard !role.isEmpty || !organization.isEmpty || !aliases.isEmpty else { return nil }
        return PersonSuggestion(name: s.name, role: role, organization: organization, responsibilities: [],
                                topics: [], heardAs: aliases, matchedPersonId: id)
    }

    /// Runs after the AI step: fills in matched people, links the recording's participants
    /// and returns only what still needs the user (remainders, ambiguous and new people).
    @MainActor
    static func link(_ set: ContextSuggestionSet, taskId: String, profileName: String,
                     service: PersonDirectoryService = .shared, store: LocalTranscriptStore = .shared) -> ContextSuggestionSet {
        let people = candidates(service.directoryPeople())
        var kept = set
        kept.people = []
        for suggestion in set.people {
            switch match(suggestion, in: people) {
            case .existing(let id):
                do {
                    if let rest = try autoApply(suggestion, to: id, profileName: profileName, taskId: taskId, service: service) {
                        kept.people.append(rest)
                    }
                } catch {
                    logger.error("Auto-apply failed: \(error.localizedDescription, privacy: .public)")
                    var proposal = suggestion
                    proposal.matchedPersonId = id
                    kept.people.append(proposal)
                }
            case .ambiguous(let ids):
                var proposal = suggestion
                proposal.candidateIds = ids
                kept.people.append(proposal)
            case .new:
                kept.people.append(suggestion)
            }
        }
        if let record = store.record(forTaskId: taskId) {
            let participants = linked(record.participants, to: people)
            if participants != record.participants {
                do { try store.updateParticipants(taskId: taskId, participants: participants) }
                catch { logger.error("Linking participants failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
        return kept
    }

    // MARK: - Helpers

    private static func result(_ ids: [String]) -> MatchResult {
        switch ids.count {
        case 0: return .new
        case 1: return .existing(id: ids[0])
        default: return .ambiguous(ids)
        }
    }

    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Comparison form: case and diacritics folded, whitespace collapsed.
    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func words(_ text: String) -> [Substring] { text.split(whereSeparator: \.isWhitespace) }
    private static func names(_ person: PersonSnapshot) -> Set<String> {
        Set(([person.name] + person.aliases).map(key).filter { !$0.isEmpty })
    }
    private static func firstWord(_ name: String) -> String { words(key(name)).first.map(String.init) ?? "" }
    private static func differs(_ new: String, from old: String) -> Bool { !key(new).isEmpty && key(new) != key(old) }

    /// Appends new items that are not there yet (case-insensitive), keeping existing spelling.
    private static func merged(_ existing: [String], _ new: [String]) -> [String] {
        var seen = Set(existing.map(key))
        return existing + new.map(trim).filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }
}
