import AVFoundation
import os

// Compile alongside Normalize.swift and the application's AudioMixer.swift.
let cancelled = OSAllocatedUnfairLock(initialState: false)
signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interrupt.setEventHandler { cancelled.withLock { $0 = true } }
interrupt.resume()
func checkCancellation() throws {
    if cancelled.withLock({ $0 }) { throw CancellationError() }
}
let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "normalize" where args.count == 3:
        var lastPercent = -1
        let gain = try AudioNormalizationProbe.normalize(URL(fileURLWithPath: args[1]), into: URL(fileURLWithPath: args[2]), checkCancellation: checkCancellation) { fraction in
            let percent = Int(fraction * 100)
            if percent / 10 != lastPercent / 10 {
                FileHandle.standardError.write(Data("\(percent)%\n".utf8))
            }
            lastPercent = percent
        }
        print("gain_db=\(20 * log10(gain))")
    case "mix" where args.count == 5:
        guard let offset = Double(args[3]), offset.isFinite,
              abs(offset) < 86_400 else { throw CocoaError(.fileReadCorruptFile) }
        let output = URL(fileURLWithPath: args[4])
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
        try checkCancellation()
        let frames = try AudioMixer.mix(micURL: URL(fileURLWithPath: args[1]), systemURL: URL(fileURLWithPath: args[2]), systemStartOffset: offset, into: output)
        if cancelled.withLock({ $0 }) {
            try FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        print("frames=\(frames)")
    default:
        FileHandle.standardError.write(Data("Usage: audio-quality normalize input.wav output.wav | mix mic.wav system.wav offset_seconds output.wav\n".utf8))
        exit(2)
    }
} catch {
    // Technical diagnostics only; never print input paths or audio/transcript content.
    FileHandle.standardError.write(Data("failed: code=\((error as NSError).code), cancelled=\(error is CancellationError)\n".utf8))
    exit(error is CancellationError ? 130 : 1)
}
