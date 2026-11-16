// SettingsView+VerwerkingLogic.swift
// ThoughtVault
//
// The parts of the Verwerking page that macOS and iOS share: what Snelle setup
// recommends and applies, the Whisper model choice, the provider tiles and the
// panel of the selected provider. The page layouts are in SettingsView+Verwerking
// (macOS) and SettingsView+VerwerkingIOS.

import SwiftUI

extension SettingsView {

    // MARK: Snelle setup

    /// OpenRouter is the install default (NotulenProvider.installDefault) but
    /// starts without a key.
    var openRouterNeedsKey: Bool {
        _ = hostedKeyRevision
        return activeLocalProvider == .openRouter && !NotulenProvider.openRouter.hasAPIKey
    }

    /// What "Toepassen" would set. Hosted providers are never picked for the
    /// user: the current choice stays when it can run, else Apple Intelligence
    /// or Ollama. OpenRouter without a key stays too: it needs a key, not a
    /// different provider.
    var recommendedProvider: NotulenProvider {
        openRouterNeedsKey ? .openRouter : ProcessingAdvisor.notuleProvider(current: activeLocalProvider)
    }

    func setupApplied(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> Bool {
        isLocalProcessing
            && localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
            && whisperModel == advice.variant
            && activeLocalProvider == recommendedProvider
    }

    func applySetup(_ advice: ProcessingAdvisor.TranscriptionAdvice) {
        processingMode = ProcessingMode.local.rawValue
        localTranscriber = LocalTranscriberEngine.whisperKit.rawValue
        whisperModel = advice.variant
        notulenProvider = recommendedProvider.rawValue
        if !WhisperModelStore.isInstalled(advice.variant) {
            WhisperModelStore.shared.download(advice.variant)
        }
    }

    func providerReason() -> String {
        if openRouterNeedsKey {
            return String(localized: "OpenRouter heeft nog geen sleutel. Vul die in bij Notulen om notulen te maken.")
        }
        let current = activeLocalProvider
        if recommendedProvider == current {
            return "Notulen blijven bij \(current.studioName), jouw huidige keuze."
        }
        let why = current.apiKeyKeychainKey != nil ? "heeft nog geen sleutel" : "is niet beschikbaar"
        return "\(current.studioName) \(why), daarom \(recommendedProvider.studioName)."
    }

    /// Summary of the notule provider in Snelle setup.
    var setupNotuleValue: String {
        openRouterNeedsKey ? String(localized: "OpenRouter: sleutel nodig") : recommendedProvider.studioName
    }

    var setupNotuleDetail: String {
        openRouterNeedsKey ? String(localized: "Vul je sleutel in om notulen te maken.") : recommendedProvider.studioSubtitle
    }

    /// Scroll target of "Sleutel invullen" in Snelle setup.
    static let providerPanelID = "providerPanel"

    func scrollToProviderPanel(_ proxy: ScrollViewProxy) {
        withAnimation(TS.Animation.smooth) { proxy.scrollTo(Self.providerPanelID, anchor: .top) }
    }

    // MARK: Whisper model

    func modelOption(selected: Bool, title: String, badge: String?, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                StudioRadio(selected: selected).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(HomeColor.text)
                        if let badge { StudioBadge(text: badge) }
                    }
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(HomeColor.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Self.minTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioScalePressStyle(scale: 0.97))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var manualModelPicker: some View {
        HStack(spacing: TS.Spacing.sm) {
            if whisperModels.isEmpty {
                TextField("model", text: $whisperModel)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.bodyMonospaced)
                    .autocorrectionDisabled()
            } else {
                Picker("Model", selection: $whisperModel) {
                    if !whisperModels.contains(whisperModel) && !whisperModel.isEmpty {
                        Text(whisperModel).tag(whisperModel)
                    }
                    ForEach(whisperModels, id: \.self) { name in
                        Text(WhisperModelStore.isInstalled(name) ? "\(name) (geïnstalleerd)" : name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await loadWhisperModels() }
            } label: {
                if whisperModelsLoading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.triangle.2.circlepath") }
            }
            .buttonStyle(.bordered)
            .disabled(whisperModelsLoading)
            .help("Beschikbare modellen laden")
            .accessibilityLabel("Beschikbare modellen laden")
        }
        .frame(maxWidth: 520)
    }

    /// Smallest pressable height: 44 pt on iOS, the denser macOS rows elsewhere.
    static var minTarget: CGFloat {
        #if os(iOS)
        44
        #else
        0
        #endif
    }

    // MARK: Notulen

    /// Provider tiles; the selection slides between them unless Reduce Motion is on.
    func providerTiles(minimum: CGFloat, reduceMotion: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(NotulenProvider.studioChoices) { provider in
                let ollamaCloud = provider == .ollama && activeLocalProvider == .ollamaCloud
                StudioChoiceTile(selected: activeLocalProvider == provider || ollamaCloud, icon: provider.studioIcon,
                                 title: provider.studioName, subtitle: provider.studioSubtitle, vertical: true,
                                 selection: reduceMotion ? nil : providerSelection) {
                    guard !ollamaCloud else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25)) {
                        notulenProvider = provider.rawValue
                    }
                }
            }
        }
    }

    var ollamaLocation: Binding<String> {
        Binding(
            get: {
                let url = URL(string: ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines))
                let legacyCloud = url?.scheme?.lowercased() == "https" && url?.host?.lowercased() == "ollama.com"
                return (activeLocalProvider == .ollamaCloud || legacyCloud) ? NotulenProvider.ollamaCloud.rawValue : NotulenProvider.ollama.rawValue
            },
            set: { value in
                if value == NotulenProvider.ollama.rawValue {
                    ollamaURL = "http://localhost:11434"
                    ollamaModel = ""
                }
                notulenProvider = value
            }
        )
    }

    /// Configuration of the selected provider, reusing the existing forms.
    var providerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if activeLocalProvider == .ollama || activeLocalProvider == .ollamaCloud {
                Picker("Ollama", selection: ollamaLocation) {
                    Text("Lokaal").tag(NotulenProvider.ollama.rawValue)
                    Text("Cloud").tag(NotulenProvider.ollamaCloud.rawValue)
                }
                .pickerStyle(.segmented)
            }
            switch activeLocalProvider {
            case .ollama:
                VStack(alignment: .leading, spacing: 10) { ollamaConfig }
                    .task(id: ollamaURL) {
                        ollamaModels = []
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        let url = URL(string: ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines))
                        await loadOllamaModels(includeCredential: url?.scheme?.lowercased() == "https" && url?.host?.lowercased() == "ollama.com")
                    }
            case .lmStudio:                    lmStudioConfig
            case .appleIntelligence:           appleIntelligenceNote
            case .openAI, .anthropic, .openRouter:
                HostedProviderConfig(provider: activeLocalProvider, onKeyChange: { hostedKeyRevision += 1 }).id(activeLocalProvider)
            case .ollamaCloud, .openAICompatible: CloudProviderConfig(provider: activeLocalProvider).id(activeLocalProvider)
            case .cloud:                       EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.field.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.controlBorder, lineWidth: 1))
        .id(Self.providerPanelID)
    }
}
