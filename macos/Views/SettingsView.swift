// SettingsView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Settings interface. On macOS this is a System Settings-style tabbed layout
// (toolbar tabs → per-tab grouped Form). On iOS it falls back to a single
// scrolling Form. All section logic is shared between both layouts.

import SwiftUI
import AVFoundation
import Speech
import UniformTypeIdentifiers


// MARK: - SettingsView

struct SettingsView: View {

    @Environment(AuthViewModel.self) var authVM
    @Environment(CalendarService.self) var calendarService

    // MARK: - AppStorage

    @AppStorage("defaultProfile") var defaultProfile: String = ""
    @AppStorage("preferOnDeviceTranscription") var preferOnDeviceTranscription: Bool = false
    @AppStorage("biometricLoginEnabled") private var biometricLoginEnabled: Bool = false
    @AppStorage("videoCallDetectionEnabled") private var videoCallDetectionEnabled: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    // Obsidian integration (API key lives in the Keychain, not here).
    @AppStorage(ObsidianService.enabledKey) private var obsidianEnabled: Bool = false
    @AppStorage(ObsidianService.baseURLKey) private var obsidianBaseURL: String = ObsidianService.defaultBaseURL
    @AppStorage(ObsidianService.vaultPathKey) private var obsidianVaultPath: String = "Notulen"
    @AppStorage(VaultFolderStore.contextNoteKey) private var obsidianContextNote: String = VaultFolderStore.defaultContextNote

    // MARK: - Local State

    @State var profiles: [Profile] = []
    @State private var isLoadingProfiles: Bool = false
    @State private var showLogoutConfirm: Bool = false
    @State private var showBugReportSheet: Bool = false
    @State private var feedbackTitle = ""
    @State private var feedbackDescription = ""
    @State private var biometricError: String? = nil
    @State private var micPermissionGranted: Bool? = nil
    @State private var speechPermissionGranted: Bool? = nil
    @State private var systemAudioGranted: Bool? = nil

    // Obsidian
    @State private var obsidianApiKey: String = ""
    @State private var obsidianTesting: Bool = false
    @State private var obsidianTestResult: ObsidianTestState? = nil
    @State private var showVaultFolderPicker: Bool = false
    @State private var vaultFolderName: String = VaultFolderStore.folderName

    enum ObsidianTestState {
        case success
        case failure(String)
    }

    /// Width-tier responsive flag: below 640pt composite field rows stack
    /// vertically instead of squeezing in a single HStack.
    @State private var isCompact: Bool = false

    #if os(macOS)
    // Verwerking studio layout (SettingsView+Studio / +Verwerking).
    @State var settingsTab: SettingsTab = {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "TVDebugSettingsTab"), let tab = SettingsTab(rawValue: raw) { return tab }
        #endif
        return .verwerking
    }()
    @State var showManualModel: Bool = false
    @State var showSetupDetails: Bool = false
    @State var showTranscriptionHelp: Bool = false
    @State var showNotuleHelp: Bool = false
    #endif

    var body: some View {
        GeometryReader { geo in
            Group {
                #if os(macOS)
                settingsStudio
                #else
                iosSettings
                #endif
            }
            .onAppear { isCompact = geo.size.width < 640 }
            .onChange(of: geo.size.width) { _, width in
                isCompact = width < 640
            }
        }
        .navigationTitle("Instellingen")
        #if os(macOS)
        .sheet(isPresented: $showBugReportSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Feedback").font(TS.Font.title3Semibold)
                Text("Kopieer je melding om deze met Yinga te delen.")
                    .font(TS.Font.body).foregroundStyle(Color.labelSecondary)
                TextField("Titel", text: $feedbackTitle).textFieldStyle(.roundedBorder)
                Text("Beschrijving").font(TS.Font.bodyMedium)
                TextEditor(text: $feedbackDescription)
                    .font(TS.Font.body).frame(height: 140)
                    .scrollIndicators(.never)
                    .accessibilityLabel("Beschrijving")
                HStack {
                    Button("Annuleer") { showBugReportSheet = false }
                        .buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Kopieer feedback") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("ThoughtVault feedback\n\(feedbackTitle.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(feedbackDescription.trimmingCharacters(in: .whitespacesAndNewlines))", forType: .string)
                        showBugReportSheet = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(feedbackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || feedbackDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 440)
        }
        #endif
        .onAppear {
            loadApiKey()
            obsidianApiKey = KeychainService.shared.load(for: ObsidianService.apiKeyKeychainKey) ?? ""
            Task {
                await loadProfiles()
                await checkServerConnection()
                await checkPermissions()

                if isLocalProcessing && localTranscriber == LocalTranscriberEngine.whisperKit.rawValue { await loadWhisperModels() }
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

    // MARK: - Form container

    /// Grouped Form rendered as a capped, centered column on wide windows,
    /// mirroring the responsive scroll-column pattern used on HomeView.
    private func cappedForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollIndicators(.never)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
    }

    // MARK: - macOS: Tabbed Layout (System Settings-style)

    #if os(macOS)
    var algemeenTab: some View {
        cappedForm {
            // Hide "Verbinding" section in local mode — no server to connect to.
            if !isLocalProcessing {
                verbindingSection
            }
            updatesSection
            overSection
        }
    }

    var profielTab: some View {
        cappedForm {
            profielenSection
            ProfileSettingsView()
            onboardingSection
        }
    }

    var agendaTab: some View {
        cappedForm {
            agendaSection
        }
    }

    var obsidianTab: some View {
        cappedForm {
            obsidianSection
        }
    }

    var accountTab: some View {
        cappedForm {
            if isLocalProcessing {
                Section("Lokale app") {
                    Text("Deze app werkt lokaal zonder ThoughtVault-login.")
                    Text("Je profiel stel je in bij Notulen.").foregroundStyle(Color.labelSecondary)
                }
            } else {
                accountSection
            }
            feedbackSection
        }
    }

    var geavanceerdTab: some View {
        cappedForm {
            permissiesSection
            Section {
                BrandFooter()
            }
        }
    }
    #endif

    // MARK: - Verbinding (Connection)

    @State private var isCheckingServer: Bool = false
    @State private var serverConnected: Bool? = nil

    var verbindingSection: some View {
        Section {
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
            Text("Status van de verbinding met de ThoughtVault-server.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Obsidian

    @State private var revealObsidianKey: Bool = false

    var obsidianSection: some View {
        Section {
            Toggle(isOn: $obsidianEnabled) {
                Text("Automatisch exporteren naar Obsidian")
                    .font(TS.Font.body)
            }
            .tint(Color.brandPrimary)

            // Folder connection — the cross-platform path (works on iOS too).
            // Compact stacks the folder name above the buttons.
            SettingFieldRow("Vault-map") {
                if isCompact {
                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        vaultFolderLabel
                        HStack(spacing: TS.Spacing.sm) {
                            vaultFolderButtons
                            Spacer()
                        }
                    }
                } else {
                    HStack(spacing: TS.Spacing.sm) {
                        vaultFolderLabel
                        Spacer()
                        vaultFolderButtons
                    }
                }
            }

            SettingFieldRow("Context-note") {
                TextField(VaultFolderStore.defaultContextNote, text: $obsidianContextNote)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            // REST API fields are desktop-only — iOS cannot reach a desktop's
            // localhost. Hidden on iOS to avoid confusion.
            #if os(macOS)
            SettingFieldRow("Base-URL") {
                TextField(ObsidianService.defaultBaseURL, text: $obsidianBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Vault-pad") {
                TextField("Notulen", text: $obsidianVaultPath)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
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

            // Compact stacks the test result below the button.
            if isCompact {
                VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                    obsidianTestButton
                    obsidianTestStatus
                }
            } else {
                HStack(spacing: TS.Spacing.sm) {
                    obsidianTestButton
                    obsidianTestStatus
                    Spacer()
                }
            }
            #endif
        } header: {
            Text("Obsidian-koppeling")
        } footer: {
            #if os(iOS)
            Text("Kies je Obsidian-vault-map (bijv. via iCloud Drive) om notulen automatisch "
                + "als Markdown-bestanden op te slaan én de context-note te lezen "
                + "(namen/termen zoals \"Michel\"). Werkt volledig offline op iPhone.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
            #else
            Text("Kies je vault-map om notulen als bestand op te slaan én de context-note te lezen "
                + "(namen/termen zoals \"Michel\"). Dit werkt op Mac én iPhone. "
                + "De Base-URL/API-sleutel eronder zijn de desktop-fallback via de Local REST API plugin, "
                + "alleen gebruikt als er geen vault-map is gekozen.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
            #endif
        }
        .fileImporter(
            isPresented: $showVaultFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    try VaultFolderStore.setFolder(url)
                    vaultFolderName = VaultFolderStore.folderName
                } catch {
                    obsidianTestResult = .failure("Map-koppeling mislukt: \(error.localizedDescription)")
                }
            }
        }
    }

    private var vaultFolderLabel: some View {
        Text(vaultFolderName.isEmpty ? "Geen map gekozen" : vaultFolderName)
            .font(TS.Font.body)
            .foregroundStyle(vaultFolderName.isEmpty ? Color.labelTertiary : Color.labelPrimary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var vaultFolderButtons: some View {
        Button(vaultFolderName.isEmpty ? "Kies map…" : "Wijzig…") {
            showVaultFolderPicker = true
        }
        .buttonStyle(SecondaryButtonStyle())
        if !vaultFolderName.isEmpty {
            Button {
                VaultFolderStore.clear()
                vaultFolderName = ""
            } label: { Image(systemName: "xmark.circle.fill") }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.labelTertiary)
            .help("Map-koppeling verwijderen")
        }
    }

    private var obsidianTestButton: some View {
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
    }

    @ViewBuilder
    private var obsidianTestStatus: some View {
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

    var profielenSection: some View {
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

    @AppStorage("processingMode") var processingMode: String = ProcessingMode.local.rawValue
    @AppStorage("localTranscriber") var localTranscriber: String = LocalTranscriberEngine.whisperKit.rawValue
    @AppStorage("whisperModel") var whisperModel: String = LocalTranscriberFactory.defaultWhisperModel
    @AppStorage(PersonalVocabulary.defaultsKey) var personalVocabulary: String = ""
    @AppStorage("ollamaURL") var ollamaURL: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3.2"
    @AppStorage("lmStudioURL") var lmStudioURL: String = "http://localhost:1234"
    @AppStorage("lmStudioModel") var lmStudioModel: String = "local-model"

    // WhisperKit model discovery
    @State var whisperModels: [String] = []
    @State var whisperModelsLoading: Bool = false

    // API key lives in the Keychain, not UserDefaults. Mirrored into @State for editing.
    @State var ollamaApiKey: String = ""
    @State var revealApiKey: Bool = false
    @FocusState private var apiKeyFocused: Bool

    @State var ollamaTesting: Bool = false
    @State var ollamaStatus: OpenAICompatibleLLMService.ConnectionStatus? = nil
    @State var ollamaModels: [String] = []
    @State var ollamaModelsLoading: Bool = false

    static let apiKeyKeychainKey = "ollamaApiKey"

    var isLocalProcessing: Bool {
        (ProcessingMode(rawValue: processingMode) ?? .local) == .local
    }

    /// True when a key is set but the endpoint is plain HTTP — the bearer would be
    /// withheld for safety, so the key won't actually authenticate.
    var apiKeyOverHTTPWarning: Bool {
        !ollamaApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ollamaURL.lowercased().hasPrefix("https://")
    }

    /// The notule provider actually used when processing locally. `.cloud` is
    /// meaningless offline (RecordingViewModel maps it to Ollama), so it is
    /// normalised away here — keeping the UI and the runtime in agreement.
    var activeLocalProvider: NotulenProvider {
        let p = NotulenProvider(rawValue: notulenProvider) ?? .ollama
        return p == .cloud ? .ollama : p
    }

    /// Picker binding for the local notule provider. Coerces a stale `.cloud`
    /// selection (the legacy default) to `.ollama` so the picker never renders blank.
    var localNotuleProviderBinding: Binding<String> {
        Binding(
            get: { activeLocalProvider.rawValue },
            set: { notulenProvider = $0 }
        )
    }

    var verwerkingsmodusSection: some View {
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

    var transcriptieSection: some View {
        Section {
            Picker("Engine", selection: $localTranscriber) {
                ForEach(LocalTranscriberEngine.allCases) { engine in
                    Text(engine == .whisperKit ? "WhisperKit" : "Apple").tag(engine.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if localTranscriber == LocalTranscriberEngine.whisperKit.rawValue {
                SettingFieldRow("Model") {
                    HStack(spacing: TS.Spacing.sm) {
                        if whisperModels.isEmpty {
                            TextField("model", text: $whisperModel)
                                .textFieldStyle(.roundedBorder)
                                .font(TS.Font.bodyMonospaced)
                                .autocorrectionDisabled()
                        } else {
                            Picker("", selection: $whisperModel) {
                                if !whisperModels.contains(whisperModel) && !whisperModel.isEmpty {
                                    Text(whisperModel).tag(whisperModel)
                                }
                                ForEach(whisperModels, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await loadWhisperModels() }
                        } label: {
                            if whisperModelsLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(whisperModelsLoading)
                        .help("Beschikbare modellen laden")
                        .accessibilityLabel("Beschikbare modellen laden")
                    }
                }
                if !whisperModels.isEmpty {
                    Text("\(whisperModels.count) modellen beschikbaar")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            SettingFieldRow("Eigen termen") {
                TextField("Michel, Django, …", text: $personalVocabulary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Transcriptie")
        } footer: {
            Text((localTranscriber == LocalTranscriberEngine.whisperKit.rawValue
                ? "WhisperKit downloadt het gekozen model bij eerste gebruik. Klik het refresh-icoon om alle beschikbare modellen te laden. "
                : "Apple Spraakherkenning werkt direct, zonder download. ")
                + "Eigen termen (komma-gescheiden) en personen uit de app sturen de herkenning van namen zoals \"Michel\".")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Notulen (Local provider)

    var lokaleNotulenSection: some View {
        Section {
            Picker("Provider", selection: localNotuleProviderBinding) {
                Text("Ollama").tag(NotulenProvider.ollama.rawValue)
                Text("LM Studio").tag(NotulenProvider.lmStudio.rawValue)
                Text("Apple Intelligence").tag(NotulenProvider.appleIntelligence.rawValue)
                Text("ChatGPT").tag(NotulenProvider.openAI.rawValue)
                Text("Claude").tag(NotulenProvider.anthropic.rawValue)
                Text("Ollama Cloud").tag(NotulenProvider.ollamaCloud.rawValue)
                Text("OpenAI-compatibel").tag(NotulenProvider.openAICompatible.rawValue)
            }

            switch activeLocalProvider {
            case .ollama:            ollamaConfig
            case .lmStudio:          lmStudioConfig
            case .appleIntelligence: appleIntelligenceNote
            case .openAI, .anthropic: HostedProviderConfig(provider: activeLocalProvider).id(activeLocalProvider)
            case .ollamaCloud, .openAICompatible: CloudProviderConfig(provider: activeLocalProvider).id(activeLocalProvider)
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

    var localNotuleDescription: String {
        switch activeLocalProvider {
        case .ollama:
            return "Notulen worden lokaal gegenereerd via Ollama. Vul een API-sleutel in voor Ollama Cloud."
        case .lmStudio:
            return "Notulen worden lokaal gegenereerd via LM Studio."
        case .appleIntelligence:
            return "Notulen worden gegenereerd met Apple Intelligence op dit apparaat."
        case .openAI:
            return "Het transcript wordt naar OpenAI gestuurd. De kosten lopen via je eigen API-account."
        case .anthropic:
            return "Het transcript wordt naar Anthropic gestuurd. De kosten lopen via je eigen API-account."
        case .ollamaCloud:
            return "Het transcript wordt naar Ollama Cloud gestuurd. De kosten lopen via je eigen account."
        case .openAICompatible:
            return "Het transcript wordt naar het HTTPS-adres van je eigen aanbieder gestuurd."
        case .cloud:
            return ""
        }
    }

    // MARK: - Notulen (Cloud)

    var cloudNotulenSection: some View {
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
    var lmStudioConfig: some View {
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
    var appleIntelligenceNote: some View {
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
    var ollamaConfig: some View {
        // Server URL + Cloud preset
        #if os(iOS)
        let ollamaHint = "Ollama draait niet op iPhone/iPad. Vul de URL van een remote Ollama-server in."
        #else
        let ollamaHint = "Lokaal draait standaard op http://localhost:11434."
        #endif
        // Compact stacks the URL field above the Cloud preset button.
        SettingFieldRow(
            "Ollama-server",
            hint: ollamaHint
        ) {
            if isCompact {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    ollamaURLField
                    #if os(iOS)
                    ollamaCloudButton
                    #endif
                }
            } else {
                HStack(spacing: TS.Spacing.sm) {
                    ollamaURLField
                    #if os(iOS)
                    ollamaCloudButton
                    #endif
                }
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
        if !ollamaModelsLoading && ollamaModels.isEmpty {
            Text("Geen modellen opgehaald. Controleer het adres en de verbinding.")
                .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
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

            if let status = ollamaStatus {
                let ready = status == .ready
                Label(
                    Self.ollamaStatusText(status),
                    systemImage: ready ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(ready ? Color.statusSuccess : Color.statusError)
            }
        }
        .padding(.top, TS.Spacing.xs)
    }

    var ollamaURLField: some View {
        TextField("http://localhost:11434", text: $ollamaURL)
            .textFieldStyle(.roundedBorder)
            .font(TS.Font.bodyMonospaced)
            .autocorrectionDisabled()
    }

    var ollamaCloudButton: some View {
        Button("Cloud") {
            ollamaURL = "https://ollama.com"
            ollamaStatus = nil
            apiKeyFocused = true
        }
        .buttonStyle(.bordered)
        .help("Stel in op Ollama Cloud en vul je API-sleutel in")
    }

    // MARK: - API key (Keychain) helpers

    func loadApiKey() {
        ollamaApiKey = KeychainService.shared.load(for: Self.apiKeyKeychainKey) ?? ""
    }

    func saveApiKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Loading the stored key into the field must not rewrite it (save() is delete + add).
        guard trimmed != (KeychainService.shared.load(for: Self.apiKeyKeychainKey) ?? "") else { return }
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: Self.apiKeyKeychainKey)
        } else {
            KeychainService.shared.save(trimmed, for: Self.apiKeyKeychainKey)
        }
    }

    func ollamaService() -> OpenAICompatibleLLMService {
        let key = ollamaApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAICompatibleLLMService(
            baseURL: ollamaURL,
            model: ollamaModel,
            apiKey: key.isEmpty ? nil : key
        )
    }

    func testOllamaConnection() async {
        ollamaTesting = true
        ollamaStatus = nil
        let status = await ollamaService().checkConnection()
        ollamaStatus = status
        ollamaTesting = false
        // The model list is public on Ollama Cloud, so load it even when the key is missing.
        if status != .unreachable { await loadOllamaModels() }
    }

    static func ollamaStatusText(_ status: OpenAICompatibleLLMService.ConnectionStatus) -> String {
        switch status {
        case .ready: return "Verbonden"
        case .unreachable: return "Niet bereikbaar"
        case .keyMissing: return "Bereikbaar, maar deze server vraagt een API-sleutel"
        case .keyRejected: return "API-sleutel geweigerd door de server"
        }
    }

    /// Fetches the available model list (local Ollama or Ollama Cloud) for the picker.
    func loadOllamaModels() async {
        ollamaModelsLoading = true
        let models = await ollamaService().fetchModels()
        guard !Task.isCancelled else { return }
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
    @AppStorage("notulenProvider") var notulenProvider: String = NotulenProvider.platformDefault.rawValue

    // MARK: - Spraakherkenning (Transcription)

    var spraakherkenningSection: some View {
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
    /// RootView (ThoughtVaultApp) present OnboardingView again; OnboardingView
    /// sets the flag back to true on finish/skip. Essential in local-only mode,
    /// where there is no login window to reach onboarding from.
    var onboardingSection: some View {
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

    var permissiesSection: some View {
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
                title: "Systeemaudio",
                description: "Geluid van videocalls; wordt bij de eerste opname gevraagd",
                status: systemAudioGranted,
                negativeLabel: "Controleer toegang"
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

    private func permissionRow(icon: String, title: String, description: String, status: Bool? = nil, negativeLabel: String = "Geweigerd") -> some View {
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
                    Text(negativeLabel)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.statusError)
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.statusError)
                }
            }
        }
    }

    // MARK: - Agenda (Calendar)

    var agendaSection: some View {
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
            Text("ThoughtVault detecteert Teams-, Zoom- en Meet-vergaderingen en biedt een snelkoppeling om opnames te starten.")
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
                        ? "Verbonden, vergaderingen worden gedetecteerd"
                        : "Geen toegang, vergaderingen worden niet gedetecteerd")
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

    var accountSection: some View {
        Section {
            NavigationLink {
                if authVM.isAuthenticated {
                    AccountView()
                } else {
                    LoginView()
                }
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

    var feedbackSection: some View {
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

    var overSection: some View {
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

    var updatesSection: some View {
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
        if isLocalProcessing {
            profiles = LocalProfileStore.choices()
            return
        }
        let remote = (try? await APIService.shared.getProfiles()) ?? []
        profiles = Profile.currentChoices(remote)
    }

    private func checkServerConnection() async {
        isCheckingServer = true
        defer { isCheckingServer = false }
        // Skip server check entirely in local mode — no server to connect to.
        guard !isLocalProcessing else {
            serverConnected = nil
            return
        }
        do {
            _ = try await APIService.shared.checkMinimumVersion()
            serverConnected = true
        } catch {
            serverConnected = false
        }
    }

    /// Fetches the available WhisperKit models for the dropdown picker.
    func loadWhisperModels() async {
        whisperModelsLoading = true
        defer { whisperModelsLoading = false }
        if let models = await WhisperKitModelDiscovery.fetchRecommendedModels() {
            whisperModels = models
            // Default the selection to the first model when nothing valid is selected yet.
            if whisperModel.isEmpty, let first = models.first {
                whisperModel = first
            }
        }
        // If fetch fails, the text field fallback remains visible (whisperModels stays empty).
    }

    private func checkPermissions() async {
        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micPermissionGranted = micStatus == .authorized

        // Speech recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechPermissionGranted = speechStatus == .authorized

        #if os(macOS)
        systemAudioGranted = PermissionManager.shared.systemAudioGranted
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
