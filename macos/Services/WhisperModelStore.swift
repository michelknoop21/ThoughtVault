// WhisperModelStore.swift
// ThoughtVault
//
// Local WhisperKit models: installed check, download with progress and
// cancel, and removal. Downloads go through WhisperKit's own `download`
// into the same folder WhisperKit loads from at transcription time.

import Foundation
import OSLog
#if canImport(WhisperKit)
import WhisperKit
#endif

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "WhisperModelStore")

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

    /// Exact folder match: "large-v3-v20240930" must not match its "_626MB" sibling.
    nonisolated static func isInstalled(_ variant: String) -> Bool {
        // A killed download can leave a partial folder; require every part WhisperKit loads.
        let folder = folder(for: variant)
        let needed = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        return needed.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

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
                logger.info("Downloaded \(variant)")
            } catch {
                // A partial folder would pass the installed check and break loading.
                try? FileManager.default.removeItem(at: Self.folder(for: variant))
                if Task.isCancelled || error is CancellationError {
                    logger.info("Download cancelled: \(variant)")
                } else {
                    logger.error("Download failed \(variant): \(error.localizedDescription)")
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
        _ = try await WhisperKit.download(variant: variant) { onProgress($0.fractionCompleted) }
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
