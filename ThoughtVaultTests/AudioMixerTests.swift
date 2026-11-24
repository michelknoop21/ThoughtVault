import XCTest
import AVFoundation
@testable import ThoughtVault

final class AudioMixerTests: XCTestCase {
    private let rate = 16_000
    private let tol: Float = 2.0 / 32767
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a 16 kHz mono WAV from (frames, value) segments.
    private func wav(_ name: String, _ segments: [(Int, Float)]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for (frames, value) in segments {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
            buffer.frameLength = AVAudioFrameCount(frames)
            for i in 0..<frames { buffer.floatChannelData![0][i] = value }
            try file.write(from: buffer)
        }
        return url
    }

    private func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    private func mix(_ mic: URL, _ sys: URL, offset: TimeInterval = 0) throws -> (frames: AVAudioFramePosition, out: [Float]) {
        let out = dir.appendingPathComponent("out.wav")
        let frames = try AudioMixer.mix(micURL: mic, systemURL: sys, systemStartOffset: offset, into: out)
        return (frames, try samples(out))
    }

    func testBothSourcesAreLevelledThenSummed() throws {
        let r = try mix(wav("m.wav", [(rate, 0.3)]), wav("s.wav", [(rate, 0.02)]))
        XCTAssertEqual(r.out.count, rate)
        XCTAssertEqual(r.out[100], 0.18, accuracy: tol)  // 0.09 from each source
    }

    func testQuietSourceIsRaisedAndSilentSourceLeftAlone() throws {
        let r = try mix(wav("m.wav", [(rate, 0.01)]), wav("s.wav", [(rate, 0.0)]))
        XCTAssertEqual(r.out[100], 0.09, accuracy: tol)
    }

    func testGainIsCapped() {
        XCTAssertEqual(AudioMixer.gain(forLevel: 0.002), 16)
        XCTAssertEqual(AudioMixer.gain(forLevel: 1.0), 0.25)
        XCTAssertEqual(AudioMixer.gain(forLevel: 0.0005), 1)
    }

    func testLoudClickDoesNotSetTheLevelAndIsClamped() throws {
        // 20 blocks at 0.05 and one at full scale: the level stays 0.05, so the gain is 1.8.
        let hi = try mix(wav("m.wav", [(2 * rate, 0.05), (1600, 1.0)]), wav("s.wav", [(rate, 0.0)]))
        XCTAssertEqual(hi.out[100], 0.09, accuracy: tol)
        XCTAssertEqual(hi.out[2 * rate + 100], 1.0, accuracy: tol)
        let lo = try mix(wav("m2.wav", [(2 * rate, -0.05), (1600, -1.0)]), wav("s2.wav", [(rate, 0.0)]))
        XCTAssertEqual(lo.out[2 * rate + 100], -1.0, accuracy: tol)
    }

    func testPositiveOffsetPadsSystem() throws {
        let r = try mix(wav("m.wav", [(rate, 0.2)]), wav("s.wav", [(rate, 0.3)]), offset: 0.5)
        XCTAssertEqual(r.out[0], 0.09, accuracy: tol)
        XCTAssertEqual(r.out[7999], 0.09, accuracy: tol)
        XCTAssertEqual(r.out[8000], 0.18, accuracy: tol)
    }

    func testNegativeOffsetDropsSystemLead() throws {
        let r = try mix(wav("m.wav", [(rate, 0.0)]), wav("s.wav", [(4000, 0.3), (12_000, 0.1)]), offset: -0.25)
        // System level is 0.3 (the dropped lead counts), so its gain is 0.09 / 0.3.
        XCTAssertEqual(r.out[0], 0.03, accuracy: tol)
        XCTAssertEqual(r.out[5000], 0.03, accuracy: tol)
    }

    func testLengthIsMaxOfAlignedInputs() throws {
        let a = try mix(wav("m.wav", [(rate, 0.1)]), wav("s.wav", [(rate, 0.1)]), offset: 0.5)
        XCTAssertEqual(a.frames, 24_000)
        XCTAssertEqual(a.out.count, 24_000)
        let b = try mix(wav("m2.wav", [(2 * rate, 0.1)]), wav("s2.wav", [(rate, 0.1)]))
        XCTAssertEqual(b.frames, 32_000)
    }

    func testFailureLeavesNoPartialOutput() throws {
        let out = dir.appendingPathComponent("out.wav")
        let mic = try wav("m.wav", [(rate, 0.1)])
        XCTAssertThrowsError(try AudioMixer.mix(micURL: mic, systemURL: dir.appendingPathComponent("nope.wav"), systemStartOffset: 0, into: out))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(leftovers.sorted(), ["m.wav"])
    }
}
