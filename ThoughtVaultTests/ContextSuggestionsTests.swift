// ContextSuggestionsTests.swift
// ThoughtVaultTests
//
// Parsing and storage of the term and people suggestions made after a notule.

import XCTest
@testable import ThoughtVault

@MainActor
final class ContextSuggestionsTests: XCTestCase {
    private var dir: URL!
    private var savedURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedURL = ContextSuggestions.url
        ContextSuggestions.url = dir.appendingPathComponent("context-suggestions.json")
    }

    override func tearDownWithError() throws {
        ContextSuggestions.url = savedURL
        try? FileManager.default.removeItem(at: dir)
    }

    private let transcript = "We bespraken het dossier met Pieter van Kaskop. De schade aan het dak is groot."

    func testParseStripsFencesAndLeadingText() {
        let raw = "Hier is het:\n```json\n{\"terms\": [{\"heard\": \"Kaskop\", \"canonical\": \"Kascop\", \"note\": \"Expertisebureau\"}]}\n```"
        let set = ContextSuggestions.parse(raw, transcript: transcript, entries: [], dismissed: [])
        XCTAssertEqual(set.terms, [TermSuggestion(heard: "Kaskop", canonical: "Kascop", note: "Expertisebureau")])
        XCTAssertTrue(set.people.isEmpty, "missing people key decodes as empty")
    }

    func testSkipNoticeIsStoredNextToSuggestionsAndNotifies() throws {
        let term = TermSuggestion(heard: "Kaskop", canonical: "Kascop", note: "")
        try ContextSuggestions.save(ContextSuggestionSet(terms: [term]), taskId: "t1")
        let posted = expectation(forNotification: .contextSuggestionsUpdated, object: nil) { $0.userInfo?["taskId"] as? String == "t1" }
        ContextSuggestions.recordSkip(.transcriptTooLong, taskId: "t1")
        wait(for: [posted], timeout: 1)
        let stored = try XCTUnwrap(ContextSuggestions.load(taskId: "t1"))
        XCTAssertEqual(stored.skipped, .transcriptTooLong)
        XCTAssertEqual(stored.terms, [term], "pending suggestions are kept")
        XCTAssertFalse(stored.isEmpty)
        XCTAssertTrue(ContextSuggestionSkip.tooLongForModel.notice.contains("te lang voor het gekozen model"))
    }

    func testParseInvalidJSONReturnsEmpty() {
        XCTAssertTrue(ContextSuggestions.parse("{\"terms\": [ {", transcript: transcript, entries: [], dismissed: []).isEmpty)
        XCTAssertTrue(ContextSuggestions.parse("geen json", transcript: transcript, entries: [], dismissed: []).isEmpty)
    }

    func testParseDropsTermWhoseHeardTextIsNotInTranscript() {
        let raw = #"{"terms": [{"heard": "Kas", "canonical": "Kascop"}, {"heard": "Gamma", "canonical": "Gama"}, {"heard": "kaskop", "canonical": "Kascop"}]}"#
        let set = ContextSuggestions.parse(raw, transcript: transcript, entries: [], dismissed: [])
        XCTAssertEqual(set.terms.map(\.heard), ["kaskop"], "partial word and absent word are dropped; match is case-insensitive")
        XCTAssertEqual(set.terms.first?.note, "", "missing note defaults to empty")
    }

    func testParseDropsAlreadyKnownAndDismissed() {
        let raw = """
        {"terms": [
          {"heard": "dak", "canonical": "Dakwerk BV"},
          {"heard": "schade", "canonical": "Schade"},
          {"heard": "dossier", "canonical": "Dossier-X"},
          {"heard": "Kaskop", "canonical": "Kascop", "note": "regel1\\nregel2 <b>\(String(repeating: "x", count: 300))"}
        ],
        "people": [
          {"name": "Pieter van Kaskop", "role": " schade-expert ", "matchedPersonId": "verzonnen"},
          {"name": "Anke Bakker"},
          {"name": "  "}
        ]}
        """
        let entries = [PersonalCorrection(canonical: "dakwerk bv", variants: ["dakwerk"])]
        let dismissed = [ContextSuggestions.dismissKey(for: .term(TermSuggestion(heard: "Dossier", canonical: "dossier-x", note: ""))),
                         "person:anke bakker"]
        let set = ContextSuggestions.parse(raw, transcript: transcript, entries: entries, dismissed: dismissed)
        XCTAssertEqual(set.terms.map(\.canonical), ["Kascop"], "known canonical, heard == canonical and dismissed are dropped")
        let note = set.terms.first?.note ?? ""
        XCTAssertLessThanOrEqual(note.utf16.count, 200)
        XCTAssertNil(note.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n<>")))
        XCTAssertEqual(set.people.map(\.name), ["Pieter van Kaskop"])
        XCTAssertEqual(set.people.first?.role, "schade-expert")
        XCTAssertNil(set.people.first?.matchedPersonId, "matching is not the AI's job")
        XCTAssertEqual(ContextSuggestions.dismissKey(for: .term(TermSuggestion(heard: "Kaskop", canonical: "Kascop", note: ""))), "term:kaskop→kascop")
    }

    func testParseCapsAtEightTermsAndEightPeople() {
        let words = (0..<12).map { "woord\($0)" }
        let terms = words.map { #"{"heard": "\#($0)", "canonical": "Term\#($0)"}"# }.joined(separator: ",")
        let people = (0..<12).map { #"{"name": "Persoon \#($0)"}"# }.joined(separator: ",")
        let set = ContextSuggestions.parse("{\"terms\": [\(terms)], \"people\": [\(people)]}",
                                           transcript: words.joined(separator: " "), entries: [], dismissed: [])
        XCTAssertEqual(set.terms.count, 8)
        XCTAssertEqual(set.people.count, 8)
    }

    func testParseSplitsSlashSeparatedSpellings() {
        let raw = #"{"terms": [{"heard": "Kaskop / Kazkop / dossier", "canonical": "Kascop", "note": "Bureau"}]}"#
        let set = ContextSuggestions.parse(raw, transcript: transcript, entries: [], dismissed: [])
        XCTAssertEqual(set.terms, [TermSuggestion(heard: "Kaskop", canonical: "Kascop", note: "Bureau"),
                                   TermSuggestion(heard: "dossier", canonical: "Kascop", note: "Bureau")],
                       "each spelling found in the transcript becomes its own term; absent ones are dropped")
    }

    func testParseDropsUnnamedPeopleAndTheUser() {
        let raw = #"{"people": [{"name": ""}, {"name": "michel knoop"}, {"name": "M. Knoop"}, {"name": "Peter", "heardAs": ["Michel Knoop"]}, {"name": "Mike de Boer", "heardAs": ["Mike"]}, {"name": "Pieter van Kaskop"}]}"#
        let set = ContextSuggestions.parse(raw, transcript: transcript, entries: [], dismissed: [], selfNames: ["Michel Knoop"], selfAliases: ["M. Knoop", "Mike"])
        XCTAssertEqual(set.people.map(\.name), ["Mike de Boer", "Pieter van Kaskop"],
                       "a heardAs equal to a self alias (a bare first name) does not drop someone else")
    }

    func testParseIgnoresThinkBlock() {
        let raw = "<think>Eerst {\"terms\": []} overwegen.</think>\n{\"terms\": [{\"heard\": \"Kaskop\", \"canonical\": \"Kascop\"}]}"
        let set = ContextSuggestions.parse(raw, transcript: transcript, entries: [], dismissed: [])
        XCTAssertEqual(set.terms.map(\.canonical), ["Kascop"])
    }

    func testStoreRoundTripRemoveAndDismiss() throws {
        let term = TermSuggestion(heard: "Kaskop", canonical: "Kascop", note: "")
        let person = PersonSuggestion(name: "Pieter", role: "", organization: "", responsibilities: [], topics: [], heardAs: [], matchedPersonId: nil)
        try ContextSuggestions.save(ContextSuggestionSet(terms: [term], people: [person]), taskId: "t1")
        try ContextSuggestions.save(ContextSuggestionSet(terms: [term], people: []), taskId: "t2")

        try ContextSuggestions.remove(taskId: "t1", item: .term(term))
        XCTAssertEqual(ContextSuggestions.load(taskId: "t1")?.terms, [])
        XCTAssertEqual(ContextSuggestions.load(taskId: "t1")?.people, [person])
        XCTAssertEqual(ContextSuggestions.load(taskId: "t2")?.terms, [term], "other tasks are untouched")
        try ContextSuggestions.remove(taskId: "t1", item: .person(person))
        XCTAssertNil(ContextSuggestions.load(taskId: "t1"), "an emptied set is removed")

        let corrections = dir.appendingPathComponent("personal-corrections.json")
        try PersonalCorrections.save([PersonalCorrection(canonical: "Kascop", variants: ["Kaskop"])], to: corrections)
        let key = ContextSuggestions.dismissKey(for: .person(person))
        try ContextSuggestions.dismiss(key: key, correctionsURL: corrections)
        try ContextSuggestions.dismiss(key: key, correctionsURL: corrections)
        let document = try JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: corrections))
        XCTAssertEqual(document.dismissed, ["person:pieter"])
        XCTAssertEqual(document.entries.map(\.canonical), ["Kascop"], "entries survive")
    }

    // MARK: - Size check

    func testFitsRejectsOversizedMessageForLocalModel() {
        let local = OpenAICompatibleLLMService(baseURL: "http://127.0.0.1:9", model: "test")   // 8,000-character chunks
        XCTAssertTrue(ContextSuggestions.fits(String(repeating: "a", count: 16_000), service: local))
        XCTAssertFalse(ContextSuggestions.fits(String(repeating: "a", count: 16_001), service: local))
    }

    /// The audit and chunk summaries share `complete`; it must never refuse a long source itself.
    func testCompleteDoesNotRefuseLongInput() async {
        let local = OpenAICompatibleLLMService(baseURL: "http://127.0.0.1:9", model: "test")
        do {
            _ = try await local.complete(system: "s", user: String(repeating: "a", count: 40_000))
            XCTFail("port 9 should refuse the connection")
        } catch LLMError.providerUnavailable {
            XCTFail("complete must not apply the context-step size limit")
        } catch {}
    }
}
