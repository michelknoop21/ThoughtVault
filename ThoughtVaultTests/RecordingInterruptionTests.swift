import XCTest
@testable import ThoughtVault

/// TV-000022: a system interruption (call, Siri, alarm) pauses the recording; it is not a failure.
final class RecordingInterruptionTests: XCTestCase {
    private func makeRecorder() -> (AudioRecorder, events: () -> [String]) {
        let recorder = AudioRecorder()
        recorder.isRecording = true
        recorder.recordAgain = { true }
        var events: [String] = []
        recorder.onInterruption = { events.append($0 ? "paused" : "resumed") }
        recorder.onSilentFailure = { _ in events.append("failure") }
        return (recorder, { events })
    }

    func testInterruptionPausesWithoutFailure() {
        let (recorder, events) = makeRecorder()
        recorder.interruptionBegan()
        XCTAssertTrue(recorder.isPaused)
        XCTAssertEqual(events(), ["paused"])
    }

    func testEndWithResumeContinuesAndExcludesTheInterruptionFromDuration() {
        let (recorder, events) = makeRecorder()
        recorder.interruptionBegan()
        Thread.sleep(forTimeInterval: 0.05)
        recorder.interruptionEnded(shouldResume: true)
        XCTAssertFalse(recorder.isPaused)
        XCTAssertEqual(events(), ["paused", "resumed"])
        XCTAssertGreaterThanOrEqual(recorder.accumulatedPauseDuration, 0.05)
    }

    func testEndWithoutResumeStaysPaused() {
        let (recorder, events) = makeRecorder()
        recorder.interruptionBegan()
        recorder.interruptionEnded(shouldResume: false)
        XCTAssertTrue(recorder.isPaused)
        XCTAssertEqual(events(), ["paused"])
        // The user resumes with the existing button.
        XCTAssertTrue(recorder.resumeRecording())
        XCTAssertFalse(recorder.isPaused)
    }

    func testUserPauseIsNotResumedByTheSystem() {
        let (recorder, events) = makeRecorder()
        recorder.pauseRecording()
        recorder.interruptionBegan()
        recorder.interruptionEnded(shouldResume: true)
        XCTAssertTrue(recorder.isPaused)
        XCTAssertEqual(events(), [])
    }

    func testManualResumeDuringInterruptionEndsTheSystemsClaim() {
        let (recorder, events) = makeRecorder()
        recorder.interruptionBegan()
        recorder.resumeRecording()
        recorder.pauseRecording()
        recorder.interruptionEnded(shouldResume: true)
        XCTAssertTrue(recorder.isPaused)
        XCTAssertEqual(events(), ["paused"])
    }

    func testRefusedResumeAfterInterruptionStaysPausedWithoutFailure() {
        let (recorder, events) = makeRecorder()
        recorder.recordAgain = { false }
        XCTAssertTrue(recorder.interruptionBegan())
        XCTAssertEqual(recorder.interruptionEnded(shouldResume: true), "refused")
        XCTAssertTrue(recorder.isPaused)
        XCTAssertFalse(recorder.interruptedBySystem)
        XCTAssertEqual(events(), ["paused"])
        // Once the system lets go, the user's resume works.
        recorder.recordAgain = { true }
        XCTAssertTrue(recorder.resumeRecording())
        XCTAssertFalse(recorder.isPaused)
    }

    func testRefusedManualResumeDuringInterruptionKeepsTheSystemsClaim() {
        let (recorder, events) = makeRecorder()
        recorder.interruptionBegan()
        recorder.recordAgain = { false }
        XCTAssertFalse(recorder.resumeRecording())
        XCTAssertTrue(recorder.isPaused)
        recorder.recordAgain = { true }
        recorder.interruptionEnded(shouldResume: true)
        XCTAssertFalse(recorder.isPaused)
        XCTAssertEqual(events(), ["paused", "resumed"])
    }

    func testRecorderWithoutAVAudioRecorderNeverCountsAsResumed() {
        let recorder = AudioRecorder()
        recorder.isRecording = true
        recorder.pauseRecording()
        XCTAssertFalse(recorder.resumeRecording())
        XCTAssertTrue(recorder.isPaused)
    }

    // MARK: - Screen state

    @MainActor
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @MainActor
    func testInterruptionPausesAndResumesTheScreenWithoutError() async {
        let vm = RecordingViewModel()
        vm.audioRecorder.isRecording = true
        vm.audioRecorder.recordAgain = { true }
        vm.recordingState = .recording
        vm.audioRecorder.interruptionBegan()
        await settle()
        XCTAssertEqual(vm.recordingState, .paused)
        XCTAssertNil(vm.recordingFailureError)
        vm.audioRecorder.interruptionEnded(shouldResume: true)
        await settle()
        XCTAssertEqual(vm.recordingState, .recording)
    }

    @MainActor
    func testRefusedManualResumeKeepsTheScreenPaused() async {
        let vm = RecordingViewModel()
        vm.audioRecorder.isRecording = true
        vm.audioRecorder.recordAgain = { false }
        vm.recordingState = .recording
        vm.audioRecorder.interruptionBegan()
        await settle()
        vm.resumeRecording()
        XCTAssertEqual(vm.recordingState, .paused)
        vm.audioRecorder.recordAgain = { true }
        vm.resumeRecording()
        XCTAssertEqual(vm.recordingState, .recording)
    }
}
