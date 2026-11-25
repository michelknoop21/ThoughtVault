import XCTest
import AVFoundation
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

    // MARK: Engine timings

    func testChunkPiecesAreShiftedOntoOneTimeline() {
        let a = TimedPiece(start: 1, end: 2, text: "een")
        let b = TimedPiece(start: 0.5, end: 1, text: "twee")
        XCTAssertEqual(TimedPiece.offset([[a], [], [b]], chunkDuration: 55),
                       [a, TimedPiece(start: 110.5, end: 111, text: "twee")])
    }

    func testAppleSpeechSegmentsBecomePieces() {
        XCTAssertEqual(OnDeviceTranscriber.pieces([(text: "Goedemorgen", start: 0.4, duration: 0.7), (text: "allemaal", start: 1.2, duration: 0.5)]),
                       [TimedPiece(start: 0.4, end: 1.1, text: "Goedemorgen"), TimedPiece(start: 1.2, end: 1.7, text: "allemaal")])
        // No timings at all: no pieces rather than every word at zero.
        XCTAssertEqual(OnDeviceTranscriber.pieces([(text: "Hallo", start: 0, duration: 0), (text: "daar", start: 0, duration: 0)]), [])
    }

    #if canImport(WhisperKit)
    /// Times are binary-exact (4.25, not 4.2): WhisperKit gives Float seconds.
    func testWhisperKitSegmentsLoseSpecialTokensAndSilenceMarks() {
        let pieces = WhisperKitTranscriber.pieces([
            (start: 0, end: 4.25, text: "<|startoftranscript|><|nl|><|transcribe|><|0.00|> Het rapport gaat vrijdag weg.<|4.24|>"),
            (start: 4.25, end: 6, text: "<|4.24|> ***<|6.00|>"),
            (start: 6, end: 7.5, text: "<|6.00|> Dat pak ik op.<|7.50|><|endoftext|>"),
        ])
        XCTAssertEqual(pieces, [TimedPiece(start: 0, end: 4.25, text: "Het rapport gaat vrijdag weg."),
                                TimedPiece(start: 6, end: 7.5, text: "Dat pak ik op.")])
    }
    #endif

    // MARK: Phase 2: storage and the microphone channel

    func testSpeakerFieldsRoundTripAndStayNilWhenEmpty() {
        let record = TranscriptRecord(id: "t", taskId: "t", title: "t", filename: "f.wav", rawTranscription: "x",
                                      notuleHtml: "", profileId: "p", source: "local")
        XCTAssertNil(record.segmentsJSON)
        let segments = [TranscriptSegment(start: 0, end: 1.5, text: "Ja.", speakerId: "S1"),
                        TranscriptSegment(start: 1.5, end: 2, text: "Nee.", speakerId: nil)]
        record.segments = segments
        record.speakerNames = ["S1": SpeakerName(name: "Jan de Vries", confirmed: false, evidence: "De enige stem op je microfoon")]
        XCTAssertEqual(record.segments, segments)
        XCTAssertEqual(record.speakerNames["S1"]?.name, "Jan de Vries")
        XCTAssertEqual(record.speakerNames["S1"]?.confirmed, false)
        record.segments = []
        record.speakerNames = [:]
        XCTAssertNil(record.segmentsJSON)
        XCTAssertNil(record.speakerNamesJSON)
    }

    /// Writes a 16 kHz file from per-second (left, right) levels; one channel when `right` is nil.
    private func stereo(_ seconds: [(Float, Float?)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("channels-\(UUID().uuidString).wav")
        let channels: AVAudioChannelCount = seconds.first?.1 == nil ? 1 : 2
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: channels))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for (left, right) in seconds {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
            buffer.frameLength = 16_000
            for i in 0..<16_000 {
                // A tone, so the level is the same in every block.
                let wave = Float(sin(Double(i) * 0.05))
                buffer.floatChannelData![0][i] = left * wave
                if channels == 2 { buffer.floatChannelData![1][i] = (right ?? 0) * wave }
            }
            try file.write(from: buffer)
        }
        return url
    }

    func testOneVoiceClearlyOnTheMicrophoneIsLocal() throws {
        // S1 speaks into the microphone, with a little leak to the system side; S2 is the call.
        let url = try stereo([(0.3, 0.02), (0.02, 0.3), (0.3, 0.02)])
        defer { try? FileManager.default.removeItem(at: url) }
        let segments = [TranscriptSegment(start: 0, end: 1, text: "a", speakerId: "S1"),
                        TranscriptSegment(start: 1, end: 2, text: "b", speakerId: "S2"),
                        TranscriptSegment(start: 2, end: 3, text: "c", speakerId: "S1")]
        XCTAssertEqual(try SpeakerDiarizer.localSpeaker(stereo: url, segments: segments), "S1")
    }

    func testTwoVoicesOnTheMicrophoneGiveNoLocalSpeaker() throws {
        // A meeting room: both voices reach the microphone, the microphone is no evidence of who is "me".
        let url = try stereo([(0.3, 0.0), (0.25, 0.0), (0.01, 0.3)])
        defer { try? FileManager.default.removeItem(at: url) }
        let segments = [TranscriptSegment(start: 0, end: 1, text: "a", speakerId: "S1"),
                        TranscriptSegment(start: 1, end: 2, text: "b", speakerId: "S2"),
                        TranscriptSegment(start: 2, end: 3, text: "c", speakerId: "S3")]
        XCTAssertNil(try SpeakerDiarizer.localSpeaker(stereo: url, segments: segments))
    }

    func testLoudspeakerLeakDoesNotMakeTheCallLocal() throws {
        // S2 is heard on the microphone through the loudspeakers, but far louder on the system side.
        let url = try stereo([(0.3, 0.0), (0.1, 0.3)])
        defer { try? FileManager.default.removeItem(at: url) }
        let segments = [TranscriptSegment(start: 0, end: 1, text: "a", speakerId: "S1"),
                        TranscriptSegment(start: 1, end: 2, text: "b", speakerId: "S2")]
        XCTAssertEqual(try SpeakerDiarizer.localSpeaker(stereo: url, segments: segments), "S1")
    }

    func testMonoRecordingHasNoChannelEvidence() throws {
        let url = try stereo([(0.3, nil), (0.3, nil)])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(try SpeakerDiarizer.localSpeaker(stereo: url, segments: [TranscriptSegment(start: 0, end: 2, text: "a", speakerId: "S1")]))
    }

    func testNoModelMeansNoLabelsAndNoDownload() async {
        guard !SpeakerDiarizer.isInstalled else { return }
        let timed = TimedTranscript(text: "Ja.", pieces: [TimedPiece(start: 0, end: 1, text: "Ja.")])
        let labels = await SpeakerDiarizer.label(timed, audio: URL(fileURLWithPath: "/nonexistent.wav"), selfName: "Jan")
        XCTAssertNil(labels)
        XCTAssertFalse(SpeakerDiarizer.isInstalled)
    }
}
