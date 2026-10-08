import AppKit
import AVFoundation
import SwiftUI
import XCTest
import os
@testable import ThoughtVault

/// Acceptance tests for the shared audio envelope, driven by the same fixture
/// as the Rust suite (tests/fixtures/envelope-fixture.json). Assertions are
/// spec thresholds, not golden floats — no cross-language float matching.
final class AudioEnvelopeProcessorTests: XCTestCase {

    func testFrequencyBandsDistinguishLowAndHighTonesAndSettleToSilence() {
        func tone(_ frequency: Double) -> [Float] {
            (0..<1024).map { Float(0.1 * sin(2 * .pi * frequency * Double($0) / 16_000)) }
        }
        var low = AudioSpectrumProcessor(), high = AudioSpectrumProcessor()
        for _ in 0..<15 {
            _ = low.process(samples: tone(250), sampleRate: 16_000, dt: 1 / 30)
            _ = high.process(samples: tone(4000), sampleRate: 16_000, dt: 1 / 30)
        }
        XCTAssertGreaterThan(low.bands[1], low.bands[5] + 0.3)
        XCTAssertGreaterThan(high.bands[5], high.bands[1] + 0.3)
        for _ in 0..<60 { _ = high.process(samples: Array(repeating: 0, count: 1024), sampleRate: 16_000, dt: 1 / 30) }
        XCTAssertLessThan(high.bands.max() ?? 1, 0.001)
        XCTAssertTrue(high.process(samples: [.nan, .infinity], sampleRate: 16_000, dt: 1 / 30).allSatisfy { $0.isFinite })
    }

    @MainActor
    func testWidgetFitsPausedHourLongRecordingWithoutCompressingControls() {
        let model = RecordingViewModel()
        model.recordingState = .paused
        model.audioRecorder.duration = 35_999
        let view = NSHostingView(rootView: RecordingWidgetView().preferredColorScheme(.dark).environment(model))
        XCTAssertLessThanOrEqual(view.fittingSize.width, 470)
        XCTAssertLessThanOrEqual(view.fittingSize.height, 60)
    }

    func testCaptureTimelinePreservesSilenceAndExcludesExplicitPause() {
        var timeline = AudioCaptureTimeline(sampleRate: 16_000, start: 100)
        XCTAssertEqual(timeline.framePosition(at: 101), 16_000)
        XCTAssertEqual(timeline.framePosition(at: 110), 160_000)
        timeline.setPaused(true, at: 110)
        XCTAssertEqual(timeline.framePosition(at: 120), 160_000)
        timeline.setPaused(false, at: 120)
        XCTAssertEqual(timeline.framePosition(at: 125), 240_000)
        timeline.setPaused(false, at: 125)
        XCTAssertEqual(timeline.framePosition(at: 126), 256_000)
    }

    func testMicrophoneIsRemovedOnlyAfterAReadableCompleteMix() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.wav")
        let combined = directory.appendingPathComponent("combined.wav")
        try Data([1, 2, 3]).write(to: source)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
        buffer.frameLength = 320
        for i in 0..<320 { buffer.floatChannelData![0][i] = i % 2 == 0 ? 0.25 : -0.25 }
        do {
            let writer = try AVAudioFile(forWriting: combined, settings: format.settings)
            try writer.write(from: buffer)
        }
        XCTAssertFalse(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: source, combinedURL: combined, expectedFrames: 321))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: combined, combinedURL: combined, expectedFrames: 320))
        XCTAssertTrue(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: source, combinedURL: combined, expectedFrames: 320))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try AVAudioFile(forReading: combined).length, 320)
        try Data([1, 2, 3]).write(to: source)
        try Data([1, 2, 3]).write(to: combined)
        XCTAssertFalse(try AudioRecorder.removeSourceIfMixIsComplete(sourceURL: source, combinedURL: combined, expectedFrames: 320))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCombinedRecordingHidesOnlyItsSourceAndRestoresItWhenMixIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "CombinedRecordingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let mic = directory.appendingPathComponent("recording_1.wav")
        let combined = directory.appendingPathComponent("combined_2.wav")
        let other = directory.appendingPathComponent("recording_3.wav")
        for url in [mic, combined, other] { try Data([1]).write(to: url) }
        defaults.set(combined.path, forKey: "combinedAudio_\(mic.lastPathComponent)")
        XCTAssertEqual(AudioRecorder.primaryRecordingURLs(from: [mic, combined, other], defaults: defaults), [combined, other])
        XCTAssertTrue(FileManager.default.fileExists(atPath: mic.path))
        try FileManager.default.removeItem(at: combined)
        XCTAssertEqual(AudioRecorder.primaryRecordingURLs(from: [mic, other], defaults: defaults), [mic, other])
    }

    func testStudioWaveformStaysBetweenTranscriptAndTransport() {
        for height: CGFloat in [480, 560, 600, 719, 720, 880, 1100] {
            let layout = StudioLayout(w: 640, h: height)
            XCTAssertGreaterThanOrEqual(layout.waveHeight, 0)
            XCTAssertGreaterThanOrEqual(layout.waveY - layout.waveHeight / 2, layout.listenY + 40)
            if layout.waveHeight > 0 {
                XCTAssertLessThanOrEqual(layout.waveY + layout.waveHeight / 2, layout.transportY - 85)
            }
        }
    }

    func testSystemAudioHandlerDoesNotAccumulateCallbackRecursion() {
        let handler = SystemAudioLiveHandler()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let completed = DispatchSemaphore(value: 0)
        handler.set { _ in calls.withLock { $0 += 1 } }
        let thread = Thread { @Sendable in
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
            for _ in 0..<20_000 { handler.append(buffer) }
            handler.set(nil)
            handler.append(buffer)
            handler.set { _ in calls.withLock { $0 += 2 } }
            handler.append(buffer)
            completed.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(completed.wait(timeout: .now() + 20), .success)
        XCTAssertEqual(calls.withLock { $0 }, 20_002)
    }

    private struct Step: Decodable {
        let dtMs: Double
        let db: Float
        let repeatCount: Int
        enum CodingKeys: String, CodingKey { case dtMs, db, repeatCount = "repeat" }
    }

    // Decoded on access — cheap and avoids Swift 6 static-mutable concurrency.
    private static var scenarios: [String: [Step]] {
        // Fixture lives at the repo root; locate it relative to this source file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ThoughtVaultTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("tests/fixtures/envelope-fixture.json")
        struct Fixture: Decodable { let scenarios: [String: [Step]] }
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(Fixture.self, from: data).scenarios
    }

    /// Runs a scenario through the processor, returning all outputs.
    private func run(_ name: String, processor: inout AudioEnvelopeProcessor) -> [Float] {
        guard let steps = Self.scenarios[name] else {
            XCTFail("Missing fixture scenario \(name)"); return []
        }
        var out: [Float] = []
        for step in steps {
            for _ in 0..<step.repeatCount {
                out.append(processor.process(db: step.db, dt: step.dtMs / 1000))
            }
        }
        return out
    }

    func testWaveformKeepsConversationalLevelsVisible() {
        XCTAssertEqual(WaveConfig.visualEnergy(0), 0)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(0.3), 0.26)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(0.5), 0.44)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(0.8) - WaveConfig.visualEnergy(0.5), 0.20)
        XCTAssertLessThanOrEqual(WaveConfig.visualEnergy(1), 0.9)
        XCTAssertEqual(WaveConfig.visualEnergy(.nan), 0)
        XCTAssertEqual(WaveConfig.visualEnergy(-1), 0)
        XCTAssertEqual(WaveConfig.visualEnergy(2), 0.9)
    }

    @MainActor
    func testMicrophonePCMIsPublishedWithoutLongWriterDelay() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/thoughtvault-system-audio-test/enabled") else {
            throw XCTSkip("Microphone timing test requires explicit local opt-in")
        }
        let recorder = AudioRecorder()
        recorder.hasPermission = true
        try await recorder.startRecording()
        let url = try XCTUnwrap(recorder.currentRecordingURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Date()
        var delays: [Double] = []
        for _ in 0..<90 {
            try await Task.sleep(for: .milliseconds(33))
            let elapsed = Date().timeIntervalSince(start)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.doubleValue ?? 0
            if elapsed > 1 { delays.append(max(0, elapsed - size / 32_000)) }
        }
        _ = try await recorder.stopRecording()
        let maximumDelay = delays.max() ?? 10
        print("MIC_PCM maximumDelaySeconds=\(maximumDelay)")
        XCTAssertLessThan(maximumDelay, 0.25, "Microphone frequency bands must follow live sound, not delayed writer flushes")
    }

    /// Opt-in hardware test: plays actual output audio through the system tap.
    /// Generate audio with tests/fixtures/generate-system-audio.py first.
    /// Enable with /tmp/thoughtvault-system-audio-test/enabled; no microphone,
    /// transcription, or provider calls are involved.
    @MainActor
    func testLiveSystemAudioDrivesWaveform() async throws {
        let root = URL(fileURLWithPath: "/tmp/thoughtvault-system-audio-test")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("enabled").path) else {
            throw XCTSkip("Live system-audio test requires explicit local opt-in")
        }
        let player = try AVAudioPlayer(data: Data(contentsOf: root.appendingPathComponent("levels.wav")))
        let capture = SystemAudioCapture()
        let url = try await capture.startCapture()
        defer {
            player.stop()
            try? FileManager.default.removeItem(at: url)
        }
        let captureStart = Date()
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(player.play())
        var samples: [(time: Double, level: Float)] = []
        do {
            while player.isPlaying {
                samples.append((player.currentTime, capture.audioLevels.last ?? 0))
                try await Task.sleep(for: .milliseconds(33))
            }
        } catch {
            _ = await capture.stopCapture()
            throw error
        }
        _ = await capture.stopCapture()
        let saved = try AVAudioFile(forReading: url)
        let savedSeconds = Double(saved.length) / saved.processingFormat.sampleRate
        XCTAssertEqual(savedSeconds, Date().timeIntervalSince(captureStart), accuracy: 0.25,
                       "Silent device gaps must remain in the recorded timeline")
        func average(_ start: Double, _ end: Double) -> Double {
            let values = samples.filter { $0.time >= start && $0.time < end }.map { Double($0.level) }
            XCTAssertFalse(values.isEmpty)
            return values.reduce(0, +) / Double(max(1, values.count))
        }
        let silence = average(1, 2.5), quiet = average(5, 6.5)
        let normal = average(9, 10.5), loud = average(13, 14.5), released = average(17, 18.5)
        let report = "SYSTEM_AUDIO silence=\(silence) quiet=\(quiet) normal=\(normal) loud=\(loud) released=\(released) samples=\(samples.count)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThan(silence, 0.03)
        XCTAssertGreaterThan(quiet, 0.15, "Real system-audio callbacks must contain the quiet tone")
        XCTAssertGreaterThan(normal - quiet, 0.08)
        XCTAssertGreaterThan(loud - normal, 0.08)
        XCTAssertLessThan(released, 0.03)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(Float(loud)) - WaveConfig.visualEnergy(Float(quiet)), 0.20)
    }

    // 1. 2 s of silence → output 0
    func testSilenceIsZero() {
        var p = AudioEnvelopeProcessor()
        let out = run("silence", processor: &p)
        XCTAssertEqual(out.last, 0)
        XCTAssertTrue(out.suffix(30).allSatisfy { $0 == 0 })
    }

    // 2. Input at the noise floor → ≤ 0.03
    func testNoiseFloorSuppressed() {
        var p = AudioEnvelopeProcessor()
        let out = run("noiseFloor", processor: &p)
        XCTAssertLessThanOrEqual(out.last ?? 1, 0.03)
    }

    // 3. Speech −35..−18 dBFS → dynamic, roughly 0.30–0.90 with real spread
    func testSpeechIsDynamic() {
        var pSoft = AudioEnvelopeProcessor()
        let soft = run("speechSoft", processor: &pSoft).last ?? 0
        var pLoud = AudioEnvelopeProcessor()
        let loud = run("speechLoud", processor: &pLoud).last ?? 0
        XCTAssertGreaterThanOrEqual(soft, 0.30)
        XCTAssertLessThanOrEqual(loud, 0.90)
        XCTAssertGreaterThanOrEqual(loud - soft, 0.15, "soft vs loud speech must be visually distinct")
    }

    // 4. −8 dBFS → > 0.90, ≤ 1.0
    func testLoudNearMax() {
        var p = AudioEnvelopeProcessor()
        let out = run("loud", processor: &p).last ?? 0
        XCTAssertGreaterThan(out, 0.90)
        XCTAssertLessThanOrEqual(out, 1.0)
    }

    // 5. Silence → speech: ≥ 80% of steady value within ~70 ms
    func testAttack() {
        var p = AudioEnvelopeProcessor()
        _ = run("attackSilence", processor: &p)
        let early = run("attackSpeechEarly", processor: &p).last ?? 0
        let steady = run("attackSpeechSteady", processor: &p).last ?? 0
        XCTAssertGreaterThanOrEqual(early, 0.8 * steady)
    }

    // 6. Speech → silence: < 10% of steady value within ~550 ms
    func testRelease() {
        var p = AudioEnvelopeProcessor()
        _ = run("attackSilence", processor: &p)
        let steady = run("attackSpeechSteady", processor: &p).last ?? 0
        let released = run("releaseSilence", processor: &p).last ?? 1
        XCTAssertLessThan(released, 0.1 * steady)
    }

    // 7. 10 ms vs 33 ms update cadence → ~equal envelope after equal wall time
    func testFrameRateIndependence() {
        var pFine = AudioEnvelopeProcessor()
        let fine = run("dtFine", processor: &pFine).last ?? 0
        var pCoarse = AudioEnvelopeProcessor()
        let coarse = run("dtCoarse", processor: &pCoarse).last ?? 0
        XCTAssertEqual(fine, coarse, accuracy: 0.05)
    }

    // 8. Extreme inputs → never NaN/Inf, always 0..1
    func testExtremesStayFinite() {
        var p = AudioEnvelopeProcessor()
        let out = run("extremes", processor: &p)
        for v in out {
            XCTAssertTrue(v.isFinite)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
        // Also survive literal NaN/Inf inputs
        XCTAssertTrue(p.process(db: .nan, dt: 0.033).isFinite)
        XCTAssertTrue(p.process(db: .infinity, dt: 0.033).isFinite)
    }

    /// The seven-second NorthStar calibration fixture. Export six frames only
    /// when requested by a local debug run; normal CI keeps the numeric check.
    @MainActor
    func testNorthstarTimeline() {
        var processor = AudioEnvelopeProcessor()
        let levels = run("northstarTimeline", processor: &processor)
        XCTAssertEqual(levels.count, 210)
        XCTAssertLessThan(WaveConfig.visualEnergy(levels[24]), 0.05)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(levels[60]), 0.50)
        XCTAssertLessThan(WaveConfig.visualEnergy(levels[60]), 0.60)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(levels[120]), 0.65)
        XCTAssertLessThan(WaveConfig.visualEnergy(levels[120]), 0.75)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(levels[165]), 0.85)
        XCTAssertLessThan(WaveConfig.visualEnergy(levels[165]), 0.91)
        XCTAssertGreaterThan(WaveConfig.visualEnergy(levels[32]), 0.45, "soft speech must appear within 100 ms")
        XCTAssertGreaterThan(WaveConfig.visualEnergy(levels[176]), 0.30, "release must not drop abruptly")
        XCTAssertLessThan(WaveConfig.visualEnergy(levels[176]), 0.40)
        XCTAssertLessThan(WaveConfig.visualEnergy(levels[188]), 0.07, "release should reach near-rest within 600 ms")
        let moments: [(String, Int)] = [
            ("silence", 24), ("soft", 60), ("normal", 120),
            ("loud", 165), ("release200", 176), ("release600", 188)
        ]
        for (name, frame) in moments {
            let value = levels[frame]
            print("WAVE_FIXTURE \(name) envelope=\(value) visual=\(WaveConfig.visualEnergy(value))")
            // xcodebuild does not forward arbitrary shell variables to XCTest.
            // Touch the marker for a local export; normal CI stays numeric-only.
            guard FileManager.default.fileExists(atPath: "/tmp/thoughtvault-wave-export-snapshots") else { continue }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("thoughtvault-wave-shots").path
            let history = Array(levels.prefix(frame + 1).suffix(AudioEnvelopeConfig.historyLength))
            let view = ZStack {
                Color(red: 0.015, green: 0.012, blue: 0.045)
                WaveformView(levelsProvider: { history }, isActive: true, maxFPS: 60)
                    .frame(width: 1916, height: 280)
                    .position(x: 1916 / 2, y: 821 * 0.483)
            }
            .frame(width: 1916, height: 821)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                XCTFail("Could not render \(name) snapshot")
                continue
            }
            do {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            } catch {
                XCTFail("Could not export \(name): \(error)")
            }
            if name == "loud" {
                let widget = WaveformView(levelsProvider: { history }, isActive: true, maxFPS: 60)
                    .frame(width: 120, height: 32)
                    .background(Color(red: 0.03, green: 0.02, blue: 0.06))
                let widgetRenderer = ImageRenderer(content: widget)
                widgetRenderer.scale = 4
                if let image = widgetRenderer.cgImage,
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    do {
                        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("widget-loud.png"))
                    } catch {
                        XCTFail("Could not export widget: \(error)")
                    }
                } else {
                    XCTFail("Could not render widget snapshot")
                }
            }
        }
    }
}
