// ParakeetTranscriber.swift
// ThoughtVault
//
// CoreML Parakeet transcription via FluidAudio. Never downloads; the model
// must be installed (see ParakeetModelStore). FluidAudio's URL overload
// handles long files itself, so there is no own chunking here.

import Foundation
import FluidAudio

private let logger = AppLog(category: "ParakeetTranscriber")

struct ParakeetTranscriber: LocalTranscriber {

    let model: String
    /// Injectable so tests need no model on disk.
    var isInstalled: @Sendable (String) -> Bool = { ParakeetModelStore.isInstalled($0) }

    func transcribe(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        try await transcribeTimed(url: url, profileId: profileId, onProgress: onProgress).text
    }

    func transcribeTimed(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> TimedTranscript {
        guard isInstalled(model) else { throw LocalTranscriberError.modelNotInstalled(model) }
        var stages = TranscriptionStageLog(engine: "Parakeet")
        do {
            onProgress(0.02)
            stages.begin("convert")

            // Same input as WhisperKit: 16kHz mono WAV with quiet recordings boosted.
            let wavURL: URL
            do {
                wavURL = try await AudioPreConverter.convertToWav16k(url)
            } catch {
                logger.warning("Pre-conversion failed (\(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))), trying original file")
                wavURL = url
            }
            defer {
                if wavURL != url { try? FileManager.default.removeItem(at: wavURL) }
            }
            stages.end(" converted=\(wavURL != url)")
            onProgress(0.06)

            stages.begin("model-load")
            let version = ParakeetModelStore.version(model)
            let models = try await AsrModels.load(from: ParakeetModelStore.folder(model), version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            stages.end()
            onProgress(0.15)
            stages.begin("transcribe")

            let stream = await manager.transcriptionProgressStream
            let progressTask = Task {
                for try await fraction in stream { onProgress(min(0.95, 0.15 + 0.8 * fraction)) }
            }
            defer { progressTask.cancel() }

            var decoder = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            let result = try await manager.transcribe(wavURL, decoderState: &decoder)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw LocalTranscriberError.emptyResult }
            onProgress(1.0)
            stages.end()
            logger.info("Parakeet transcription complete: \(text.count) characters")
            // Word times from the model's own token timings; the text itself stays the engine's text.
            let pieces = buildWordTimings(from: result.tokenTimings ?? []).map {
                TimedPiece(start: $0.startTime, end: $0.endTime, text: $0.word)
            }
            return TimedTranscript(text: text, pieces: pieces)
        } catch let error as LocalTranscriberError {
            stages.failed(error)
            throw error
        } catch {
            stages.failed(error)
            throw LocalTranscriberError.transcriptionFailed(error.localizedDescription)
        }
    }
}
