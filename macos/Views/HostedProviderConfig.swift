// HostedProviderConfig.swift
// ThoughtVault
//
// Settings for the hosted notule providers (OpenAI, Anthropic): the user's
// own API key in the Keychain, a model, and a connection test. Shared by the
// macOS Verwerking page and the iOS settings subpage.

import SwiftUI

struct HostedProviderConfig: View {
    let provider: NotulenProvider

    @State private var apiKey = ""
    @State private var reveal = false
    @State private var testing = false
    @State private var connected: Bool?
    @State private var models: [String] = []
    @State private var loaded = false
    @AppStorage("openAIModel") private var openAIModel = OpenAICompatibleLLMService.openAIDefaultModel
    @AppStorage("anthropicModel") private var anthropicModel = AnthropicLLMService.defaultModel

    private var isOpenAI: Bool { provider == .openAI }
    private var providerName: String { isOpenAI ? "OpenAI" : "Anthropic" }
    private var keychainKey: String { provider.apiKeyKeychainKey ?? "" }
    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var modelBinding: Binding<String> { isOpenAI ? $openAIModel : $anthropicModel }
    private var keyURL: URL {
        URL(string: isOpenAI ? "https://platform.openai.com/api-keys" : "https://console.anthropic.com/settings/keys")!
    }

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
                    .font(TS.Font.bodyMonospaced)
                    .autocorrectionDisabled()
                    .onChange(of: apiKey) { _, value in save(value) }

                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.bordered)
                        .help(reveal ? "Verberg sleutel" : "Toon sleutel")
                        .accessibilityLabel(reveal ? "Sleutel verbergen" : "Sleutel tonen")
                }
            }

            SettingFieldRow("Model") {
                HStack(spacing: TS.Spacing.sm) {
                    if models.isEmpty {
                        TextField(isOpenAI ? OpenAICompatibleLLMService.openAIDefaultModel : AnthropicLLMService.defaultModel,
                                  text: modelBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.bodyMonospaced)
                            .autocorrectionDisabled()
                    } else {
                        Picker("", selection: modelBinding) {
                            if !models.contains(modelBinding.wrappedValue) {
                                Text(modelBinding.wrappedValue).tag(modelBinding.wrappedValue)
                            }
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { Task { await test() } } label: {
                        if testing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(testing || !hasKey)
                    .help("Beschikbare modellen laden")
                    .accessibilityLabel("Beschikbare modellen laden")
                }
            }

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
        if !hasKey { return ("Geen sleutel ingesteld", Color.labelTertiary) }
        switch connected {
        case .some(true):  return ("Verbonden met \(providerName)", Color.statusSuccess)
        case .some(false): return ("Sleutel geweigerd of niet bereikbaar", Color.statusError)
        case .none:        return ("Sleutel opgeslagen", Color.labelSecondary)
        }
    }

    private func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: keychainKey)
        } else {
            KeychainService.shared.save(trimmed, for: keychainKey)
        }
        connected = nil
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
        } else {
            list = await AnthropicLLMService(model: anthropicModel, apiKey: key).fetchModels()
        }
        connected = !list.isEmpty
        models = list
    }
}
