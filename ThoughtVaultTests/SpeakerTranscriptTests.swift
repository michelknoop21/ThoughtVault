import XCTest
@testable import ThoughtVault

final class SpeakerTranscriptTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            let name: String
            let pieces: [TimedPiece]
            let turns: [SpeakerTurn]
            let segments: [TranscriptSegment]
            let text: String
        }
        let cases: [Case]
    }

    /// The same file the Rust tests read, so both implementations stay equal.
    func testSharedContractFixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/speakers/contract-fixture.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.cases.count, 5)
        for item in fixture.cases {
            let segments = SpeakerTranscript.segments(pieces: item.pieces, turns: item.turns)
            XCTAssertEqual(segments.map(\.text), item.segments.map(\.text), item.name)
            XCTAssertEqual(segments.map(\.speakerId), item.segments.map(\.speakerId), item.name)
            for (got, want) in zip(segments, item.segments) {
                XCTAssertEqual(got.start, want.start, accuracy: 1e-9, item.name)
                XCTAssertEqual(got.end, want.end, accuracy: 1e-9, item.name)
            }
            XCTAssertEqual(SpeakerTranscript.text(segments), item.text, item.name)
        }
    }

    func testHasLabels() {
        XCTAssertTrue(SpeakerTranscript.hasLabels("Onbekende spreker: Nee.\nSpreker 1: Ja."))
        XCTAssertFalse(SpeakerTranscript.hasLabels("De spreker zei: Spreker 1 is er niet."))
        XCTAssertFalse(SpeakerTranscript.hasLabels("Gewone tekst."))
    }

    /// A label is not spoken text: it must not turn a neutral line into a mandatory constraint.
    func testLabelsAddNoAuditConstraints() {
        let labelled = "Spreker 1: Ja, dat klopt.\nOnbekende spreker: Ja, precies.\nSpreker 2: We delen geen klantgegevens."
        XCTAssertEqual(NotuleAudit.constraintSentences(labelled), ["Spreker 2: We delen geen klantgegevens."])
    }

    /// With labels in the transcript the model must not attach names to speakers itself.
    func testParticipantBlockDependsOnLabels() {
        let people = [Participant(name: "Jan de Vries")]
        let plain = people.notulePromptBlock(speakerLabels: false)
        XCTAssertEqual(plain, people.notulePromptBlock)
        XCTAssertTrue(plain.contains("wijs losse uitspraken niet aan individuele sprekers toe"))
        let labelled = people.notulePromptBlock(speakerLabels: true)
        XCTAssertTrue(labelled.contains("- Jan de Vries"))
        XCTAssertTrue(labelled.contains("koppel zelf geen naam uit deze lijst aan een sprekerlabel"))
        XCTAssertFalse(labelled.contains("op naam"))
    }
}
