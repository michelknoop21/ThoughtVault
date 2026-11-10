import XCTest
import AVFoundation
@testable import ThoughtVault

final class SystemAudioStorageTests: XCTestCase {
    private func writeWAV(_ url: URL, frames: AVAudioFrameCount) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        try writer.write(from: buffer)
    }

    func testSystemOutputURLIsInRecordingsDirectory() throws {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 9
        comps.hour = 14; comps.minute = 5; comps.second = 7
        let date = try XCTUnwrap(Calendar.current.date(from: comps))
        let url = SystemAudioCapture.outputURL(in: AudioRecorder.recordingsDirectoryURL(), date: date)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Recordings")
        XCTAssertEqual(url.pathExtension, "wav")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("system_audio_20261109-140507-"), url.lastPathComponent)
        // DST fall-back or two starts in one second must not reuse a file.
        XCTAssertNotEqual(url, SystemAudioCapture.outputURL(in: AudioRecorder.recordingsDirectoryURL(), date: date))

        try writeWAV(url, frames: 160)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(AudioRecorder.savedRecordingURLs().contains { $0.lastPathComponent == url.lastPathComponent })
    }

    func testSystemTempRemovedOnlyAfterVerifiedMix() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("system.wav")
        let combined = dir.appendingPathComponent("combined.wav")
        try writeWAV(source, frames: 800)
        try writeWAV(combined, frames: 1600)

        XCTAssertFalse(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: source, combinedURL: combined, expectedFrames: 2600))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: source, combinedURL: dir.appendingPathComponent("missing.wav"), expectedFrames: 800))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: source, combinedURL: combined, expectedFrames: 1600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testActiveSystemCaptureIsNotAnOrphan() throws {
        let url = AudioRecorder.recordingsDirectoryURL().appendingPathComponent("system_audio_active-\(UUID().uuidString).wav")
        try writeWAV(url, frames: 160)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: url.path)
        let recorder = AudioRecorder()
        XCTAssertTrue(recorder.getOrphanedRecordings().contains { $0.lastPathComponent == url.lastPathComponent })
        XCTAssertFalse(recorder.getOrphanedRecordings(excluding: [url]).contains { $0.lastPathComponent == url.lastPathComponent })
    }
}
