import XCTest
import AVFoundation
@testable import ThoughtVault

// Ported from windows/src/services/__tests__/localPipeline.retry.test.ts: native error text
// reaches the task, and a missing speech model fails clearly instead of downloading.

final class LocalPipelineTests: XCTestCase {
    @MainActor
    func testSyncedRecordWithServerIDUsesLocalStorage() throws {
        let id = "synced-" + UUID().uuidString
        let record = TranscriptRecord(taskId: id, title: "Lokale gesynchroniseerde notule", rawTranscription: "Besluit", notuleHtml: "<p>Besluit</p>")
        try LocalTranscriptStore.shared.save(record)
        defer { try? LocalTranscriptStore.shared.delete(taskId: id) }
        XCTAssertTrue(isLocalTranscript(id))
        XCTAssertTrue(isLocalTranscript("local-test"))
        XCTAssertFalse(isLocalTranscript("unknown-" + UUID().uuidString))
    }


    func testMissingModelThrowsWithoutDownload() async {
        let transcriber = WhisperKitTranscriber(model: "openai_whisper-test", isInstalled: { _ in false })
        do {
            _ = try await transcriber.transcribe(url: URL(fileURLWithPath: "/nonexistent.wav"), profileId: nil) { _ in }
            XCTFail("Expected modelNotInstalled")
        } catch let error as LocalTranscriberError {
            guard case .modelNotInstalled(let variant) = error else { return XCTFail("Wrong error: \(error)") }
            XCTAssertEqual(variant, "openai_whisper-test")
            XCTAssertEqual(error.localizedDescription,
                           "Het spraakmodel is nog niet gedownload. Download het in Instellingen; de opname blijft bewaard.")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testParakeetWithoutModelThrowsModelNotInstalled() async {
        let transcriber = ParakeetTranscriber(model: "ultra", isInstalled: { _ in false })
        do {
            _ = try await transcriber.transcribe(url: URL(fileURLWithPath: "/nonexistent.wav"), profileId: nil) { _ in }
            XCTFail("Expected modelNotInstalled")
        } catch LocalTranscriberError.modelNotInstalled(let model) {
            XCTAssertEqual(model, "ultra")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFactoryBuildsParakeet() throws {
        let suite = "LocalPipelineTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(LocalTranscriberEngine.parakeet.rawValue, forKey: "localTranscriber")
        defaults.set("redux", forKey: ParakeetCatalog.defaultsKey)
        let transcriber = try XCTUnwrap(LocalTranscriberFactory.make(defaults: defaults) as? ParakeetTranscriber)
        XCTAssertEqual(transcriber.model, "redux")
    }

    func testImportStoresDuration() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
            buffer.frameLength = 16_000
            try file.write(from: buffer)
        }
        let seconds = await RecordingViewModel.audioDuration(url)
        XCTAssertEqual(try XCTUnwrap(seconds), 1.0, accuracy: 0.05)
        let missing = await RecordingViewModel.audioDuration(url.appending(path: "nope"))
        XCTAssertNil(missing)
    }

    func testNativeErrorTextIsPreserved() {
        let message = RecordingViewModel.transcriptionFailureMessage(LocalTranscriberError.transcriptionFailed("Segment lezen mislukt: invalid UTF-8"))
        XCTAssertTrue(message.contains("Segment lezen mislukt: invalid UTF-8"))
    }
}
