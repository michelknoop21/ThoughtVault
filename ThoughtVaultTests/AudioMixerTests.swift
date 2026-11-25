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

    /// Every channel of a file; a mono file gives one array.
    private func channels(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return (0..<Int(buffer.format.channelCount)).map {
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: Int(buffer.frameLength)))
        }
    }

    /// Left is the microphone, right the system audio.
    private func mix(_ mic: URL, _ sys: URL, offset: TimeInterval = 0) throws -> (frames: AVAudioFramePosition, mic: [Float], sys: [Float]) {
        let out = dir.appendingPathComponent("out.wav")
        let frames = try AudioMixer.mix(micURL: mic, systemURL: sys, systemStartOffset: offset, into: out)
        let both = try channels(out)
        XCTAssertEqual(both.count, 2)
        return (frames, both[0], both[1])
    }

    func testEachSourceIsLevelledOnItsOwnChannel() throws {
        let r = try mix(wav("m.wav", [(rate, 0.3)]), wav("s.wav", [(rate, 0.02)]))
        XCTAssertEqual(r.mic.count, rate)
        XCTAssertEqual(r.mic[100], 0.09, accuracy: tol)
        XCTAssertEqual(r.sys[100], 0.09, accuracy: tol)
    }

    /// The engines read a mono downmix; without it they would hear only the microphone.
    func testEnginesHearBothChannels() async throws {
        let out = dir.appendingPathComponent("call.wav")
        _ = try AudioMixer.mix(micURL: try wav("m.wav", [(rate, 0)]), systemURL: try wav("s.wav", [(rate, 0.3)]),
                               systemStartOffset: 0, into: out)
        let converted = try await AudioPreConverter.convertToWav16k(out)
        defer { try? FileManager.default.removeItem(at: converted) }
        let mono = try channels(converted)
        XCTAssertEqual(mono.count, 1)
        XCTAssertGreaterThan(abs(mono[0][8000]), 0.01)
        let chunks = try await AudioChunker.chunk(url: out, chunkDuration: 10)
        defer { chunks.forEach { try? FileManager.default.removeItem(at: $0) } }
        let chunk = try channels(XCTUnwrap(chunks.first))
        XCTAssertEqual(chunk.count, 1)
        XCTAssertGreaterThan(abs(chunk[0][8000]), 0.01)
    }

    func testQuietSourceIsRaisedAndSilentSourceLeftAlone() throws {
        let r = try mix(wav("m.wav", [(rate, 0.01)]), wav("s.wav", [(rate, 0.0)]))
        XCTAssertEqual(r.mic[100], 0.09, accuracy: tol)
        XCTAssertEqual(r.sys[100], 0, accuracy: tol)
    }

    func testGainIsCapped() {
        XCTAssertEqual(AudioMixer.gain(forLevel: 0.002), 16)
        XCTAssertEqual(AudioMixer.gain(forLevel: 1.0), 0.25)
        XCTAssertEqual(AudioMixer.gain(forLevel: 0.0005), 1)
    }

    func testLoudClickDoesNotSetTheLevelAndIsClamped() throws {
        // 20 blocks at 0.05 and one at full scale: the level stays 0.05, so the gain is 1.8.
        let hi = try mix(wav("m.wav", [(2 * rate, 0.05), (1600, 1.0)]), wav("s.wav", [(rate, 0.0)]))
        XCTAssertEqual(hi.mic[100], 0.09, accuracy: tol)
        XCTAssertEqual(hi.mic[2 * rate + 100], 1.0, accuracy: tol)
        let lo = try mix(wav("m2.wav", [(2 * rate, -0.05), (1600, -1.0)]), wav("s2.wav", [(rate, 0.0)]))
        XCTAssertEqual(lo.mic[2 * rate + 100], -1.0, accuracy: tol)
    }

    func testPositiveOffsetPadsSystem() throws {
        let r = try mix(wav("m.wav", [(rate, 0.2)]), wav("s.wav", [(rate, 0.3)]), offset: 0.5)
        XCTAssertEqual(r.mic[0], 0.09, accuracy: tol)
        XCTAssertEqual(r.sys[7999], 0, accuracy: tol)
        XCTAssertEqual(r.sys[8000], 0.09, accuracy: tol)
    }

    func testNegativeOffsetDropsSystemLead() throws {
        let r = try mix(wav("m.wav", [(rate, 0.0)]), wav("s.wav", [(4000, 0.3), (12_000, 0.1)]), offset: -0.25)
        // System level is 0.3 (the dropped lead counts), so its gain is 0.09 / 0.3.
        XCTAssertEqual(r.sys[0], 0.03, accuracy: tol)
        XCTAssertEqual(r.sys[5000], 0.03, accuracy: tol)
        XCTAssertEqual(r.mic[0], 0, accuracy: tol)
    }

    func testLengthIsMaxOfAlignedInputs() throws {
        let a = try mix(wav("m.wav", [(rate, 0.1)]), wav("s.wav", [(rate, 0.1)]), offset: 0.5)
        XCTAssertEqual(a.frames, 24_000)
        XCTAssertEqual(a.mic.count, 24_000)
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
