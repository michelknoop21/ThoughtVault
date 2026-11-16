// DiagnosticLog.swift
// ThoughtVault
//
// Log lines that let the developer answer "what happened" without asking the user:
// a settings snapshot, app lifecycle transitions and the audio route. Values come
// from fixed sets only; never a URL, host name, key, file name or device name.

import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import CoreAudio
#endif

private let log = AppLog(category: "Diagnostics")

@MainActor
enum DiagnosticLog {

    // MARK: Settings snapshot

    /// One line with every setting that decides recording and processing behaviour.
    static func logSettings(trigger: String, recordingMode: RecordingMode, liveTranscription: Bool,
                            defaults: UserDefaults = .standard) {
        log.info("Settings: trigger=\(trigger) " + settingsLine(recordingMode: recordingMode,
                                                                 liveTranscription: liveTranscription, defaults: defaults))
    }

    static func settingsLine(recordingMode: RecordingMode, liveTranscription: Bool, defaults: UserDefaults) -> String {
        let mode = ProcessingMode.isLocalMode ? "local" : "cloud"
        let engine = LocalTranscriberEngine(rawValue: defaults.string(forKey: "localTranscriber") ?? "") ?? .whisperKit
        let model: String
        let installed: Bool
        switch engine {
        case .whisperKit:
            model = defaults.string(forKey: "whisperModel") ?? LocalTranscriberFactory.defaultWhisperModel
            installed = WhisperModelStore.isInstalled(model)
        case .parakeet:
            model = ParakeetCatalog.selectedID(defaults: defaults)
            installed = ParakeetModelStore.isInstalled(model)
        case .appleSpeech:
            model = "on-device"
            installed = true
        }
        let provider = NotulenProvider.configured(defaults: defaults)
        let fallback = NotuleGenerator.fallbackProvider(for: provider)
        let process = ProcessInfo.processInfo
        return [
            "mode=\(mode)",
            "engine=\(engine.rawValue)", "model=\(model)", "installed=\(installed)",
            "notule=\(provider.rawValue)", notuleTarget(provider, defaults: defaults), "key=\(provider.hasAPIKey)",
            "fallback=\(fallback?.rawValue ?? "none")", "fallback_key=\(fallback?.hasAPIKey ?? false)",
            "vault=\(VaultFolderStore.isConfigured)",
            "record_mode=\(recordingMode.rawValue)", "live=\(liveTranscription)",
            "app=\(DeviceInfo.appVersion.replacingOccurrences(of: " ", with: ""))",
            "os=\(DeviceInfo.os.replacingOccurrences(of: " ", with: "-"))", "device=\(DeviceInfo.device)",
            "low_power=\(process.isLowPowerModeEnabled)", "thermal=\(thermal(process.thermalState))",
            "disk_free_gb=\(freeDiskGB.map(String.init) ?? "?")",
            "ram_gb=\(Int((Double(process.physicalMemory) / 1_073_741_824).rounded()))",
        ].joined(separator: " ")
    }

    /// Model name and, for providers with a user-set URL, only the kind of host.
    static func notuleTarget(_ provider: NotulenProvider, defaults: UserDefaults = .standard) -> String {
        switch provider {
        case .cloud: return "notule_model=server"
        case .appleIntelligence: return "notule_model=on-device"
        case .ollama:
            return "notule_model=\(defaults.string(forKey: "ollamaModel") ?? "llama3.2") notule_host=\(hostClass(defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"))"
        case .lmStudio:
            return "notule_model=\(defaults.string(forKey: "lmStudioModel") ?? "local-model") notule_host=\(hostClass(defaults.string(forKey: "lmStudioURL") ?? "http://localhost:1234"))"
        case .openAI: return "notule_model=\(defaults.string(forKey: "openAIModel") ?? OpenAICompatibleLLMService.openAIDefaultModel)"
        case .anthropic: return "notule_model=\(defaults.string(forKey: "anthropicModel") ?? AnthropicLLMService.defaultModel)"
        case .ollamaCloud: return "notule_model=\(defaults.string(forKey: "ollamaCloudModel") ?? "")"
        case .openRouter: return "notule_model=\(defaults.string(forKey: "openRouterModel") ?? OpenAICompatibleLLMService.openRouterDefaultModel)"
        case .openAICompatible:
            let config = CloudAIConfiguration.selected(defaults: defaults)
            return "notule_model=\(config?.model ?? "") notule_host=\(config.map { hostClass($0.baseURL) } ?? "none")"
        }
    }

    /// "localhost", "private" (LAN, .local, bare name) or "public", with the scheme; never the host itself.
    nonisolated static func hostClass(_ string: String) -> String {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")), !host.isEmpty
        else { return "invalid" }
        let kind: String
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host.hasPrefix("127.") {
            kind = "localhost"
        } else if !host.contains(".") || host.hasSuffix(".local")
                    || host.range(of: #"^(10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|f[cd][0-9a-f]{2}:|fe80:)"#,
                                  options: .regularExpression) != nil {
            kind = "private"
        } else {
            kind = "public"
        }
        return "\(kind)-\(scheme == "https" ? "https" : "http")"
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static var freeDiskGB: Int? {
        let values = try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { Int((Double($0) / 1_000_000_000).rounded()) }
    }

    // MARK: Lifecycle

    private static var backgroundSince: Date?

    /// Logs a scene phase transition; on return to the foreground, how long the app was away and where
    /// each in-flight local task stood, so a suspension between two log lines is visible.
    static func scenePhaseChanged(to phase: String, inFlight: [TranscriptTask]) {
        if phase == "background" { backgroundSince = Date() }
        var line = "Scene phase: \(phase)"
        if phase == "active", let since = backgroundSince {
            backgroundSince = nil
            line += " away_s=\(Int(Date().timeIntervalSince(since).rounded()))"
            for task in inFlight {
                line += " task=\(LogRedact.mask(task.id)):\(task.status.rawValue):\(Int((task.progress * 100).rounded()))%"
            }
        }
        #if os(iOS)
        line += " bg_remaining=\(backgroundTimeRemaining)"
        #endif
        log.info(line)
    }

    #if os(iOS)
    /// Seconds iOS still allows in the background; "foreground" while the app is active.
    static var backgroundTimeRemaining: String {
        let remaining = UIApplication.shared.backgroundTimeRemaining
        return remaining > 1_000_000 ? "foreground" : String(Int(remaining.rounded()))
    }
    #endif
}

// MARK: - Audio route

enum AudioRouteLog {
    #if os(iOS)
    /// Port types of the current route, e.g. "in=builtInMic out=bluetoothA2DP". Never a port name.
    static func route(_ session: AVAudioSession = .sharedInstance()) -> String {
        let route = session.currentRoute
        let ports = { (list: [AVAudioSessionPortDescription]) in
            list.isEmpty ? "none" : list.map { portType($0.portType) }.joined(separator: ",")
        }
        return "in=\(ports(route.inputs)) out=\(ports(route.outputs))"
    }

    static func session(_ session: AVAudioSession = .sharedInstance()) -> String {
        "\(route(session)) other_audio=\(session.isOtherAudioPlaying) silence_hint=\(session.secondaryAudioShouldBeSilencedHint)"
            + " rate=\(Int(session.sampleRate)) input_available=\(session.isInputAvailable)"
            + " options=\(session.categoryOptions.rawValue)"
    }

    private static func portType(_ type: AVAudioSession.Port) -> String {
        switch type {
        case .builtInMic: return "builtInMic"
        case .builtInReceiver: return "builtInReceiver"
        case .builtInSpeaker: return "builtInSpeaker"
        case .headsetMic: return "headsetMic"
        case .headphones: return "headphones"
        case .bluetoothA2DP: return "bluetoothA2DP"
        case .bluetoothHFP: return "bluetoothHFP"
        case .bluetoothLE: return "bluetoothLE"
        case .carAudio: return "carAudio"
        case .airPlay: return "airPlay"
        case .HDMI: return "HDMI"
        case .usbAudio: return "usbAudio"
        case .lineIn: return "lineIn"
        case .lineOut: return "lineOut"
        default: return "other"
        }
    }

    static func routeChangeReason(_ raw: UInt) -> String {
        switch AVAudioSession.RouteChangeReason(rawValue: raw) {
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        default: return "unknown(\(raw))"
        }
    }

    static func interruptionReason(_ userInfo: [AnyHashable: Any]) -> String {
        guard let raw = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt else { return "none" }
        switch AVAudioSession.InterruptionReason(rawValue: raw) {
        case .default: return "default"
        case .builtInMicMuted: return "builtInMicMuted"
        case .routeDisconnected: return "routeDisconnected"
        default: return "other(\(raw))"
        }
    }
    #endif

    #if os(macOS)
    /// Transport type of the default input device ("builtIn", "usb", "bluetooth", ...); never its name.
    static func inputTransport() -> String {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return "none" }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return "unknown" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "builtIn"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "bluetoothLE"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "continuity"
        default: return "other(\(transport))"
        }
    }
    #endif
}

// MARK: - Error log codes

extension AudioRecorderError: LogCoded {
    var logCode: String {
        switch self {
        case .permissionDenied: return "permissionDenied"
        case .failedToStart: return "failedToStart"
        case .recordingInterrupted: return "recordingInterrupted"
        case .emptyRecording: return "emptyRecording"
        }
    }
}

extension LocalTranscriberError: LogCoded {
    var logCode: String {
        switch self {
        case .engineUnavailable: return "engineUnavailable"
        case .transcriptionFailed: return "transcriptionFailed"
        case .emptyResult: return "emptyResult"
        case .modelNotInstalled: return "modelNotInstalled"
        case .timedOut(let stage, _): return "timedOut stage=\(stage) reason=timeout"
        }
    }
}

extension LLMError: LogCoded {
    var logCode: String {
        switch self {
        case .providerUnavailable: return "providerUnavailable"
        case .serverError(let status): return "serverError http=\(status)"
        case .generationFailed: return "generationFailed"
        case .emptyResponse: return "emptyResponse"
        case .timedOut: return "timedOut"
        case .truncated: return "truncated"
        }
    }
}

extension APIError: LogCoded {
    var logCode: String {
        switch self {
        case .invalidResponse: return "invalidResponse"
        case .httpError(let status, _, _): return "httpError http=\(status)"
        case .decodingError: return "decodingError"
        case .fileTooLarge: return "fileTooLarge"
        case .sessionExpired: return "sessionExpired"
        case .networkError: return "networkError"
        case .localModeActive: return "localModeActive"
        }
    }

    var logUnderlying: Error? {
        switch self {
        case .decodingError(let error), .networkError(let error): return error
        default: return nil
        }
    }
}

extension TranscriberError: LogCoded {
    var logCode: String {
        switch self {
        case .recognizerUnavailable: return "recognizerUnavailable"
        case .permissionDenied: return "permissionDenied"
        case .recognitionFailed: return "recognitionFailed"
        case .emptyResult: return "emptyResult"
        }
    }
}

extension NotuleReviewError: LogCoded {
    var logCode: String { "rejected" }
}

extension NotuleAuditError: LogCoded {
    var logCode: String { finding == nil ? "failed" : "finding" }
}

extension AudioExtractorError: LogCoded {
    var logCode: String {
        switch self {
        case .noAudioTrack: return "noAudioTrack"
        case .readFailed: return "readFailed"
        }
    }
}

extension LocalStoreError: LogCoded {
    var logCode: String { "recordNotFound" }
}

extension KeychainError: LogCoded {
    var logCode: String {
        switch self {
        case .writeFailed(let status): return "writeFailed status=\(status)"
        }
    }
}

extension SupportRelayError: LogCoded {
    var logCode: String {
        switch self {
        case .http(let status): return "http=\(status)"
        case .automaticReportingDisabled: return "automaticReportingDisabled"
        }
    }
}

extension ObsidianService.ObsidianError: LogCoded {
    var logCode: String {
        switch self {
        case .missingConfig: return "missingConfig"
        case .badStatus(let status, _): return "badStatus http=\(status)"
        case .externallyChanged: return "externallyChanged"
        case .vaultLinkBroken: return "vaultLinkBroken"
        }
    }
}

#if os(macOS)
extension SystemAudioCaptureError: LogCoded {
    var logCode: String {
        switch self {
        case .noOutputDevice: return "noOutputDevice"
        case .coreAudio(_, let status): return "coreAudio status=\(status)"
        }
    }
}
#endif
