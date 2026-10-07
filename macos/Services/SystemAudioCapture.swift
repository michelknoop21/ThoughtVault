#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import OSLog
import os

private let log = OSLog(subsystem: "com.buildmind.ThoughtVault", category: "SystemAudio")

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
    private var timer: Timer?
    private var startDate: Date?
    private var pausedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var envelope = AudioEnvelopeProcessor()
    private var lastMeterDate: Date?
    private let ioQueue = DispatchQueue(label: "com.buildmind.ThoughtVault.SystemAudioCapture.io")

    @discardableResult
    func startCapture(includeMicrophone: Bool = false) async throws -> URL {
        let outputUID = try Self.defaultOutputUID()
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("system_audio_\(UUID().uuidString).wav")
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

            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            try Self.check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "tapformaat")
            guard let inputFormat = AVAudioFormat(streamDescription: &format) else {
                throw SystemAudioCaptureError.coreAudio("tapformaat", -1)
            }
            let writer = TapAudioWriter(file: file, inputFormat: inputFormat) { [weak self] db in
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
                }
            }
            self.writer = writer
            // Core Audio invokes this on ioQueue, not the enclosing MainActor.
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) {
                @Sendable _, input, _, _, _ in writer.consume(input)
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
        envelope.reset()
        lastMeterDate = nil
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startDate = self.startDate else { return }
                let pause = self.pausedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.duration = max(0, Date().timeIntervalSince(startDate) - self.accumulatedPauseDuration - pause)
            }
        }
        return outputURL
    }

    /// Receives every converted 16 kHz mono buffer (for live recognition); nil stops delivery.
    func setLiveHandler(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        writer?.setLiveHandler(handler)
    }

    func stopCapture() async -> CaptureResult {
        guard isCapturing else { return CaptureResult(systemAudioURL: currentOutputURL, microphoneURL: nil) }
        if let writer {
            os_log("[SystemAudio] Captured %llu frames, wrote %llu frames", log: log,
                   writer.framesReceived, writer.framesWritten)
        }
        tearDown()
        timer?.invalidate()
        timer = nil
        isCapturing = false
        resetMetrics()
        return CaptureResult(systemAudioURL: currentOutputURL, microphoneURL: nil)
    }

    private func tearDown() {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        ioQueue.sync {}
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

    func pauseDurationTimer() { if pausedAt == nil { pausedAt = Date() } }
    func resumeDurationTimer() {
        guard let pausedAt else { return }
        accumulatedPauseDuration += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }
    func resetMetrics() {
        duration = 0
        pausedAt = nil
        accumulatedPauseDuration = 0
        audioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
        envelope.reset()
        lastMeterDate = nil
        micAudioLevels = Array(repeating: 0, count: AudioEnvelopeConfig.historyLength)
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw SystemAudioCaptureError.coreAudio(operation, status) }
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

private final class TapAudioWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let levelHandler: @Sendable (Float) -> Void
    private let liveHandler = OSAllocatedUnfairLock<(@Sendable (AVAudioPCMBuffer) -> Void)?>(initialState: nil)
    private var lastLevel = Date.distantPast
    private(set) var framesReceived: UInt64 = 0
    private(set) var framesWritten: UInt64 = 0

    init(file: AVAudioFile, inputFormat: AVAudioFormat, levelHandler: @escaping @Sendable (Float) -> Void) {
        self.file = file
        self.inputFormat = inputFormat
        self.converter = AVAudioConverter(from: inputFormat, to: file.processingFormat)
        self.levelHandler = levelHandler
    }

    func setLiveHandler(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        liveHandler.withLock { $0 = handler }
    }

    func consume(_ buffers: UnsafePointer<AudioBufferList>) {
        guard buffers.pointee.mNumberBuffers > 0 else { return }
        let bytesPerFrame = max(inputFormat.streamDescription.pointee.mBytesPerFrame, 1)
        let frames = buffers.pointee.mBuffers.mDataByteSize / bytesPerFrame
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: buffers) else { return }
        pcm.frameLength = AVAudioFrameCount(frames)
        framesReceived += UInt64(frames)
        if Date().timeIntervalSince(lastLevel) >= 1 / AudioEnvelopeConfig.publishRateHz {
            lastLevel = Date()
            if let samples = pcm.floatChannelData?[0] {
                var sum: Float = 0
                for index in 0..<Int(frames) { sum += samples[index] * samples[index] }
                let db = 20 * log10(max(sqrt(sum / Float(frames)), 1e-10))
                levelHandler(db)
            }
        }
        do {
            guard let converter else { return }
            let capacity = AVAudioFrameCount(ceil(Double(frames) * file.processingFormat.sampleRate / inputFormat.sampleRate) + 32)
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
            if converted.frameLength > 0 {
                try file.write(from: converted)
                framesWritten += UInt64(converted.frameLength)
                liveHandler.withLock { $0 }?(converted)
            }
        } catch {
            os_log("[SystemAudio] Audio write failed: %{public}@", log: log, error.localizedDescription)
        }
    }
}
#endif
