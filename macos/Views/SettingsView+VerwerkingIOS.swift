// SettingsView+VerwerkingIOS.swift
// ThoughtVault
//
// iOS Verwerking page: the cards of the macOS page (Snelle setup, Transcriptie,
// Notulen) in one column, with the same building blocks. Adds the Whisper
// model download, which on macOS lives in the side column.

#if os(iOS)
import SwiftUI

extension SettingsView {

    var verwerkingIOSPage: some View {
        let advice = ProcessingAdvisor.cachedTranscription
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    IOSScreenTitle(title: String(localized: "Verwerking"),
                                   subtitle: String(localized: "Stel in hoe ThoughtVault gesprekken transcribeert en notulen genereert."))
                    iosQuickSetupCard(advice, proxy)
                    iosTranscriptionCard(advice)
                    iosNotuleCard.id("notuleCard")
                }
                .padding(.horizontal, IOSMetric.gutter)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Screenshot hooks (debug builds only, see IOSDebug).
                switch IOSDebug.open {
                case "verwerking-transcriptie": proxy.scrollTo("transcriptionModel", anchor: .top)
                case "verwerking-notulen": proxy.scrollTo("notuleCard", anchor: .top)
                default: break
                }
            }
        }
        .iosScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Snelle setup

    private func iosQuickSetupCard(_ advice: ProcessingAdvisor.TranscriptionAdvice, _ proxy: ScrollViewProxy) -> some View {
        let applied = setupApplied(advice)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                StudioIconTile(systemName: "sparkles", size: 40, tint: HomeColor.lavender)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snelle setup").font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                    Text("Aanbevolen instellingen voor dit toestel")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(HomeColor.text)
                    Text("Op basis van je systeem en je huidige configuratie stellen we dit voor. Je kunt alles daarna nog aanpassen.")
                        .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2).padding(.top, 2)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            iosSetupChoice(icon: "mic", label: String(localized: "Transcriptie"), value: String(localized: "Lokaal op dit toestel"),
                           detail: ProcessingAdvisor.displayName(advice.variant))
            iosSetupChoice(icon: "doc.text", label: String(localized: "Notulen"), value: setupNotuleValue, detail: setupNotuleDetail,
                           keyAction: openRouterNeedsKey && isLocalProcessing ? { scrollToProviderPanel(proxy) } : nil)
            if showSetupDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text(advice.reason)
                    Text(providerReason())
                    if !WhisperModelStore.isInstalled(advice.variant) {
                        Text("Het model is nog niet gedownload. Toepassen start de download.")
                    }
                }
                .font(.system(size: 13)).foregroundStyle(HomeColor.text2)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
            HStack(spacing: 12) {
                Button { applySetup(advice) } label: {
                    Text(applied ? "Toegepast" : "Toepassen")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(applied ? HomeColor.violet.opacity(0.35) : HomeColor.violet))
                        .contentTransition(.opacity)
                }
                .buttonStyle(StudioScalePressStyle(scale: 0.97))
                .disabled(applied)
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { showSetupDetails.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showSetupDetails ? "Verberg details" : "Bekijk details").lineLimit(1)
                        Image(systemName: showSetupDetails ? "chevron.up" : "chevron.down").font(.system(size: 12))
                    }
                    .font(.system(size: 14)).foregroundStyle(HomeColor.lavender)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StudioScalePressStyle(scale: 0.97))
            }
            .animation(.easeOut(duration: 0.2), value: applied)
        }
        .studioCard(fill: HomeColor.violet.opacity(0.10), border: HomeColor.violet.opacity(0.45), padding: 16)
    }

    private func iosSetupChoice(icon: String, label: String, value: String, detail: String,
                                keyAction: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StudioIconTile(systemName: icon, size: 40, tint: keyAction == nil ? HomeColor.ready : HomeColor.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13)).foregroundStyle(HomeColor.text2)
                Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(HomeColor.text)
                Text(detail).font(.system(size: 13)).foregroundStyle(HomeColor.text3)
                if let keyAction {
                    Button("Sleutel invullen", action: keyAction)
                        .buttonStyle(StudioQuietButtonStyle(height: 44))
                        .padding(.top, 6)
                } else {
                    StudioBadge(text: String(localized: "Aanbevolen")).padding(.top, 4)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.card.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.cardBorder, lineWidth: 1))
    }

    // MARK: Card header

    private func iosCardHeader(icon: String, title: String, subtitle: String, helpShown: Binding<Bool>, help: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            StudioIconTile(systemName: icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(HomeColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { helpShown.wrappedValue.toggle() } label: {
                Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(HomeColor.lavender)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(StudioScalePressStyle(scale: 0.97))
            .accessibilityLabel("Hoe werkt dit?")
            .popover(isPresented: helpShown, arrowEdge: .top) {
                Text(help)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(16)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func iosLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 13.5, weight: .medium)).foregroundStyle(HomeColor.text2)
    }

    // MARK: Transcriptie

    private func iosTranscriptionCard(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            iosCardHeader(icon: "mic", title: String(localized: "Transcriptie"), subtitle: String(localized: "Zet audio om naar tekst."),
                          helpShown: $showTranscriptionHelp,
                          help: String(localized: "Lokaal zet WhisperKit, Parakeet of Apple Spraakherkenning de opname op dit toestel om naar tekst en verlaat de audio je apparaat niet. Bij Cloud wordt de opname naar de ThoughtVault-server geüpload, die ook de notulen maakt."))

            iosLabel(String(localized: "Locatie"))
            VStack(spacing: 10) {
                StudioChoiceTile(selected: isLocalProcessing, icon: "iphone", title: String(localized: "Lokaal (aanbevolen)"),
                                 subtitle: String(localized: "Audio verlaat je apparaat niet.")) {
                    withAnimation(.easeOut(duration: 0.2)) { processingMode = ProcessingMode.local.rawValue }
                }
                StudioChoiceTile(selected: !isLocalProcessing, icon: "cloud", title: String(localized: "Cloud"),
                                 subtitle: String(localized: "Via de ThoughtVault-server")) {
                    withAnimation(.easeOut(duration: 0.2)) { processingMode = ProcessingMode.cloud.rawValue }
                }
            }

            Divider().overlay(HomeColor.divider)

            if isLocalProcessing {
                iosLocalModelRows(advice).transition(.opacity)
            } else {
                Text("Audio wordt naar de server geüpload voor transcriptie en notulen.")
                    .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if OnDeviceTranscriber.shared.isAvailable() {
                    Toggle(isOn: $preferOnDeviceTranscription) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transcriptie op apparaat").font(.system(size: 14, weight: .medium)).foregroundStyle(HomeColor.text)
                            Text("Sneller, geen audiodata naar server").font(.system(size: 12.5)).foregroundStyle(HomeColor.text3)
                        }
                    }
                    .tint(HomeColor.violet)
                }
            }
        }
        .studioCard(padding: 16)
    }

    @ViewBuilder
    private func iosLocalModelRows(_ advice: ProcessingAdvisor.TranscriptionAdvice) -> some View {
        let whisper = localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
        let automatic = whisper && whisperModel == advice.variant && !showManualModel

        VStack(alignment: .leading, spacing: 4) {
            iosLabel(String(localized: "Engine"))
                .padding(.top, 8)
                .id("transcriptionModel")
            ForEach(LocalTranscriberEngine.allCases) { engine in
                modelOption(selected: localTranscriber == engine.rawValue, title: engine.displayName, badge: nil,
                            subtitle: engine.iosSubtitle) {
                    withAnimation(.easeOut(duration: 0.2)) { localTranscriber = engine.rawValue }
                }
            }
        }

        Divider().overlay(HomeColor.divider)

        VStack(alignment: .leading, spacing: 4) {
            iosLabel(String(localized: "Model"))
            switch LocalTranscriberEngine(rawValue: localTranscriber) ?? .whisperKit {
            case .whisperKit:
                modelOption(selected: automatic, title: String(localized: "Automatisch (aanbevolen)"), badge: String(localized: "Aanbevolen"),
                            subtitle: String(localized: "\(ProcessingAdvisor.displayName(advice.variant)), beste keuze voor dit toestel")) {
                    showManualModel = false
                    whisperModel = advice.variant
                }
                modelOption(selected: !automatic, title: String(localized: "Zelf kiezen"), badge: nil,
                            subtitle: String(localized: "Kies handmatig een model")) {
                    withAnimation(.easeOut(duration: 0.2)) { showManualModel = true }
                }
                if !automatic { manualModelPicker.padding(.vertical, 6).transition(.opacity) }
                WhisperDownloadRow(variant: whisperModel)
                    .padding(.top, 8)
            case .parakeet:
                ParakeetModelRows()
            case .appleSpeech:
                Text("Apple Spraakherkenning werkt direct, zonder download.")
                    .font(.system(size: 13)).foregroundStyle(HomeColor.text3)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: localTranscriber)
    }

    // MARK: Notulen

    private var iosNotuleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            iosCardHeader(icon: "doc.text", title: String(localized: "Notulen"),
                          subtitle: String(localized: "Maak gestructureerde notulen van het transcript."),
                          helpShown: $showNotuleHelp,
                          help: String(localized: "Het transcript gaat naar de aanbieder die je kiest en die schrijft de notulen. Ollama, LM Studio en Apple Intelligence draaien lokaal. OpenRouter, ChatGPT, Claude, Ollama Cloud en een OpenAI-compatibele aanbieder gebruiken je eigen API-sleutel en account."))

            if isLocalProcessing {
                providerTiles(minimum: 118, reduceMotion: reduceMotion)
                providerPanel
                NotuleFallbackPicker()
                Text(localNotuleDescription).font(.system(size: 12.5)).foregroundStyle(HomeColor.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Notulen worden op de ThoughtVault-server gegenereerd.")
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(StudioScalePressStyle(scale: 0.97))
        }
        .studioCard(padding: 16)
    }
}

private extension LocalTranscriberEngine {
    var iosSubtitle: String {
        switch self {
        case .whisperKit:  String(localized: "Whisper-model, eenmalig downloaden")
        case .parakeet:    String(localized: "Parakeet-model, eenmalig downloaden")
        case .appleSpeech: String(localized: "Werkt direct, zonder download")
        }
    }
}

/// The selected Whisper model on this device: download with progress and
/// Stop, remove, or retry after a failure.
private struct WhisperDownloadRow: View {
    let variant: String
    @State private var confirmRemove = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = WhisperModelStore.shared

    private enum Phase: Equatable { case missing, downloading, installed, failed }

    private var phase: Phase {
        _ = store.revision   // re-read disk state after a download or removal
        if store.downloading == variant { return .downloading }
        if WhisperModelStore.isInstalled(variant) { return .installed }
        if store.failure?.variant == variant { return .failed }
        return .missing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "internaldrive").foregroundStyle(HomeColor.text3).frame(width: 20).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: ProcessingAdvisor.displayName(variant))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(HomeColor.text)
                    status.font(.system(size: 13)).foregroundStyle(HomeColor.text3)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            action
                .padding(.leading, 32)
                .transition(.opacity)
                .id(phase)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: phase)
        .confirmationDialog("Model verwijderen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) { store.remove(variant) }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Het model wordt van dit toestel verwijderd. Je kunt het later opnieuw downloaden.")
        }
    }

    private var status: Text {
        switch phase {
        case .installed:
            let size = WhisperModelStore.installedSize(variant).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
            return Text("Gedownload, \(size)")
        case .downloading: return Text("Wordt gedownload")
        case .missing, .failed: return Text("Nog niet gedownload. Nodig om op dit toestel te transcriberen.")
        }
    }

    @ViewBuilder private var action: some View {
        switch phase {
        case .missing:
            Button { store.download(variant) } label: { Label("Download", systemImage: "arrow.down.to.line") }
                .buttonStyle(StudioQuietButtonStyle(height: 44))
                .disabled(store.downloading != nil || variant.isEmpty)
        case .downloading:
            HStack(spacing: 10) {
                ProgressView(value: store.progress)
                    .tint(HomeColor.violet)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.progress)
                    .accessibilityLabel("Downloaden")
                Text("\(Int(store.progress * 100))%")
                    .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(HomeColor.text2)
                    .fixedSize()
                Button("Stop") { store.cancel() }
                    .buttonStyle(StudioQuietButtonStyle(height: 44))
            }
        case .installed:
            Button("Verwijder") { confirmRemove = true }
                .buttonStyle(StudioQuietButtonStyle(height: 44))
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Downloaden lukte niet: \(store.failure?.message ?? "")")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 12.5)).foregroundStyle(HomeColor.warning)
                .fixedSize(horizontal: false, vertical: true)
                Button("Opnieuw") { store.download(variant) }
                    .buttonStyle(StudioQuietButtonStyle(height: 44))
                    .disabled(store.downloading != nil)
            }
        }
    }
}
#endif
