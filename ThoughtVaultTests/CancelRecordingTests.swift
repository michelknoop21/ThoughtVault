import XCTest
#if os(macOS)
import AppKit
#endif
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
#if os(macOS)
    @MainActor
    func testSystemCaptureThatNeverStartedReturnsNoURL() async {
        let capture = SystemAudioCapture()
        capture.currentOutputURL = URL(fileURLWithPath: "/tmp/earlier-system.wav")
        let result = await capture.stopCapture()
        XCTAssertNil(result.systemAudioURL)
    }

    @MainActor
    func testSystemStopReturnsSessionURLOnce() async {
        let capture = SystemAudioCapture()
        let url = URL(fileURLWithPath: "/tmp/session-system.wav")
        capture.isCapturing = true
        capture.currentOutputURL = url
        let first = await capture.stopCapture()
        XCTAssertEqual(first.systemAudioURL, url)
        XCTAssertNil(capture.currentOutputURL)
        let second = await capture.stopCapture()
        XCTAssertNil(second.systemAudioURL)
    }

    @MainActor
    func testMicrophoneCancelKeepsEarlierSystemAudio() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let earlierSystem = dir.appendingPathComponent("system_audio_earlier.wav")
        let session = dir.appendingPathComponent("session.wav")
        for u in [earlierSystem, session] { try Data([1]).write(to: u) }

        let vm = RecordingViewModel()
        vm.selectedMode = .microphone
        vm.systemAudioCapture.currentOutputURL = earlierSystem // left over from an earlier session
        vm.audioRecorder.isRecording = true
        vm.audioRecorder.currentRecordingURL = session
        vm.recordingState = .recording
        await vm.cancelRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: earlierSystem.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.path))
        XCTAssertEqual(vm.recordingState, .idle)
    }

    /// Sleep is stopped by the view model; the recorder must not end the session itself,
    /// or `finishSession()` returns nil and combined mode never mixes.
    func testSleepLeavesSessionForTheViewModel() {
        let recorder = AudioRecorder()
        let url = URL(fileURLWithPath: "/tmp/sleep-session.wav")
        recorder.isRecording = true
        recorder.currentRecordingURL = url
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(recorder.finishSession(), url)
    }
#endif
}
