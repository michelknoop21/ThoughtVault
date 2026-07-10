// AudioChunker.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Splits long audio files into fixed-duration 16kHz mono WAV chunks so engines
// with practical length limits (SFSpeechRecognizer ~1 min) or memory limits
// (WhisperKit loads the full file as Float array) can transcribe sequentially.

import Foundation
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "AudioChunker")

enum AudioChunker {

    /// Duration of the audio file in seconds, or nil if unreadable.
    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        guard format.sampleRate > 0 else { return nil }
        return Double(file.length) / format.sampleRate
    }

    /// Splits `url` into 16kHz mono WAV chunks of at most `chunkDuration` seconds.
    /// Converts and splits in a single streaming pass (no full-file buffering).
    /// Caller is responsible for deleting the returned temp files.
    static func chunk(url: URL, chunkDuration: TimeInterval) async throws -> [URL] {
        let sourceFile = try AVAudioFile(forReading: url)
        let sourceFormat = sourceFile.processingFormat

        let diskSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // Probe target processing format via a throwaway file (AVAudioFile exposes
        // Float32 processingFormat for Int16 disk settings — see AudioPreConverter).
        let framesPerChunk = AVAudioFramePosition(chunkDuration * 16_000.0)

        var chunkURLs: [URL] = []
        var outputFile: AVAudioFile?
        var framesInCurrentChunk: AVAudioFramePosition = 0

        func openNewChunk() throws -> AVAudioFile {
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunk_\(chunkURLs.count)_\(UUID().uuidString).wav")
            let file = try AVAudioFile(forWriting: chunkURL, settings: diskSettings)
            chunkURLs.append(chunkURL)
            framesInCurrentChunk = 0
            return file
        }

        outputFile = try openNewChunk()
        let targetFormat = outputFile!.processingFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw LocalTranscriberError.transcriptionFailed("Audio-conversie niet mogelijk voor dit formaat.")
        }

        let inputChunkSize = AVAudioFrameCount(max(4096, Int(sourceFormat.sampleRate)))
        let estimatedOutputChunkSize = AVAudioFrameCount(
            Double(inputChunkSize) * (targetFormat.sampleRate / sourceFormat.sampleRate) + 1024
        )
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputChunkSize),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedOutputChunkSize) else {
            throw LocalTranscriberError.transcriptionFailed("Kon audio-buffer niet aanmaken.")
        }

        var reachedEndOfStream = false
        while !reachedEndOfStream {
            try sourceFile.read(into: inputBuffer, frameCount: inputChunkSize)

            nonisolated(unsafe) let capturedInputBuffer = inputBuffer
            var didProvideInput = false
            while true {
                outputBuffer.frameLength = 0
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    if didProvideInput || capturedInputBuffer.frameLength == 0 {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    didProvideInput = true
                    outStatus.pointee = .haveData
                    return capturedInputBuffer
                }

                if status == .error || conversionError != nil {
                    throw LocalTranscriberError.transcriptionFailed(
                        "Audio-conversie mislukt: \(conversionError?.localizedDescription ?? "onbekend")"
                    )
                }

                if outputBuffer.frameLength > 0 {
                    // ponytail: chunk boundary at buffer granularity (~64ms drift max),
                    // sample-exact splitting not needed for speech.
                    if framesInCurrentChunk >= framesPerChunk {
                        outputFile = try openNewChunk()
                    }
                    try outputFile!.write(from: outputBuffer)
                    framesInCurrentChunk += AVAudioFramePosition(outputBuffer.frameLength)
                }

                if status == .endOfStream {
                    reachedEndOfStream = true
                    break
                }
                if status == .inputRanDry || status == .haveData {
                    break
                }
            }

            if inputBuffer.frameLength == 0 {
                reachedEndOfStream = true
            }
        }

        logger.info("Chunked \(url.lastPathComponent) into \(chunkURLs.count) chunk(s) of ≤\(Int(chunkDuration))s")
        return chunkURLs
    }
}
