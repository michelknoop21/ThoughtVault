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

    /// Capture flips 48 -> 16 -> 48 -> 24 -> 48 -> 16 -> 48 kHz; every format notification lands one
    /// buffer late, as Core Audio may deliver it. The signal must stay at its timeline position
    /// (in sync with the microphone track) after each switch, without accumulating offset.
    func testTapWriterStaysInSyncAcrossRepeatedSampleRateChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        func mono(_ rate: Double) throws -> AVAudioFormat {
            try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false))
        }
        let rate16 = try mono(16_000), rate24 = try mono(24_000), rate48 = try mono(48_000)
        // Non-periodic chirp (200 Hz rising 300 Hz/s): its position in the file is unambiguous.
        func chirp(_ t: Double) -> Float { Float(0.5 * sin(2 * .pi * (200 * t + 150 * t * t))) }
        let segment = 30, switches = [30, 60, 90, 120, 150, 180], buffers = 210 // 20 ms buffers, 4.2 s
        let formats = [rate48, rate16, rate48, rate24, rate48, rate16, rate48]
        do {
            let file = try AVAudioFile(forWriting: url, settings: rate16.settings)
            let writer = TapAudioWriter(file: file, inputFormat: rate48) { _, _ in }
            let start = mach_absolute_time()
            for b in 0..<buffers {
                let format = formats[b / segment]
                if switches.contains(b - 1) { writer.updateFormat(format) }
                let frames = Int(format.sampleRate * 0.02)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
                pcm.frameLength = AVAudioFrameCount(frames)
                for i in 0..<frames { pcm.floatChannelData![0][i] = chirp(Double(b) * 0.02 + Double(i) / format.sampleRate) }
                writer.consume(pcm.audioBufferList, hostTime: start + AVAudioTime.hostTime(forSeconds: Double(b) * 0.02))
            }
            XCTAssertEqual(writer.formatChanges, 6)
            XCTAssertEqual(writer.framesDropped, 0)
        }

        let read = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(read.length), Double(buffers) * 320, accuracy: 64)
        // A single read(into:) may return a partial read; loop like the app does.
        let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: read.processingFormat, frameCapacity: 4096))
        var samples: [Float] = []
        while read.framePosition < read.length {
            try read.read(into: chunk)
            if chunk.frameLength == 0 { break }
            samples += UnsafeBufferPointer(start: chunk.floatChannelData![0], count: Int(chunk.frameLength))
        }
        XCTAssertEqual(Int64(samples.count), read.length)

        // Lag of the chirp in the middle of every segment: 0 means sample n is the signal at time n/16000.
        for s in 0..<(buffers / segment) {
            let centre = (s * segment + segment / 2) * 320
            var best = (lag: 0, score: -Float.infinity)
            for lag in -400...400 {
                var score: Float = 0
                for n in (centre - 1000)..<(centre + 1000) { score += samples[n + lag] * chirp(Double(n) / 16_000) }
                if score > best.score { best = (lag, score) }
            }
            XCTAssertLessThanOrEqual(abs(best.lag), 2, "segment \(s) shifted \(best.lag) frames")
        }

        // No gaps away from the switches; right after a late notification a short, explained jump is allowed.
        var longestQuiet = 0, run = 0
        for (n, value) in samples.enumerated().dropFirst(64) {
            let nearSwitch = switches.contains { (($0 * 320)..<(($0 + 3) * 320)).contains(n) }
            run = abs(value) < 1e-3 && !nearSwitch ? run + 1 : 0
            longestQuiet = max(longestQuiet, run)
        }
        XCTAssertLessThan(longestQuiet, 8, "gap in output")
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
