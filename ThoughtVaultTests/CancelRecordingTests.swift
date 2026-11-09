import XCTest
@testable import ThoughtVault

final class CancelRecordingTests: XCTestCase {
    func testStopClearsCurrentRecordingURL() {
        let recorder = AudioRecorder()
        let url = URL(fileURLWithPath: "/tmp/session.wav")
        recorder.isRecording = true
        recorder.currentRecordingURL = url
        XCTAssertEqual(recorder.finishSession(), url)
        XCTAssertNil(recorder.currentRecordingURL)
        XCTAssertNil(recorder.finishSession())
    }

    func testStaleURLIsNeverReturnedWhenNotRecording() async {
        let recorder = AudioRecorder()
        recorder.currentRecordingURL = URL(fileURLWithPath: "/tmp/previous.wav")
        XCTAssertNil(recorder.finishSession())
        let url = await recorder.stopRecording(discardingTooSmall: false)
        XCTAssertNil(url)
    }

    func testCancelDeletesOnlyThisSessionsFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let previous = dir.appendingPathComponent("previous.wav")
        let session = dir.appendingPathComponent("session.wav")
        let system = dir.appendingPathComponent("system.wav")
        for u in [previous, session, system] { try Data([1]).write(to: u) }

        AudioRecorder.filesToDiscard(sessionMicURL: session, systemURL: system, microphoneURL: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: system.path))
    }

    func testSystemOnlyCancelKeepsPreviousMicFile() {
        let previous = URL(fileURLWithPath: "/tmp/previous-mic.wav")
        let files = AudioRecorder.filesToDiscard(sessionMicURL: nil, systemURL: URL(fileURLWithPath: "/tmp/sys.wav"), microphoneURL: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), ["sys.wav"])
        XCTAssertFalse(files.contains(previous))
    }
}
