import XCTest
import AVFoundation
@testable import ThoughtVault

final class AudioExtractorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "mp4"))
    }

    func testExtractsOneSecondFromMP4() async throws {
        let out = dir.appendingPathComponent("out.wav")
        try await AudioExtractor.extractAudio(from: try fixture("tone-1s"), to: out)
        let file = try AVAudioFile(forReading: out)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length), 16_000, accuracy: 400)
    }

    func testVideoWithoutAudioTrackThrowsReadableError() async throws {
        let out = dir.appendingPathComponent("out.wav")
        do {
            try await AudioExtractor.extractAudio(from: try fixture("video-no-audio"), to: out)
            XCTFail("expected throw")
        } catch let error as AudioExtractorError {
            XCTAssertEqual(error, .noAudioTrack)
            XCTAssertEqual(error.localizedDescription, "Deze video bevat geen geluidsspoor.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testInvalidFileThrows() async throws {
        let bad = dir.appendingPathComponent("bad.mp4")
        try "dit is geen video".write(to: bad, atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("out.wav")
        do {
            try await AudioExtractor.extractAudio(from: bad, to: out)
            XCTFail("expected throw")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testUploadContentTypeForMP4IsVideoMP4() {
        XCTAssertEqual(APIService.uploadContentType(for: URL(fileURLWithPath: "/x/a.mp4")), "video/mp4")
    }

    func testUploadContentTypeForWav() {
        // Asserts the actual system value (see report for what it is).
        XCTAssertEqual(APIService.uploadContentType(for: URL(fileURLWithPath: "/x/a.wav")), "audio/vnd.wave")
    }
}
