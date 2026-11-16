// ParakeetModelStore.swift
// ThoughtVault
//
// Local Parakeet models (FluidAudio): installed check, download with progress
// and cancel, and removal. Downloads go into FluidAudio's own cache folder,
// the same one ParakeetTranscriber loads from.

import Foundation
import FluidAudio

private let logger = AppLog(category: "ParakeetModelStore")

@MainActor
@Observable
final class ParakeetModelStore {

    enum State: Equatable {
        case missing, downloading(Double), installed, failed(String)
    }

    static let shared = ParakeetModelStore()

    /// State per model id from `ParakeetCatalog`.
    private(set) var states: [String: State] = [:]

    private var downloads: [String: Task<Void, Never>] = [:]

    private init() {
        for model in ParakeetCatalog.all {
            states[model.id] = Self.isInstalled(model.id) ? .installed : .missing
        }
    }

    nonisolated static func version(_ id: String) -> AsrModelVersion {
        switch id {
        case "ultra": .ultra
        case "redux": .redux
        default: .v3
        }
    }

    /// FluidAudio's cache folder for a model; download and load both use it.
    nonisolated static func folder(_ id: String) -> URL { AsrModels.defaultCacheDirectory(for: version(id)) }

    /// Load-ready on disk: FluidAudio rejects partial downloads here.
    nonisolated static func isInstalled(_ id: String) -> Bool {
        AsrModels.modelsExist(at: folder(id), version: version(id))
    }

    /// iPhone and iPad have less memory than a Mac and their own minimum OS.
    nonisolated static var isPhone: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    /// Memory, OS version and free disk space of this device.
    nonisolated static var device: (memoryGB: Int, system: Int, freeMegabytes: Int) {
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return (Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()),
                ProcessInfo.processInfo.operatingSystemVersion.majorVersion, Int(free / 1_000_000))
    }

    /// The recommended model for this device.
    nonisolated static var recommended: ParakeetModel {
        let device = device
        return ParakeetCatalog.recommended(memoryGB: device.memoryGB, system: device.system,
                                           phone: isPhone, freeMegabytes: device.freeMegabytes)
    }

    /// Why a model cannot run on this device; nil when it fits.
    nonisolated static func blocker(_ model: ParakeetModel) -> ParakeetCatalog.Blocker? {
        let device = device
        return ParakeetCatalog.blocker(model, memoryGB: device.memoryGB, system: device.system,
                                       phone: isPhone, freeMegabytes: device.freeMegabytes)
    }

    func state(_ id: String) -> State { states[id] ?? .missing }

    func isInstalled(_ id: String) -> Bool { state(id) == .installed }

    /// Fetches the model. Calling again after a failure retries.
    func download(_ id: String) {
        guard downloads[id] == nil else { return }
        states[id] = .downloading(0)
        downloads[id] = Task {
            do {
                _ = try await AsrModels.download(version: Self.version(id)) { progress in
                    Task { @MainActor in
                        if case .downloading = self.state(id) { self.states[id] = .downloading(progress.fractionCompleted) }
                    }
                }
                try Task.checkCancellation()
                var folder = Self.folder(id)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
                states[id] = .installed
                logger.info("Downloaded Parakeet \(id)")
            } catch {
                // A partial folder must not be mistaken for an installed model.
                try? FileManager.default.removeItem(at: Self.folder(id))
                if Task.isCancelled || error is CancellationError {
                    states[id] = .missing
                    logger.info("Download cancelled: Parakeet \(id)")
                } else {
                    states[id] = .failed(error.localizedDescription)
                    logger.error("Download failed Parakeet \(id): \(LogRedact.mask(error.localizedDescription)) error=\(LogRedact.describe(error))")
                }
            }
            downloads[id] = nil
        }
    }

    func cancel(_ id: String) {
        downloads[id]?.cancel()
    }

    /// Removes the model from disk; cancels a running download first.
    func remove(_ id: String) {
        downloads[id]?.cancel()
        do {
            if FileManager.default.fileExists(atPath: Self.folder(id).path) {
                try FileManager.default.removeItem(at: Self.folder(id))
            }
            states[id] = .missing
        } catch {
            states[id] = .failed(error.localizedDescription)
        }
    }
}
