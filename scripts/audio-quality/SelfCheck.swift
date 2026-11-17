import AVFoundation

@main
struct SelfCheck {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for rate in [16_000.0, 24_000, 44_100, 48_000] {
            for channels: AVAudioChannelCount in [1, 2] {
                for amplitude: Float in [0, 0.001, 0.1, 1] {
                    let source = directory.appendingPathComponent("source.wav")
                    let destination = directory.appendingPathComponent("output.wav")
                    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
                    do {
                        var settings = format.settings
                        settings[AVLinearPCMIsNonInterleaved] = false
                        let file = try AVAudioFile(forWriting: source, settings: settings)
                        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 40_001)!
                        buffer.frameLength = 40_001
                        for c in 0..<Int(channels) {
                            for i in 0..<40_001 { buffer.floatChannelData![c][i] = i.isMultiple(of: 2) ? amplitude : -amplitude }
                        }
                        try file.write(from: buffer)
                    }
                    let original = try Data(contentsOf: source)
                    var progress = 0.0
                    let gain = try AudioNormalizationProbe.normalize(source, into: destination, progress: {
                        precondition($0 >= progress && $0 <= 1)
                        progress = $0
                    })
                    precondition(progress == 1 && gain <= pow(10, 12 / 20))
                    let output = try AVAudioFile(forReading: destination)
                    precondition(output.length == 40_001 && output.processingFormat == format)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
                    while output.framePosition < output.length {
                        try output.read(into: buffer)
                        for c in 0..<Int(channels) {
                            for i in 0..<Int(buffer.frameLength) {
                                let value = abs(buffer.floatChannelData![c][i])
                                precondition(abs(value - amplitude * gain) < 1e-6)
                                precondition(value <= pow(10, -1 / 20) + 1e-6)
                            }
                        }
                    }
                    do {
                        _ = try AudioNormalizationProbe.normalize(source, into: destination)
                        preconditionFailure("Overwrote existing file")
                    } catch { precondition((error as NSError).code == CocoaError.fileWriteFileExists.rawValue) }
                    try FileManager.default.removeItem(at: destination)
                    var checks = 0
                    do {
                        _ = try AudioNormalizationProbe.normalize(source, into: destination, checkCancellation: {
                            checks += 1
                            if checks == 5 { throw CancellationError() }
                        })
                        preconditionFailure("Ignored cancellation")
                    } catch is CancellationError {}
                    precondition(!FileManager.default.fileExists(atPath: destination.path))
                    let preserved = try Data(contentsOf: source)
                    precondition(preserved == original)
                    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                    precondition(leftovers == ["source.wav"])
                    try FileManager.default.removeItem(at: source)
                }
            }
        }
        let missing = directory.appendingPathComponent("missing.wav")
        let destination = directory.appendingPathComponent("failed.wav")
        do {
            _ = try AudioNormalizationProbe.normalize(missing, into: destination)
            preconditionFailure("Accepted a missing input")
        } catch {}
        precondition(!FileManager.default.fileExists(atPath: destination.path))
        print("PASS: 32 rate/channel/level cases, frame preservation, peak ceiling, silence, progress, cancellation and source preservation")
    }
}
