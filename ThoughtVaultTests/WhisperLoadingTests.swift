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
}
