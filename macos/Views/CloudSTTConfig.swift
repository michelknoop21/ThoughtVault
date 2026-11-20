// CloudSTTConfig.swift
// ThoughtVault
//
// Settings for the opt-in cloud transcription engine: provider preset, model,
// base URL (custom only) and the API key in the Keychain. Shared by the macOS
// Verwerking page and the iOS transcription section.

import SwiftUI

struct CloudSTTConfig: View {
    @AppStorage(CloudSTTProvider.providerDefaultsKey) private var providerRaw = CloudSTTProvider.openai.rawValue
    @AppStorage(CloudSTTProvider.modelDefaultsKey) private var model = ""
    @AppStorage(CloudSTTProvider.baseURLDefaultsKey) private var baseURL = ""
    @State private var apiKey = ""
    @State private var saveTask: Task<Void, Never>?

    private var provider: CloudSTTProvider { CloudSTTProvider(rawValue: providerRaw) ?? .openai }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            SettingFieldRow("Aanbieder") {
                Picker("Aanbieder", selection: $providerRaw) {
                    ForEach(CloudSTTProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if provider == .custom {
                SettingFieldRow("Adres") {
                    TextField("https://api.example.com/v1", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                }
            }

            SettingFieldRow("Model") {
                if provider.models.isEmpty {
                    TextField("whisper-1", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                } else {
                    Picker("Model", selection: $model) {
                        ForEach(provider.models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingFieldRow("API-sleutel") {
                SecureField("Plak je \(provider.displayName)-sleutel", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.bodyMonospaced)
                    .autocorrectionDisabled()
                    .onChange(of: apiKey) { _, value in scheduleSave(value) }
                    .onSubmit { commit(apiKey) }
            }

            Text(provider == .openai
                 ? "Audio gaat naar OpenAI voor transcriptie. De sleutel is dezelfde als voor ChatGPT-notulen."
                 : "Audio gaat naar \(provider == .custom ? "het opgegeven adres" : provider.displayName) voor transcriptie.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
        .onAppear(perform: syncProvider)
        .onChange(of: providerRaw) { _, _ in syncProvider() }
    }

    /// Loads the provider's key and keeps the model valid for its preset list.
    private func syncProvider() {
        saveTask?.cancel()
        apiKey = KeychainService.shared.load(for: provider.keychainKey) ?? ""
        if !provider.models.isEmpty, !provider.models.contains(model) { model = provider.models[0] }
    }

    /// Waits for a pause in typing so partial keys never reach the Keychain.
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
        let key = provider.keychainKey
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (KeychainService.shared.load(for: key) ?? "") else { return }
        if trimmed.isEmpty { KeychainService.shared.delete(for: key) } else { KeychainService.shared.save(trimmed, for: key) }
    }
}
