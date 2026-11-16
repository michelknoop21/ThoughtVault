// OnboardingView+Notulen.swift
// ThoughtVault
//
// Wizard step "Wie schrijft je notulen?": the user picks OpenRouter, the
// on-device model or another provider, enters a key and keeps or changes the
// model, so a new install never starts without a working notule provider.
// Key, model and connection test reuse HostedProviderConfig/CloudProviderConfig.
// The iOS layout is in OnboardingView+NotulenIOS.

import SwiftUI

/// Decisions of the notulen step, kept free of views so they can be tested.
enum OnboardingNotulen {
    enum Choice: CaseIterable { case openRouter, onDevice, other }

    /// Local flag: the user skipped the step without choosing a provider.
    static let skippedKey = "onboardingNotulenSkipped"

    /// Tile that a stored provider belongs to (a re-run of the wizard starts on it).
    static func choice(for provider: NotulenProvider) -> Choice {
        switch provider {
        case .openRouter, .cloud: return .openRouter
        case .appleIntelligence, .ollama, .lmStudio: return .onDevice
        case .openAI, .anthropic, .ollamaCloud, .openAICompatible: return .other
        }
    }

    /// Provider a tile installs. The current provider stays when it already belongs to the tile.
    static func provider(for choice: Choice, current: NotulenProvider, appleIntelligence: Bool) -> NotulenProvider {
        if current != .cloud, Self.choice(for: current) == choice { return current }
        switch choice {
        case .openRouter: return .openRouter
        case .onDevice: return appleIntelligence ? .appleIntelligence : .ollama
        case .other: return .openAICompatible
        }
    }

    /// Ollama and LM Studio run on a Mac; an iPhone has no local server for them.
    #if os(macOS)
    static let localServers = true
    #else
    static let localServers = false
    #endif

    /// Hosted providers need a stored key the provider did not just refuse;
    /// Ollama and LM Studio need a server on this device.
    static func isReady(_ provider: NotulenProvider, keyRejected: Bool = false, localServers: Bool = localServers) -> Bool {
        switch provider {
        case .openRouter, .openAI, .anthropic, .ollamaCloud, .openAICompatible: return !keyRejected && provider.hasAPIKey
        case .ollama, .lmStudio: return localServers
        case .appleIntelligence, .cloud: return true
        }
    }

    static func keyForNext(typed: String, stored: String?) -> String? {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? stored : key
    }

    static func keyTest(_ provider: NotulenProvider, key: String, session: URLSession = .shared) async -> KeyTestOutcome {
        let address: String
        switch provider {
        case .openRouter: address = "https://openrouter.ai/api/v1/key"
        case .openAI: address = "https://api.openai.com/v1/models"
        case .anthropic: address = "https://api.anthropic.com/v1/models"
        case .ollamaCloud, .openAICompatible:
            let base = provider == .ollamaCloud
                ? OpenAICompatibleLLMService.ollamaCloudBaseURL : CloudAIConfiguration.selected()?.baseURL ?? ""
            let service = OpenAICompatibleLLMService(baseURL: base, model: "", apiKey: key)
            address = service.endpoint("/v1/chat/completions")
        default: return .inconclusive
        }
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", url.host != nil else { return .inconclusive }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let protectedProbe = provider == .ollamaCloud || provider == .openAICompatible
        if protectedProbe {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let response = try? await session.data(for: request).1
        let status = (response as? HTTPURLResponse)?.statusCode
        // An authenticated empty chat request may return a validation error.
        if protectedProbe, status == 400 || status == 422 { return .passed }
        return KeyTestOutcome(status: status)
    }

    static func apply(_ provider: NotulenProvider, defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: "notulenProvider")
        defaults.set(false, forKey: skippedKey)
    }

    /// Skipping writes no provider; settings keep showing that a key is still needed.
    static func skip(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: skippedKey)
    }
}

extension OnboardingView {

    var notulenProvider: NotulenProvider {
        OnboardingNotulen.provider(for: notulenChoice, current: .configured(),
                                   appleIntelligence: ProcessingAdvisor.appleIntelligenceAvailable)
    }

    func notulenNext() {
        guard !notulenTesting else { return }
        let provider = notulenProvider
        guard let keychainKey = provider.apiKeyKeychainKey else {
            guard OnboardingNotulen.isReady(provider) else { notulenSkipAsk = true; return }
            OnboardingNotulen.apply(provider)
            advanceStep()
            return
        }
        if let draft = notulenDrafts[keychainKey], draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notulenSkipAsk = true
            return
        }
        guard let key = OnboardingNotulen.keyForNext(typed: notulenDrafts[keychainKey] ?? "",
                                                     stored: KeychainService.shared.load(for: keychainKey)),
              !key.isEmpty else { notulenSkipAsk = true; return }
        notulenTesting = true
        Task { @MainActor in
            defer { notulenTesting = false }
            do { try KeychainService.shared.save(key, for: keychainKey) }
            catch { notulenSkipAsk = true; return }
            guard await OnboardingNotulen.keyTest(provider, key: key) == .passed else {
                notulenSkipAsk = true
                return
            }
            guard notulenProvider == provider, provider.apiKeyKeychainKey == keychainKey,
                  KeychainService.shared.load(for: keychainKey) == key else { return }
            OnboardingNotulen.apply(provider)
            advanceStep()
        }
    }

    func notulenSkipAlert<V: View>(_ content: V) -> some View {
        content.disabled(notulenTesting).alert("Zonder taalmodel verder?", isPresented: $notulenSkipAsk) {
            Button("Model kiezen", role: .cancel) {}
            Button("Toch overslaan") {
                OnboardingNotulen.skip()
                advanceStep()
            }
        } message: {
            Text("Opnemen en omzetten naar tekst werken gewoon. Notulen maakt de app pas als je een model kiest in Instellingen › Verwerking.")
        }
    }

    /// Key, model and test of the chosen provider, or a note for the on-device model.
    @ViewBuilder
    func notulenConfig(device: String) -> some View {
        let provider = notulenProvider
        switch provider {
        case .openRouter, .openAI, .anthropic:
            HostedProviderConfig(provider: provider, onKeyDraft: { key, value in notulenDrafts[key] = value }).id(provider)
        case .ollamaCloud, .openAICompatible:
            CloudProviderConfig(provider: provider, onKeyDraft: { key, value in notulenDrafts[key] = value }).id(provider)
        case .appleIntelligence:
            notulenNote("Apple Intelligence schrijft de notule op deze \(device). Er gaat niets naar internet.")
        default:
            #if os(macOS)
            notulenNote("Ollama schrijft de notule op deze Mac. Installeer Ollama en kies het model later in Instellingen › Verwerking.")
            #else
            notulenNote("Apple Intelligence is niet beschikbaar op deze iPhone. Kies OpenRouter of stel later een eigen server in bij Instellingen › Verwerking.")
            #endif
        }
    }

    private func notulenNote(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "cpu")
            .font(TS.Font.callout)
            .foregroundStyle(HomeColor.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Spot for the model tiers (Snel / Gebalanceerd / Grondig). Until the suggested-model
    // catalog lands, the model picker inside HostedProviderConfig is the choice.
    var notulenModelHint: some View {
        Text("Het aanbevolen model staat al klaar. Later wisselen kan in Instellingen › Verwerking.")
            .font(TS.Font.footnote)
            .foregroundStyle(HomeColor.text3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Selectable provider tile of the notulen step (Mac tiles, iOS rows).
struct NotulenChoiceTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var recommended = false
    let selected: Bool
    let action: () -> Void

    private var titleText: some View {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(HomeColor.text).fixedSize()
    }

    @ViewBuilder private var badge: some View {
        if recommended { StudioBadge(text: String(localized: "Aanbevolen"), color: HomeColor.lavender).fixedSize() }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                StudioRadio(selected: selected).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    // Badge beside the title when it fits, under it in a narrow tile.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { titleText; badge }
                        VStack(alignment: .leading, spacing: 6) { titleText; badge }
                    }
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(HomeColor.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background {
                let shape = RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                shape.fill(selected ? HomeColor.violet.opacity(0.14) : HomeColor.card)
                shape.strokeBorder(selected ? HomeColor.violet : HomeColor.cardBorder, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioScalePressStyle(scale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#if os(macOS)
extension OnboardingView {

    var notulenStep: some View {
        let steps = visibleSteps
        let index = (steps.firstIndex(of: .notulen) ?? 0) + 1
        return notulenSkipAlert(ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("STAP \(index) VAN \(steps.count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(HomeColor.text3)
                Text("Wie schrijft je notulen?")
                    .font(TS.Font.titleBold)
                    .foregroundStyle(HomeColor.text)
                    .padding(.top, 6)
                Text("Opnemen en omzetten naar tekst gebeurt op je eigen Mac. Voor de notule kies je een taalmodel: op deze Mac of bij een aanbieder met je eigen sleutel.")
                    .font(.system(size: 15))
                    .foregroundStyle(HomeColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12, alignment: .top)], spacing: 10) {
                    notulenTiles
                }
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 12) {
                    notulenConfig(device: "Mac")
                }
                .studioCard(fill: HomeColor.card, padding: 18)
                .padding(.top, 22)
                .animation(.easeOut(duration: 0.2), value: notulenChoice)

                if notulenChoice != .onDevice {
                    Text("Kies een model")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HomeColor.text)
                        .padding(.top, 26)
                    notulenModelHint.padding(.top, 3)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, TS.Spacing.xl)
            .padding(.vertical, TS.Spacing.md)
            .frame(maxWidth: .infinity)
        })
    }

    @ViewBuilder
    private var notulenTiles: some View {
        NotulenChoiceTile(title: "OpenRouter", subtitle: "Eén sleutel voor veel modellen. Je betaalt per notule.",
                          recommended: true, selected: notulenChoice == .openRouter) { notulenChoice = .openRouter }
        NotulenChoiceTile(title: "Op deze Mac", subtitle: "Gratis en blijft op je Mac. Kortere, eenvoudiger notulen.",
                          selected: notulenChoice == .onDevice) { notulenChoice = .onDevice }
        NotulenChoiceTile(title: "Andere aanbieder", subtitle: "Een eigen adres met je eigen sleutel.",
                          selected: notulenChoice == .other) { notulenChoice = .other }
    }

    /// Footer of this step: Overslaan on the left, Terug and Volgende on the right.
    var notulenFooter: some View {
        HStack(spacing: TS.Spacing.md) {
            Button("Overslaan") { notulenSkipAsk = true }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HomeColor.lavender)
            Text("Je kunt dit later doen.")
                .font(TS.Font.footnote)
                .foregroundStyle(HomeColor.text3)
            Spacer()
            Button { goBackStep() } label: {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "chevron.left")
                    Text("Terug")
                }
            }
            .buttonStyle(StudioQuietButtonStyle(height: 40))
            Button { notulenNext() } label: {
                HStack(spacing: TS.Spacing.xs) {
                    Text("Volgende")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .disabled(notulenTesting)
        .padding(.horizontal, TS.Spacing.xl)
        .padding(.vertical, TS.Spacing.lg)
        .overlay(alignment: .top) { Rectangle().fill(HomeColor.divider).frame(height: 1) }
        .overlay(alignment: .bottom) {
            BrandFooter().padding(.bottom, TS.Spacing.xs)
        }
    }
}
#endif
