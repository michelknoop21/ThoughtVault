// SettingsView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Settings interface organized in Dutch-labeled sections covering connection,
// profiles, transcription preferences, permissions, calendar, account, and feedback.

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

    var body: some View {
        Form {
            verbindingSection
            lokaleVerwerkingSection
            notulenGeneratieSection
            profielenSection
            spraakherkenningSection
            permissiesSection
            agendaSection
            accountSection
            feedbackSection
            overSection
            updatesSection

            #if os(macOS)
            Section {
                YingaFooter()
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("Instellingen")
        .onAppear {
            serverURLInput = serverURL
            Task {
                await loadProfiles()
                await checkServerConnection()
                await checkPermissions()
                if isLocalProcessing { await loadOllamaModels() }
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

    // MARK: - Verbinding (Connection)

    @State private var isCheckingServer: Bool = false
    @State private var serverConnected: Bool? = nil

    private var verbindingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Server URL")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)

                HStack {
                    TextField("https://n8n.prezent.nl/tstudio/api", text: $serverURLInput)
                        .textFieldStyle(.plain)
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
            .padding(.vertical, TS.Spacing.xs)

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
    @AppStorage("ollamaApiKey") private var ollamaApiKey: String = ""

    @State private var ollamaTesting: Bool = false
    @State private var ollamaConnected: Bool? = nil
    @State private var ollamaModels: [String] = []
    @State private var ollamaModelsLoading: Bool = false

    private var isLocalProcessing: Bool {
        (ProcessingMode(rawValue: processingMode) ?? .local) == .local
    }

    private var lokaleVerwerkingSection: some View {
        Section {
            Picker("Verwerking", selection: $processingMode) {
                Label("Lokaal (geen server)", systemImage: "cpu")
                    .tag(ProcessingMode.local.rawValue)
                Label("Cloud (server)", systemImage: "cloud.fill")
                    .tag(ProcessingMode.cloud.rawValue)
            }
            .font(TS.Font.body)

            if isLocalProcessing {
                // Transcription engine
                Picker("Transcriptie", selection: $localTranscriber) {
                    ForEach(LocalTranscriberEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }
                .font(TS.Font.body)

                if localTranscriber == LocalTranscriberEngine.whisperKit.rawValue {
                    LabeledContent("Whisper-model") {
                        TextField("model", text: $whisperModel)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(TS.Font.bodyMonospaced)
                    }
                }

                // Ollama configuration
                LabeledContent("Ollama URL") {
                    TextField("http://localhost:11434", text: $ollamaURL)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(TS.Font.bodyMonospaced)
                        .autocorrectionDisabled()
                }
                // Model: dynamic picker when models are loaded, manual entry otherwise.
                if ollamaModels.isEmpty {
                    LabeledContent("Ollama model") {
                        TextField("llama3.2", text: $ollamaModel)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(TS.Font.bodyMonospaced)
                            .autocorrectionDisabled()
                    }
                } else {
                    Picker("Ollama model", selection: $ollamaModel) {
                        // Keep the saved value selectable even if it is not in the fetched list.
                        if !ollamaModels.contains(ollamaModel) && !ollamaModel.isEmpty {
                            Text(ollamaModel).tag(ollamaModel)
                        }
                        ForEach(ollamaModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .font(TS.Font.body)
                }

                HStack(spacing: TS.Spacing.sm) {
                    Button {
                        Task { await loadOllamaModels() }
                    } label: {
                        if ollamaModelsLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Modellen laden", systemImage: "arrow.triangle.2.circlepath")
                                .font(TS.Font.footnoteSemibold)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(ollamaModelsLoading)

                    if !ollamaModels.isEmpty {
                        Text("\(ollamaModels.count) beschikbaar")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                LabeledContent("API-sleutel") {
                    SecureField("leeg = lokaal", text: $ollamaApiKey)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(TS.Font.bodyMonospaced)
                }

                HStack(spacing: TS.Spacing.sm) {
                    Button {
                        Task { await testOllamaConnection() }
                    } label: {
                        if ollamaTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Verbinding testen")
                                .font(TS.Font.footnoteSemibold)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(ollamaTesting)

                    if let connected = ollamaConnected {
                        Label(
                            connected ? "Verbonden" : "Niet bereikbaar",
                            systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(TS.Font.footnote)
                        .foregroundStyle(connected ? Color.statusSuccess : Color.statusError)
                    }
                }
            }
        } header: {
            Text("Lokale verwerking")
        } footer: {
            Text(isLocalProcessing
                 ? "Alles draait lokaal: transcriptie via \(localTranscriber == LocalTranscriberEngine.whisperKit.rawValue ? "WhisperKit" : "Apple Spraakherkenning") en notulen via Ollama. Vul een API-sleutel in om Ollama Cloud (https://ollama.com) te gebruiken."
                 : "De server verzorgt transcriptie en notulen. Zet op 'Lokaal' om zonder server te werken.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
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

    @AppStorage("notulenProvider") private var notulenProvider: String = NotulenProvider.cloud.rawValue

    private var notulenGeneratieSection: some View {
        Section {
            // AI Provider picker
            Picker("AI-provider", selection: $notulenProvider) {
                Label("Cloud (Server)", systemImage: "cloud.fill")
                    .tag(NotulenProvider.cloud.rawValue)
                Label("Ollama", systemImage: "server.rack")
                    .tag(NotulenProvider.ollama.rawValue)
                Label("LM Studio", systemImage: "desktopcomputer")
                    .tag(NotulenProvider.lmStudio.rawValue)
                Label("Apple Intelligence", systemImage: "apple.logo")
                    .tag(NotulenProvider.appleIntelligence.rawValue)
            }
            .font(TS.Font.body)

            // Eigen profielen link
            NavigationLink {
                ProfilesView()
            } label: {
                Label("Eigen profielen beheren", systemImage: "person.text.rectangle")
                    .font(TS.Font.body)
            }
        } header: {
            Text("Notulen generatie")
        } footer: {
            Text(notulenProviderDescription)
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    private var notulenProviderDescription: String {
        switch NotulenProvider(rawValue: notulenProvider) ?? .cloud {
        case .cloud: return "Notulen worden gegenereerd via de server (N8N + Claude)."
        case .ollama: return "Notulen worden lokaal gegenereerd via Ollama."
        case .lmStudio: return "Notulen worden lokaal gegenereerd via LM Studio."
        case .appleIntelligence: return "Notulen worden gegenereerd met Apple Intelligence op dit apparaat."
        }
    }

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
                    Text("Systeeminstell. openen")
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
                                .fill(Color.brandSecondary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Text(String((user.name ?? user.email).prefix(1)).uppercased())
                                .font(TS.Font.headlineBold)
                                .foregroundStyle(Color.brandSecondary)
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
                                .background(Color.brandPrimary.opacity(0.10))
                                .foregroundStyle(Color.brandPrimary)
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

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthViewModel())
            .environment(CalendarService.shared)
    }
    .frame(width: 500, height: 700)
}
