import XCTest
@testable import ThoughtVault

/// Runs tests/fixtures/glossary-automatch.json, shared with windows/src/services/__tests__/glossaryAutoMatch.test.ts.
final class GlossaryAutoMatchTests: XCTestCase {
    private struct Person: Decodable { var id: String; var name: String; var aliases: [String] }
    private struct Case: Decodable {
        var name: String; var transcript: String; var entries: [PersonalCorrection]; var people: [Person]
        var dismissed: [String]; var candidates: [[String]]; var answer: String; var text: String; var learned: [[String]]
    }
    private struct Fixture: Decodable { var soundKeys: [[String]]; var cases: [Case] }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "glossary-automatch", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    private func targets(_ c: Case) -> [MatchTarget] {
        GlossaryAutoMatch.targets(entries: c.entries, people: c.people.map { ($0.id, $0.name, $0.aliases) }, profileId: nil)
    }

    func testSoundKeys() throws {
        for pair in try fixture().soundKeys { XCTAssertEqual(GlossaryAutoMatch.soundKey(pair[0]), pair[1], pair[0]) }
    }

    func testFixture() throws {
        for c in try fixture().cases {
            let candidates = GlossaryAutoMatch.candidates(in: c.transcript, targets: targets(c), dismissed: c.dismissed)
            XCTAssertEqual(candidates.map { [$0.heard, $0.target.canonical] }, c.candidates, c.name)
            let result = GlossaryAutoMatch.apply(c.transcript, candidates: candidates, yes: GlossaryAutoMatch.parseAnswers(c.answer, count: candidates.count))
            XCTAssertEqual(result.text, c.text, c.name)
            XCTAssertEqual(result.learned.map { [$0.target.canonical, $0.heard] }, c.learned, c.name)
        }
    }

    func testGarbageMeansNo() async throws {
        let c = try fixture().cases[0]
        let targets = targets(c)
        let garbage = await GlossaryAutoMatch.run(c.transcript, targets: targets, dismissed: []) { _, _ in "geen idee" }
        XCTAssertEqual(garbage.text, c.transcript); XCTAssertTrue(garbage.learned.isEmpty)
        let failing = await GlossaryAutoMatch.run(c.transcript, targets: targets, dismissed: []) { _, _ in throw URLError(.cannotConnectToHost) }
        XCTAssertEqual(failing.text, c.transcript)
        let slow = await GlossaryAutoMatch.run(c.transcript, targets: targets, dismissed: [], timeout: .milliseconds(20)) { _, _ in
            try await Task.sleep(for: .seconds(30)); return "1 ja"
        }
        XCTAssertEqual(slow.text, c.transcript)
    }

    func testPromptBudgetAndSentenceLimit() {
        let long = (0..<40).map { "Zin \($0) met Jengo erin en verder heel veel woorden om de zin lang te maken tot ver voorbij de grens van honderdzestig tekens zodat inkorten nodig is." }.joined(separator: " ")
        let candidates = GlossaryAutoMatch.candidates(in: long, targets: GlossaryAutoMatch.targets(entries: [PersonalCorrection(canonical: "Yinga", variants: [])], people: [], profileId: nil), dismissed: [])
        XCTAssertLessThanOrEqual(candidates.count, 12)
        XCTAssertTrue(candidates.allSatisfy { ($0.sentence as NSString).length <= 160 && $0.sentence.contains($0.heard) })
        XCTAssertLessThanOrEqual(GlossaryAutoMatch.system.utf16.count + GlossaryAutoMatch.prompt(candidates).user.utf16.count, 1500)
    }
}
