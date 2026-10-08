// CloudProviderConfig.swift
// ThoughtVault
//
// Settings for Ollama Cloud and user-defined OpenAI-compatible endpoints:
// endpoint, model, the user's own API key in the Keychain and a connection test.

import SwiftUI

struct CloudProviderConfig: View {
    let provider: NotulenProvider

    @AppStorage("ollamaCloudModel") private var ollamaCloudModel = ""
    @AppStorage(CloudAIConfiguration.selectedKey) private var selected = ""
    @State private var configurations = CloudAIConfiguration.load()
    @State private var apiKey = ""
    @State private var testing = false
    @State private var connected: Bool?
    @State private var models: [String] = []
    @State private var saveTask: Task<Void, Never>?

    private var isOllamaCloud: Bool { provider == .ollamaCloud }
    private var current: CloudAIConfiguration? { configurations.first { $0.id == selected } }
    private var keychainKey: String { isOllamaCloud ? "ollamaApiKey" : current?.keychainKey ?? "" }
    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var baseURL: String { isOllamaCloud ? OpenAICompatibleLLMService.ollamaCloudBaseURL : current?.baseURL ?? "" }
    private var isHTTPS: Bool { URL(string: baseURL)?.scheme?.lowercased() == "https" }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            if !isOllamaCloud { endpointFields }

            if isOllamaCloud || current != nil {
                SettingFieldRow("API-sleutel") {
                    SecureField("Plak je sleutel", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, value in scheduleSave(value, for: keychainKey) }
                        .onSubmit { commit(apiKey, for: keychainKey) }
                }

                SettingFieldRow("Model") {
                    HStack(spacing: TS.Spacing.sm) {
                        if models.isEmpty {
                            TextField("Modelnaam", text: modelBinding)
                                .textFieldStyle(.roundedBorder)
                                .font(TS.Font.bodyMonospaced)
                                .autocorrectionDisabled()
                        } else {
                            Picker("", selection: modelBinding) {
                                if !models.contains(modelBinding.wrappedValue) {
                                    Text(modelBinding.wrappedValue.isEmpty ? "Kies een model" : modelBinding.wrappedValue)
                                        .tag(modelBinding.wrappedValue)
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
                        .disabled(testing || !hasKey || !isHTTPS)
                        .help("Beschikbare modellen laden")
                        .accessibilityLabel("Beschikbare modellen laden")
                    }
                }

                HStack(spacing: TS.Spacing.sm) {
                    Circle().fill(status.color).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(status.text)
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(status.color)
                }
            }
        }
        .onAppear { apiKey = KeychainService.shared.load(for: keychainKey) ?? "" }
        .onChange(of: keychainKey) { old, new in
            // Store what was typed for the previous endpoint before showing the next key.
            commit(apiKey, for: old)
            apiKey = KeychainService.shared.load(for: new) ?? ""
            connected = nil
            models = []
        }
        .onChange(of: configurations) { _, value in CloudAIConfiguration.save(value) }
    }

    @ViewBuilder
    private var endpointFields: some View {
        SettingFieldRow("Aanbieder") {
            HStack(spacing: TS.Spacing.sm) {
                Picker("", selection: $selected) {
                    Text("Kies een aanbieder").tag("")
                    ForEach(configurations) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Toevoegen") {
                    let config = CloudAIConfiguration()
                    configurations.append(config)
                    selected = config.id
                }
                .buttonStyle(.bordered)
                if let current {
                    Button("Verwijderen", role: .destructive) {
                        saveTask?.cancel()
                        KeychainService.shared.delete(for: current.keychainKey)
                        configurations.removeAll { $0.id == current.id }
                        selected = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        ForEach($configurations) { $config in
            if config.id == selected {
                SettingFieldRow("Naam") {
                    TextField("Naam", text: $config.name).textFieldStyle(.roundedBorder)
                }
                SettingFieldRow("Adres", hint: "HTTPS, eventueel met /v1") {
                    TextField("https://api.example.com/v1", text: $config.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var modelBinding: Binding<String> {
        if isOllamaCloud { return $ollamaCloudModel }
        return Binding(
            get: { current?.model ?? "" },
            set: { value in
                guard let index = configurations.firstIndex(where: { $0.id == selected }) else { return }
                configurations[index].model = value
            }
        )
    }

    private var status: (text: String, color: Color) {
        if !isHTTPS { return ("Vul een HTTPS-adres in", Color.labelTertiary) }
        if !hasKey { return ("Geen sleutel ingesteld", Color.labelTertiary) }
        switch connected {
        case .some(true):  return ("Verbonden", Color.statusSuccess)
        case .some(false): return ("Sleutel geweigerd of niet bereikbaar", Color.statusError)
        case .none:        return ("Sleutel opgeslagen", Color.labelSecondary)
        }
    }

    /// Waits for a pause in typing so partial keys never reach the Keychain
    /// (and through it iCloud). Return in the field commits immediately.
    private func scheduleSave(_ value: String, for key: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            commit(value, for: key)
        }
    }

    private func commit(_ value: String, for key: String) {
        saveTask?.cancel()
        guard !key.isEmpty else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Loading the stored key into the field must not rewrite it.
        guard trimmed != (KeychainService.shared.load(for: key) ?? "") else { return }
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: key)
        } else {
            KeychainService.shared.save(trimmed, for: key)
        }
        connected = nil
    }

    private func test() async {
        testing = true
        defer { testing = false }
        commit(apiKey, for: keychainKey)
        let service = OpenAICompatibleLLMService(baseURL: baseURL, model: modelBinding.wrappedValue, apiKey: apiKey)
        let list = await service.fetchModels()
        // Listing models can succeed without a valid key, so also probe a protected endpoint.
        connected = await service.checkConnection() == .ready
        models = list
    }
}
