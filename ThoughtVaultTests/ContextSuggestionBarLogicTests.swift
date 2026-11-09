// ContextSuggestionBarLogicTests.swift
// ThoughtVaultTests
//
// Texts and merge rules of the suggestion bar above the notule.

import XCTest
@testable import ThoughtVault

@MainActor
final class ContextSuggestionBarLogicTests: XCTestCase {

    private func remainder(role: String = "", organization: String = "", heardAs: [String] = []) -> PersonSuggestion {
        PersonSuggestion(name: "Jan de Vries", role: role, organization: organization, responsibilities: [],
                         topics: [], heardAs: heardAs, matchedPersonId: "p1")
    }

    private func snapshot(role: String = "", organization: String = "", aliases: [String] = []) -> PersonSnapshot {
        PersonSnapshot(PersonProfile(name: "Jan de Vries", role: role, organization: organization, aliases: aliases, isSelf: false))
    }

    func testCounterUsesDutchSingularAndPlural() {
        XCTAssertEqual(ContextSuggestionBarLogic.counter(terms: 2, people: 1), "2 termen, 1 persoon")
        XCTAssertEqual(ContextSuggestionBarLogic.counter(terms: 1, people: 2), "1 term, 2 personen")
        XCTAssertEqual(ContextSuggestionBarLogic.counter(terms: 0, people: 3), "3 personen")
        XCTAssertEqual(ContextSuggestionBarLogic.counter(terms: 1, people: 0), "1 term")
    }

    func testAmbiguousQuestionListsCandidates() {
        XCTAssertEqual(ContextSuggestionBarLogic.ambiguousQuestion(["Jan de Vries", "Jan Smit"]), "Is dit Jan de Vries of Jan Smit?")
        XCTAssertEqual(ContextSuggestionBarLogic.ambiguousQuestion(["A", "B", "C"]), "Is dit A, B of C?")
        XCTAssertEqual(ContextSuggestionBarLogic.ambiguousQuestion([]), "")
    }

    func testApplyRemainderKeepsFieldsWhenProposalIsEmpty() {
        let result = ContextSuggestionBarLogic.applyRemainder(remainder(), to: snapshot(role: "CTO", organization: "Acme"))
        XCTAssertEqual(result.role, "CTO")
        XCTAssertEqual(result.organization, "Acme")
    }

    func testApplyRemainderSetsRoleAndOrganization() {
        let result = ContextSuggestionBarLogic.applyRemainder(remainder(role: " Teamleider ", organization: "Gemeente"), to: snapshot(role: "CTO"))
        XCTAssertEqual(result.role, "Teamleider")
        XCTAssertEqual(result.organization, "Gemeente")
    }

    func testApplyRemainderMergesAliasesCaseInsensitively() {
        let result = ContextSuggestionBarLogic.applyRemainder(
            remainder(heardAs: ["JAN DE FRIES", "jan de vries", "Jan V.", "jan v.", " "]),
            to: snapshot(aliases: ["Jan de Fries"]))
        XCTAssertEqual(result.aliases, ["Jan de Fries", "Jan V."])
    }

    func testChangeSummaryDescribesEachChange() {
        let lines = ContextSuggestionBarLogic.changeSummary(
            remainder(role: "Teamleider", organization: "Gemeente", heardAs: ["Jan V.", "jan de vries"]),
            current: snapshot(role: "CTO"))
        XCTAssertEqual(lines, ["Rol: CTO → Teamleider", "Organisatie: Gemeente", "Ook bekend als: Jan V."])
        XCTAssertEqual(ContextSuggestionBarLogic.changeSummary(remainder(role: "CTO"), current: snapshot(role: "CTO")), [])
    }
}
