#if os(macOS)
import AVFoundation
import Foundation
import ScreenCaptureKit

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
            self.errorMessage = "Schermopnamemachtiging is vereist voor systeemaudio-opname."
            throw error
        }

        // Prepare output files
        let outputURL = makeOutputURL(prefix: "system_audio")
        let micURL = includeMicrophone ? makeOutputURL(prefix: "mic_audio") : nil

        // Build stream configuration — audio-only, minimal video (ScreenCaptureKit requires video config)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = false
        if #available(macOS 15.0, *) {
            config.captureMicrophone = includeMicrophone
        }

        // Minimal video to satisfy ScreenCaptureKit requirements (2x2 px @ 1 fps)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 5

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
            sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated)
        )
        if includeMicrophone {
            if #available(macOS 15.0, *) {
                try captureStream.addStreamOutput(
                    output,
                    type: .microphone,
                    sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated)
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

        do {
            try await captureStream.stopCapture()
        } catch {
            // Non-fatal — proceed to clean up regardless
        }

        stream = nil
        streamOutput = nil
        audioFile = nil
        micAudioFile = nil

        durationTimer?.invalidate()
        durationTimer = nil

        let result = CaptureResult(systemAudioURL: currentOutputURL, microphoneURL: currentMicURL)

        self.isCapturing = false
        self.capturingMicrophone = false

        resetMetrics()

        return result
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.duration = elapsed
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

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }

        if outputType == .audio {
            writeSamples(from: sampleBuffer, to: systemAudioFile, levelHandler: systemLevelHandler)
            return
        }

        if #available(macOS 15.0, *), outputType == .microphone {
            guard let micFile = microphoneAudioFile else { return }
            writeSamples(from: sampleBuffer, to: micFile, levelHandler: micLevelHandler ?? { _ in })
            return
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        errorHandler(error)
    }

    // MARK: - Sample Writing

    private func writeSamples(
        from sampleBuffer: CMSampleBuffer,
        to audioFile: AVAudioFile,
        levelHandler: (Float) -> Void
    ) {
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                guard
                    let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                    let format = AVAudioFormat(
                        standardFormatWithSampleRate: description.mSampleRate,
                        channels: description.mChannelsPerFrame
                    ),
                    let pcmBuffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        bufferListNoCopy: audioBufferList.unsafePointer
                    )
                else { return }

                // Calculate RMS level for waveform visualization
                let level = calculateLevel(from: pcmBuffer)
                levelHandler(level)

                // Write samples to file
                try audioFile.write(from: pcmBuffer)
            }
        } catch {
            // Non-fatal write error; continue capturing
        }
    }

    // MARK: - Level Calculation

    private func calculateLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        let samples = channelData[0]
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            let sample = samples[i]
            sumOfSquares += sample * sample
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
