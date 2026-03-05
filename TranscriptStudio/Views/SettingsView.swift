// SettingsView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Settings interface organized in Dutch-labeled sections covering connection,
// profiles, transcription preferences, permissions, calendar, account, and feedback.

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(AuthViewModel.self) var authVM
    @Environment(CalendarService.self) var calendarService

    // MARK: - AppStorage

    @AppStorage("serverURL") private var serverURL: String = "https://n8n.prezent.nl"
    @AppStorage("defaultProfile") private var defaultProfile: String = ""
    @AppStorage("preferOnDeviceTranscription") private var preferOnDeviceTranscription: Bool = false
    @AppStorage("biometricLoginEnabled") private var biometricLoginEnabled: Bool = false

    // MARK: - Local State

    @State private var profiles: [Profile] = []
    @State private var isLoadingProfiles: Bool = false
    @State private var serverURLInput: String = ""
    @State private var showServerURLSaved: Bool = false
    @State private var showLogoutConfirm: Bool = false
    @State private var showBugReportSheet: Bool = false

    var body: some View {
        Form {
            verbindingSection
            notulenGeneratieSection
            profielenSection
            spraakherkenningSection
            permissiesSection
            agendaSection
            accountSection
            feedbackSection
            overSection
        }
        .formStyle(.grouped)
        .navigationTitle("Instellingen")
        .onAppear {
            serverURLInput = serverURL
            Task {
                await loadProfiles()
                await checkServerConnection()
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
                    TextField("https://n8n.prezent.nl", text: $serverURLInput)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
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
                        serverURL = serverURLInput
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
                description: "Vereist voor audio-opnames"
            )

            permissionRow(
                icon: "waveform",
                title: "Spraakherkenning",
                description: "Vereist voor on-device transcriptie"
            )

            #if os(macOS)
            permissionRow(
                icon: "rectangle.dashed",
                title: "Schermopname",
                description: "Vereist voor systeemgeluidsopname"
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

    private func permissionRow(icon: String, title: String, description: String) -> some View {
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
        }
    }

    // MARK: - Agenda (Calendar)

    private var agendaSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agenda toegang")
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

            if calendarService.hasCalendarAccess && !calendarService.upcomingMeetings.isEmpty {
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
        } header: {
            Text("Agenda")
        } footer: {
            Text("TranscriptStudio detecteert Teams-, Zoom- en Meet-vergaderingen en biedt een snelkoppeling om opnames te starten.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Biometrisch (Biometric)

    private var biometricSection: some View {
        Section {
            if BiometricService.shared.availableType != .none {
                Toggle(isOn: $biometricLoginEnabled) {
                    let type = BiometricService.shared.availableType
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: type == .faceID ? "faceid" : "touchid")
                            .foregroundStyle(Color.brandPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type == .faceID ? "Face ID inloggen" : "Touch ID inloggen")
                                .font(TS.Font.body)
                            Text("Log in zonder wachtwoord")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                }
                .tint(Color.brandPrimary)
                .onChange(of: biometricLoginEnabled) { _, enabled in
                    BiometricService.shared.isEnabled = enabled
                }
            }
        } header: {
            Text("Beveiliging")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            if let user = authVM.currentUser {
                HStack(spacing: TS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Color.brandPrimary.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Text(String(user.email.prefix(1)).uppercased())
                            .font(TS.Font.headlineBold)
                            .foregroundStyle(Color.brandPrimary)
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
                        Text(role)
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

            // Biometric toggle in account section
            if BiometricService.shared.availableType != .none {
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
                    BiometricService.shared.isEnabled = enabled
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
