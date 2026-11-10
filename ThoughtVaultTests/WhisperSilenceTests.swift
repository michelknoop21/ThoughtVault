import XCTest
import AVFoundation
@testable import ThoughtVault

/// Real-model checks that silence yields no hallucinated or repeated text. Skipped without the model.
final class WhisperSilenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        let model = LocalTranscriberFactory.defaultWhisperModel
        try XCTSkipUnless(WhisperModelStore.isInstalled(model), "Whisper model not installed")
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-silence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private var fixtureURL: URL {
        Bundle(for: Self.self).url(forResource: "dutch-qa", withExtension: "wav")!
    }

    private func transcribe(_ url: URL) async throws -> String {
        let t = WhisperKitTranscriber(model: LocalTranscriberFactory.defaultWhisperModel)
        let text = try await t.transcribe(url: url, profileId: nil) { _ in }
        return text
    }

    private func makeAudio(name: String, silenceSeconds: Double, appending speech: URL?) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let out = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        chunk.frameLength = 16_000 // zero-filled: one second of silence
        for _ in 0..<Int(silenceSeconds) { try out.write(from: chunk) }
        if let speech {
            let src = try AVAudioFile(forReading: speech, commonFormat: .pcmFormatInt16, interleaved: true)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(src.length))!
            try src.read(into: buf)
            try out.write(from: buf)
        }
        return url
    }

    private func sentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func assertNoRepeats(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let counts = Dictionary(grouping: sentences(text), by: { $0 }).mapValues(\.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 <= 2 }, "Repeated sentence in: \(text)", file: file, line: line)
    }

    func testLongSilenceProducesNoHallucinatedText() async throws {
        let url = try makeAudio(name: "silence.wav", silenceSeconds: 60, appending: nil)
        do {
            let text = try await transcribe(url)
            assertNoRepeats(text)
            XCTAssertLessThan(text.filter { $0.isLetter || $0.isNumber }.count, 20, "Hallucinated: \(text)")
        } catch LocalTranscriberError.emptyResult {
            // Empty output on pure silence is the ideal outcome.
        }
    }

    func testDutchClipStillTranscribes() async throws {
        let text = try await transcribe(fixtureURL)
        XCTAssertFalse(text.isEmpty)
        let hits = ["alex", "maandag", "installatie", "notulen"].filter { text.lowercased().contains($0) }
        XCTAssertGreaterThanOrEqual(hits.count, 2, "Got: \(text)")
    }

    func testSilenceThenSpeechHasNoTextBeforeSpeech() async throws {
        let url = try makeAudio(name: "silence-speech.wav", silenceSeconds: 60, appending: fixtureURL)
        let text = try await transcribe(url)
        let head = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)).lowercased()
        XCTAssertTrue(["begincontrole", "thoughtvault", "alex"].contains { head.contains($0) }, "Head: \(head)")
        assertNoRepeats(text)
    }
}
