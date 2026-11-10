import XCTest
import AVFoundation
@testable import ThoughtVault

final class RecordingRecoveryTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeWav(float: Bool, name: String = "r.wav") throws -> URL {
        let url = dir.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: float ? 32 : 16, AVLinearPCMIsFloatKey: float,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000)!
        buf.frameLength = 16_000
        for i in 0..<16_000 { buf.floatChannelData![0][i] = sin(Float(i) / 20) * 0.5 }
        try file.write(from: buf)
        return url
    }

    /// Zeroes the RIFF size and the `data` chunk size, like a recording that was never finalised.
    private func breakHeader(_ url: URL) throws {
        var d = try Data(contentsOf: url)
        var off = 12
        while off + 8 <= d.count {
            let id = String(decoding: d[off..<off + 4], as: UTF8.self)
            let size = Int(d[off + 4]) | Int(d[off + 5]) << 8 | Int(d[off + 6]) << 16 | Int(d[off + 7]) << 24
            if id == "data" { for i in 4..<8 { d[off + i] = 0 }; break }
            off += 8 + size + (size & 1)
        }
        for i in 4..<8 { d[i] = 0 }
        try d.write(to: url)
    }

    private func assertRepairs(float: Bool) throws {
        let url = try writeWav(float: float)
        try breakHeader(url)
        XCTAssertNotEqual((try? AVAudioFile(forReading: url))?.length, 16_000)
        XCTAssertTrue(try RecordingRecovery.repairHeaderIfNeeded(at: url))
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 16_000)
    }

    func testRepairsUnfinalizedInt16Header() throws { try assertRepairs(float: false) }
    func testRepairsUnfinalizedFloat32Header() throws { try assertRepairs(float: true) }

    func testLeavesValidHeaderUntouched() throws {
        let url = try writeWav(float: false)
        let before = try Data(contentsOf: url)
        XCTAssertFalse(try RecordingRecovery.repairHeaderIfNeeded(at: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testIgnoresNonWav() throws {
        let url = dir.appendingPathComponent("x.m4a")
        try Data(repeating: 0, count: 64).write(to: url)
        XCTAssertFalse(try RecordingRecovery.repairHeaderIfNeeded(at: url))
    }

    func testRecoverOrphansReturnsReadableFiles() throws {
        let url = try writeWav(float: false)
        try breakHeader(url)
        XCTAssertEqual(RecordingRecovery.recoverOrphans([url]), [url])
    }

    func testCleanupSkipsRecordingsWithoutTranscript() throws {
        let tag = UUID().uuidString
        let known = AudioRecorder.recordingsDirectoryURL().appendingPathComponent("test_known_\(tag).wav")
        let unknown = AudioRecorder.recordingsDirectoryURL().appendingPathComponent("test_unknown_\(tag).wav")
        for u in [known, unknown] {
            try Data([1]).write(to: u)
            try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-8 * 86_400)], ofItemAtPath: u.path)
        }
        defer { for u in [known, unknown] { try? FileManager.default.removeItem(at: u) } }
        AudioRecorder.cleanupOldRecordings(protecting: [], knownRecordingNames: [known.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: known.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }
}
