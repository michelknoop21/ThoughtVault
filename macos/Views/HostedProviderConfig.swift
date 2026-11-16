// HostedProviderConfig.swift
// ThoughtVault
//
// Settings for the hosted notule providers (OpenAI, Anthropic, OpenRouter): the user's
// own API key in the Keychain, a model, and a connection test. Shared by the
// macOS Verwerking page and the iOS settings subpage.

import SwiftUI

struct HostedProviderConfig: View {
    let provider: NotulenProvider
    /// Called after the key in the Keychain changed.
    var onKeyChange: () -> Void = {}

    @State private var apiKey = ""
    @State private var reveal = false
    @State private var testing = false
    @State private var connected: Bool?
    @State private var models: [String] = []
    /// Prices the provider reported with its model list (USD per million tokens).
    @State private var prices: [String: ModelPrice] = [:]
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: String?
    @AppStorage("openAIModel") private var openAIModel = OpenAICompatibleLLMService.openAIDefaultModel
    @AppStorage("anthropicModel") private var anthropicModel = AnthropicLLMService.defaultModel
    @AppStorage("openRouterModel") private var openRouterModel = OpenAICompatibleLLMService.openRouterDefaultModel

    private var isOpenAI: Bool { provider == .openAI }
    private var isOpenRouter: Bool { provider == .openRouter }
    private var providerName: String { isOpenAI ? "OpenAI" : isOpenRouter ? "OpenRouter" : "Anthropic" }
    private var keychainKey: String { provider.apiKeyKeychainKey ?? "" }
    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var modelBinding: Binding<String> { isOpenAI ? $openAIModel : isOpenRouter ? $openRouterModel : $anthropicModel }
    /// Suggested and listed models within the price cap (all three providers bill per token).
    private var options: [String] { SuggestedModels.choices(for: provider, current: "", available: models, prices: prices) }
    private var keyURL: URL {
        URL(string: isOpenAI ? "https://platform.openai.com/api-keys"
            : isOpenRouter ? "https://openrouter.ai/settings/keys" : "https://console.anthropic.com/settings/keys")!
    }

    /// Keys and model ids are long; on a phone the body size cut both off ("mistralai/mistral-…").
    #if os(iOS)
    private static let fieldFont = TS.Font.footnoteMonospaced
    #else
    private static let fieldFont = TS.Font.bodyMonospaced
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            SettingFieldRow("API-sleutel") {
                HStack(spacing: TS.Spacing.sm) {
                    Group {
                        if reveal {
                            TextField("Plak je \(providerName)-sleutel", text: $apiKey)
                        } else {
                            SecureField("Plak je \(providerName)-sleutel", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(Self.fieldFont)
                    .autocorrectionDisabled()
                    .onChange(of: apiKey) { _, value in scheduleSave(value) }
                    .onSubmit { commit(apiKey) }

                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.bordered)
                        .help(reveal ? "Verberg sleutel" : "Toon sleutel")
                        .accessibilityLabel(reveal ? "Sleutel verbergen" : "Sleutel tonen")
                }
            }

            SettingFieldRow("Model") {
                HStack(spacing: TS.Spacing.sm) {
                    Picker("", selection: modelBinding) {
                        if !options.contains(modelBinding.wrappedValue) {
                            Text("\(modelBinding.wrappedValue) (boven de prijsgrens)").tag(modelBinding.wrappedValue)
                        }
                        ForEach(options, id: \.self) { Text(TaskHistoryFormat.modelLabel($0, price: prices[$0])).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await test() } } label: {
                        if testing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(testing || !hasKey)
                    .help("Beschikbare modellen laden")
                    .accessibilityLabel("Beschikbare modellen laden")
                }
            }

            Text("Aanbevolen modellen tot $3 per miljoen invoertokens en $15 per miljoen uitvoertokens. Duurdere modellen zijn niet te kiezen.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: TS.Spacing.sm) {
                Circle().fill(status.color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(status.text)
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(status.color)
                Spacer(minLength: 8)
                if hasKey {
                    Button("Sleutel verwijderen", role: .destructive) { apiKey = ""; connected = nil; models = [] }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack(spacing: TS.Spacing.xs) {
                Image(systemName: "link").font(TS.Font.caption).foregroundStyle(Color.labelTertiary)
                Link("Sleutel aanmaken bij \(providerName)", destination: keyURL).font(TS.Font.caption)
            }
            if isOpenAI {
                Text("API-sleutel. Inloggen met je ChatGPT-abonnement volgt zodra dat voor ThoughtVault beschikbaar is.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            apiKey = KeychainService.shared.load(for: keychainKey) ?? ""
        }
    }

    private var status: (text: String, color: Color) {
        if let saveError { return (saveError, Color.statusError) }
        if !hasKey { return ("Geen sleutel ingesteld", Color.labelTertiary) }
        switch connected {
        case .some(true):  return ("Verbonden met \(providerName)", Color.statusSuccess)
        case .some(false): return ("Sleutel geweigerd of niet bereikbaar", Color.statusError)
        case .none:        return ("Sleutel opgeslagen", Color.labelSecondary)
        }
    }

    /// Waits for a pause in typing so partial keys never reach the Keychain
    /// (and through it iCloud). Return in the field commits immediately.
    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            commit(value)
        }
    }

    private func commit(_ value: String) {
        saveTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Loading the stored key into the field must not rewrite it.
        guard trimmed != (KeychainService.shared.load(for: keychainKey) ?? "") else { return }
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: keychainKey)
        } else {
            do {
                try KeychainService.shared.save(trimmed, for: keychainKey)
            } catch {
                saveError = error.localizedDescription
                return
            }
        }
        saveError = nil
        connected = nil
        onKeyChange()
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let list: [String]
        if isOpenAI {
            let all = await OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.openAIBaseURL,
                                                       model: openAIModel, apiKey: key).fetchModels()
            // The list also holds embedding, audio and image models; keep chat models.
            list = all.filter { $0.hasPrefix("gpt-") || $0.hasPrefix("o") }.filter { !$0.contains("audio") && !$0.contains("image") && !$0.contains("realtime") && !$0.contains("transcribe") && !$0.contains("tts") }
        } else if isOpenRouter {
            // One request gives the models and their prices.
            prices = await SuggestedModels.fetchReportedPrices(provider: .openRouter, baseURL: OpenAICompatibleLLMService.openRouterBaseURL, apiKey: key) ?? [:]
            list = prices.keys.sorted()
        } else {
            list = await AnthropicLLMService(model: anthropicModel, apiKey: key).fetchModels()
        }
        connected = !list.isEmpty
        models = list
    }
}
