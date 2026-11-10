// WhisperModelStore.swift
// ThoughtVault
//
// Local WhisperKit models: installed check, download with progress and
// cancel, and removal. Downloads go through WhisperKit's own `download`
// into the same folder WhisperKit loads from at transcription time.

import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

private let logger = AppLog(category: "WhisperModelStore")

@MainActor
@Observable
final class WhisperModelStore {

    static let shared = WhisperModelStore()

    /// Variant currently downloading, with 0...1 progress.
    private(set) var downloading: String?
    private(set) var progress: Double = 0
    /// Last download failure, per variant.
    private(set) var failure: (variant: String, message: String)?
    /// Bumped after a download or removal so views re-read the disk state.
    private(set) var revision = 0

    private var task: Task<Void, Never>?

    private init() {}

    /// WhisperKit's default download location (HubApi under Documents).
    nonisolated static var modelsFolder: URL {
        URL.documentsDirectory.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }

    /// Model folder for a variant name; nil unless it is a plain folder name.
    nonisolated static func folder(for variant: String) -> URL {
        let safe = variant.isEmpty || variant.contains("/") || variant.contains("..") ? "invalid-variant" : variant
        return modelsFolder.appendingPathComponent(safe)
    }

    /// Hub base folder WhisperKit loads the tokenizer from (HubApi default).
    nonisolated static var hubRoot: URL { URL.documentsDirectory.appendingPathComponent("huggingface") }

    /// "Installed" means offline-ready: all model parts plus a tokenizer.json.
    /// Exact folder match: "large-v3-v20240930" must not match its "_626MB" sibling.
    nonisolated static func isInstalled(_ variant: String) -> Bool {
        isInstalled(modelFolder: folder(for: variant), tokenizerRoot: hubRoot)
    }

    nonisolated static func isInstalled(modelFolder: URL, tokenizerRoot: URL) -> Bool {
        // A killed download can leave a partial folder; require every part WhisperKit loads.
        let fm = FileManager.default
        let needed = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        guard needed.allSatisfy({ fm.fileExists(atPath: modelFolder.appendingPathComponent($0).path) }) else { return false }
        #if canImport(WhisperKit)
        if fm.fileExists(atPath: modelFolder.appendingPathComponent("tokenizer.json").path) { return true }
        guard let variant = tokenizerVariant(modelFolder: modelFolder) else { return false }
        return fm.fileExists(atPath: tokenizerFolder(for: variant, root: tokenizerRoot).appendingPathComponent("tokenizer.json").path)
        #else
        return true
        #endif
    }

    #if canImport(WhisperKit)
    /// Folder WhisperKit searches for the tokenizer of a variant.
    nonisolated static func tokenizerFolder(for variant: ModelVariant, root: URL = hubRoot) -> URL {
        root.appendingPathComponent("models/openai/whisper-\(variant.description)")
    }

    /// Mirrors WhisperKit's `ModelUtilities.detectVariant` using config.json (vocab_size, d_model).
    /// Nil when the config is missing or the vocabulary size is unknown.
    nonisolated static func tokenizerVariant(modelFolder: URL) -> ModelVariant? {
        guard let data = try? Data(contentsOf: modelFolder.appendingPathComponent("config.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vocab = json["vocab_size"] as? Int
        else { return nil }
        let dim = json["d_model"] as? Int ?? 0
        switch vocab {
        case 51865:
            switch dim {
            case 384: return .tiny
            case 768: return .small
            case 1024: return .medium
            case 1280: return .largev2
            default: return .base
            }
        case 51864:
            switch dim {
            case 384: return .tinyEn
            case 768: return .smallEn
            case 1024: return .mediumEn
            default: return .baseEn
            }
        case 51866: return .largev3
        default: return nil
        }
    }
    #endif

    /// Size on disk of an installed model, in bytes.
    nonisolated static func installedSize(_ variant: String) -> Int64? {
        guard isInstalled(variant),
              let files = FileManager.default.enumerator(at: folder(for: variant), includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    func download(_ variant: String) {
        #if canImport(WhisperKit)
        guard downloading == nil else { return }
        downloading = variant
        progress = 0
        failure = nil
        task = Task {
            do {
                try await Self.fetch(variant) { fraction in
                    Task { @MainActor in self.progress = fraction }
                }
                try Task.checkCancellation()
                logger.info("Downloaded \(LogRedact.mask(variant))")
            } catch {
                // A partial folder would pass the installed check and break loading.
                try? FileManager.default.removeItem(at: Self.folder(for: variant))
                if Task.isCancelled || error is CancellationError {
                    logger.info("Download cancelled: \(LogRedact.mask(variant))")
                } else {
                    logger.error("Download failed \(LogRedact.mask(variant)): \(LogRedact.mask(error.localizedDescription))")
                    failure = (variant, error.localizedDescription)
                }
            }
            downloading = nil
            task = nil
            revision += 1
        }
        #endif
    }

    #if canImport(WhisperKit)
    nonisolated private static func fetch(_ variant: String, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = try await WhisperKit.download(variant: variant) { onProgress($0.fractionCompleted) }
        // Fetch the tokenizer together with the model so the first transcription works offline.
        guard let tokenizerVariant = tokenizerVariant(modelFolder: folder) else {
            throw NSError(domain: "WhisperModelStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Het tokenizer-type van dit model kon niet worden bepaald."])
        }
        _ = try await ModelUtilities.loadTokenizer(for: tokenizerVariant)
    }
    #endif

    func cancel() {
        task?.cancel()
    }

    func remove(_ variant: String) {
        guard downloading != variant else { return }
        do {
            try FileManager.default.removeItem(at: Self.folder(for: variant))
            failure = nil
        } catch {
            failure = (variant, error.localizedDescription)
        }
        revision += 1
    }
}
