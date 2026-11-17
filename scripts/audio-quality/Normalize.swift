import AVFoundation

/// Evaluation only. The app keeps using the original until the quality gate passes.
enum AudioNormalizationProbe {
    static func gain(peak: Float) -> Float {
        peak > 0 ? min(pow(10, 12 / 20), pow(10, -1 / 20) / peak) : 1
    }

    /// One gain for all channels; bounded memory, unchanged rate and frame count.
    static func normalize(_ source: URL, into destination: URL,
                          checkCancellation: () throws -> Void = {},
                          progress: (Double) -> Void = { _ in }) throws -> Float {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384),
              let data = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
        var peak: Float = 0
        while input.framePosition < input.length {
            try checkCancellation()
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { throw CocoaError(.fileReadCorruptFile) }
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<Int(buffer.frameLength) {
                    guard data[channel][i].isFinite else { throw CocoaError(.fileReadCorruptFile) }
                    peak = max(peak, abs(data[channel][i]))
                }
            }
            progress(Double(input.framePosition) / Double(input.length) / 2)
        }
        let gain = gain(peak: peak)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".normalizing-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        input.framePosition = 0
        do {
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let output = try AVAudioFile(forWriting: temporary, settings: settings)
            while input.framePosition < input.length {
                try checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { throw CocoaError(.fileReadCorruptFile) }
                for channel in 0..<Int(format.channelCount) {
                    for i in 0..<Int(buffer.frameLength) { data[channel][i] *= gain }
                }
                try output.write(from: buffer)
                progress(0.5 + Double(input.framePosition) / Double(input.length) / 2)
            }
        }
        try checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress(1)
        return gain
    }
}
