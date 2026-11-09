import AVFoundation

/// Mixes the microphone and system recordings into one 16 kHz mono file.
/// Sample = (mic + system) / 2, same rule as the Windows recorder.
enum AudioMixer {
    private static let sampleRate = 16_000.0
    private static let chunkFrames: AVAudioFrameCount = 16_000 * 10

    /// `systemStartOffset` is how many seconds later the system capture started than the microphone
    /// (negative = earlier). Returns the number of frames written to `outputURL`.
    static func mix(micURL: URL, systemURL: URL, systemStartOffset: TimeInterval, into outputURL: URL) throws -> AVAudioFramePosition {
        let micFile = try AVAudioFile(forReading: micURL)
        let sysFile = try AVAudioFile(forReading: systemURL)
        let shift = Int64((systemStartOffset * sampleRate).rounded())
        // Negative shift: the system lead before the microphone start is dropped.
        let drop = max(0, -shift)
        let pad = max(0, shift)
        let sysAligned = max(0, sysFile.length - drop) + pad
        let total = max(micFile.length, sysAligned)

        guard total > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let micBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
              let sysBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
              let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
              let mic = micBuf.floatChannelData?[0], let sys = sysBuf.floatChannelData?[0], let out = outBuf.floatChannelData?[0]
        else { throw CocoaError(.fileReadCorruptFile) }

        let tempURL = outputURL.deletingLastPathComponent().appendingPathComponent(".mixing-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let diskSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // Scoped so the file is finalized (closed) before the move.
            let outFile = try AVAudioFile(forWriting: tempURL, settings: diskSettings)
            sysFile.framePosition = drop
            var written: Int64 = 0
            while written < total {
                let n = Int(min(Int64(chunkFrames), total - written))
                micBuf.frameLength = 0
                if micFile.framePosition < micFile.length {
                    try micFile.read(into: micBuf, frameCount: AVAudioFrameCount(n))
                }
                // System frames start at output frame `pad`; before that the system side is silent.
                let silent = Int(max(0, min(Int64(n), pad - written)))
                sysBuf.frameLength = 0
                if silent < n, sysFile.framePosition < sysFile.length {
                    try sysFile.read(into: sysBuf, frameCount: AVAudioFrameCount(n - silent))
                }
                let micCount = Int(micBuf.frameLength), sysCount = Int(sysBuf.frameLength)
                for i in 0..<n {
                    let m: Float = i < micCount ? mic[i] : 0
                    let j = i - silent
                    let s: Float = j >= 0 && j < sysCount ? sys[j] : 0
                    out[i] = max(-1, min(1, (m + s) / 2))
                }
                outBuf.frameLength = AVAudioFrameCount(n)
                try outFile.write(from: outBuf)
                written += Int64(n)
            }
            _ = outFile
        }
        _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
        return total
    }
}
