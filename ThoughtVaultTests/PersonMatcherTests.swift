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

    private func makeService() throws -> PersonDirectoryService {
        let container = try ModelContainer(
            for: TranscriptRecord.self, PersonProfile.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return PersonDirectoryService(container: container)
    }

    // MARK: - match

    func testExactNameMatches() {
        let anke = PersonProfile(name: "Anke Bakker")
        let people = PersonMatcher.candidates([anke, PersonProfile(name: "Jan Smit")])
        XCTAssertEqual(PersonMatcher.match(suggestion("anke bakker"), in: people), .existing(id: anke.id))
        XCTAssertEqual(PersonMatcher.match(suggestion("Kees"), in: people), .new)
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
    }
}
