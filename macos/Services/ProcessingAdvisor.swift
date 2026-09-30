// ProcessingAdvisor.swift
// ThoughtVault
//
// Recommended processing setup from this Mac's real specs. Two plain rules:
//   Transcription: local WhisperKit with the model WhisperKit recommends for
//   this chip, compact (626 MB) when memory is under 16 GB.
//   Notulen: keep the user's choice when it can run; otherwise Apple
//   Intelligence when available, else Ollama. Hosted providers are never
//   chosen for the user.

import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

struct SystemSpecs {
    let modelIdentifier: String
    let chip: String
    let memoryBytes: UInt64
    let availableStorage: Int64?
    let totalStorage: Int64?
    let osVersion: String

    /// Read once per launch; hardware does not change while the app runs.
    static let cached = current()

    static func current() -> SystemSpecs {
        let home = URL.homeDirectory
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let patch = os.patchVersion > 0 ? ".\(os.patchVersion)" : ""
        return SystemSpecs(
            modelIdentifier: sysctlString("hw.model") ?? "Onbekend",
            chip: sysctlString("machdep.cpu.brand_string") ?? "Onbekend",
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            availableStorage: values?.volumeAvailableCapacityForImportantUsage,
            totalStorage: values?.volumeTotalCapacity.map(Int64.init),
            osVersion: "\(os.majorVersion).\(os.minorVersion)\(patch)"
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    var memoryGB: Int { Int((Double(memoryBytes) / 1_073_741_824).rounded()) }

    /// "Apple M4 Pro" -> 4; nil for Intel or unknown chips.
    var appleChipGeneration: Int? {
        guard chip.hasPrefix("Apple M") else { return nil }
        return Int(chip.dropFirst("Apple M".count).prefix { $0.isNumber })
    }
}

enum ProcessingAdvisor {

    static let compactModel = "openai_whisper-large-v3-v20240930_626MB"

    struct TranscriptionAdvice {
        let variant: String
        let reason: String
    }

    /// WhisperKit's own per-chip default, unless this Mac has under 16 GB
    /// memory: then the compact 626 MB version of the same model.
    static let cachedTranscription = transcription(for: .cached)

    static func transcription(for specs: SystemSpecs) -> TranscriptionAdvice {
        var variant = compactModel
        #if canImport(WhisperKit)
        let recommended = WhisperKit.recommendedModels().default
        if !recommended.isEmpty { variant = recommended }
        #endif
        if specs.memoryGB < 16 && variant != compactModel {
            return TranscriptionAdvice(variant: compactModel,
                                       reason: "\(specs.memoryGB) GB geheugen is krap voor het volledige model, dus de compacte versie.")
        }
        return TranscriptionAdvice(variant: variant,
                                   reason: "Dit model wordt door WhisperKit aanbevolen voor \(specs.chip) met \(specs.memoryGB) GB geheugen.")
    }

    /// Whether a provider can run without further setup. Local servers are
    /// assumed reachable (the user configured them); hosted ones need a key.
    static func isUsable(_ provider: NotulenProvider) -> Bool {
        switch provider {
        case .cloud: return false
        case .ollama, .lmStudio: return true
        case .openAI, .anthropic: return provider.hasAPIKey
        case .appleIntelligence: return appleIntelligenceAvailable
        }
    }

    static func notuleProvider(current: NotulenProvider) -> NotulenProvider {
        if isUsable(current) { return current }
        return appleIntelligenceAvailable ? .appleIntelligence : .ollama
    }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) { return AppleFoundationModelService.unavailabilityReason == nil }
        #endif
        return false
    }

    /// Human name of a WhisperKit variant, e.g. "Whisper Large v3 Turbo".
    static func displayName(_ variant: String) -> String {
        if variant.hasPrefix("openai_whisper-large-v3-v20240930") { return "Whisper Large v3 Turbo" }
        return variant.replacingOccurrences(of: "openai_whisper-", with: "Whisper ")
            .replacingOccurrences(of: "distil-whisper_", with: "")
    }
}
