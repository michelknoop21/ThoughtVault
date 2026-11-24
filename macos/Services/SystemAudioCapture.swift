#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

private let log = AppLog(category: "SystemAudio")

struct CaptureResult {
    let systemAudioURL: URL?
    let microphoneURL: URL?
}

enum SystemAudioCaptureError: LocalizedError {
    case noOutputDevice
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            return "Geen audio-uitvoer beschikbaar. Kies een uitvoerapparaat en probeer opnieuw."
        case .coreAudio(let operation, let status):
            return "Systeemaudio kon niet worden gestart (\(operation), code \(status)). Controleer Systeemaudio in Systeeminstellingen > Privacy en beveiliging."
        }
    }
}

@Observable
@MainActor
final class SystemAudioCapture {
    var isCapturing = false
    var duration: TimeInterval = 0
    var audioLevels = Array(repeating: Float(0), count: AudioEnvelopeConfig.historyLength)
    var frequencyBands = Array(repeating: Float(0), count: AudioSpectrumProcessor.frequencies.count)
    var micAudioLevels = Array(repeating: Float(0), count: AudioEnvelopeConfig.historyLength)
    var hasPermission = false
    var errorMessage: String?
    var currentOutputURL: URL?
    var currentMicURL: URL?
#if DEBUG
    var meterDebugText = ""
#endif

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: TapAudioWriter?
    private var formatListener: AudioObjectPropertyListenerBlock?
    private var timer: Timer?
    private var startDate: Date?
    /// Wall-clock start of the last capture; kept after stop for mix alignment.
    private(set) var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var envelope = AudioEnvelopeProcessor()
    private var lastMeterDate: Date?
    private let ioQueue = DispatchQueue(label: "com.buildmind.ThoughtVault.SystemAudioCapture.io")

    nonisolated static func outputURL(in directory: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // Local time repeats on DST fall-back and two starts can share a second: add a unique suffix.
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return directory.appendingPathComponent("system_audio_\(formatter.string(from: date))-\(suffix).wav")
    }

    @discardableResult
    func startCapture(includeMicrophone: Bool = false) async throws -> URL {
        let outputUID = try Self.defaultOutputUID()
        let outputURL = Self.outputURL(in: AudioRecorder.recordingsDirectoryURL(), date: Date())
        guard let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                             channels: 1, interleaved: false) else {
            throw SystemAudioCaptureError.coreAudio("audioformaat", -1)
        }
        let file = try AVAudioFile(forWriting: outputURL, settings: fileFormat.settings)
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "ThoughtVault Systeemaudio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.deviceUID = outputUID

        do {
            try Self.check(AudioHardwareCreateProcessTap(description, &tapID), "tap")
            let tapUID = try Self.tapUID(for: tapID)
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "ThoughtVault Audio Capture",
                kAudioAggregateDeviceUIDKey: "nl.prezent.ThoughtVault.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID,
                                                   kAudioSubTapDriftCompensationKey: true]],
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "aggregate device")

            let inputFormat = try Self.captureFormat(tapID: tapID, aggregateID: aggregateID)
            let writer = TapAudioWriter(file: file, inputFormat: inputFormat) { [weak self] db, bands in
                Task { @MainActor [weak self] in
                    guard let self, self.isCapturing else { return }
                    let now = Date()
                    let dt = self.lastMeterDate.map { now.timeIntervalSince($0) } ?? 1 / AudioEnvelopeConfig.publishRateHz
                    self.lastMeterDate = now
                    let level = self.envelope.process(db: db, dt: dt)
#if DEBUG
                    self.meterDebugText = String(format: "system db %.1f  floor %.1f  gate %.2f  target %.2f  out %.3f  dt %.0fms",
                                                 db, self.envelope.noiseFloorDb, self.envelope.lastGate,
                                                 self.envelope.lastTarget, level, dt * 1000)
#endif
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(level)
                    self.frequencyBands = bands.map { $0 * self.envelope.lastGate }
                }
            }
            self.writer = writer
            startedAt = writer.startedAt
            // A Bluetooth headset drops to 16 kHz (HFP) once a microphone opens; follow it,
            // otherwise 16 kHz buffers are read as 48 kHz and come out sped up with gaps.
            let (tap, device) = (tapID, aggregateID)
            let listener: AudioObjectPropertyListenerBlock = { @Sendable _, _ in
                do {
                    writer.updateFormat(try Self.captureFormat(tapID: tap, aggregateID: device))
                } catch {
                    log.error("[SystemAudio] Format refresh failed: \(LogRedact.describe(error))")
                }
            }
            formatListener = listener
            var tapFormatAddress = Self.formatAddress(kAudioTapPropertyFormat)
            var rateAddress = Self.formatAddress(kAudioDevicePropertyNominalSampleRate)
            let tapStatus = AudioObjectAddPropertyListenerBlock(tapID, &tapFormatAddress, ioQueue, listener)
            let rateStatus = AudioObjectAddPropertyListenerBlock(aggregateID, &rateAddress, ioQueue, listener)
            if tapStatus != noErr || rateStatus != noErr {
                log.error("[SystemAudio] Format listener not registered (tap \(tapStatus), device \(rateStatus))")
            }
            // Core Audio invokes this on ioQueue, not the enclosing MainActor.
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) {
                @Sendable now, input, inputTime, _, _ in
                let timestamp = inputTime.pointee
                let hostTime = timestamp.mFlags.contains(.hostTimeValid) ? timestamp.mHostTime : now.pointee.mHostTime
                writer.consume(input, hostTime: hostTime)
            }, "audiocallback")
            try Self.check(AudioDeviceStart(aggregateID, ioProcID), "opname")
        } catch {
            tearDown()
            errorMessage = error.localizedDescription
            throw error
        }

        hasPermission = true
        currentOutputURL = outputURL
        currentMicURL = nil // Combined mode records the microphone with AudioRecorder.
        isCapturing = true
        duration = 0
        audioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
        frequencyBands = Array(repeating: 0, count: AudioSpectrumProcessor.frequencies.count)
        envelope.reset()
        lastMeterDate = nil
        startDate = startedAt
        timer = Timer.scheduledTimer(withTimeInterval: 1 / AudioEnvelopeConfig.publishRateHz, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startDate = self.startDate else { return }
                let pause = self.pausedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.duration = max(0, Date().timeIntervalSince(startDate) - self.accumulatedPauseDuration - pause)
                if let lastMeterDate = self.lastMeterDate, Date().timeIntervalSince(lastMeterDate) > 0.15 {
                    let level = self.envelope.process(db: -120, dt: 1 / AudioEnvelopeConfig.publishRateHz)
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(level)
                    self.frequencyBands = self.frequencyBands.map { $0 * 0.79 }
                }
            }
        }
        return outputURL
    }

    /// Receives every converted 16 kHz mono buffer (for live recognition); nil stops delivery.
    func setLiveHandler(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        writer?.setLiveHandler(handler)
    }

    /// Returns this session's file once; nil when nothing was capturing, so a caller
    /// (cancel deletes the result) can never get an earlier session's file.
    func stopCapture() async -> CaptureResult {
        guard isCapturing else { return CaptureResult(systemAudioURL: nil, microphoneURL: nil) }
        tearDown()
        timer?.invalidate()
        timer = nil
        isCapturing = false
        resetMetrics()
        defer { currentOutputURL = nil }
        return CaptureResult(systemAudioURL: currentOutputURL, microphoneURL: nil)
    }

    private func tearDown() {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if let formatListener {
            var tapFormatAddress = Self.formatAddress(kAudioTapPropertyFormat)
            var rateAddress = Self.formatAddress(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(tapID, &tapFormatAddress, ioQueue, formatListener)
            AudioObjectRemovePropertyListenerBlock(aggregateID, &rateAddress, ioQueue, formatListener)
            self.formatListener = nil
        }
        ioQueue.sync {
            writer?.finishTimeline()
            if let writer {
                log.info("[SystemAudio] Captured \(writer.framesReceived) frames, wrote \(writer.framesWritten), dropped \(writer.framesDropped), skipped \(writer.framesSkipped), \(writer.silenceFills) silence fills, \(writer.formatChanges) format changes")
            }
        }
        writer = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    func pauseDurationTimer() {
        if pausedAt == nil { pausedAt = Date() }
        ioQueue.sync { writer?.setPaused(true) }
    }
    func resumeDurationTimer() {
        guard let pausedAt else { return }
        accumulatedPauseDuration += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        ioQueue.sync { writer?.setPaused(false) }
    }
    func resetMetrics() {
        duration = 0
        pausedAt = nil
        accumulatedPauseDuration = 0
        audioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
        frequencyBands = Array(repeating: 0, count: AudioSpectrumProcessor.frequencies.count)
        envelope.reset()
        lastMeterDate = nil
        micAudioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
    }

    nonisolated private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw SystemAudioCaptureError.coreAudio(operation, status) }
    }

    nonisolated private static func formatAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Tap channel layout at the aggregate device's current rate: the IO proc delivers at that rate.
    nonisolated private static func captureFormat(tapID: AudioObjectID, aggregateID: AudioObjectID) throws -> AVAudioFormat {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = formatAddress(kAudioTapPropertyFormat)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "tapformaat")
        let tapRate = format.mSampleRate
        var deviceRate = Float64(0)
        size = UInt32(MemoryLayout<Float64>.size)
        address = formatAddress(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &deviceRate) == noErr, deviceRate > 0 {
            format.mSampleRate = deviceRate
        }
        log.info("[SystemAudio] Tap format \(tapRate) Hz, device \(deviceRate) Hz, \(format.mChannelsPerFrame) ch")
        guard let inputFormat = AVAudioFormat(streamDescription: &format) else {
            throw SystemAudioCaptureError.coreAudio("tapformaat", -1)
        }
        return inputFormat
    }

    private static func tapUID(for tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        try check(withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, $0)
        }, "tap-ID")
        return uid as String
    }

    private static func defaultOutputUID() throws -> String {
        var outputID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                             0, nil, &size, &outputID), "audio-uitvoer")
        guard outputID != kAudioObjectUnknown else { throw SystemAudioCaptureError.noOutputDevice }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        try check(withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(outputID, &address, 0, nil, &size, $0)
        }, "audio-uitvoer")
        return uid as String
    }
}

final class SystemAudioLiveHandler: Sendable {
    // Returning an inout closure directly accumulates Swift reabstraction thunks on each read.
    private struct Handler: Sendable { let append: @Sendable (AVAudioPCMBuffer) -> Void }
    private let slot = OSAllocatedUnfairLock<Handler?>(initialState: nil)

    func set(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        let value = handler.map { Handler(append: $0) }
        slot.withLock { $0 = value }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let handler = slot.withLock { $0 }
        handler?.append(buffer)
    }
}

/// Not thread-safe: every call must come from the capture's serial ioQueue.
final class TapAudioWriter: @unchecked Sendable {
    let startedAt: Date
    private var file: AVAudioFile?
    private var inputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private let levelHandler: @Sendable (Float, [Float]) -> Void
    private var spectrum = AudioSpectrumProcessor()
    private var spectralSamples: [Float] = []
    private var timeline: AudioCaptureTimeline
    private let liveHandler = SystemAudioLiveHandler()
    private var lastLevel = Date.distantPast
    private(set) var framesReceived: UInt64 = 0
    private(set) var framesWritten: UInt64 = 0
    private(set) var framesDropped: UInt64 = 0
    private(set) var silenceFills: UInt64 = 0
    private(set) var formatChanges: UInt64 = 0
    private(set) var framesSkipped: UInt64 = 0
    private var converterPendingFrames = 0.0
    private var framesToSkip: Int64 = 0
    /// 1 ms at 16 kHz: converter latency, not worth a gap or a skip.
    private static let realignTolerance: Int64 = 16
    private var lastCallbackFrames: UInt32 = 0
    private var lastCallbackHostTime: UInt64 = 0

    init(file: AVAudioFile, inputFormat: AVAudioFormat, levelHandler: @escaping @Sendable (Float, [Float]) -> Void) {
        self.file = file
        self.inputFormat = inputFormat
        self.converter = AVAudioConverter(from: inputFormat, to: file.processingFormat)
        self.levelHandler = levelHandler
        startedAt = Date()
        timeline = AudioCaptureTimeline(sampleRate: file.processingFormat.sampleRate,
                                        start: AVAudioTime.seconds(forHostTime: mach_absolute_time()))
    }

    func setLiveHandler(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        liveHandler.set(handler)
    }

    func updateFormat(_ format: AVAudioFormat) {
        guard let file, format != inputFormat else { return }
        do {
            try drainConverter()
        } catch {
            log.error("[SystemAudio] Converter drain failed: code=\((error as NSError).code)")
        }
        inputFormat = format
        converter = AVAudioConverter(from: format, to: file.processingFormat)
        formatChanges += 1
        converterPendingFrames = 0
        log.info("[SystemAudio] Input format now \(format.sampleRate) Hz, converter available: \(converter != nil)")
    }

    /// Logs whenever the callback size changes, with the rate implied by the previous callback interval,
    /// so a log shows what the device really delivers next to the format we assume.
    /// `hostTime` is the buffer's audio timestamp (inputTime), not its arrival time.
    private func traceCallback(frames: UInt32, hostTime: UInt64) {
        defer { (lastCallbackFrames, lastCallbackHostTime) = (frames, hostTime) }
        guard frames != lastCallbackFrames else { return }
        let interval = lastCallbackHostTime == 0 || hostTime <= lastCallbackHostTime ? 0
            : AVAudioTime.seconds(forHostTime: hostTime - lastCallbackHostTime)
        log.info("[SystemAudio] Callback \(frames) frames (was \(lastCallbackFrames)), measured \(interval > 0 ? Double(lastCallbackFrames) / interval : 0) Hz, assumed \(inputFormat.sampleRate) Hz")
    }

    func consume(_ buffers: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        guard let file, !timeline.isPaused else { return }
        guard buffers.pointee.mNumberBuffers > 0 else { return }
        let bytesPerFrame = max(inputFormat.streamDescription.pointee.mBytesPerFrame, 1)
        let frames = buffers.pointee.mBuffers.mDataByteSize / bytesPerFrame
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: buffers) else { return }
        pcm.frameLength = AVAudioFrameCount(frames)
        framesReceived += UInt64(frames)
        traceCallback(frames: frames, hostTime: hostTime)
        do {
            guard let converter else { framesDropped += UInt64(frames); return }
            let capacity = AVAudioFrameCount(ceil(Double(frames) * file.processingFormat.sampleRate / inputFormat.sampleRate) + 32)
            let target = timeline.framePosition(at: AVAudioTime.seconds(forHostTime: hostTime))
            // Buffered resampler samples already belong to the timeline, even before file output.
            let drift = target - Int64(framesWritten) - Int64(max(0, converterPendingFrames).rounded())
            if drift > Self.realignTolerance {
                framesToSkip = 0
                try writeSilence(until: Int64(framesWritten) + drift)
            } else if drift < -Self.realignTolerance {
                framesToSkip = -drift
            }
            guard let converted = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var consumed = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return pcm
            }
            if let conversionError { throw conversionError }
            if consumed { converterPendingFrames += Double(frames) * file.processingFormat.sampleRate / inputFormat.sampleRate }
            try writeConverted(converted)
        } catch {
            log.error("[SystemAudio] Audio write failed: code=\((error as NSError).code), \(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))")
        }
    }

    /// Preserve the resampler's buffered tail before replacing it or ending capture.
    private func drainConverter() throws {
        guard let file, let converter,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024) else { return }
        while true {
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { _, status in
                status.pointee = .endOfStream
                return nil
            }
            if let error { throw error }
            try writeConverted(buffer)
            if status == .endOfStream || buffer.frameLength == 0 { break }
        }
    }

    private func writeConverted(_ converted: AVAudioPCMBuffer) throws {
        guard let file else { return }
        converterPendingFrames -= Double(converted.frameLength)
        if framesToSkip > 0, let data = converted.floatChannelData?[0] {
            let skip = min(framesToSkip, Int64(converted.frameLength))
            let keep = Int(converted.frameLength) - Int(skip)
            memmove(data, data + Int(skip), keep * MemoryLayout<Float>.size)
            converted.frameLength = AVAudioFrameCount(keep)
            framesToSkip -= skip
            framesSkipped += UInt64(skip)
        }
        if converted.frameLength > 0 {
            try file.write(from: converted)
            framesWritten += UInt64(converted.frameLength)
            if let samples = converted.floatChannelData?[0] {
                spectralSamples.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(converted.frameLength)))
                if spectralSamples.count > 1024 { spectralSamples.removeFirst(spectralSamples.count - 1024) }
                let now = Date()
                let dt = now.timeIntervalSince(lastLevel)
                if dt >= 1 / AudioEnvelopeConfig.publishRateHz {
                    lastLevel = now
                    let sum = spectralSamples.reduce(Float(0)) { $0 + $1 * $1 }
                    let db = 20 * log10(max(sqrt(sum / Float(spectralSamples.count)), 1e-10))
                    let bands = spectrum.process(samples: spectralSamples, sampleRate: file.processingFormat.sampleRate, dt: dt)
                    levelHandler(db, bands)
                }
            }
            liveHandler.append(converted)
        }
    }

    func setPaused(_ paused: Bool) {
        timeline.setPaused(paused, at: AVAudioTime.seconds(forHostTime: mach_absolute_time()))
    }

    func finishTimeline() {
        // Core Audio may retain callback closures after stop; finalize the WAV before returning it.
        defer {
            if #available(macOS 15.0, *) { file?.close() }
            file = nil
        }
        do {
            try drainConverter()
            try writeSilence(until: timeline.framePosition(at: AVAudioTime.seconds(forHostTime: mach_absolute_time())))
        } catch {
            log.error("[SystemAudio] Final timeline write failed: code=\((error as NSError).code), \(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))")
        }
    }

    private func writeSilence(until target: Int64) throws {
        guard let file, target > Int64(framesWritten),
              let silence = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000) else { return }
        if let data = silence.floatChannelData?[0] { data.initialize(repeating: 0, count: 16_000) }
        silenceFills += 1
        while Int64(framesWritten) < target {
            silence.frameLength = AVAudioFrameCount(min(16_000, target - Int64(framesWritten)))
            try file.write(from: silence)
            framesWritten += UInt64(silence.frameLength)
        }
    }
}
#endif
