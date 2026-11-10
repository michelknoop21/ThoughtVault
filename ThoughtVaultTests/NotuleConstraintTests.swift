import XCTest
@testable import ThoughtVault

final class NotuleConstraintTests: XCTestCase {
    // Ported from windows/src/services/__tests__/llm.decimal-constraints.test.ts:
    // "keeps the complete numeric constraint in the generation request: %s" and
    // "still enforces a prohibition after a normal sentence boundary" (constraint extraction in llm.ts).
    func testConstraintSentencesKeepDecimalDots() {
        for constraint in ["Niet 15.000 euro.", "Niet 1.500.000 euro.", "Niet 15.000,50 euro.", "Niet 15.5 euro."] {
            let raw = "Budgetcontrole. \(constraint) Milan controleert de techniek woensdag. Noor controleert de inhoud donderdag."
            XCTAssertEqual(NotuleAudit.constraintSentences(raw), [constraint])
        }
        XCTAssertEqual(NotuleAudit.constraintSentences("Niet 15.000 euro. Geen klantgegevens naar externe diensten."),
                       ["Niet 15.000 euro.", "Geen klantgegevens naar externe diensten."])
    }

    // Same sentence regex in `units` (notuleAudit.ts).
    func testUnitsKeepDecimalDots() {
        let units = NotuleAudit.units("Het budget is 12.450 euro inclusief btw.  Niet\n15.000 euro.\n\nNiet 15.5 euro!", prefix: "T")
        XCTAssertEqual(units.map(\.id), ["T1", "T2", "T3", "T4"])
        XCTAssertEqual(units.map(\.text), ["Het budget is 12.450 euro inclusief btw.", "Niet", "15.000 euro.", "Niet 15.5 euro!"])
    }

    // Ids are numbered after empty matches are dropped (filter, then map with index).
    func testUnitsNumberAfterDroppingEmpties() {
        XCTAssertEqual(NotuleAudit.units("Een.   \n   \nTwee?", prefix: "Q").map(\.id), ["Q1", "Q2"])
        XCTAssertEqual(NotuleAudit.units("Een.   \n   \nTwee?", prefix: "Q").map(\.text), ["Een.", "Twee?"])
    }

    // JavaScript `\b` is ASCII-only, so "é" counts as a boundary and "nietig" does not match.
    func testConstraintKeywordBoundaryIsASCII() {
        XCTAssertEqual(NotuleAudit.constraintSentences("éniet zo. Dat is nietig. Er is een OPEN VRAAG. NIET doen. Niet doen."),
                       ["éniet zo.", "Er is een OPEN VRAAG.", "NIET doen.", "Niet doen."])
    }

    // Duplicates are dropped, original order kept, matches only trimmed (not whitespace-normalised).
    func testConstraintSentencesAreUniqueAndTrimmed() {
        XCTAssertEqual(NotuleAudit.constraintSentences("Geen  budget.\nGeen  budget. Wel tijd."), ["Geen  budget."])
    }

    // parseAuditResponse: one complete fence or bare JSON.
    func testParseAuditResponse() throws {
        XCTAssertEqual(try NotuleAudit.parseAuditResponse("  ```JSON \r\n{\"a\":1}\r\n```  ") as? [String: Int], ["a": 1])
        XCTAssertEqual(try NotuleAudit.parseAuditResponse("```\n[1]\n```") as? [Int], [1])
        XCTAssertTrue(try NotuleAudit.parseAuditResponse("null") is NSNull)
        XCTAssertThrowsError(try NotuleAudit.parseAuditResponse("```json\n{}\n```\n```json\n{}\n```"))
        XCTAssertThrowsError(try NotuleAudit.parseAuditResponse("Zie: ```json\n{}\n```"))
        XCTAssertThrowsError(try NotuleAudit.parseAuditResponse(""))
    }

    // DOMPurify drops non-text tags but keeps their text, and escapes stray angle brackets.
    func testDraftForReviewKeepsTextOfDroppedTags() {
        XCTAssertEqual(NotuleAudit.draftForReview(#"<a href="x">Sam</a><P CLASS="x">Bram</P><!-- c --><video>weg</video>"#),
                       "Sam<p>Bram</p>")
        XCTAssertEqual(NotuleAudit.draftForReview("<<script>script>alert(1)</script>"), "&lt;")
    }

    func testFactualityRulesCopiedVerbatim() {
        XCTAssertTrue(NotuleAudit.factualityRules.hasPrefix("Behoud expliciete ontkenningen, verboden,"))
        XCTAssertTrue(NotuleAudit.factualityRules.hasSuffix("Controleer vóór het antwoorden alle besluiten en acties tegen de transcriptie op deze beperkingen en herstel weglatingen."))
    }
}
