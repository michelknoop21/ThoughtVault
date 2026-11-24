import XCTest
@testable import ThoughtVault

/// TV-000022: a system interruption (call, Siri, alarm) pauses the recording; it is not a failure.
final class RecordingInterruptionTests: XCTestCase {
    private func makeRecorder() -> (AudioRecorder, events: () -> [String]) {
        let recorder = AudioRecorder()
        recorder.isRecording = true
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
}
