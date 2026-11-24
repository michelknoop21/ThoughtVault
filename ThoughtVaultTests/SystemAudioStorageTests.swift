import XCTest
import AVFoundation
import CoreAudio
import AppKit
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
        try checkTapWriterFormats(rates: [48_000, 16_000, 48_000, 24_000, 48_000, 16_000, 48_000], channels: 1, lateNotification: true)
    }

    func testTapWriterHandles44100AndStereoChanges() throws {
        for channels: AVAudioChannelCount in [1, 2] {
            try checkTapWriterFormats(rates: [48_000, 44_100, 16_000, 24_000, 44_100, 48_000], channels: channels, lateNotification: false)
        }
    }

    func testTapWriterStaysInSyncWhenFormatNotificationArrivesEarly() throws {
        for lead in [1, 4] {
            try checkTapWriterFormats(rates: [48_000, 16_000, 48_000, 24_000, 48_000], channels: 1, lateNotification: false, notificationLead: lead)
        }
    }

    private func checkTapWriterFormats(rates: [Double], channels: AVAudioChannelCount, lateNotification: Bool, notificationLead: Int = 0) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        func format(_ rate: Double, channels: AVAudioChannelCount = 1) throws -> AVAudioFormat {
            try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false))
        }
        let rate16 = try format(16_000)
        // Non-periodic chirp (200 Hz rising 300 Hz/s): its position in the file is unambiguous.
        func chirp(_ t: Double) -> Float { Float(0.5 * sin(2 * .pi * (200 * t + 150 * t * t))) }
        let segment = 30, buffers = rates.count * 30 // 20 ms buffers
        let switches = (1..<rates.count).map { $0 * segment }
        let formats = try rates.map { try format($0, channels: channels) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: rate16.settings)
            let writer = TapAudioWriter(file: file, inputFormat: formats[0]) { _, _ in }
            let start = mach_absolute_time()
            for b in 0..<buffers {
                let format = formats[b / segment]
                let notificationIndex = b + (lateNotification ? -1 : notificationLead)
                if switches.contains(notificationIndex) { writer.updateFormat(formats[notificationIndex / segment]) }
                let frames = Int(format.sampleRate * 0.02)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
                pcm.frameLength = AVAudioFrameCount(frames)
                for channel in 0..<Int(channels) {
                    for i in 0..<frames { pcm.floatChannelData![channel][i] = chirp(Double(b) * 0.02 + Double(i) / format.sampleRate) }
                }
                writer.consume(pcm.audioBufferList, hostTime: start + AVAudioTime.hostTime(forSeconds: Double(b) * 0.02))
            }
            XCTAssertEqual(writer.formatChanges, UInt64(rates.count - 1))
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
            // 44.1 kHz converter changes may retain up to 1 ms of filter latency.
            // Keep the existing delayed-notification regression at its stricter two frames.
            XCTAssertLessThanOrEqual(abs(best.lag), lateNotification ? 2 : 16, "segment \(s) shifted \(best.lag) frames")
        }

        // No gaps away from the switches; right after a late notification a short, explained jump is allowed.
        var longestQuiet = 0, run = 0, quietEnd = 0
        for (n, value) in samples.enumerated().dropFirst(64) {
            let nearSwitch = switches.contains { ((($0 - notificationLead) * 320)..<(($0 + 3) * 320)).contains(n) }
            run = abs(value) < 1e-3 && !nearSwitch ? run + 1 : 0
            if run > longestQuiet { longestQuiet = run; quietEnd = n }
        }
        XCTAssertLessThan(longestQuiet, 8, "gap in output ending at frame \(quietEnd), channels \(channels)")
    }

    @MainActor
    func testLiveSpeechRoundTrip() async throws {
        try await checkLiveSpeech(openHeadsetMicrophone: false)
    }

    @MainActor
    func testLiveSpeechAcrossHeadsetMicrophoneChanges() async throws {
        try await checkLiveSpeech(openHeadsetMicrophone: true)
    }

    @MainActor
    private func checkLiveSpeech(openHeadsetMicrophone: Bool) async throws {
        let root = URL(fileURLWithPath: "/tmp/thoughtvault-system-audio-test")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("speech-enabled").path))
        func outputLatencyFrames() throws -> Double {
            func value(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> UInt32 {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                var result: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
                let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result)
                guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                return result
            }
            let device = try value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var rate: Double = 0, size = UInt32(MemoryLayout<Double>.size)
            var status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
            guard status == noErr, rate > 0 else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            address.mSelector = kAudioDevicePropertyStreams
            address.mScope = kAudioDevicePropertyScopeOutput
            status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams)
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            let streamLatency = try streams.map { try value($0, kAudioStreamPropertyLatency) }.max() ?? 0
            let deviceLatency = try value(device, kAudioDevicePropertyLatency, kAudioDevicePropertyScopeOutput)
            return Double(deviceLatency + streamLatency) / rate * 16_000
        }
        // Stay clear of the route transitions at 6/12/18/24 seconds and the recording pause.
        let markers = [2, 8, 16, 20, 27]
        var latencies: [Double] = []
        let sourceURL = root.appendingPathComponent("speech.wav")
        let player = try AVAudioPlayer(contentsOf: sourceURL)
        let microphone = AVCaptureSession()
        if openHeadsetMicrophone {
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            let headset = try XCTUnwrap(devices.first { UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBluetooth }, "An attached Bluetooth microphone is required")
            let input = try AVCaptureDeviceInput(device: headset)
            let output = AVCaptureAudioDataOutput()
            guard microphone.canAddInput(input), microphone.canAddOutput(output) else { XCTFail("Cannot open headset microphone"); return }
            microphone.addInput(input)
            microphone.addOutput(output)
        }
        defer { microphone.stopRunning() }
        let capture = SystemAudioCapture()
        let url = try await capture.startCapture()
        defer {
            player.stop()
            try? FileManager.default.removeItem(at: url)
        }
        var skippedSourceFrames = 0
        do {
            try await Task.sleep(for: .seconds(1))
            XCTAssertTrue(player.play())
            var phase = 0
            while player.isPlaying {
                while latencies.count < markers.count, player.currentTime >= Double(markers[latencies.count]) {
                    latencies.append(try outputLatencyFrames())
                }
                if openHeadsetMicrophone, player.currentTime >= Double(phase + 1) * 6, phase < 4 {
                    if phase.isMultiple(of: 2) { microphone.startRunning() } else { microphone.stopRunning() }
                    phase += 1
                    if phase == 2 {
                        let pauseStart = AVAudioTime.seconds(forHostTime: mach_absolute_time())
                        capture.pauseDurationTimer()
                        try await Task.sleep(for: .milliseconds(500))
                        capture.resumeDurationTimer()
                        skippedSourceFrames = Int(((AVAudioTime.seconds(forHostTime: mach_absolute_time()) - pauseStart) * 16_000).rounded())
                    }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            microphone.stopRunning()
            try await Task.sleep(for: .milliseconds(200))
        } catch {
            _ = await capture.stopCapture()
            throw error
        }
        _ = await capture.stopCapture()
        func read(_ url: URL) throws -> [Float] {
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
            var values: [Float] = []
            while file.framePosition < file.length {
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                values.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            }
            return values
        }
        let source = try read(sourceURL), recorded = try read(url)
        XCTAssertGreaterThan(recorded.count, source.count)
        // Keep the captured speech only in the explicitly enabled local evidence directory.
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(latencies.count, markers.count)
        guard latencies.count == markers.count else { return }
        var lags: [Double] = []
        for (marker, second) in markers.enumerated() {
            let start = second * 16_000, length = 4000
            guard start + length < source.count else { XCTFail("Speech fixture must be 30 seconds"); return }
            func correlation(_ lag: Int) -> Double {
                guard start + lag >= 0, start + lag + length < recorded.count else { return -1 }
                var dot = 0.0, a = 0.0, b = 0.0
                for i in stride(from: 0, to: length, by: 4) {
                    let x = Double(source[start + i]), y = Double(recorded[start + lag + i])
                    dot += x * y; a += x * x; b += y * y
                }
                return dot / max(1e-20, sqrt(a * b))
            }
            var best = (lag: 0, score: -1.0)
            for lag in stride(from: 0, through: 6 * 16_000, by: 4) {
                let score = correlation(lag)
                if score > best.score { best = (lag, score) }
            }
            let centre = best.lag
            for lag in (centre - 16)...(centre + 16) {
                let score = correlation(lag)
                if score > best.score { best = (lag, score) }
            }
            print("SPEECH_ROUNDTRIP second=\(second) lag_frames=\(best.lag) device_latency_frames=\(latencies[marker]) pause_frames=\(skippedSourceFrames) correlation=\(best.score)")
            XCTAssertGreaterThan(best.score, 0.98, "Speech waveform changed at second \(second)")
            // Compare capture timing, not the Bluetooth route's changing playback latency.
            lags.append(Double(best.lag + (second >= 16 ? skippedSourceFrames : 0)) - latencies[marker])
        }
        XCTAssertLessThanOrEqual((lags.max() ?? 0) - (lags.min() ?? 0), 320, "Speech drift exceeded 20 ms")
    }

    /// Opt-in wall-clock test; system audio only, so no room microphone audio is saved.
    @MainActor
    func testTwoHourPhysicalSpeechCapture() async throws {
        let root = URL(fileURLWithPath: "/tmp/thoughtvault-system-audio-test").resolvingSymlinksInPath()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("two-hour-enabled").path))
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = root.resolvingSymlinksInPath()
        panel.message = "Kies de SSD-bewijsmap voor de twee-uursproef."
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let folder = panel.url,
              folder.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path else { throw CocoaError(.userCancelled) }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let directory = AudioRecorder.recordingsDirectoryURL()
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            XCTFail("The isolated recordings directory must be empty")
            return
        }
        let destination = root.appendingPathComponent("two-hour-capture", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: destination)
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = try AVAudioPlayer(contentsOf: root.appendingPathComponent("speech.wav"))
        player.numberOfLoops = -1
        let capture = SystemAudioCapture()
        let url = try await capture.startCapture()
        let start = Date()
        func progress(_ finished: Bool) throws {
            let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let data = try JSONSerialization.data(withJSONObject: ["startedAt": start.timeIntervalSince1970, "elapsed": Date().timeIntervalSince(start), "bytes": bytes, "capturePath": destination.resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path, "sourceDuration": player.duration, "finished": finished], options: [.sortedKeys])
            try data.write(to: root.appendingPathComponent("two-hour-progress.json"), options: .atomic)
        }
        do {
            try progress(false)
            try await Task.sleep(for: .seconds(1))
            XCTAssertTrue(player.play())
            let deadline = ContinuousClock.now.advanced(by: .seconds(7200))
            repeat {
                try await Task.sleep(for: .seconds(30))
                try Task.checkCancellation()
                XCTAssertTrue(capture.isCapturing)
                XCTAssertTrue(player.isPlaying)
                guard capture.isCapturing, player.isPlaying else { throw CocoaError(.fileReadUnknown) }
                try progress(false)
            } while ContinuousClock.now < deadline
            player.stop()
            _ = await capture.stopCapture()
            let result = try AVAudioFile(forReading: url)
            XCTAssertEqual(result.processingFormat.sampleRate, 16_000)
            XCTAssertGreaterThanOrEqual(Double(result.length) / 16_000, 7200)
            try progress(true)
        } catch {
            player.stop()
            _ = await capture.stopCapture()
            throw error
        }
    }

    /// Accelerated two-hour stream, not a substitute for a two-hour hardware recording.
    func testTapWriterTwoHourSyntheticTimeline() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/thoughtvault-system-audio-test/soak-enabled"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-soak-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let outputFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let formats = try [16_000.0, 24_000, 44_100, 48_000].flatMap { rate in
            try [AVAudioChannelCount(1), 2].map { channels in
                try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
            }
        }
        let buffers = try formats.map { format in
            try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 50)))
        }
        let waves = formats.map { format in
            (0..<Int(format.sampleRate / 50)).map { Float(sin(2 * .pi * 1000 * Double($0) / format.sampleRate)) }
        }
        // Distinct buffer amplitudes expose missing/duplicated 20 ms passages.
        func amplitude(_ buffer: Int) -> Float { Float((buffer * 7919 % 97) + 20) / 256 }
        let count = 7200 * 50
        do {
            let file = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
            let writer = TapAudioWriter(file: file, inputFormat: formats[0]) { _, _ in }
            let start = mach_absolute_time()
            for b in 0..<count {
                let index = (b / 3000) % formats.count
                let format = formats[index], pcm = buffers[index], wave = waves[index]
                if b.isMultiple(of: 3000) { writer.updateFormat(format) }
                pcm.frameLength = pcm.frameCapacity
                let level = amplitude(b)
                for channel in 0..<Int(format.channelCount) {
                    for i in 0..<wave.count { pcm.floatChannelData![channel][i] = wave[i] * level }
                }
                writer.consume(pcm.audioBufferList, hostTime: start + AVAudioTime.hostTime(forSeconds: Double(b) / 50))
            }
            writer.finishTimeline()
            XCTAssertEqual(writer.framesDropped, 0)
            XCTAssertEqual(writer.formatChanges, 119)
            XCTAssertEqual(Int64(writer.framesWritten), Int64(count * 320), accuracy: 64)
        }
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 320))
        var mismatches = 0, checked = 0
        for b in 0..<count {
            try file.read(into: buffer)
            guard buffer.frameLength == 320 else { break }
            if b % 3000 < 3 { continue } // resampler transition, checked separately at 1 ms
            let samples = buffer.floatChannelData![0]
            let rms = sqrt((96..<224).reduce(Float(0)) { $0 + samples[$1] * samples[$1] } / 128)
            if abs(rms - amplitude(b) / sqrt(2)) > 0.002 { mismatches += 1 }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 359_000)
        XCTAssertEqual(mismatches, 0, "Missing, duplicate or shifted buffer signatures")
        print("SYNTHETIC_SOAK seconds=7200 format_changes=119 checked=\(checked) mismatches=\(mismatches)")
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
