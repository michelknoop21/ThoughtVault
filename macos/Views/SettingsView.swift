// SettingsView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Settings interface. On macOS this is a System Settings-style tabbed layout
// (toolbar tabs → per-tab grouped Form). On iOS it falls back to a single
// scrolling Form. All section logic is shared between both layouts.

import SwiftUI
import AVFoundation
import Speech
#if os(macOS)
import ScreenCaptureKit
#endif

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(AuthViewModel.self) var authVM
    @Environment(CalendarService.self) var calendarService

    // MARK: - AppStorage

    @AppStorage("serverURL") private var serverURL: String = "https://n8n.prezent.nl/tstudio/api"
    @AppStorage("defaultProfile") private var defaultProfile: String = ""
    @AppStorage("preferOnDeviceTranscription") private var preferOnDeviceTranscription: Bool = false
    @AppStorage("biometricLoginEnabled") private var biometricLoginEnabled: Bool = false
    @AppStorage("videoCallDetectionEnabled") private var videoCallDetectionEnabled: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    // Obsidian integration (API key lives in the Keychain, not here).
    @AppStorage(ObsidianService.enabledKey) private var obsidianEnabled: Bool = false
    @AppStorage(ObsidianService.baseURLKey) private var obsidianBaseURL: String = ObsidianService.defaultBaseURL
    @AppStorage(ObsidianService.vaultPathKey) private var obsidianVaultPath: String = "Notulen"

    // MARK: - Local State

    @State private var profiles: [Profile] = []
    @State private var isLoadingProfiles: Bool = false
    @State private var serverURLInput: String = ""
    @State private var showServerURLSaved: Bool = false
    @State private var serverURLError: String? = nil
    @State private var showLogoutConfirm: Bool = false
    @State private var showBugReportSheet: Bool = false
    @State private var biometricError: String? = nil
    @State private var micPermissionGranted: Bool? = nil
    @State private var speechPermissionGranted: Bool? = nil
    @State private var screenRecordingGranted: Bool? = nil

    // Obsidian
    @State private var obsidianApiKey: String = ""
    @State private var obsidianTesting: Bool = false
    @State private var obsidianTestResult: ObsidianTestState? = nil

    enum ObsidianTestState {
        case success
        case failure(String)
    }

    var body: some View {
        Group {
            #if os(macOS)
            tabbedSettings
            #else
            flatSettings
            #endif
        }
        .navigationTitle("Instellingen")
        .onAppear {
            serverURLInput = serverURL
            loadApiKey()
            obsidianApiKey = KeychainService.shared.load(for: ObsidianService.apiKeyKeychainKey) ?? ""
            Task {
                await loadProfiles()
                await checkServerConnection()
                await checkPermissions()
                if isLocalProcessing && activeLocalProvider == .ollama { await loadOllamaModels() }
            }
        }
        .confirmationDialog(
            "Uitloggen",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Uitloggen", role: .destructive) {
                authVM.logout()
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Weet je zeker dat je wilt uitloggen?")
        }
    }

    // MARK: - macOS: Tabbed Layout (System Settings-style)

    #if os(macOS)
    private var tabbedSettings: some View {
        TabView {
            algemeenTab
                .tabItem { Label("Algemeen", systemImage: "gear") }

            verwerkingTab
                .tabItem { Label("Verwerking", systemImage: "waveform") }

            profielTab
                .tabItem { Label("Profiel", systemImage: "person.crop.circle") }

            agendaTab
                .tabItem { Label("Agenda", systemImage: "calendar") }

            obsidianTab
                .tabItem { Label("Obsidian", systemImage: "tray.and.arrow.down") }

            accountTab
                .tabItem { Label("Account", systemImage: "lock") }

            geavanceerdTab
                .tabItem { Label("Geavanceerd", systemImage: "slider.horizontal.3") }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var algemeenTab: some View {
        Form {
            verbindingSection
            updatesSection
            overSection
        }
        .formStyle(.grouped)
    }

    private var verwerkingTab: some View {
        Form {
            verwerkingsmodusSection
            if isLocalProcessing {
                transcriptieSection
                lokaleNotulenSection
            } else {
                cloudNotulenSection
            }
            profielenSection
            spraakherkenningSection
        }
        .formStyle(.grouped)
    }

    private var profielTab: some View {
        Form {
            ProfileSettingsView()
            onboardingSection
        }
        .formStyle(.grouped)
    }

    private var agendaTab: some View {
        Form {
            agendaSection
        }
        .formStyle(.grouped)
    }

    private var obsidianTab: some View {
        Form {
            obsidianSection
        }
        .formStyle(.grouped)
    }

    private var accountTab: some View {
        Form {
            accountSection
            feedbackSection
        }
        .formStyle(.grouped)
    }

    private var geavanceerdTab: some View {
        Form {
            permissiesSection
            Section {
                YingaFooter()
            }
        }
        .formStyle(.grouped)
    }
    #endif

    // MARK: - iOS: Flat Layout (single Form)

    #if os(iOS)
    private var flatSettings: some View {
        Form {
            verbindingSection
            verwerkingsmodusSection
            if isLocalProcessing {
                transcriptieSection
                lokaleNotulenSection
            } else {
                cloudNotulenSection
            }
            ProfileSettingsView()
            onboardingSection
            profielenSection
            spraakherkenningSection
            permissiesSection
            agendaSection
            obsidianSection
            accountSection
            feedbackSection
            overSection
            updatesSection
        }
        .formStyle(.grouped)
    }
    #endif

    // MARK: - Verbinding (Connection)

    @State private var isCheckingServer: Bool = false
    @State private var serverConnected: Bool? = nil

    private var verbindingSection: some View {
        Section {
            SettingFieldRow("Server URL") {
                HStack(spacing: TS.Spacing.sm) {
                    TextField("https://n8n.prezent.nl/tstudio/api", text: $serverURLInput)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .onChange(of: serverURLInput) { _, _ in
                            serverURLError = nil
                        }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    if showServerURLSaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusSuccess)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Button("Opslaan") {
                        saveServerURL()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(serverURLInput == serverURL || serverURLInput.isEmpty)
                }

                if let error = serverURLError {
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                        .transition(.opacity)
                }
            }

            // Server status
            HStack(spacing: TS.Spacing.sm) {
                if isCheckingServer {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Verbinding controleren...")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)
                } else if let connected = serverConnected {
                    Circle()
                        .fill(connected ? Color.statusSuccess : Color.statusError)
                        .frame(width: 8, height: 8)
                    Text(connected ? "Verbonden" : "Niet verbonden")
                        .font(TS.Font.footnote)
                        .foregroundStyle(connected ? Color.statusSuccess : Color.statusError)
                }
                Spacer()
            }
        } header: {
            Text("Verbinding")
        } footer: {
            Text("De URL van de n8n-server waarop TranscriptStudio draait. Moet beginnen met https://")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    private func saveServerURL() {
        // Validate URL
        let trimmed = serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else {
            withAnimation(TS.Animation.quick) {
                serverURLError = "Ongeldige URL. Voer een geldige URL in."
            }
            return
        }
        guard url.scheme == "https" else {
            withAnimation(TS.Animation.quick) {
                serverURLError = "Alleen HTTPS-verbindingen zijn toegestaan."
            }
            return
        }

        serverURLError = nil
        serverURL = trimmed
        serverURLInput = trimmed
        withAnimation(TS.Animation.quick) {
            showServerURLSaved = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(TS.Animation.quick) {
                showServerURLSaved = false
            }
        }
    }

    // MARK: - Obsidian

    @State private var revealObsidianKey: Bool = false

    private var obsidianSection: some View {
        Section {
            Toggle(isOn: $obsidianEnabled) {
                Text("Automatisch exporteren naar Obsidian")
                    .font(TS.Font.body)
            }
            .tint(Color.brandPrimary)

            SettingFieldRow("Base-URL") {
                TextField(ObsidianService.defaultBaseURL, text: $obsidianBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }

            SettingFieldRow("Vault-pad") {
                TextField("Notulen", text: $obsidianVaultPath)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            SettingFieldRow("API-sleutel") {
                HStack(spacing: TS.Spacing.sm) {
                    Group {
                        if revealObsidianKey {
                            TextField("Bearer-sleutel uit de plugin", text: $obsidianApiKey)
                        } else {
                            SecureField("Bearer-sleutel uit de plugin", text: $obsidianApiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.bodyMonospaced)
                    .autocorrectionDisabled()
                    .onChange(of: obsidianApiKey) { _, newValue in saveObsidianKey(newValue) }

                    Button {
                        revealObsidianKey.toggle()
                    } label: {
                        Image(systemName: revealObsidianKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .help(revealObsidianKey ? "Verberg sleutel" : "Toon sleutel")
                }
            }

            HStack(spacing: TS.Spacing.sm) {
                Button {
                    Task { await testObsidianConnection() }
                } label: {
                    if obsidianTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test verbinding")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(obsidianTesting)

                if case .success = obsidianTestResult {
                    HStack(spacing: TS.Spacing.xs) {
                        Circle().fill(Color.statusSuccess).frame(width: 8, height: 8)
                        Text("Verbonden")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.statusSuccess)
                    }
                } else if case .failure(let message) = obsidianTestResult {
                    HStack(spacing: TS.Spacing.xs) {
                        Circle().fill(Color.statusError).frame(width: 8, height: 8)
                        Text(message)
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.statusError)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
        } header: {
            Text("Obsidian-koppeling")
        } footer: {
            Text("Schrijft notulen naar je Obsidian-vault via de Local REST API plugin. "
                + "De plugin draait op een self-signed HTTPS-poort (standaard 127.0.0.1:27124).")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    private func saveObsidianKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: ObsidianService.apiKeyKeychainKey)
        } else {
            KeychainService.shared.save(trimmed, for: ObsidianService.apiKeyKeychainKey)
        }
    }

    private func testObsidianConnection() async {
        obsidianTesting = true
        obsidianTestResult = nil
        // Use the just-edited field values directly so the test reflects unsaved input.
        let service = ObsidianService(
            baseURL: obsidianBaseURL,
            vaultPath: obsidianVaultPath,
            apiKey: obsidianApiKey
        )
        switch await service.testConnection() {
        case .success:
            obsidianTestResult = .success
        case .failure(let error):
            obsidianTestResult = .failure(error.localizedDescription)
        }
        obsidianTesting = false
    }

    // MARK: - Profielen (Profiles)

    private var profielenSection: some View {
        Section {
            if isLoadingProfiles {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Profielen laden...")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)
                }
            } else if profiles.isEmpty {
                Text("Geen profielen gevonden")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelTertiary)
            } else {
                Picker("Standaard profiel", selection: $defaultProfile) {
                    Text("Geen standaard").tag("")
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .font(TS.Font.body)
            }
        } header: {
            Text("Profielen")
        } footer: {
            Text("Het standaard profiel wordt automatisch geselecteerd bij een nieuwe opname.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Lokale Verwerking (Local Processing)

    @AppStorage("processingMode") private var processingMode: String = ProcessingMode.local.rawValue
    @AppStorage("localTranscriber") private var localTranscriber: String = LocalTranscriberEngine.whisperKit.rawValue
    @AppStorage("whisperModel") private var whisperModel: String = LocalTranscriberFactory.defaultWhisperModel
    @AppStorage("ollamaURL") private var ollamaURL: String = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel: String = "llama3.2"
    @AppStorage("lmStudioURL") private var lmStudioURL: String = "http://localhost:1234"
    @AppStorage("lmStudioModel") private var lmStudioModel: String = "local-model"

    // API key lives in the Keychain, not UserDefaults. Mirrored into @State for editing.
    @State private var ollamaApiKey: String = ""
    @State private var revealApiKey: Bool = false
    @FocusState private var apiKeyFocused: Bool

    @State private var ollamaTesting: Bool = false
    @State private var ollamaConnected: Bool? = nil
    @State private var ollamaModels: [String] = []
    @State private var ollamaModelsLoading: Bool = false

    private static let apiKeyKeychainKey = "ollamaApiKey"

    private var isLocalProcessing: Bool {
        (ProcessingMode(rawValue: processingMode) ?? .local) == .local
    }

    /// True when a key is set but the endpoint is plain HTTP — the bearer would be
    /// withheld for safety, so the key won't actually authenticate.
    private var apiKeyOverHTTPWarning: Bool {
        !ollamaApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ollamaURL.lowercased().hasPrefix("https://")
    }

    /// The notule provider actually used when processing locally. `.cloud` is
    /// meaningless offline (RecordingViewModel maps it to Ollama), so it is
    /// normalised away here — keeping the UI and the runtime in agreement.
    private var activeLocalProvider: NotulenProvider {
        let p = NotulenProvider(rawValue: notulenProvider) ?? .ollama
        return p == .cloud ? .ollama : p
    }

    /// Picker binding for the local notule provider. Coerces a stale `.cloud`
    /// selection (the legacy default) to `.ollama` so the picker never renders blank.
    private var localNotuleProviderBinding: Binding<String> {
        Binding(
            get: { activeLocalProvider.rawValue },
            set: { notulenProvider = $0 }
        )
    }

    private var verwerkingsmodusSection: some View {
        Section {
            Picker("Verwerkingsmodus", selection: $processingMode) {
                Text("Lokaal").tag(ProcessingMode.local.rawValue)
                Text("Cloud").tag(ProcessingMode.cloud.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Verwerking")
        } footer: {
            Text(isLocalProcessing
                ? "Transcriptie én notulen draaien volledig op dit apparaat. Geen server of account nodig."
                : "Audio wordt naar de server geüpload voor transcriptie en notulen.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Transcriptie (Local)

    private var transcriptieSection: some View {
        Section {
            Picker("Engine", selection: $localTranscriber) {
                ForEach(LocalTranscriberEngine.allCases) { engine in
                    Text(engine == .whisperKit ? "WhisperKit" : "Apple").tag(engine.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if localTranscriber == LocalTranscriberEngine.whisperKit.rawValue {
                SettingFieldRow("Model") {
                    TextField("model", text: $whisperModel)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text("Transcriptie")
        } footer: {
            Text(localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
                ? "WhisperKit downloadt het gekozen model bij eerste gebruik."
                : "Apple Spraakherkenning werkt direct, zonder download.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Notulen (Local provider)

    private var lokaleNotulenSection: some View {
        Section {
            Picker("Provider", selection: localNotuleProviderBinding) {
                Text("Ollama").tag(NotulenProvider.ollama.rawValue)
                Text("LM Studio").tag(NotulenProvider.lmStudio.rawValue)
                Text("Apple Intelligence").tag(NotulenProvider.appleIntelligence.rawValue)
            }

            switch activeLocalProvider {
            case .ollama:            ollamaConfig
            case .lmStudio:          lmStudioConfig
            case .appleIntelligence: appleIntelligenceNote
            case .cloud:             EmptyView()
            }

            NavigationLink {
                ProfilesView()
            } label: {
                Label("Eigen profielen beheren", systemImage: "person.text.rectangle")
                    .font(TS.Font.body)
            }
        } header: {
            Text("Notulen")
        } footer: {
            Text(localNotuleDescription)
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    private var localNotuleDescription: String {
        switch activeLocalProvider {
        case .ollama:
            return "Notulen worden lokaal gegenereerd via Ollama. Vul een API-sleutel in voor Ollama Cloud."
        case .lmStudio:
            return "Notulen worden lokaal gegenereerd via LM Studio."
        case .appleIntelligence:
            return "Notulen worden gegenereerd met Apple Intelligence op dit apparaat."
        case .cloud:
            return ""
        }
    }

    // MARK: - Notulen (Cloud)

    private var cloudNotulenSection: some View {
        Section {
            NavigationLink {
                ProfilesView()
            } label: {
                Label("Eigen profielen beheren", systemImage: "person.text.rectangle")
                    .font(TS.Font.body)
            }
        } header: {
            Text("Notulen")
        } footer: {
            Text("Notulen worden via de server gegenereerd (N8N + Claude).")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - LM Studio config

    @ViewBuilder
    private var lmStudioConfig: some View {
        SettingFieldRow(
            "LM Studio-server",
            hint: "LM Studio draait standaard op http://localhost:1234."
        ) {
            TextField("http://localhost:1234", text: $lmStudioURL)
                .textFieldStyle(.roundedBorder)
                .font(TS.Font.bodyMonospaced)
                .autocorrectionDisabled()
        }

        SettingFieldRow("Model") {
            TextField("local-model", text: $lmStudioModel)
                .textFieldStyle(.roundedBorder)
                .font(TS.Font.bodyMonospaced)
                .autocorrectionDisabled()
        }
    }

    // MARK: - Apple Intelligence note

    @ViewBuilder
    private var appleIntelligenceNote: some View {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            if let reason = AppleFoundationModelService.unavailabilityReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusWarning)
            } else {
                Label("Beschikbaar op dit apparaat.", systemImage: "checkmark.circle.fill")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusSuccess)
            }
        } else {
            Label("Vereist macOS 26 of nieuwer.", systemImage: "exclamationmark.triangle.fill")
                .font(TS.Font.caption)
                .foregroundStyle(Color.statusWarning)
        }
        #else
        Label("Niet beschikbaar in deze build.", systemImage: "exclamationmark.triangle.fill")
            .font(TS.Font.caption)
            .foregroundStyle(Color.statusWarning)
        #endif
    }

    @ViewBuilder
    private var ollamaConfig: some View {
        // Server URL + Cloud preset
        SettingFieldRow(
            "Ollama-server",
            hint: "Lokaal draait standaard op http://localhost:11434."
        ) {
            HStack(spacing: TS.Spacing.sm) {
                TextField("http://localhost:11434", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.bodyMonospaced)
                    .autocorrectionDisabled()

                Button("Cloud") {
                    ollamaURL = "https://ollama.com"
                    ollamaConnected = nil
                    apiKeyFocused = true
                }
                .buttonStyle(.bordered)
                .help("Stel in op Ollama Cloud en vul je API-sleutel in")
            }
        }

        // Model: dynamic picker when loaded, manual entry otherwise
        SettingFieldRow("Model") {
            HStack(spacing: TS.Spacing.sm) {
                if ollamaModels.isEmpty {
                    TextField("llama3.2", text: $ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                } else {
                    Picker("", selection: $ollamaModel) {
                        if !ollamaModels.contains(ollamaModel) && !ollamaModel.isEmpty {
                            Text(ollamaModel).tag(ollamaModel)
                        }
                        ForEach(ollamaModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await loadOllamaModels() }
                } label: {
                    if ollamaModelsLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(ollamaModelsLoading)
                .help("Beschikbare modellen laden")
                .accessibilityLabel("Beschikbare modellen laden")
            }
        }
        if !ollamaModels.isEmpty {
            Text("\(ollamaModels.count) modellen beschikbaar")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }

        // API key (Keychain-backed)
        SettingFieldRow("API-sleutel") {
            HStack(spacing: TS.Spacing.sm) {
                Group {
                    if revealApiKey {
                        TextField("leeg = lokale Ollama", text: $ollamaApiKey)
                    } else {
                        SecureField("leeg = lokale Ollama", text: $ollamaApiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(TS.Font.bodyMonospaced)
                .autocorrectionDisabled()
                .focused($apiKeyFocused)
                .onChange(of: ollamaApiKey) { _, newValue in saveApiKey(newValue) }

                Button {
                    revealApiKey.toggle()
                } label: {
                    Image(systemName: revealApiKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .help(revealApiKey ? "Verberg sleutel" : "Toon sleutel")
                .accessibilityLabel(revealApiKey ? "Sleutel verbergen" : "Sleutel tonen")
            }
        }

        HStack(spacing: TS.Spacing.xs) {
            Image(systemName: "link")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
            Link("Sleutel ophalen op ollama.com", destination: URL(string: "https://ollama.com/settings/keys")!)
                .font(TS.Font.caption)
        }

        if apiKeyOverHTTPWarning {
            Label("Sleutel wordt alleen over HTTPS verstuurd. Gebruik een https-URL (bijv. de Cloud-knop).",
                  systemImage: "exclamationmark.triangle.fill")
                .font(TS.Font.caption)
                .foregroundStyle(Color.statusWarning)
        }

        // Connection test
        HStack(spacing: TS.Spacing.sm) {
            Button {
                Task { await testOllamaConnection() }
            } label: {
                if ollamaTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Verbinding testen", systemImage: "bolt.horizontal.circle")
                        .font(TS.Font.footnoteSemibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandPrimary)
            .disabled(ollamaTesting)

            if let connected = ollamaConnected {
                Label(
                    connected ? "Verbonden" : "Niet bereikbaar",
                    systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(connected ? Color.statusSuccess : Color.statusError)
            }
        }
        .padding(.top, TS.Spacing.xs)
    }

    // MARK: - API key (Keychain) helpers

    private func loadApiKey() {
        ollamaApiKey = KeychainService.shared.load(for: Self.apiKeyKeychainKey) ?? ""
    }

    private func saveApiKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: Self.apiKeyKeychainKey)
        } else {
            KeychainService.shared.save(trimmed, for: Self.apiKeyKeychainKey)
        }
    }

    private func ollamaService() -> OpenAICompatibleLLMService {
        let key = ollamaApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAICompatibleLLMService(
            baseURL: ollamaURL,
            model: ollamaModel,
            apiKey: key.isEmpty ? nil : key
        )
    }

    private func testOllamaConnection() async {
        ollamaTesting = true
        ollamaConnected = nil
        let available = await ollamaService().isAvailable
        ollamaConnected = available
        ollamaTesting = false
        if available { await loadOllamaModels() }
    }

    /// Fetches the available model list (local Ollama or Ollama Cloud) for the picker.
    private func loadOllamaModels() async {
        ollamaModelsLoading = true
        let models = await ollamaService().fetchModels()
        ollamaModels = models
        // Default the selection to the first model when nothing valid is selected yet.
        if ollamaModel.isEmpty, let first = models.first {
            ollamaModel = first
        }
        ollamaModelsLoading = false
    }

    // MARK: - Notulen Generatie (AI Provider)

    // Source of truth for the local notule provider. Read by RecordingViewModel's
    // processLocally / regenerateNotuleLocally. Selected in `lokaleNotulenSection`.
    @AppStorage("notulenProvider") private var notulenProvider: String = NotulenProvider.ollama.rawValue

    // MARK: - Spraakherkenning (Transcription)

    private var spraakherkenningSection: some View {
        Section {
            if OnDeviceTranscriber.shared.isAvailable() {
                Toggle(isOn: $preferOnDeviceTranscription) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcriptie op apparaat")
                            .font(TS.Font.body)
                        Text("Sneller, geen audiodata naar server")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .tint(Color.brandPrimary)
            } else {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.labelTertiary)
                    Text("On-device transcriptie niet beschikbaar op dit apparaat.")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        } header: {
            Text("Spraakherkenning")
        } footer: {
            if OnDeviceTranscriber.shared.isAvailable() {
                Text(preferOnDeviceTranscription
                    ? "Spraak lokaal op dit apparaat omgezet naar tekst, zonder dat audio naar de server wordt verstuurd."
                    : "Audio wordt geüpload naar de server voor transcriptie via Whisper.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
    }

    // MARK: - Onboarding re-entry

    /// Lets the user re-run the first-run onboarding. Resetting the flag makes
    /// RootView (TranscriptStudioApp) present OnboardingView again; OnboardingView
    /// sets the flag back to true on finish/skip. Essential in local-only mode,
    /// where there is no login window to reach onboarding from.
    private var onboardingSection: some View {
        Section {
            Button {
                hasCompletedOnboarding = false
            } label: {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .foregroundStyle(Color.brandPrimary)
                    Text("Onboarding opnieuw doorlopen")
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Onboarding")
        } footer: {
            Text("Doorloop de welkomststappen en toestemmingen opnieuw, bijvoorbeeld om je profiel of permissies opnieuw in te stellen.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Permissies (Permissions)

    private var permissiesSection: some View {
        Section {
            permissionRow(
                icon: "mic.fill",
                title: "Microfoon",
                description: "Vereist voor audio-opnames",
                status: micPermissionGranted
            )

            permissionRow(
                icon: "waveform",
                title: "Spraakherkenning",
                description: "Vereist voor on-device transcriptie",
                status: speechPermissionGranted
            )

            #if os(macOS)
            permissionRow(
                icon: "rectangle.dashed",
                title: "Schermopname",
                description: "Vereist voor systeemgeluidsopname",
                status: screenRecordingGranted
            )
            #endif

            Button {
                #if os(macOS)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                #else
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            } label: {
                HStack {
                    Text("Systeeminstellingen openen")
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.brandSecondary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Permissies")
        }
    }

    private func permissionRow(icon: String, title: String, description: String, status: Bool? = nil) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TS.Font.bodyMedium)
                Text(description)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            HStack(spacing: TS.Spacing.xs) {
                switch status {
                case .none:
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Color.labelTertiary)
                case .some(true):
                    Text("Verleend")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.statusSuccess)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusSuccess)
                case .some(false):
                    Text("Geweigerd")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.statusError)
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.statusError)
                }
            }
        }
    }

    // MARK: - Agenda (Calendar)

    private var agendaSection: some View {
        Section {
            // Provider picker (only show when Microsoft is configured)
            if calendarService.isMicrosoftConfigured {
                Picker("Agendabron", selection: Binding(
                    get: { calendarService.activeProvider },
                    set: { newProvider in
                        calendarService.activeProvider = newProvider
                        Task { await calendarService.fetchUpcomingMeetings() }
                    }
                )) {
                    Text("Apple Agenda").tag(CalendarProvider.apple)
                    Text("Microsoft 365").tag(CalendarProvider.microsoft)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, TS.Spacing.xs)
            }

            // Apple Calendar provider
            if calendarService.activeProvider == .apple {
                appleCalendarStatus
            }

            // Microsoft 365 provider
            if calendarService.activeProvider == .microsoft {
                microsoftCalendarStatus
            }

            // Upcoming meetings (regardless of provider)
            if !calendarService.upcomingMeetings.isEmpty {
                VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                    Text("Aankomende vergaderingen")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelSecondary)

                    ForEach(calendarService.upcomingMeetings) { meeting in
                        HStack(spacing: TS.Spacing.sm) {
                            Image(systemName: meeting.platform.iconName)
                                .font(TS.Font.footnote)
                                .foregroundStyle(Color.brandSecondary)
                            Text(meeting.title)
                                .font(TS.Font.footnote)
                                .lineLimit(1)
                            Spacer()
                            Text(meeting.formattedTime)
                                .font(TS.Font.captionMonospaced)
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }
                }
                .padding(.vertical, TS.Spacing.xs)
            }
            #if os(macOS)
            Divider()

            Toggle(isOn: $videoCallDetectionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatische vergaderdetectie")
                        .font(TS.Font.body)
                    Text("Detecteert wanneer een videogesprek start en toont een melding om de opname te starten.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .tint(Color.brandPrimary)
            #endif
        } header: {
            Text("Agenda")
        } footer: {
            Text("TranscriptStudio detecteert Teams-, Zoom- en Meet-vergaderingen en biedt een snelkoppeling om opnames te starten.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Apple Calendar Status

    private var appleCalendarStatus: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Agenda")
                        .font(TS.Font.body)
                    Text(calendarService.hasCalendarAccess
                        ? "Verbonden — vergaderingen worden gedetecteerd"
                        : "Geen toegang — vergaderingen worden niet gedetecteerd")
                        .font(TS.Font.caption)
                        .foregroundStyle(calendarService.hasCalendarAccess
                            ? Color.statusSuccess
                            : Color.labelSecondary)
                }

                Spacer()

                Image(systemName: calendarService.hasCalendarAccess
                    ? "checkmark.circle.fill"
                    : "xmark.circle")
                    .foregroundStyle(calendarService.hasCalendarAccess
                        ? Color.statusSuccess
                        : Color.labelTertiary)
            }

            if !calendarService.hasCalendarAccess {
                Button {
                    Task { await calendarService.requestAccess() }
                } label: {
                    Text("Agenda koppelen")
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.brandSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Microsoft Calendar Status

    @State private var isMicrosoftConnecting = false

    private var microsoftCalendarStatus: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microsoft 365")
                        .font(TS.Font.body)
                    if calendarService.isMicrosoftConnected {
                        Text(calendarService.microsoftAccountEmail ?? "Verbonden")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.statusSuccess)
                    } else {
                        Text("Niet verbonden")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                Spacer()

                Image(systemName: calendarService.isMicrosoftConnected
                    ? "checkmark.circle.fill"
                    : "xmark.circle")
                    .foregroundStyle(calendarService.isMicrosoftConnected
                        ? Color.statusSuccess
                        : Color.labelTertiary)
            }

            if calendarService.isMicrosoftConnected {
                Button {
                    Task {
                        await calendarService.disconnectMicrosoft()
                    }
                } label: {
                    Text("Verbinding verbreken")
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.statusError)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    isMicrosoftConnecting = true
                    Task {
                        do {
                            try await MicrosoftGraphService.shared.initiateAuth()
                            await calendarService.updateMicrosoftConnection()
                            await calendarService.fetchUpcomingMeetings()
                        } catch {
                            // Auth cancelled or failed — user can retry
                        }
                        isMicrosoftConnecting = false
                    }
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        if isMicrosoftConnecting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Verbinden met Microsoft 365")
                            .font(TS.Font.bodyMedium)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isMicrosoftConnecting)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountView()
            } label: {
                if let user = authVM.currentUser {
                    HStack(spacing: TS.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.surfaceTertiary)
                                .frame(width: 40, height: 40)
                            Text(String((user.name ?? user.email).prefix(1)).uppercased())
                                .font(TS.Font.headlineBold)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            if let name = user.name, !name.isEmpty {
                                Text(name)
                                    .font(TS.Font.bodyMedium)
                            }
                            Text(user.email)
                                .font(TS.Font.footnote)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        Spacer()

                        if let role = user.role {
                            Text(role == "admin" ? "Admin" : "Gebruiker")
                                .font(TS.Font.microSemibold)
                                .padding(.horizontal, TS.Spacing.sm)
                                .padding(.vertical, TS.Spacing.xs)
                                .background(Color.surfaceTertiary)
                                .foregroundStyle(Color.labelSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
                        }
                    }
                } else {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "person.circle")
                            .foregroundStyle(Color.labelTertiary)
                        Text(authVM.userEmail.isEmpty ? "Niet ingelogd" : authVM.userEmail)
                            .font(TS.Font.body)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
            }

            // Biometric toggle in account section
            if BiometricService.shared.availableType != .none {
                VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                    Toggle(isOn: $biometricLoginEnabled) {
                        let type = BiometricService.shared.availableType
                        HStack(spacing: TS.Spacing.sm) {
                            Image(systemName: type == .faceID ? "faceid" : "touchid")
                                .foregroundStyle(Color.brandPrimary)
                            Text(type == .faceID ? "Face ID inloggen" : "Touch ID inloggen")
                                .font(TS.Font.body)
                        }
                    }
                    .tint(Color.brandPrimary)
                    .onChange(of: biometricLoginEnabled) { _, enabled in
                        biometricError = nil
                        BiometricService.shared.isEnabled = enabled
                        if enabled {
                            guard let token = KeychainService.shared.load(for: "authToken") else {
                                biometricError = "Geen actieve sessie. Log eerst in met e-mail en wachtwoord."
                                biometricLoginEnabled = false
                                BiometricService.shared.isEnabled = false
                                return
                            }
                            Task {
                                do {
                                    try await BiometricService.shared.saveTokenWithBiometrics(token)
                                } catch {
                                    biometricError = error.localizedDescription
                                    biometricLoginEnabled = false
                                    BiometricService.shared.isEnabled = false
                                }
                            }
                        } else {
                            BiometricService.shared.removeBiometricToken()
                        }
                    }

                    if let error = biometricError {
                        Text(error)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.statusError)
                    }
                }
            }

            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Uitloggen")
                        .font(TS.Font.bodyMedium)
                }
                .foregroundStyle(Color.statusError)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Account")
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        Section {
            Button {
                showBugReportSheet = true
            } label: {
                HStack {
                    Label("Probleem melden of suggestie", systemImage: "ladybug.fill")
                        .font(TS.Font.body)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Feedback")
        }
    }

    // MARK: - Over (About)

    private var overSection: some View {
        Section {
            HStack {
                Text("Versie")
                    .font(TS.Font.body)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Text(appVersion())
                    .font(TS.Font.captionMonospaced)
                    .foregroundStyle(Color.labelTertiary)
            }

            HStack {
                Text("Platform")
                    .font(TS.Font.body)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                #if os(macOS)
                Text("macOS")
                    .font(TS.Font.captionMonospaced)
                    .foregroundStyle(Color.labelTertiary)
                #else
                Text("iOS")
                    .font(TS.Font.captionMonospaced)
                    .foregroundStyle(Color.labelTertiary)
                #endif
            }
        } header: {
            Text("Over")
        }
    }

    // MARK: - Updates

    @AppStorage("checkForUpdates") private var checkForUpdates = true

    private var updatesSection: some View {
        Section {
            Toggle(isOn: $checkForUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Controleer op updates")
                        .font(TS.Font.body)
                    Text("Toon een melding op de homepage als er een nieuwe versie beschikbaar is")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .tint(Color.brandPrimary)
        } header: {
            Text("Updates")
        }
    }

    // MARK: - Helpers

    private func loadProfiles() async {
        isLoadingProfiles = true
        defer { isLoadingProfiles = false }
        profiles = (try? await APIService.shared.getProfiles()) ?? []
    }

    private func checkServerConnection() async {
        isCheckingServer = true
        defer { isCheckingServer = false }
        do {
            _ = try await APIService.shared.checkMinimumVersion()
            serverConnected = true
        } catch {
            serverConnected = false
        }
    }

    private func checkPermissions() async {
        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micPermissionGranted = micStatus == .authorized

        // Speech recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechPermissionGranted = speechStatus == .authorized

        // Screen recording (macOS only)
        #if os(macOS)
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            screenRecordingGranted = true
        } catch {
            screenRecordingGranted = false
        }
        #endif
    }

    private func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    private func deviceInfo() -> String {
        #if os(macOS)
        return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        return "\(UIDevice.current.model) - iOS \(UIDevice.current.systemVersion)"
        #endif
    }
}

// MARK: - SettingFieldRow

/// Unified settings field row: a leading caption label, the editable control
/// below it, and an optional explanatory hint. Standardising on a single
/// label-above layout keeps every input (text fields, composite control groups,
/// pickers) aligned across all settings sections, regardless of trailing-control
/// width. Use segmented `Picker`s for true binary toggles instead of this row.
struct SettingFieldRow<Content: View>: View {
    private let title: String
    private let hint: String?
    private let content: Content

    init(
        _ title: String,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Text(title)
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)
            content
            if let hint {
                Text(hint)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(.vertical, TS.Spacing.xs)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthViewModel())
            .environment(CalendarService.shared)
    }
    .frame(width: 560, height: 700)
}
