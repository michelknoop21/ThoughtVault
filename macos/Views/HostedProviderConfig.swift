// HostedProviderConfig.swift
// ThoughtVault
//
// Settings for the hosted notule providers (OpenAI, Anthropic, OpenRouter): the user's
// own API key in the Keychain, a model, and a connection test. Shared by the
// macOS Verwerking page and the iOS settings subpage.

import SwiftUI

/// What a key test says about the key itself. Only 401/403 mean the provider refused it;
/// a timeout or server error is inconclusive.
enum KeyTestOutcome: Equatable {
    case passed, rejected, inconclusive

    init(connection: OpenAICompatibleLLMService.ConnectionStatus) {
        self = connection == .ready ? .passed : connection == .keyRejected ? .rejected : .inconclusive
    }

    init(status: Int?) {
        switch status {
        case 200: self = .passed
        case 401, 403: self = .rejected
        default: self = .inconclusive
        }
    }
}

struct HostedProviderConfig: View {
    let provider: NotulenProvider
    /// Called after the key in the Keychain changed.
    var onKeyChange: () -> Void = {}
    /// Outcome of each key test with the key it tested.
    var onKeyTest: (KeyTestOutcome, String) -> Void = { _, _ in }

    var onKeyDraft: (String, String) -> Void = { _, _ in }

    @State private var apiKey = ""
    @State private var reveal = false
    @State private var testing = false
    @State private var connected: Bool?
    /// Why the last test failed, when the provider says so.
    @State private var failure: String?
    @State private var models: [String] = []
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
    private var defaultModel: String {
        isOpenAI ? OpenAICompatibleLLMService.openAIDefaultModel : isOpenRouter ? OpenAICompatibleLLMService.openRouterDefaultModel : AnthropicLLMService.defaultModel
    }
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
                    .onChange(of: apiKey) { _, value in onKeyDraft(keychainKey, value); scheduleSave(value) }
                    .onSubmit { commit(apiKey) }

                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.bordered)
                        .help(reveal ? "Verberg sleutel" : "Toon sleutel")
                        .accessibilityLabel(reveal ? "Sleutel verbergen" : "Sleutel tonen")
                }
            }

            SettingFieldRow("Model") {
                HStack(spacing: TS.Spacing.sm) {
                    if models.isEmpty {
                        TextField(defaultModel, text: modelBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(Self.fieldFont)
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
        if let saveError { return (saveError, Color.statusError) }
        if !hasKey { return ("Geen sleutel ingesteld", Color.labelTertiary) }
        switch connected {
        case .some(true):  return ("Verbonden met \(providerName)", Color.statusSuccess)
        case .some(false): return (failure ?? String(localized: "Sleutel geweigerd of niet bereikbaar"), Color.statusError)
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
        failure = nil
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // OpenRouter lists its models without a key, so the list alone proves nothing.
        if isOpenRouter {
            let status = await Self.openRouterKeyStatus(key)
            onKeyTest(KeyTestOutcome(status: status), key)
            if let problem = Self.openRouterKeyProblem(status: status) {
                failure = problem
                connected = false
                models = []
                return
            }
        }
        let list: [String]
        if isOpenAI {
            let result = await OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.openAIBaseURL,
                                                          model: openAIModel, apiKey: key).fetchModelList()
            onKeyTest(KeyTestOutcome(status: result.status), key)
            // The list also holds embedding, audio and image models; keep chat models.
            list = result.models.filter { $0.hasPrefix("gpt-") || $0.hasPrefix("o") }.filter { !$0.contains("audio") && !$0.contains("image") && !$0.contains("realtime") && !$0.contains("transcribe") && !$0.contains("tts") }
        } else if isOpenRouter {
            list = await OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.openRouterBaseURL,
                                                    model: openRouterModel, apiKey: key).fetchModels()
        } else {
            let result = await AnthropicLLMService(model: anthropicModel, apiKey: key).fetchModelList()
            onKeyTest(KeyTestOutcome(status: result.status), key)
            list = result.models
        }
        connected = !list.isEmpty
        models = list
    }

    /// Status of OpenRouter's key endpoint (nil without an answer). Only the status is
    /// inspected; the key never reaches a log.
    private static func openRouterKeyStatus(_ key: String) async -> Int? {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let response = try? await URLSession.shared.data(for: request).1
        return (response as? HTTPURLResponse)?.statusCode
    }

    /// nil for 200, else what went wrong.
    private static func openRouterKeyProblem(status: Int?) -> String? {
        switch status {
        case 200: return nil
        case nil: return String(localized: "OpenRouter is niet bereikbaar. Controleer je internetverbinding.")
        case 401, 403: return String(localized: "OpenRouter weigert deze sleutel. Controleer of je hem volledig hebt geplakt.")
        case let status?: return String(localized: "OpenRouter gaf foutcode \(status). Probeer het later opnieuw.")
        }
    }
}
