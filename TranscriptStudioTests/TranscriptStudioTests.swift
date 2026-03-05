import XCTest
@testable import TranscriptStudio

final class TranscriptStudioTests: XCTestCase {
    func testModelsDecodable() throws {
        // Test that core models decode correctly.
        // The Transcript model uses "date" as the JSON key (via CodingKeys).
        let json = """
        {"id":"test-123","title":"Test vergadering","raw_transcription":"Dit is een test transcriptie.","notule_html":null,"tags":[],"date":"2026-03-04T12:00:00Z"}
        """.data(using: .utf8)!

        let transcript = try JSONDecoder().decode(Transcript.self, from: json)
        XCTAssertEqual(transcript.id, "test-123")
        XCTAssertEqual(transcript.title, "Test vergadering")
    }

    func testTaskStatusProgress() {
        XCTAssertEqual(TaskStatus.pending.progress, 0.0)
        XCTAssertEqual(TaskStatus.completed.progress, 1.0)
        XCTAssertFalse(TaskStatus.completed.isActive)
        XCTAssertTrue(TaskStatus.transcribing.isActive)
    }

    func testUploadFailureReasonRetryability() {
        XCTAssertFalse(UploadFailureReason.fileTooLarge.isRetryable)
        XCTAssertTrue(UploadFailureReason.serverError(500).isRetryable)
        XCTAssertTrue(UploadFailureReason.unknown.isRetryable)
    }
}
