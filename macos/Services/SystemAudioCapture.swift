#if os(macOS)
@preconcurrency import AVFoundation
import Foundation
import OSLog
import ScreenCaptureKit

private let log = OSLog(subsystem: "nl.prezent.TranscriptStudio", category: "SystemAudio")

// MARK: - CaptureResult

struct CaptureResult {
    let systemAudioURL: URL?
    let microphoneURL: URL?
}

// MARK: - SystemAudioCapture

@Observable
@MainActor
final class SystemAudioCapture: NSObject {

    // MARK: - Observable State

    var isCapturing: Bool = false
    var duration: TimeInterval = 0
    var audioLevels: [Float] = Array(repeating: 0, count: 60)
    var micAudioLevels: [Float] = Array(repeating: 0, count: 60)
    var hasPermission: Bool = false
    var errorMessage: String? = nil
    var currentOutputURL: URL? = nil
    var currentMicURL: URL? = nil

    // MARK: - Private

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var micAudioFile: AVAudioFile?
    private var streamOutput: AudioStreamOutput?
    private var durationTimer: Timer?
    private var startDate: Date?
    private var capturingMicrophone: Bool = false
    private let sampleHandlerQueue = DispatchQueue(label: "nl.prezent.TranscriptStudio.SystemAudioCapture.samples")

    // MARK: - Init / Deinit

    override init() {
        super.init()
    }

    // MARK: - Permission

    func checkPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.hasPermission = true
        } catch {
            self.hasPermission = false
        }
    }

    // MARK: - Capture Lifecycle

    @discardableResult
    func startCapture(includeMicrophone: Bool = false) async throws -> URL {
        // Verify permission
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.hasPermission = true
        } catch {
            self.hasPermission = false
            self.errorMessage = "Systeemaudio-machtiging is vereist voor opname."
            throw error
        }

        // Prepare output files
        let outputURL = makeOutputURL(prefix: "system_audio")
        let micURL = includeMicrophone ? makeOutputURL(prefix: "mic_audio") : nil

        // Build stream configuration — audio capture with minimal video workload.
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = false
        if #available(macOS 15.0, *) {
            config.captureMicrophone = includeMicrophone
        } else {
            // macOS 14: SCStream requires .screen output, so minimize video workload.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.queueDepth = 5
        }

        // Use first available display as capture target
        guard let display = shareableContent.displays.first else {
            let msg = "Geen beschikbaar scherm gevonden voor systeemaudio-opname."
            self.errorMessage = msg
            throw NSError(domain: "SystemAudioCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Set up audio format: 16kHz mono float32 PCM
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "SystemAudioCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Kon audioformaat niet aanmaken."])
        }

        // Open output AVAudioFile for system audio
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: outputURL, settings: audioFormat.settings)
        } catch {
            self.errorMessage = "Kon audiobestand niet aanmaken: \(error.localizedDescription)"
            throw error
        }
        self.audioFile = file

        // Open output AVAudioFile for microphone (if requested)
        var micFile: AVAudioFile? = nil
        if let micURL {
            do {
                micFile = try AVAudioFile(forWriting: micURL, settings: audioFormat.settings)
            } catch {
                self.errorMessage = "Kon microfoonbestand niet aanmaken: \(error.localizedDescription)"
                throw error
            }
        }
        self.micAudioFile = micFile

        // Set up stream output handler
        let output = AudioStreamOutput(
            systemAudioFile: file,
            microphoneAudioFile: micFile,
            systemLevelHandler: { [weak self] level in
                Task { @MainActor in
                    guard let self else { return }
                    var levels = self.audioLevels
                    levels.removeFirst()
                    levels.append(level)
                    self.audioLevels = levels
                }
            },
            micLevelHandler: includeMicrophone ? { [weak self] level in
                Task { @MainActor in
                    guard let self else { return }
                    var levels = self.micAudioLevels
                    levels.removeFirst()
                    levels.append(level)
                    self.micAudioLevels = levels
                }
            } : nil,
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.errorMessage = "Stream fout: \(error.localizedDescription)"
                }
            }
        )
        self.streamOutput = output

        // Create and start stream — pass delegate for error reporting
        let captureStream = SCStream(filter: filter, configuration: config, delegate: output)
        try captureStream.addStreamOutput(
            output,
            type: .audio,
            sampleHandlerQueue: sampleHandlerQueue
        )
        if #unavailable(macOS 15.0) {
            // macOS 14: SCStream requires at least one .screen output to function.
            // On macOS 15+ we omit this so the app is categorized as "System Audio Only"
            // instead of "Screen and System Audio Recording" in System Settings.
            try captureStream.addStreamOutput(
                output,
                type: .screen,
                sampleHandlerQueue: sampleHandlerQueue
            )
        }
        if includeMicrophone {
            if #available(macOS 15.0, *) {
                try captureStream.addStreamOutput(
                    output,
                    type: .microphone,
                    sampleHandlerQueue: sampleHandlerQueue
                )
            }
        }
        try await captureStream.startCapture()

        self.stream = captureStream

        let now = Date()
        self.startDate = now

        self.currentOutputURL = outputURL
        self.currentMicURL = micURL
        self.capturingMicrophone = includeMicrophone
        self.isCapturing = true
        self.duration = 0
        self.audioLevels = Array(repeating: 0, count: 60)
        self.micAudioLevels = Array(repeating: 0, count: 60)
        self.errorMessage = nil

        startDurationTimer()

        return outputURL
    }

    func stopCapture() async -> CaptureResult {
        guard isCapturing, let captureStream = stream else {
            return CaptureResult(systemAudioURL: currentOutputURL, microphoneURL: currentMicURL)
        }

        // 1. Stop the stream — no new samples will be delivered
        do {
            try await captureStream.stopCapture()
        } catch {
            os_log("[SystemAudio] Failed to stop capture stream: %{public}@", log: log, error.localizedDescription)
        }

        // 2. Remove stream reference
        stream = nil

        // 3. Log capture summary before releasing output handler
        if let output = streamOutput {
            os_log("[SystemAudio] Capture summary — system samples: %llu, screen samples: %llu, system frames received: %llu, written: %llu",
                   log: log, output.systemSampleCount, output.screenSampleCount,
                   output.systemFramesReceived, output.systemFramesWritten)
        }

        // 4. Remove output handler (stops writing)
        streamOutput = nil

        // 4. Flush any enqueued sample writes before releasing AVAudioFile references
        sampleHandlerQueue.sync {}

        // 5. Flush audio files by releasing references —
        //    no concurrent writer exists at this point
        audioFile = nil
        micAudioFile = nil

        durationTimer?.invalidate()
        durationTimer = nil

        // Converters are released with streamOutput (AudioStreamOutput owns them)

        let result = CaptureResult(systemAudioURL: currentOutputURL, microphoneURL: currentMicURL)

        // Log final file sizes for diagnostics
        let fm = FileManager.default
        if let sysURL = result.systemAudioURL,
           let attrs = try? fm.attributesOfItem(atPath: sysURL.path),
           let size = attrs[.size] as? Int64 {
            os_log("[SystemAudio] System audio file size: %lld bytes at %{public}@", log: log, size, sysURL.lastPathComponent)
        }
        if let micURL = result.microphoneURL,
           let attrs = try? fm.attributesOfItem(atPath: micURL.path),
           let size = attrs[.size] as? Int64 {
            os_log("[SystemAudio] Mic audio file size: %lld bytes at %{public}@", log: log, size, micURL.lastPathComponent)
        }

        self.isCapturing = false
        self.capturingMicrophone = false

        resetMetrics()

        return result
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }
    }

    // MARK: - Reset

    func resetMetrics() {
        self.duration = 0
        self.audioLevels = Array(repeating: 0, count: 60)
        self.micAudioLevels = Array(repeating: 0, count: 60)
    }

    // MARK: - File URL

    private func makeOutputURL(prefix: String) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)_\(timestamp).wav")
    }
}

// MARK: - AudioStreamOutput

private final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {

    private let systemAudioFile: AVAudioFile
    private let microphoneAudioFile: AVAudioFile?
    private let systemLevelHandler: (Float) -> Void
    private let micLevelHandler: ((Float) -> Void)?
    private let errorHandler: (Error) -> Void

    init(
        systemAudioFile: AVAudioFile,
        microphoneAudioFile: AVAudioFile?,
        systemLevelHandler: @escaping (Float) -> Void,
        micLevelHandler: ((Float) -> Void)?,
        errorHandler: @escaping (Error) -> Void
    ) {
        self.systemAudioFile = systemAudioFile
        self.microphoneAudioFile = microphoneAudioFile
        self.systemLevelHandler = systemLevelHandler
        self.micLevelHandler = micLevelHandler
        self.errorHandler = errorHandler
    }

    // MARK: - SCStreamOutput

    private var hasLoggedAudioFormat = false
    private var hasLoggedMicFormat = false
    private(set) var systemFramesReceived: UInt64 = 0
    private(set) var systemFramesWritten: UInt64 = 0
    private var micFramesReceived: UInt64 = 0
    private var micFramesWritten: UInt64 = 0
    private var lastDiagnosticLog: Date = .distantPast
    private(set) var systemSampleCount: UInt64 = 0
    private(set) var screenSampleCount: UInt64 = 0

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else {
            os_log("[SystemAudio] Received invalid sample buffer (type=%d)", log: log, outputType.rawValue)
            return
        }

        if outputType == .screen {
            screenSampleCount += 1
            return
        }

        if outputType == .audio {
            systemSampleCount += 1
            if !hasLoggedAudioFormat {
                hasLoggedAudioFormat = true
                if let desc = sampleBuffer.formatDescription?.audioStreamBasicDescription {
                    os_log("[SystemAudio] System audio format: %.0f Hz, %d ch, flags=0x%X, bitsPerChannel=%d",
                           log: log, desc.mSampleRate, desc.mChannelsPerFrame, desc.mFormatFlags, desc.mBitsPerChannel)
                } else {
                    os_log("[SystemAudio] First system audio sample received but NO format description available", log: log)
                }
            }
            writeSamples(from: sampleBuffer, to: systemAudioFile, levelHandler: systemLevelHandler, streamLabel: "system")
            return
        }

        if #available(macOS 15.0, *), outputType == .microphone {
            guard let micFile = microphoneAudioFile else { return }
            if !hasLoggedMicFormat, let desc = sampleBuffer.formatDescription?.audioStreamBasicDescription {
                hasLoggedMicFormat = true
                os_log("[SystemAudio] Microphone format: %.0f Hz, %d ch, flags=0x%X",
                       log: log, desc.mSampleRate, desc.mChannelsPerFrame, desc.mFormatFlags)
            }
            writeSamples(from: sampleBuffer, to: micFile, levelHandler: micLevelHandler ?? { _ in }, streamLabel: "mic")
            return
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        errorHandler(error)
    }

    // MARK: - Sample Writing

    /// Lazily created converters for resampling audio from ScreenCaptureKit's native format
    /// (often 48 kHz stereo) to the output file's format (16 kHz mono).
    /// Keyed by the audio file's hash to support separate converters for system and mic streams.
    private var converters: [ObjectIdentifier: AVAudioConverter] = [:]
    private var converterFormats: [ObjectIdentifier: AVAudioFormat] = [:]

    private func writeSamples(
        from sampleBuffer: CMSampleBuffer,
        to audioFile: AVAudioFile,
        levelHandler: (Float) -> Void,
        streamLabel: String
    ) {
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription
                else {
                    os_log("[SystemAudio] No audio format description in sample buffer (%{public}@)", log: log, streamLabel)
                    return
                }

                // ScreenCaptureKit may deliver interleaved or non-interleaved float32.
                let isInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

                guard let sourceFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: description.mSampleRate,
                    channels: description.mChannelsPerFrame,
                    interleaved: isInterleaved
                ) else {
                    os_log("[SystemAudio] Could not create AVAudioFormat: %.0f Hz, %d ch, interleaved=%d (%{public}@)",
                           log: log, description.mSampleRate, description.mChannelsPerFrame, isInterleaved ? 1 : 0, streamLabel)
                    return
                }

                guard let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFormat,
                    bufferListNoCopy: audioBufferList.unsafePointer
                ) else {
                    os_log("[SystemAudio] Could not create PCM buffer from audio buffer list (%{public}@)", log: log, streamLabel)
                    return
                }

                let incomingFrames = UInt64(pcmBuffer.frameLength)

                // Calculate RMS level for waveform visualization
                let level = calculateLevel(from: pcmBuffer)
                levelHandler(level)

                let fileFormat = audioFile.processingFormat
                var framesWritten: UInt64 = 0

                // If source format matches file format, write directly
                if sourceFormat.sampleRate == fileFormat.sampleRate
                    && sourceFormat.channelCount == fileFormat.channelCount {
                    try audioFile.write(from: pcmBuffer)
                    framesWritten = incomingFrames
                } else {
                    // Resample: ScreenCaptureKit often delivers 48 kHz stereo even when
                    // we requested 16 kHz mono. Convert to match the output file.
                    let fileKey = ObjectIdentifier(audioFile)
                    if converters[fileKey] == nil || converterFormats[fileKey] != sourceFormat {
                        converters[fileKey] = AVAudioConverter(from: sourceFormat, to: fileFormat)
                        converterFormats[fileKey] = sourceFormat
                    }
                    guard let conv = converters[fileKey] else {
                        os_log("[SystemAudio] Could not create audio converter (%{public}@)", log: log, streamLabel)
                        return
                    }

                    let ratio = fileFormat.sampleRate / sourceFormat.sampleRate
                    let outputFrames = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
                    guard let outputBuffer = AVAudioPCMBuffer(
                        pcmFormat: fileFormat, frameCapacity: outputFrames
                    ) else {
                        os_log("[SystemAudio] Could not create output buffer (%{public}@)", log: log, streamLabel)
                        return
                    }

                    nonisolated(unsafe) var inputConsumed = false
                    var error: NSError?
                    conv.convert(to: outputBuffer, error: &error) { _, outStatus in
                        if inputConsumed {
                            outStatus.pointee = .endOfStream
                            return nil
                        }
                        inputConsumed = true
                        outStatus.pointee = .haveData
                        return pcmBuffer
                    }
                    if let error {
                        os_log("[SystemAudio] Converter error (%{public}@): %{public}@", log: log, streamLabel, error.localizedDescription)
                        return
                    }

                    if outputBuffer.frameLength > 0 {
                        try audioFile.write(from: outputBuffer)
                        framesWritten = UInt64(outputBuffer.frameLength)
                    }
                }

                // Update diagnostic counters
                if streamLabel == "system" {
                    systemFramesReceived += incomingFrames
                    systemFramesWritten += framesWritten
                } else {
                    micFramesReceived += incomingFrames
                    micFramesWritten += framesWritten
                }

                // Log diagnostics every 5 seconds
                let now = Date()
                if now.timeIntervalSince(lastDiagnosticLog) >= 5.0 {
                    lastDiagnosticLog = now
                    os_log("[SystemAudio] Diagnostics — system: %llu received / %llu written, mic: %llu received / %llu written, level=%.3f (%{public}@)",
                           log: log,
                           systemFramesReceived, systemFramesWritten,
                           micFramesReceived, micFramesWritten,
                           level, streamLabel)
                }
            }
        } catch {
            os_log("[SystemAudio] Write error (%{public}@): %{public}@", log: log, streamLabel, error.localizedDescription)
        }
    }

    // MARK: - Level Calculation

    private func calculateLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        let channels = Int(buffer.format.channelCount)
        let isInterleaved = buffer.format.isInterleaved

        var sumOfSquares: Float = 0

        if isInterleaved {
            // Interleaved: samples are packed [L, R, L, R, ...] in a single buffer
            guard let data = buffer.audioBufferList.pointee.mBuffers.mData else { return 0 }
            let samples = data.assumingMemoryBound(to: Float.self)
            let stride = max(channels, 1)
            for i in Swift.stride(from: 0, to: frameCount * stride, by: stride) {
                let sample = samples[i]
                sumOfSquares += sample * sample
            }
        } else {
            // Non-interleaved: separate buffer per channel
            guard let channelData = buffer.floatChannelData else { return 0 }
            let samples = channelData[0]
            for i in 0..<frameCount {
                let sample = samples[i]
                sumOfSquares += sample * sample
            }
        }

        let rms = sqrt(sumOfSquares / Float(frameCount))

        // Convert RMS to dB with -60dB floor
        let db = 20 * log10(max(rms, 1e-10))
        let db60Floor: Float = -60.0
        if db <= db60Floor { return 0 }
        let normalized = pow((db - db60Floor) / 60.0, 0.6)
        return max(0, min(1, normalized))
    }
}

#endif
