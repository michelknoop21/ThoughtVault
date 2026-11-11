import XCTest
@testable import ThoughtVault

final class WhisperLoadingTests: XCTestCase {
    /// Explicit opt-in: uses a cached real model and synthetic audio, never user recordings.
    func testCachedModelTranscribesMultipleVADWindowsTwice() async throws {
        guard let path = ProcessInfo.processInfo.environment["THOUGHTVAULT_WHISPER_SMOKE_WAV"],
              let model = ProcessInfo.processInfo.environment["THOUGHTVAULT_WHISPER_SMOKE_MODEL"] else {
            throw XCTSkip("Set THOUGHTVAULT_WHISPER_SMOKE_WAV and THOUGHTVAULT_WHISPER_SMOKE_MODEL for real inference.")
        }
        let url = URL(fileURLWithPath: path)
        XCTAssertGreaterThan(try XCTUnwrap(AudioChunker.duration(of: url)), 60)
        let transcriber = WhisperKitTranscriber(model: model)
        for _ in 0..<2 {
            let text = try await transcriber.transcribe(url: url, profileId: nil) { _ in }
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Regression: a glossary must not cost transcript text. With the glossary
    /// sent as Whisper prompt, a 109 s file dropped from 291 to 110 words and a
    /// 29-min meeting came back empty. Explicit opt-in: cached real model and
    /// synthetic audio, never user recordings.
    func testGlossaryDoesNotShortenTranscript() async throws {
        guard let path = ProcessInfo.processInfo.environment["THOUGHTVAULT_WHISPER_SMOKE_WAV"],
              let model = ProcessInfo.processInfo.environment["THOUGHTVAULT_WHISPER_SMOKE_MODEL"] else {
            throw XCTSkip("Set THOUGHTVAULT_WHISPER_SMOKE_WAV and THOUGHTVAULT_WHISPER_SMOKE_MODEL for real inference.")
        }
        let url = URL(fileURLWithPath: path)
        let transcriber = WhisperKitTranscriber(model: model)
        func words(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

        // The test support directory is shared per process; remove the glossary so
        // other Whisper tests keep running without one.
        try? FileManager.default.removeItem(at: PersonalCorrections.url)
        defer { try? FileManager.default.removeItem(at: PersonalCorrections.url) }
        let without = try await transcriber.transcribe(url: url, profileId: nil) { _ in }

        try PersonalCorrections.save([
            PersonalCorrection(canonical: "Voorbeeldpartner", variants: []),
            PersonalCorrection(canonical: "Kwartaalcijfers", variants: []),
            PersonalCorrection(canonical: "Noor", variants: []),
        ])
        let vocabulary = await MainActor.run { PersonalVocabulary.terms(profileId: nil) }
        XCTAssertFalse(vocabulary.isEmpty, "The glossary must be active for this comparison.")
        let with = try await transcriber.transcribe(url: url, profileId: nil) { _ in }

        let attachment = XCTAttachment(string: "zonder woordenlijst: \(words(without)) woorden\nmet woordenlijst: \(words(with)) woorden\n\n\(with)")
        attachment.name = "Whisper ASR with and without glossary"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(words(without), 0)
        XCTAssertGreaterThanOrEqual(Double(words(with)), 0.9 * Double(words(without)),
                                    "A glossary must not make the transcript shorter.")
    }
}
