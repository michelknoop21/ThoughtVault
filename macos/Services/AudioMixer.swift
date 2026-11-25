import AVFoundation

/// Mixes the microphone and system recordings into one 16 kHz stereo file: left is the microphone,
/// right is the system audio. Keeping them apart preserves the evidence of who spoke on which side,
/// which speaker detection uses; every engine reads the file through a mono downmix.
/// Each source is first brought to the same speech level and clamped to full scale.
/// The capture levels differ per microphone and per call app.
enum AudioMixer {
    private static let sampleRate = 16_000.0
    private static let chunkFrames: AVAudioFrameCount = 16_000 * 10
    private static let levelBlock = 1_600  // 100 ms
    /// Target for the loud speech blocks of a source, about -21 dBFS RMS. Measured on a 56 minute
    /// meeting this puts both voices near -22 dBFS with 0.01% of the samples at full scale.
    private static let targetLevel: Float = 0.09

    /// Gain that brings a source with this speech level to the target. A source without signal
    /// keeps gain 1, and the range is capped so noise is not blown up and a hot source is not crushed.
    static func gain(forLevel level: Float) -> Float {
        level < 0.001 ? 1 : min(16, max(0.25, targetLevel / level))
    }

    /// Speech level of one source: the 95th percentile of the RMS per 100 ms block. A percentile
    /// ignores the silence between turns and a single loud click, which a peak or a mean would not.
    private static func speechLevel(of file: AVAudioFile, buffer: AVAudioPCMBuffer, data: UnsafeMutablePointer<Float>) throws -> Float {
        defer { file.framePosition = 0 }
        var blocks: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunkFrames)
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }
            for start in stride(from: 0, to: count, by: levelBlock) {
                let end = min(count, start + levelBlock)
                var sum: Float = 0
                for i in start..<end { sum += data[i] * data[i] }
                blocks.append((sum / Float(end - start)).squareRoot())
            }
        }
        guard !blocks.isEmpty else { return 0 }
        blocks.sort()
        return blocks[Int(0.95 * Float(blocks.count - 1))]
    }

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
              let stereo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let micBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
              let sysBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
              let outBuf = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: chunkFrames),
              let mic = micBuf.floatChannelData?[0], let sys = sysBuf.floatChannelData?[0],
              let left = outBuf.floatChannelData?[0], let right = outBuf.floatChannelData?[1]
        else { throw CocoaError(.fileReadCorruptFile) }

        let micGain = gain(forLevel: try speechLevel(of: micFile, buffer: micBuf, data: mic))
        let sysGain = gain(forLevel: try speechLevel(of: sysFile, buffer: sysBuf, data: sys))

        let tempURL = outputURL.deletingLastPathComponent().appendingPathComponent(".mixing-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let diskSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
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
                    left[i] = max(-1, min(1, m * micGain))
                    right[i] = max(-1, min(1, s * sysGain))
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
