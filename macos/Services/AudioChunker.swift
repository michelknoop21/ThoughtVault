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
        var createdURLs: [URL] = []
        do {
            return try chunkThrowing(url: url, chunkDuration: chunkDuration, created: &createdURLs)
        } catch {
            // Clean up partial chunks so a mid-stream failure doesn't leak temp files.
            createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    private static func chunkThrowing(url: URL, chunkDuration: TimeInterval, created: inout [URL]) throws -> [URL] {
        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: url)
        } catch {
            throw LocalTranscriberError.transcriptionFailed(
                "Kon bronbestand niet openen (\(url.lastPathComponent)): \(error.localizedDescription)"
            )
        }
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

        var outputFile: AVAudioFile?
        var framesInCurrentChunk: AVAudioFramePosition = 0

        func openNewChunk() throws -> AVAudioFile {
            let index = created.count
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunk_\(index)_\(UUID().uuidString).wav")
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forWriting: chunkURL, settings: diskSettings)
            } catch {
                throw LocalTranscriberError.transcriptionFailed(
                    "Kon deelbestand \(index) niet aanmaken (frame \(sourceFile.framePosition)): \(error.localizedDescription)"
                )
            }
            created.append(chunkURL)
            framesInCurrentChunk = 0
            return file
        }

        outputFile = try openNewChunk()
        let targetFormat = outputFile!.processingFormat

        // Writes frames [start, start+count) of a Float32 non-interleaved buffer.
        func writeSlice(from buffer: AVAudioPCMBuffer, start: AVAudioFrameCount, count: AVAudioFrameCount, to file: AVAudioFile) throws {
            guard let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
                  let src = buffer.floatChannelData, let dst = slice.floatChannelData else {
                throw LocalTranscriberError.transcriptionFailed("Kon audio-slice-buffer niet aanmaken.")
            }
            for ch in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[ch], src[ch] + Int(start), Int(count) * MemoryLayout<Float>.size)
            }
            slice.frameLength = count
            do {
                try file.write(from: slice)
            } catch {
                throw LocalTranscriberError.transcriptionFailed(
                    "Schrijven naar deelbestand \(created.count - 1) mislukt (frame \(sourceFile.framePosition), \(count) frames): \(error.localizedDescription)"
                )
            }
        }

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
            // AVAudioFile.read throws a bare `nilError` (Foundation._GenericObjCError 0)
            // when framePosition already sits at EOF, so never issue that one extra
            // read: clamp to what is left and let an empty buffer drive the
            // converter's end-of-stream flush below.
            let framePosition = sourceFile.framePosition
            let framesRemaining = sourceFile.length - framePosition
            if framesRemaining > 0 {
                let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(inputChunkSize), framesRemaining))
                do {
                    try sourceFile.read(into: inputBuffer, frameCount: framesToRead)
                } catch {
                    throw LocalTranscriberError.transcriptionFailed(
                        "Lezen mislukt op frame \(framePosition) van \(sourceFile.length) (deelbestand \(created.count - 1)): \(error.localizedDescription)"
                    )
                }
            } else {
                inputBuffer.frameLength = 0
            }

            nonisolated(unsafe) let capturedInputBuffer = inputBuffer
            var didProvideInput = false
            while true {
                outputBuffer.frameLength = 0
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    if capturedInputBuffer.frameLength == 0 {
                        // Source exhausted: flush the converter's resampler tail.
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    if didProvideInput {
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
                    // Split at the exact sample boundary so no chunk exceeds framesPerChunk.
                    var offset: AVAudioFrameCount = 0
                    while offset < outputBuffer.frameLength {
                        if framesInCurrentChunk >= framesPerChunk {
                            outputFile = try openNewChunk()
                        }
                        let remainingInChunk = AVAudioFrameCount(framesPerChunk - framesInCurrentChunk)
                        let toWrite = min(outputBuffer.frameLength - offset, remainingInChunk)
                        try writeSlice(from: outputBuffer, start: offset, count: toWrite, to: outputFile!)
                        offset += toWrite
                        framesInCurrentChunk += AVAudioFramePosition(toWrite)
                    }
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

        let count = created.count
        logger.info("Chunked \(url.lastPathComponent) into \(count) chunk(s) of ≤\(Int(chunkDuration))s")
        return created
    }
}
