// SettingsView+VerwerkingSide.swift
// ThoughtVault
//
// Right column of the Verwerking NorthStar: this Mac's real specs, the
// recommended transcription model with download, and what leaves the device.

#if os(macOS)
import SwiftUI

extension SettingsView {

    func verwerkingSide(_ specs: SystemSpecs, _ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        VStack(spacing: 18) {
            macCard(specs)
            modelCard(advice)
            privacyCard
        }
    }

    // MARK: Jouw Mac

    private func macCard(_ specs: SystemSpecs) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                StudioIconTile(systemName: "laptopcomputer", size: 40, tint: HomeColor.text)
                Text("Jouw Mac").font(.system(size: 17, weight: .semibold)).foregroundStyle(HomeColor.text)
            }
            VStack(alignment: .leading, spacing: 11) {
                specRow("Chip", specs.chip)
                specRow("Model-ID", specs.modelIdentifier)
                specRow("Geheugen", "\(specs.memoryGB) GB")
                if let storage = storageText(specs) { specRow("Opslag vrij", storage) }
                specRow("macOS", specs.osVersion)
            }
        }
        .studioCard(fill: HomeColor.side, border: HomeColor.sideBorder)
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 13)).foregroundStyle(HomeColor.text3).frame(width: 96, alignment: .leading)
            Text(value).font(.system(size: 14)).foregroundStyle(HomeColor.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func storageText(_ specs: SystemSpecs) -> String? {
        guard let free = specs.availableStorage, let total = specs.totalStorage else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .decimal
        formatter.zeroPadsFractionDigits = false
        return "\(formatter.string(fromByteCount: free)) van \(formatter.string(fromByteCount: total))"
    }

    // MARK: Aanbevolen model

    private func modelCard(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        let store = WhisperModelStore.shared
        _ = store.revision   // re-read disk state after a download or removal
        let variant = advice.variant
        let installed = WhisperModelStore.isInstalled(variant)
        let inUse = whisperModel == variant && localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
        let downloading = store.downloading == variant

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                StudioIconTile(systemName: "star", size: 40, tint: HomeColor.ready)
                Text("Aanbevolen model").font(.system(size: 17, weight: .semibold)).foregroundStyle(HomeColor.text)
            }
            HStack(spacing: 10) {
                Text(ProcessingAdvisor.displayName(variant))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(HomeColor.text)
                StudioBadge(text: "Aanbevolen")
            }
            Text(advice.reason)
                .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                checkRow("Draait volledig lokaal, audio blijft op je Mac")
                checkRow("Ondersteunt Nederlands")
            }
            if let size = modelSizeText(variant) {
                HStack(spacing: 10) {
                    Image(systemName: "internaldrive").foregroundStyle(HomeColor.text3).frame(width: 20)
                    Text(size).font(.system(size: 13.5)).foregroundStyle(HomeColor.text)
                }
            }

            if downloading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: store.progress).tint(HomeColor.violet)
                    HStack {
                        Text("Downloaden, \(Int(store.progress * 100))%").font(.system(size: 12.5)).foregroundStyle(HomeColor.text2)
                        Spacer()
                        Button("Annuleren") { store.cancel() }.buttonStyle(.plain)
                            .font(.system(size: 12.5)).foregroundStyle(HomeColor.lavender)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        if installed { whisperModel = variant; localTranscriber = LocalTranscriberEngine.whisperKit.rawValue; showManualModel = false }
                        else { store.download(variant) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: installed ? (inUse ? "checkmark.circle.fill" : "checkmark") : "arrow.down.to.line")
                            Text(installed ? (inUse ? "In gebruik" : "Gebruik dit model") : "Downloaden")
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 37)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(HomeColor.violet.opacity(inUse ? 0.35 : 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(inUse || store.downloading != nil)
                    if installed {
                        Menu {
                            Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([WhisperModelStore.folder(for: variant)]) }
                            Button("Verwijderen", role: .destructive) { store.remove(variant) }
                                .disabled(inUse)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 46, height: 37)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(HomeColor.control))
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .accessibilityLabel("Meer opties voor het model")
                    }
                }
            }
            if let failure = store.failure, failure.variant == variant {
                Label("Downloaden mislukt: \(failure.message)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(HomeColor.warning)
            }

            Button {
                localTranscriber = LocalTranscriberEngine.whisperKit.rawValue
                showManualModel = true
                Task { await loadWhisperModels() }
            } label: {
                HStack(spacing: 6) { Text("Andere modellen bekijken"); Image(systemName: "arrow.right") }
                    .font(.system(size: 13.5)).foregroundStyle(HomeColor.lavender)
            }
            .buttonStyle(.plain)
        }
        .studioCard(fill: HomeColor.side, border: HomeColor.sideBorder)
    }

    private func checkRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(HomeColor.ready).frame(width: 20).padding(.top, 2)
            Text(text).font(.system(size: 13.5)).foregroundStyle(HomeColor.text)
        }
    }

    private func modelSizeText(_ variant: String) -> String? {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if let bytes = WhisperModelStore.installedSize(variant) { return formatter.string(fromByteCount: bytes) }
        if let range = variant.range(of: #"(\d+)MB$"#, options: .regularExpression) {
            return variant[range].replacingOccurrences(of: "MB", with: " MB")
        }
        return nil
    }

    // MARK: Privacy & gegevens

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                StudioIconTile(systemName: "shield", size: 40, tint: HomeColor.warning)
                Text("Privacy & gegevens").font(.system(size: 17, weight: .semibold)).foregroundStyle(HomeColor.text)
            }
            if isLocalProcessing {
                privacyRow(icon: "mic", tint: HomeColor.ready, title: "Transcriptie (lokaal)",
                           text: "Audio en transcript blijven op deze Mac.")
                privacyRow(icon: notuleLeavesDevice ? "cloud" : "doc.text", tint: notuleLeavesDevice ? HomeColor.lavender : HomeColor.ready,
                           title: "Notulen (\(activeLocalProvider.studioName))", text: notulePrivacyText)
            } else {
                privacyRow(icon: "cloud", tint: HomeColor.lavender, title: "Transcriptie en notulen (server)",
                           text: "De audio wordt naar de ThoughtVault-server geüpload.")
            }
        }
        .studioCard(fill: HomeColor.side, border: HomeColor.sideBorder)
    }

    private func privacyRow(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StudioIconTile(systemName: icon, size: 40, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(HomeColor.text)
                Text(text).font(.system(size: 12.5)).foregroundStyle(HomeColor.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Ollama on an https endpoint is Ollama Cloud; hosted providers always leave the Mac.
    private var notuleLeavesDevice: Bool {
        switch activeLocalProvider {
        case .openAI, .anthropic: return true
        case .ollama:             return ollamaURL.lowercased().hasPrefix("https://")
        default:                  return false
        }
    }

    private var notulePrivacyText: String {
        switch activeLocalProvider {
        case .openAI:    return "Het transcript wordt naar OpenAI gestuurd om de notulen te maken."
        case .anthropic: return "Het transcript wordt naar Anthropic gestuurd om de notulen te maken."
        case .ollama:    return notuleLeavesDevice ? "Het transcript wordt naar Ollama Cloud gestuurd om de notulen te maken."
                                                   : "Het transcript blijft op je eigen Ollama-server."
        case .lmStudio:  return "Het transcript blijft op je eigen LM Studio-server."
        default:         return "Het transcript blijft op dit apparaat."
        }
    }
}
#endif
