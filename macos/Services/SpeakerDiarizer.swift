// SpeakerDiarizer.swift
// ThoughtVault
//
// Who speaks when, on the whole recording at once (never per chunk, so a voice keeps one id).
// Uses FluidAudio's offline diarizer (pyannote community-1 segmentation, WeSpeaker embeddings,
// VBx clustering), chosen on measurements of Dutch recordings (docs/qa/sprekers-2026-11-24).
// The models are never downloaded implicitly: the user fetches them in Settings, Verwerking.

import AVFoundation
import FluidAudio

private let logger = AppLog(category: "SpeakerDiarizer")

enum SpeakerDiarizer {
    /// Segments with speakers, and name proposals per speaker id.
    typealias Labels = (segments: [TranscriptSegment], names: [String: SpeakerName])

    /// FluidAudio's models folder; the diarizer lives in `Repo.diarizer.folderName` inside it.
    nonisolated static var folder: URL { OfflineDiarizerModels.defaultModelsDirectory() }

    nonisolated static var repoFolder: URL { folder.appendingPathComponent(Repo.diarizer.folderName) }

    nonisolated private static let requiredFiles = [
        ModelNames.OfflineDiarizer.segmentationFile, ModelNames.OfflineDiarizer.fbankFile,
        ModelNames.OfflineDiarizer.embeddingFile, ModelNames.OfflineDiarizer.pldaRhoFile,
        ModelNames.OfflineDiarizer.pldaParameters,
    ]

    /// Load-ready on disk. Checked before every load, because loading downloads what is missing.
    nonisolated static var isInstalled: Bool {
        requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: repoFolder.appendingPathComponent($0).path) }
    }

    /// Speaker turns over the whole recording. Reads a mono downmix, so a stereo call counts both sides.
    static func turns(for url: URL) async throws -> [SpeakerTurn] {
        guard isInstalled else { throw LocalTranscriberError.modelNotInstalled("speaker-diarization") }
        let wav = try await AudioPreConverter.convertToWav16k(url)
        defer { if wav != url { try? FileManager.default.removeItem(at: wav) } }
        let manager = OfflineDiarizerManager()
        manager.initialize(models: try await OfflineDiarizerModels.load(from: folder))
        let result = try await manager.process(wav)
        return result.segments.map {
            SpeakerTurn(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), speaker: $0.speakerId)
        }
    }

    // MARK: Microphone channel

    /// Seconds per block that gets one speaker.
    private static let block = 0.1
    /// How much more a speaker must be heard on the microphone than on the system side (6 dB in power).
    private static let sideRatio: Double = 4

    /// The speaker id heard on the microphone of a stereo call (left channel), when exactly one voice is.
    /// The microphone alone proves nothing: around a table or in a hybrid meeting several people speak
    /// into it, and loudspeaker sound leaks into it. So a speaker counts as local only when their speech
    /// is clearly louder on the microphone than on the system side, and only a single local speaker is
    /// returned. Anything else, a mono recording included, gives nil.
    static func localSpeaker(stereo url: URL, segments: [TranscriptSegment]) throws -> String? {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.channelCount == 2 else { return nil }
        let blockFrames = max(1, Int(file.processingFormat.sampleRate * block))
        var owner = [String?](repeating: nil, count: Int(file.length) / blockFrames + 1)
        for segment in segments {
            guard let id = segment.speakerId else { continue }
            let first = max(0, Int(segment.start / block))
            let end = min(owner.count, max(first + 1, Int((segment.end / block).rounded(.up))))
            for index in first..<end { owner[index] = id }
        }
        guard owner.contains(where: { $0 != nil }),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(blockFrames * 100)),
              let channels = buffer.floatChannelData else { return nil }
        var mic: [String: Double] = [:], system: [String: Double] = [:]
        var frame = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }
            for i in 0..<count {
                let index = (frame + i) / blockFrames
                guard index < owner.count, let id = owner[index] else { continue }
                mic[id, default: 0] += Double(channels[0][i] * channels[0][i])
                system[id, default: 0] += Double(channels[1][i] * channels[1][i])
            }
            frame += count
        }
        let local = mic.filter { $0.value > 0 && $0.value > sideRatio * (system[$0.key] ?? 0) }.map(\.key)
        logger.info("Channel rule: speakers=\(mic.count) local=\(local.count)")
        return local.count == 1 ? local[0] : nil
    }

    // MARK: Whole step

    /// Segments with speakers for a transcription, and a name proposal for the one local voice.
    /// Returns nil when there is nothing to label: no model, no timings, a single voice, or a failure.
    /// Speaker detection never stops a recording from being processed.
    static func label(_ timed: TimedTranscript, audio url: URL, selfName: String?) async -> Labels? {
        guard isInstalled, !timed.pieces.isEmpty else { return nil }
        let start = Date()
        do {
            let turns = try await turns(for: url)
            let segments = SpeakerTranscript.segments(pieces: timed.pieces, turns: turns)
            let speakers = Set(segments.compactMap(\.speakerId))
            logger.info("Speakers=\(speakers.count) turns=\(turns.count) segments=\(segments.count) s=\(Int(Date().timeIntervalSince(start)))")
            guard speakers.count > 1 else { return nil }
            var names: [String: SpeakerName] = [:]
            if let selfName, !selfName.isEmpty, let local = try localSpeaker(stereo: url, segments: segments) {
                names[local] = SpeakerName(name: selfName, confirmed: false,
                                           evidence: String(localized: "De enige stem op je microfoon"))
            }
            return (segments, names)
        } catch {
            logger.warning("Speaker detection skipped: \(LogRedact.describe(error))")
            return nil
        }
    }
}

// MARK: - Model store

/// Download, cancel and removal of the speaker detection models, for the Settings row.
@MainActor
@Observable
final class SpeakerModelStore {
    enum State: Equatable { case missing, downloading, installed, failed(String) }

    static let shared = SpeakerModelStore()
    private(set) var state: State = SpeakerDiarizer.isInstalled ? .installed : .missing
    private var task: Task<Void, Never>?

    private init() {}

    func download() {
        guard task == nil else { return }
        state = .downloading
        task = Task {
            do {
                _ = try await OfflineDiarizerModels.load(from: SpeakerDiarizer.folder)
                try Task.checkCancellation()
                var folder = SpeakerDiarizer.repoFolder
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
                state = SpeakerDiarizer.isInstalled ? .installed : .failed(String(localized: "Modelbestanden ontbreken na het downloaden."))
                logger.info("Downloaded speaker models")
            } catch {
                try? FileManager.default.removeItem(at: SpeakerDiarizer.repoFolder)
                if Task.isCancelled || error is CancellationError {
                    state = .missing
                } else {
                    state = .failed(error.localizedDescription)
                    logger.error("Speaker model download failed: \(LogRedact.describe(error))")
                }
            }
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    func remove() {
        task?.cancel()
        do {
            if FileManager.default.fileExists(atPath: SpeakerDiarizer.repoFolder.path) {
                try FileManager.default.removeItem(at: SpeakerDiarizer.repoFolder)
            }
            state = .missing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
