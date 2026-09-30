// SettingsView+Verwerking.swift
// ThoughtVault
//
// Verwerking page of the Settings NorthStar: header, Snelle setup, the
// Transcriptie card and the Notulen card. Every control writes the existing
// settings (processingMode, localTranscriber, whisperModel, notulenProvider,
// per-provider configuration); nothing here has a state of its own.

#if os(macOS)
import SwiftUI

extension SettingsView {

    func verwerkingPage(_ layout: SettingsLayout) -> some View {
        let specs = SystemSpecs.cached
        let advice = ProcessingAdvisor.cachedTranscription
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: layout.gap) {
                VStack(alignment: .leading, spacing: 18) {
                    verwerkingHeader
                    quickSetupCard(advice)
                    transcriptionCard(advice)
                    notuleCard
                    if !layout.twoColumn {
                        verwerkingSide(specs, advice)
                    }
                }
                .frame(maxWidth: 960, alignment: .leading)
                if layout.twoColumn {
                    verwerkingSide(specs, advice)
                        .frame(width: layout.rightWidth)
                        .padding(.top, 8)
                }
            }
            .padding(.leading, layout.leading)
            .padding(.trailing, layout.trailing)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(Self.debugScrollBottom ? .bottom : .top)
    }

    /// Screenshot hook (debug builds only): `-TVDebugBottom YES`.
    private static var debugScrollBottom: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "TVDebugBottom") == "YES"
        #else
        return false
        #endif
    }

    private var verwerkingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verwerking")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(HomeColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Stel in hoe ThoughtVault gesprekken transcribeert en notulen genereert.")
                .font(.system(size: 15))
                .foregroundStyle(HomeColor.text2)
        }
        .padding(.bottom, 10)
    }

    // MARK: Snelle setup

    /// What "Toepassen" would set. Hosted providers are never picked for the
    /// user: the current choice stays when it can run, else Apple Intelligence
    /// or Ollama.
    private var recommendedProvider: NotulenProvider {
        ProcessingAdvisor.notuleProvider(current: activeLocalProvider)
    }

    private func setupApplied(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> Bool {
        isLocalProcessing
            && localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
            && whisperModel == advice.variant
            && activeLocalProvider == recommendedProvider
    }

    private func applySetup(_ advice: ProcessingAdvisor.TranscriptionAdvice) {
        processingMode = ProcessingMode.local.rawValue
        localTranscriber = LocalTranscriberEngine.whisperKit.rawValue
        whisperModel = advice.variant
        notulenProvider = recommendedProvider.rawValue
        if !WhisperModelStore.isInstalled(advice.variant) {
            WhisperModelStore.shared.download(advice.variant)
        }
    }

    private func providerReason() -> String {
        let current = activeLocalProvider
        if recommendedProvider == current {
            return "Notulen blijven bij \(current.studioName), jouw huidige keuze."
        }
        let why = current.apiKeyKeychainKey != nil ? "heeft nog geen sleutel" : "is niet beschikbaar"
        return "\(current.studioName) \(why), daarom \(recommendedProvider.studioName)."
    }

    private func quickSetupCard(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        let applied = setupApplied(advice)
        let provider = recommendedProvider
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                StudioIconTile(systemName: "sparkles", size: 46, tint: HomeColor.lavender)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snelle setup").font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                    Text("Aanbevolen instellingen voor jouw Mac")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(HomeColor.text)
                    Text("Op basis van je systeem en je huidige configuratie stellen we dit voor. Je kunt alles daarna nog aanpassen.")
                        .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 14) {
                    Button { applySetup(advice) } label: {
                        Text(applied ? "Toegepast" : "Toepassen")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 113, height: 37)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(applied ? HomeColor.violet.opacity(0.35) : HomeColor.violet))
                    }
                    .buttonStyle(.plain)
                    .disabled(applied)
                    Button {
                        withAnimation(TS.Animation.smooth) { showSetupDetails.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Bekijk details")
                            Image(systemName: showSetupDetails ? "chevron.up" : "arrow.right").font(.system(size: 12))
                        }
                        .font(.system(size: 13.5)).foregroundStyle(HomeColor.lavender)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 18) {
                setupChoice(icon: "mic", label: "Transcriptie", value: "Lokaal op deze Mac",
                            detail: ProcessingAdvisor.displayName(advice.variant))
                setupChoice(icon: "doc.text", label: "Notulen", value: provider.studioName,
                            detail: provider.studioSubtitle)
            }
            if showSetupDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text(advice.reason)
                    Text(providerReason())
                    if !WhisperModelStore.isInstalled(advice.variant) {
                        Text("Het model is nog niet gedownload. Toepassen start de download.")
                    }
                }
                .font(.system(size: 13)).foregroundStyle(HomeColor.text2)
            }
        }
        .studioCard(fill: HomeColor.violet.opacity(0.10), border: HomeColor.violet.opacity(0.45), padding: 20)
    }

    private func setupChoice(icon: String, label: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            StudioIconTile(systemName: icon, size: 46, tint: HomeColor.ready)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                Text(value).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(HomeColor.text)
                Text(detail).font(.system(size: 13.5)).foregroundStyle(HomeColor.text3)
            }
            Spacer(minLength: 6)
            StudioBadge(text: "Aanbevolen")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.card.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.cardBorder, lineWidth: 1))
    }

    // MARK: Card header

    private func cardHeader(icon: String, title: String, subtitle: String, helpShown: Binding<Bool>, help: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            StudioIconTile(systemName: icon, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(HomeColor.text)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(HomeColor.text2)
            }
            Spacer()
            Button { helpShown.wrappedValue.toggle() } label: {
                HStack(spacing: 6) {
                    Text("Hoe werkt dit?")
                    Image(systemName: "info.circle")
                }
                .font(.system(size: 13.5)).foregroundStyle(HomeColor.lavender)
            }
            .buttonStyle(.plain)
            .popover(isPresented: helpShown, arrowEdge: .bottom) {
                Text(help)
                    .font(.system(size: 13))
                    .frame(width: 300, alignment: .leading)
                    .padding(16)
            }
        }
    }

    // MARK: Transcriptie

    private func transcriptionCard(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(icon: "mic", title: "Transcriptie", subtitle: "Zet audio om naar tekst.",
                       helpShown: $showTranscriptionHelp,
                       help: "Lokaal zet WhisperKit de opname op je Mac om naar tekst en verlaat de audio je apparaat niet. Bij Cloud wordt de opname naar de ThoughtVault-server geüpload, die ook de notulen maakt.")

            HStack(alignment: .top, spacing: 16) {
                Text("Locatie").font(.system(size: 14)).foregroundStyle(HomeColor.text2).frame(width: 96, alignment: .leading).padding(.top, 20)
                StudioChoiceTile(selected: isLocalProcessing, icon: "laptopcomputer", title: "Lokaal (aanbevolen)",
                                 subtitle: "Audio verlaat je apparaat niet.") {
                    processingMode = ProcessingMode.local.rawValue
                }
                StudioChoiceTile(selected: !isLocalProcessing, icon: "cloud", title: "Cloud",
                                 subtitle: "Via de ThoughtVault-server") {
                    processingMode = ProcessingMode.cloud.rawValue
                }
            }

            Divider().overlay(HomeColor.divider)

            if isLocalProcessing {
                localModelRows(advice)
            } else {
                Text("Audio wordt naar de server geüpload voor transcriptie en notulen.")
                    .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
            }

            if OnDeviceTranscriber.shared.isAvailable() {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcriptie op apparaat").font(.system(size: 14, weight: .medium)).foregroundStyle(HomeColor.text)
                        Text("Sneller, geen audiodata naar server").font(.system(size: 12.5)).foregroundStyle(HomeColor.text3)
                    }
                    Spacer(minLength: 8)
                    Toggle("Transcriptie op apparaat", isOn: $preferOnDeviceTranscription)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(HomeColor.violet)
                }
            }
        }
        .studioCard()
    }

    @ViewBuilder
    private func localModelRows(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        let whisper = localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
        let automatic = whisper && whisperModel == advice.variant && !showManualModel

        HStack(alignment: .top, spacing: 16) {
            Text("Engine").font(.system(size: 14)).foregroundStyle(HomeColor.text2).frame(width: 96, alignment: .leading)
            Picker("Engine", selection: $localTranscriber) {
                ForEach(LocalTranscriberEngine.allCases) { engine in
                    Text(engine == .whisperKit ? "WhisperKit" : "Apple Spraakherkenning").tag(engine.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
        }

        if whisper {
            HStack(alignment: .top, spacing: 16) {
                Text("Model").font(.system(size: 14)).foregroundStyle(HomeColor.text2).frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    modelOption(selected: automatic,
                                title: "Automatisch (aanbevolen)", badge: "Aanbevolen",
                                subtitle: "\(ProcessingAdvisor.displayName(advice.variant)), beste keuze voor jouw Mac") {
                        showManualModel = false
                        whisperModel = advice.variant
                    }
                    modelOption(selected: !automatic, title: "Zelf kiezen", badge: nil,
                                subtitle: "Kies handmatig een model") {
                        showManualModel = true
                    }
                    if !automatic { manualModelPicker }
                }
            }
        } else {
            Text("Apple Spraakherkenning werkt direct, zonder download.")
                .font(.system(size: 13)).foregroundStyle(HomeColor.text3)
        }

        HStack(alignment: .top, spacing: 16) {
            Text("Eigen termen").font(.system(size: 14)).foregroundStyle(HomeColor.text2).frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Michel, Django, …", text: $personalVocabulary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Komma-gescheiden. Deze termen en de personen uit de app sturen de herkenning van namen.")
                    .font(.system(size: 12.5)).foregroundStyle(HomeColor.text3)
            }
        }
    }

    private func modelOption(selected: Bool, title: String, badge: String?, subtitle: String,
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
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var manualModelPicker: some View {
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

    // MARK: Notulen

    private var notuleCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(icon: "doc.text", title: "Notulen", subtitle: "Maak gestructureerde notulen van het transcript.",
                       helpShown: $showNotuleHelp,
                       help: "Het transcript gaat naar de aanbieder die je kiest en die schrijft de notulen. Ollama, LM Studio en Apple Intelligence draaien lokaal. ChatGPT en Claude gebruiken je eigen API-sleutel en API-account.")

            if isLocalProcessing {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(NotulenProvider.studioChoices) { provider in
                        StudioChoiceTile(selected: activeLocalProvider == provider, icon: provider.studioIcon,
                                         title: provider.studioName, subtitle: provider.studioSubtitle, vertical: true) {
                            notulenProvider = provider.rawValue
                        }
                    }
                }
                providerPanel
                Text(localNotuleDescription).font(.system(size: 12.5)).foregroundStyle(HomeColor.text3)
            } else {
                Text("Notulen worden via de server gegenereerd (N8N + Claude).")
                    .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
            }

            Divider().overlay(HomeColor.divider)
            NavigationLink { ProfilesView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.text.rectangle").foregroundStyle(HomeColor.lavender)
                    Text("Eigen profielen beheren").font(.system(size: 14)).foregroundStyle(HomeColor.text)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(HomeColor.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .studioCard()
    }

    /// Configuration of the selected provider, reusing the existing forms.
    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch activeLocalProvider {
            case .ollama:                      ollamaConfig
            case .lmStudio:                    lmStudioConfig
            case .appleIntelligence:           appleIntelligenceNote
            case .openAI, .anthropic:          HostedProviderConfig(provider: activeLocalProvider).id(activeLocalProvider)
            case .cloud:                       EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.field.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.controlBorder, lineWidth: 1))
    }
}
#endif
