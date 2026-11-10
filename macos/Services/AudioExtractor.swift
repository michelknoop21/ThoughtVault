import AVFoundation

enum AudioExtractorError: LocalizedError, Equatable {
    case noAudioTrack
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "Deze video bevat geen geluidsspoor."
        case .readFailed(let detail):
            return detail.isEmpty ? "De video kon niet worden gelezen." : "De video kon niet worden gelezen. \(detail)"
        }
    }
}

enum AudioExtractor {
    private static let sampleRate = 16_000.0

    /// Streams the first audio track of `videoURL` into a 16 kHz mono Int16 WAV.
    /// Writes to a temp file first; nothing is left at `wavURL` on failure.
    static func extractAudio(from videoURL: URL, to wavURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw AudioExtractorError.readFailed(error.localizedDescription)
        }
        guard let track = tracks.first else { throw AudioExtractorError.noAudioTrack }

        let tmpURL = wavURL.deletingLastPathComponent()
            .appendingPathComponent(".extract_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        do {
            try read(asset: asset, track: track, into: tmpURL)
            try? FileManager.default.removeItem(at: wavURL)
            try FileManager.default.moveItem(at: tmpURL, to: wavURL)
        } catch let error as AudioExtractorError {
            throw error
        } catch {
            throw AudioExtractorError.readFailed(error.localizedDescription)
        }
    }

    private static func read(asset: AVURLAsset, track: AVAssetTrack, into url: URL) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw AudioExtractorError.readFailed("") }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioExtractorError.readFailed(reader.error?.localizedDescription ?? "")
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        while let sample = output.copyNextSampleBuffer() {
            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample),
                  let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { continue }
            pcm.frameLength = frames
            let status = CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: Int(frames) * 2, destination: pcm.int16ChannelData![0])
            guard status == kCMBlockBufferNoErr else {
                throw AudioExtractorError.readFailed("CMBlockBuffer \(status)")
            }
            try file.write(from: pcm)
        }
        if reader.status == .failed {
            throw AudioExtractorError.readFailed(reader.error?.localizedDescription ?? "")
        }
    }
}
