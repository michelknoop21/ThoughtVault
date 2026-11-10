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
        XCTAssertEqual(NotuleAudit.constraintSentences("éniet doen. Dat is nietig. Er is een OPEN VRAAG. NIET doen. Niet doen."),
                       ["éniet doen.", "Er is een OPEN VRAAG.", "NIET doen.", "Niet doen."])
    }

    // A hedged or questioning negation is not a constraint.
    func testHedgedNegationsAreNotMandatory() {
        let raw = "Ik denk niet dat het dat is. Misschien zit het niet bij de regenpijp. Is dat niet raar? Nee, dat weet ik niet. Waarschijnlijk niet."
        XCTAssertEqual(NotuleAudit.constraintSentences(raw), [])
    }

    // Every negation without a hedge stays mandatory, also with pronouns or "dus"/"kan" (the review's
    // examples); a number, a permission, a decision or a strong keyword keeps even a hedged one mandatory.
    func testAnchoredAndFactualNegationsStayMandatory() {
        let kept = ["We delen geen klantgegevens met derden.", "We starten niet zonder handtekening van de klant.", "Dus de afspraak van vrijdag gaat niet door.", "We betalen geen duizend euro.", "De API kan niet zonder authenticatie worden gebruikt.", "Het budget is 12.450 euro inclusief btw, niet 15.000 euro.", "We mogen geen klantgegevens doorsturen.",
                    "Ik mag alleen de gevolgschade noteren, dat zit er niet in.", "Er is nog geen leverancier gekozen.",
                    "Bram is afwezig, dus ik weet het niet.", "We besluiten dit niet vandaag.", "Is de migratie op 16 november niet doorgegaan?",
                    "De bibliotheek is tijdens de interne proef niet toegankelijk voor bezoekers."]
        XCTAssertEqual(NotuleAudit.constraintSentences(kept.joined(separator: " ")), kept)
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
