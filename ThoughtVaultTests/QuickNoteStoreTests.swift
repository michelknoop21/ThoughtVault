import XCTest
import AVFoundation
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

    func testDraftEditsReplaceAndClearingRemovesOnlyThatRecordingNote() {
        QuickNoteStore.saveDraft("Eerste punt", audioFilename: "current.wav", defaults: defaults)
        QuickNoteStore.save("Andere opname", audioFilename: "other.wav", defaults: defaults)
        QuickNoteStore.saveDraft("Eerste punt\nTweede punt", audioFilename: "current.wav", defaults: defaults)
        XCTAssertEqual(QuickNoteStore.note(audioFilename: "current.wav", defaults: defaults), "Eerste punt\nTweede punt")
        QuickNoteStore.saveDraft(" \n", audioFilename: "current.wav", defaults: defaults)
        XCTAssertNil(QuickNoteStore.note(audioFilename: "current.wav", defaults: defaults))
        XCTAssertEqual(QuickNoteStore.note(audioFilename: "other.wav", defaults: defaults), "Andere opname")
    }

    func testPromptBlockCarriesNoteAsContext() {
        XCTAssertEqual(QuickNoteStore.promptBlock(nil), "")
        XCTAssertTrue(QuickNoteStore.promptBlock("Budget besproken").contains("Budget besproken"))
    }

    func testPromptBlockAsksForRewrittenNotesSection() {
        let block = QuickNoteStore.promptBlock("Budget besproken")
        XCTAssertTrue(block.contains("<h2>Notities</h2>"))
        XCTAssertTrue(block.contains("Herschrijf"))
    }

    func testEnsureNotesSectionAppendsEscapedNoteWhenMissing() {
        let html = QuickNoteStore.ensureNotesSection("<h2>Besluiten</h2><p>Ja</p>", note: "A & B <x>\nregel 2")
        XCTAssertEqual(html, "<h2>Besluiten</h2><p>Ja</p><h2>Notities</h2><p>A &amp; B &lt;x&gt;<br>regel 2</p>")
    }

    func testEnsureNotesSectionKeepsExistingSectionAndNoNote() {
        let withSection = "<p>x</p><H2 class=\"a\"> Notities </H2><p>herschreven</p>"
        XCTAssertEqual(QuickNoteStore.ensureNotesSection(withSection, note: "ruw"), withSection)
        XCTAssertEqual(QuickNoteStore.ensureNotesSection("<p>x</p>", note: nil), "<p>x</p>")
        XCTAssertEqual(QuickNoteStore.ensureNotesSection("<p>x</p>", note: "  \n"), "<p>x</p>")
    }

    func testEnsureNotesSectionGoesBeforeClosingBody() {
        XCTAssertEqual(QuickNoteStore.ensureNotesSection("<body><p>x</p></body>", note: "n"),
                       "<body><p>x</p><h2>Notities</h2><p>n</p></body>")
    }
    func testNotebookPreservesEditableActionsAndCompletionState() {
        let original = "Afspraken\n\nContext\n- [ ] Alex belt de klant\n- [x] Toegang geregeld"
        var note = QuickNoteDocument(original)
        XCTAssertEqual(note.notes, "Afspraken\n\nContext")
        XCTAssertEqual(note.items.count, 2)
        XCTAssertEqual(note.text, original)
        note.items[0].done = true
        note.items[0].text = "Alex mailt de klant"
        let restored = QuickNoteDocument(note.text)
        XCTAssertTrue(restored.items[0].done)
        XCTAssertEqual(restored.items[0].text, "Alex mailt de klant")
        XCTAssertTrue(restored.items[1].done)
    }

    func testOwnNotesExportChoiceNeverRemovesOrdinaryMeetingSections() {
        let original = "<body><h2>Notities</h2><p>Gewone vergaderinhoud.</p></body>"
        let note = "Eigen & <script>\n- [ ] Open actie\n- [x] Afgerond"
        let withNotes = QuickNoteStore.exportHTML(original, note: note, includeNotes: true)
        XCTAssertTrue(withNotes.contains("Eigen notities"))
        XCTAssertTrue(withNotes.contains("&lt;script&gt;"))
        XCTAssertTrue(withNotes.contains("☑ Afgerond"))
        XCTAssertEqual(QuickNoteStore.exportHTML(withNotes, note: note, includeNotes: false), original)
        XCTAssertEqual(QuickNoteStore.exportHTML(withNotes, note: note, includeNotes: true), withNotes)
        let edited = withNotes.replacingOccurrences(of: "Open actie", with: "Bewerkte actie")
        XCTAssertEqual(QuickNoteStore.exportHTML(edited, note: note, includeNotes: true), edited)
        // An iCloud document can have its section even when its audio is on another device.
        XCTAssertEqual(QuickNoteStore.exportHTML(withNotes, note: nil, includeNotes: true), withNotes)
        XCTAssertEqual(QuickNoteStore.exportHTML(withNotes, note: nil, includeNotes: false), original)
        let noComments = withNotes.replacingOccurrences(of: "<!--thoughtvault-own-notes-->", with: "").replacingOccurrences(of: "<!--/thoughtvault-own-notes-->", with: "")
        XCTAssertEqual(QuickNoteStore.withoutOwnNotes(noComments), original)
    }

    func testRecordingIdentitySurvivesReloadAndIsIsolatedPerAudio() {
        let identity = RecordingIdentity(title: "Eigen titel", calendarID: "event-42", calendarTitle: "Agenda-afspraak", calendarStart: Date(timeIntervalSince1970: 1_000), calendarURL: nil)
        identity.save(audioFilename: "current.wav", defaults: defaults)
        XCTAssertEqual(RecordingIdentity.load(audioFilename: "current.wav", defaults: defaults), identity)
        XCTAssertNil(RecordingIdentity.load(audioFilename: "other.wav", defaults: defaults))
    }

    func testExplicitAudioOptimizationKeepsOriginalAndLimitsPeak() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("original.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        for amplitude: Float in [0, 0.01, 1] {
            do {
                let file = try AVAudioFile(forWriting: source, settings: format.settings)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 40_001))
                buffer.frameLength = buffer.frameCapacity
                buffer.floatChannelData![0].initialize(repeating: amplitude, count: Int(buffer.frameLength))
                try file.write(from: buffer)
            }
            let before = try Data(contentsOf: source)
            let result = try await AudioPreConverter.transcriptionInput(source, optimize: true) { _ in }
            defer { if result != source { try? FileManager.default.removeItem(at: result) } }
            XCTAssertNotEqual(result, source)
            XCTAssertEqual(try Data(contentsOf: source), before)
            let read = try AVAudioFile(forReading: result)
            XCTAssertEqual(read.length, 40_001)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: read.processingFormat, frameCapacity: 1024))
            try read.read(into: buffer)
            let expected: Float = amplitude > 0 ? min(amplitude * pow(10, 12 / 20), pow(10, -1 / 20)) : 0
            XCTAssertEqual(buffer.floatChannelData![0][0], expected, accuracy: 0.00001)
        }
        let missing = dir.appendingPathComponent("missing.wav")
        let fallback = try await AudioPreConverter.transcriptionInput(missing, optimize: true) { _ in }
        XCTAssertEqual(fallback, missing)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AudioPreConverter.transcriptionInput(source, optimize: true) { _ in }
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled optimization continued") }
        catch is CancellationError { }
    }

}
