import XCTest
@testable import ThoughtVault

/// Regression: the "Snelle notitie" typed during a recording used to be discarded.
final class QuickNoteStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "QuickNoteStoreTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNoteStoredOnStopIsFoundThroughTranscriptAudioMapping() {
        QuickNoteStore.save("  Actiepunt: Lisa belt de klant  \n", audioFilename: "recording_1.wav", defaults: defaults)
        // Every processing path links its transcript to the audio file via localAudio_<taskId>.
        defaults.set("/Recordings/recording_1.wav", forKey: "localAudio_task-42")

        XCTAssertEqual(QuickNoteStore.note(forTranscriptId: "task-42", defaults: defaults), "Actiepunt: Lisa belt de klant")
        XCTAssertNil(QuickNoteStore.note(forTranscriptId: "other-task", defaults: defaults))
    }

    func testEmptyNoteIsNotStored() {
        QuickNoteStore.save("   \n", audioFilename: "recording_2.wav", defaults: defaults)
        XCTAssertNil(QuickNoteStore.note(audioFilename: "recording_2.wav", defaults: defaults))
    }

    func testPromptBlockCarriesNoteAsContext() {
        XCTAssertEqual(QuickNoteStore.promptBlock(nil), "")
        XCTAssertTrue(QuickNoteStore.promptBlock("Budget besproken").contains("Budget besproken"))
    }
}
