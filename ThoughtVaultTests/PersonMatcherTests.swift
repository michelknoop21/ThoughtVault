// PersonMatcherTests.swift
// ThoughtVaultTests
//
// Linking people from a conversation to the directory and filling in their profiles.

import XCTest
import SwiftData
@testable import ThoughtVault

@MainActor
final class PersonMatcherTests: XCTestCase {
    private var dir: URL!
    private var savedURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("matcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedURL = ContextHistory.url
        ContextHistory.url = dir.appendingPathComponent("context-history.json")
    }

    override func tearDownWithError() throws {
        ContextHistory.url = savedURL
        try? FileManager.default.removeItem(at: dir)
    }

    private func suggestion(_ name: String, role: String = "", organization: String = "",
                            responsibilities: [String] = [], topics: [String] = [], heardAs: [String] = []) -> PersonSuggestion {
        PersonSuggestion(name: name, role: role, organization: organization, responsibilities: responsibilities,
                         topics: topics, heardAs: heardAs, matchedPersonId: nil)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: TranscriptRecord.self, PersonProfile.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeService() throws -> PersonDirectoryService {
        PersonDirectoryService(container: try makeContainer())
    }

    // MARK: - match

    func testExactNameMatches() {
        let anke = PersonProfile(name: "Anke Bakker")
        let people = PersonMatcher.candidates([anke, PersonProfile(name: "Jan Smit")])
        XCTAssertEqual(PersonMatcher.match(suggestion("anke bakker"), in: people), .existing(id: anke.id))
        XCTAssertEqual(PersonMatcher.match(suggestion("Kees"), in: people), .new)
        XCTAssertEqual(PersonMatcher.match(suggestion(" Ánke  Bakker "), in: people), .existing(id: anke.id),
                       "diacritics and extra whitespace are folded")
    }

    func testOneWordHeardAsNeverFallsBackToFirstName() {
        let people = PersonMatcher.candidates([PersonProfile(name: "Pieter Jansen")])
        XCTAssertEqual(PersonMatcher.match(suggestion("Pieter van Kaskop", heardAs: ["Pieter"]), in: people), .new)
    }

    func testOneWordHeardAsDoesNotMatchAliasExactly() {
        let people = PersonMatcher.candidates([PersonProfile(name: "Anke Bakker", aliases: ["Anke"])])
        XCTAssertEqual(PersonMatcher.match(suggestion("Anke de Boer", heardAs: ["Anke"]), in: people), .new)
    }

    func testAliasMatches() {
        let anke = PersonProfile(name: "Anke Bakker", aliases: ["Anke B."])
        let people = PersonMatcher.candidates([anke])
        XCTAssertEqual(PersonMatcher.match(suggestion("A. Bakker", heardAs: ["anke b."]), in: people), .existing(id: anke.id))
        XCTAssertEqual(PersonMatcher.match(suggestion("Anke B."), in: people), .existing(id: anke.id))
    }

    func testAmbiguousFirstNameIsNotAutoLinked() {
        let devries = PersonProfile(name: "Jan de Vries"), smit = PersonProfile(name: "Jan Smit")
        let people = PersonMatcher.candidates([devries, smit, PersonProfile(name: "Anke Bakker")])
        XCTAssertEqual(PersonMatcher.match(suggestion("Jan"), in: people), .ambiguous([devries.id, smit.id]))
        XCTAssertEqual(PersonMatcher.match(suggestion("Anke"), in: people), .existing(id: people[2].id),
                       "a unique first name links")
    }

    func testSelfProfileIsIgnored() {
        let me = PersonProfile(name: "Michel Knoop", isSelf: true)
        XCTAssertEqual(PersonMatcher.match(suggestion("Michel Knoop"), in: PersonMatcher.candidates([me])), .new)
    }

    // MARK: - autoApply

    func testAutoApplyAddsResponsibilitiesWithoutDuplicates() throws {
        let service = try makeService()
        let person = PersonProfile(name: "Anke Bakker", expertiseTags: ["Dakschade"])
        person.responsibilities = ["rapport opstellen"]
        try service.add(person)

        let rest = try PersonMatcher.autoApply(
            suggestion("Anke Bakker", responsibilities: ["Rapport opstellen", "Offerte sturen"], topics: ["dakschade", "Vochtmeting"]),
            to: person.id, profileName: "Schade-expertise", taskId: "T1", service: service)

        XCTAssertNil(rest)
        XCTAssertEqual(person.responsibilities, ["rapport opstellen", "Offerte sturen"])
        XCTAssertEqual(person.expertiseTags, ["Dakschade", "Vochtmeting"])
        XCTAssertEqual(person.meetingTypes, ["Schade-expertise"])
    }

    func testAutoApplyNeverOverwritesRoleButReturnsProposal() throws {
        let service = try makeService()
        let person = PersonProfile(name: "Anke Bakker", role: "Projectleider", aliases: ["Anke B."])
        try service.add(person)

        let rest = try XCTUnwrap(PersonMatcher.autoApply(
            suggestion("Anke Bakker", role: "Directeur", organization: "Kascop", heardAs: ["Anke B.", "Anke Bakkers"]),
            to: person.id, profileName: "", taskId: "T1", service: service))

        XCTAssertEqual(person.role, "Projectleider")
        XCTAssertEqual(person.organization, "")
        XCTAssertEqual(rest.role, "Directeur")
        XCTAssertEqual(rest.organization, "Kascop", "an empty organization is still only proposed")
        XCTAssertEqual(rest.heardAs, ["Anke Bakkers"])
        XCTAssertEqual(rest.matchedPersonId, person.id)
    }

    func testAutoApplyRecordsHistoryEntry() throws {
        let service = try makeService()
        let person = PersonProfile(name: "Anke Bakker")
        try service.add(person)

        _ = try PersonMatcher.autoApply(suggestion("Anke Bakker", topics: ["Dakschade"]),
                                        to: person.id, profileName: "Overleg", taskId: "T1", service: service)

        let versions = ContextHistory.versions(kind: .person, itemId: person.id)
        XCTAssertEqual(versions.map(\.source), ["gesprek:T1"])
    }

    // MARK: - Participants

    func testParticipantDecodesWithoutPersonId() throws {
        let decoded = try JSONDecoder().decode([Participant].self, from: Data(#"[{"name":"Anke","role":"","organization":""}]"#.utf8))
        XCTAssertEqual(decoded, [Participant(name: "Anke")])
        XCTAssertNil(decoded[0].personId)
    }

    func testLinkedParticipantsSetsPersonIdOnExactMatch() {
        let anke = PersonProfile(name: "Anke Bakker", aliases: ["Anke B."])
        let linked = PersonMatcher.linked([Participant(name: "anke b."), Participant(name: "Kees")],
                                          to: PersonMatcher.candidates([anke]))
        XCTAssertEqual(linked.map(\.personId), [anke.id, nil])

        var kept = Participant(name: "Anke Bakker")
        kept.personId = "other"
        XCTAssertEqual(PersonMatcher.linked([kept], to: PersonMatcher.candidates([anke])).map(\.personId), ["other"],
                       "an existing link is never replaced")
    }

    // MARK: - link

    func testLinkRoutesAmbiguousMatchedAndNewPeople() throws {
        let container = try makeContainer()
        let service = PersonDirectoryService(container: container)
        let store = LocalTranscriptStore(container: container)
        let devries = PersonProfile(name: "Jan de Vries"), smit = PersonProfile(name: "Jan Smit")
        let anke = PersonProfile(name: "Anke Bakker")
        for person in [devries, smit, anke] { try service.add(person) }
        let record = TranscriptRecord(taskId: "T1", title: "Overleg")
        record.participants = [Participant(name: "Anke Bakker"), Participant(name: "Kees de Wit")]
        try store.save(record)

        let set = ContextSuggestionSet(
            terms: [TermSuggestion(heard: "Kaskop", canonical: "Kascop", note: "")],
            people: [suggestion("Jan"), suggestion("Anke Bakker", topics: ["Dakschade"]), suggestion("Kees de Wit")])
        let kept = PersonMatcher.link(set, taskId: "T1", profileName: "Overleg", service: service, store: store)

        XCTAssertEqual(kept.terms, set.terms)
        XCTAssertEqual(kept.people.map(\.name), ["Jan", "Kees de Wit"], "the fully applied match is not proposed")
        XCTAssertEqual(Set(kept.people[0].candidateIds), [devries.id, smit.id])
        XCTAssertNil(kept.people[0].matchedPersonId)
        XCTAssertEqual(kept.people[1].candidateIds, [])
        XCTAssertNil(kept.people[1].matchedPersonId)
        XCTAssertEqual(anke.expertiseTags, ["Dakschade"])
        XCTAssertEqual(anke.meetingTypes, ["Overleg"])
        XCTAssertEqual(store.record(forTaskId: "T1")?.participants.map(\.personId), [anke.id, nil])
        XCTAssertNotNil(store.record(forTaskId: "T1")?.participantsJSON?.range(of: anke.id), "the link is saved")
    }
}
