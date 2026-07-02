// AccountView.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Account management view with profile editing, password change,
// 2FA management, GDPR data export, and logout functionality.

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - AccountView

struct AccountView: View {

    @Environment(AuthViewModel.self) var authVM

    // Name editing
    @State private var isEditingName: Bool = false
    @State private var editName: String = ""

    // Password change
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isChangingPassword: Bool = false
    @State private var passwordMessage: (text: String, isError: Bool)? = nil

    // 2FA
    @State private var twoFAStatus: TwoFAStatus? = nil
    @State private var isLoading2FA: Bool = false
    @State private var setupData: TwoFASetupResponse? = nil
    @State private var verifyCode: String = ""
    @State private var backupCodes: [String]? = nil
    @State private var showDisableForm: Bool = false
    @State private var disablePassword: String = ""
    @State private var twoFAMessage: (text: String, isError: Bool)? = nil

    // GDPR
    @State private var isExportingData: Bool = false
    @State private var exportSuccessMessage: String? = nil

    // General
    @State private var showLogoutConfirm: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            profileSection
            passwordSection
            twoFASection
            gdprSection
            dangerZoneSection
            logoutSection
        }
        .listStyle(.inset)
        .navigationTitle("Account")
        .task {
            await load2FAStatus()
        }
        .alert(
            "Uitloggen",
            isPresented: $showLogoutConfirm
        ) {
            Button("Uitloggen", role: .destructive) { authVM.logout() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Weet je zeker dat je wilt uitloggen?")
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            if let user = authVM.currentUser {
                HStack(spacing: TS.Spacing.md) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.brandSecondary, Color.brandSecondary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        Text(String((user.name ?? user.email).prefix(1)).uppercased())
                            .font(TS.Font.title3Bold)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if isEditingName {
                            HStack(spacing: 8) {
                                TextField("Je volledige naam", text: $editName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(TS.Font.body)
                                    .onSubmit { saveNameAction() }

                                Button {
                                    saveNameAction()
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.brandPrimary)
                                .controlSize(.small)

                                Button {
                                    isEditingName = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            HStack(spacing: 6) {
                                if let name = user.name, !name.isEmpty {
                                    Text(name)
                                        .font(TS.Font.headlineBold)
                                        .foregroundStyle(Color.labelPrimary)
                                } else {
                                    Text("Naam niet ingesteld")
                                        .font(TS.Font.headlineBold)
                                        .foregroundStyle(Color.labelTertiary)
                                        .italic()
                                }

                                Button {
                                    editName = user.name ?? ""
                                    isEditingName = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.labelSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(user.email)
                            .font(TS.Font.body)
                            .foregroundStyle(Color.labelSecondary)

                        if let role = user.role {
                            Text(role == "admin" ? "Admin" : "Gebruiker")
                                .font(TS.Font.microSemibold)
                                .foregroundStyle(Color.brandPrimary)
                                .padding(.horizontal, TS.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Color.brandPrimary.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, TS.Spacing.xs)
            } else {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.labelTertiary)
                    Text(authVM.userEmail.isEmpty ? "Niet ingelogd" : authVM.userEmail)
                        .font(TS.Font.body)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        } header: {
            Text("Profiel")
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                SecureField("Huidig wachtwoord", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Nieuw wachtwoord", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Bevestig nieuw wachtwoord", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)

                if let msg = passwordMessage {
                    HStack(spacing: 6) {
                        Image(systemName: msg.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(msg.isError ? Color.statusError : Color.statusSuccess)
                        Text(msg.text)
                            .font(TS.Font.footnote)
                            .foregroundStyle(msg.isError ? Color.statusError : Color.statusSuccess)
                    }
                }

                Button {
                    Task { await changePassword() }
                } label: {
                    if isChangingPassword {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Wachtwoord wijzigen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .controlSize(.small)
                .disabled(isChangingPassword || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
            }
            .padding(.vertical, TS.Spacing.xs)
        } header: {
            Text("Wachtwoord wijzigen")
        }
    }

    // MARK: - 2FA Section

    private var twoFASection: some View {
        Section {
            // Status row
            HStack {
                Image(systemName: twoFAStatus?.enabled == true ? "shield.checkered" : "shield")
                    .foregroundStyle(twoFAStatus?.enabled == true ? Color.statusSuccess : Color.labelTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Twee-factor authenticatie")
                        .font(TS.Font.bodyMedium)
                    Text(twoFAStatusText)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                if twoFAStatus?.enabled == true {
                    Text("Actief")
                        .font(TS.Font.microSemibold)
                        .foregroundStyle(Color.statusSuccess)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.statusSuccess.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            // 2FA not enabled — setup button or flow
            if let status = twoFAStatus, !status.enabled, setupData == nil {
                Button {
                    Task { await startSetup2FA() }
                } label: {
                    if isLoading2FA {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("2FA activeren", systemImage: "lock.shield")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .controlSize(.small)
                .disabled(isLoading2FA)
            }

            // QR code setup step
            if let setup = setupData, backupCodes == nil {
                twoFASetupView(setup: setup)
            }

            // Backup codes display
            if let codes = backupCodes {
                backupCodesView(codes: codes)
            }

            // 2FA enabled — disable + regenerate
            if twoFAStatus?.enabled == true, backupCodes == nil, setupData == nil {
                twoFAEnabledActions
            }

            if let msg = twoFAMessage {
                HStack(spacing: 6) {
                    Image(systemName: msg.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(msg.isError ? Color.statusError : Color.statusSuccess)
                    Text(msg.text)
                        .font(TS.Font.footnote)
                        .foregroundStyle(msg.isError ? Color.statusError : Color.statusSuccess)
                }
            }
        } header: {
            Text("Beveiliging")
        }
    }

    private var twoFAStatusText: String {
        guard let status = twoFAStatus else { return "Status laden..." }
        if status.enabled {
            if let remaining = status.backupCodesRemaining {
                return "Actief — \(remaining) backup codes resterend"
            }
            return "Actief"
        }
        return "Niet geactiveerd"
    }

    private func twoFASetupView(setup: TwoFASetupResponse) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("Scan de QR-code met je authenticator app (bijv. Google Authenticator, Authy):")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)

            if let imageData = Data(base64Encoded: setup.qrCode.replacingOccurrences(of: "data:image/png;base64,", with: "")),
               let nsImage = platformImage(from: imageData) {
                HStack {
                    Spacer()
                    Image(platformImage: nsImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Of voer deze code handmatig in:")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                Text(setup.secret)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(TS.Spacing.sm)
                    .background(Color.labelPrimary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Verificatiecode (6 cijfers)")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                HStack(spacing: 8) {
                    TextField("000000", text: $verifyCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                        .font(.system(size: 16, design: .monospaced))
                        #if os(macOS)
                        .multilineTextAlignment(.center)
                        #endif
                        .onChange(of: verifyCode) { _, newValue in
                            verifyCode = String(newValue.filter(\.isNumber).prefix(6))
                        }

                    Button {
                        Task { await verify2FASetup() }
                    } label: {
                        if isLoading2FA {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Verifiëren")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandPrimary)
                    .controlSize(.small)
                    .disabled(isLoading2FA || verifyCode.count != 6)

                    Button("Annuleren") {
                        setupData = nil
                        verifyCode = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func backupCodesView(codes: [String]) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusWarning)
                Text("Bewaar deze backup codes op een veilige plek.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.statusWarning)
            }

            Text("Ze kunnen elk eenmalig worden gebruikt om in te loggen als je geen toegang hebt tot je authenticator app.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(TS.Spacing.sm)
            .background(Color.labelPrimary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Begrepen, sluiten") {
                backupCodes = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var twoFAEnabledActions: some View {
        Group {
            if showDisableForm {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    Text("Wachtwoord ter bevestiging")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)
                    SecureField("Wachtwoord", text: $disablePassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)

                    HStack(spacing: 8) {
                        Button {
                            Task { await disable2FA() }
                        } label: {
                            if isLoading2FA {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Bevestigen")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(Color.statusError)
                        .disabled(isLoading2FA || disablePassword.isEmpty)

                        Button("Annuleren") {
                            showDisableForm = false
                            disablePassword = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button("2FA deactiveren") {
                        showDisableForm = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(Color.statusError)

                    Button {
                        Task { await regenerateBackupCodes() }
                    } label: {
                        if isLoading2FA {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Backup codes opnieuw genereren")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoading2FA)
                }
            }
        }
    }

    // MARK: - GDPR Section

    private var gdprSection: some View {
        Section {
            Button {
                Task { await exportUserData() }
            } label: {
                HStack {
                    if isExportingData {
                        ProgressView()
                            .controlSize(.small)
                        Text("Gegevens exporteren...")
                            .font(TS.Font.body)
                            .foregroundStyle(Color.labelPrimary)
                    } else {
                        Label("Gegevens exporteren (GDPR)", systemImage: "square.and.arrow.down")
                            .font(TS.Font.body)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    Spacer()
                    Image(systemName: "arrow.down.doc")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isExportingData)

            if let successMessage = exportSuccessMessage {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusSuccess)
                    Text(successMessage)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.statusSuccess)
                }
            }

            if let error = errorMessage {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusError)
                    Text(error)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.statusError)
                }
            }
        } header: {
            Text("Privacy & Gegevens")
        } footer: {
            Text("Op grond van de AVG (GDPR) heb je het recht al je opgeslagen gegevens op te vragen of te laten verwijderen.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Link(destination: URL(string: "mailto:support@prezent.nl?subject=GDPR%20Account%20Verwijdering%20TranscriptStudio")!) {
                HStack {
                    Label("Account verwijderen via support", systemImage: "envelope.fill")
                        .foregroundStyle(Color.statusError)
                        .font(TS.Font.bodyMedium)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Gevarenzone")
        } footer: {
            Text("Om je account en alle gegevens te verwijderen, neem contact op met support@prezent.nl. We verwerken je verzoek binnen 30 dagen conform de AVG.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Logout Section

    private var logoutSection: some View {
        Section {
            Button {
                showLogoutConfirm = true
            } label: {
                Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(Color.statusError)
                    .font(TS.Font.bodyMedium)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Sessie")
        }
    }

    // MARK: - Actions

    private func saveNameAction() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingName = false
            return
        }
        Task {
            do {
                try await APIService.shared.updateUserName(trimmed)
                let userInfo = try? await APIService.shared.getCurrentUser()
                authVM.currentUser = userInfo
                isEditingName = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func changePassword() async {
        passwordMessage = nil

        if newPassword != confirmPassword {
            passwordMessage = ("Wachtwoorden komen niet overeen", true)
            return
        }
        if newPassword.count < 8 {
            passwordMessage = ("Wachtwoord moet minimaal 8 tekens bevatten", true)
            return
        }

        isChangingPassword = true
        do {
            try await APIService.shared.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            passwordMessage = ("Wachtwoord succesvol gewijzigd", false)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            passwordMessage = (error.localizedDescription, true)
        }
        isChangingPassword = false
    }

    private func load2FAStatus() async {
        do {
            twoFAStatus = try await APIService.shared.get2FAStatus()
        } catch {
            // Silently fail — status will show as unknown
        }
    }

    private func startSetup2FA() async {
        isLoading2FA = true
        twoFAMessage = nil
        do {
            setupData = try await APIService.shared.setup2FA()
            verifyCode = ""
            backupCodes = nil
        } catch {
            twoFAMessage = (error.localizedDescription, true)
        }
        isLoading2FA = false
    }

    private func verify2FASetup() async {
        guard verifyCode.count == 6 else { return }
        isLoading2FA = true
        twoFAMessage = nil
        do {
            let result = try await APIService.shared.verify2FASetup(code: verifyCode)
            backupCodes = result.backupCodes
            setupData = nil
            twoFAStatus = TwoFAStatus(enabled: true, backupCodesRemaining: result.backupCodes.count)
            twoFAMessage = ("Twee-factor authenticatie geactiveerd", false)
        } catch {
            twoFAMessage = (error.localizedDescription, true)
        }
        isLoading2FA = false
    }

    private func disable2FA() async {
        guard !disablePassword.isEmpty else { return }
        isLoading2FA = true
        twoFAMessage = nil
        do {
            try await APIService.shared.disable2FA(password: disablePassword)
            twoFAStatus = TwoFAStatus(enabled: false, backupCodesRemaining: nil)
            showDisableForm = false
            disablePassword = ""
            backupCodes = nil
            twoFAMessage = ("Twee-factor authenticatie uitgeschakeld", false)
        } catch {
            twoFAMessage = (error.localizedDescription, true)
        }
        isLoading2FA = false
    }

    private func regenerateBackupCodes() async {
        isLoading2FA = true
        twoFAMessage = nil
        do {
            let result = try await APIService.shared.regenerateBackupCodes()
            backupCodes = result.backupCodes
            twoFAStatus = TwoFAStatus(enabled: true, backupCodesRemaining: result.backupCodes.count)
            twoFAMessage = ("Backup codes opnieuw gegenereerd", false)
        } catch {
            twoFAMessage = (error.localizedDescription, true)
        }
        isLoading2FA = false
    }

    // MARK: - Data Export

    private func exportUserData() async {
        isExportingData = true
        exportSuccessMessage = nil
        errorMessage = nil

        do {
            let isoFormatter = ISO8601DateFormatter()
            let transcripts = LocalTranscriptStore.shared.allTranscripts()

            // Real export: every locally stored transcript + its generated minutes.
            let transcriptDicts: [[String: Any]] = transcripts.map { t in
                var d: [String: Any] = [
                    "task_id": t.taskId,
                    "title": t.title,
                    "date": isoFormatter.string(from: t.date),
                    "tags": t.tags
                ]
                if let raw = t.rawTranscription { d["raw_transcription"] = raw }
                if let html = t.notuleHtml { d["notule_html"] = html }
                if let profile = t.profileName { d["profile_name"] = profile }
                if let duration = t.duration { d["duration_seconds"] = duration }
                return d
            }

            let exportData: [String: Any] = [
                "export_date": isoFormatter.string(from: Date()),
                "account": [
                    "email": authVM.currentUser?.email ?? authVM.userEmail,
                    "name": authVM.currentUser?.name ?? ""
                ],
                "transcript_count": transcripts.count,
                "transcripts": transcriptDicts,
                "note": "Bevat alle lokaal opgeslagen transcripties en notulen. Voor eventuele server-side verwerkingsdata: support@prezent.nl."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) {
                #if os(macOS)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "transcriptstudio_gegevens.json"
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url {
                    try jsonData.write(to: url)
                    exportSuccessMessage = "Gegevens opgeslagen als \(url.lastPathComponent)"
                }
                #else
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("transcriptstudio_gegevens.json")
                try jsonData.write(to: tempURL)
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    rootVC.present(activityVC, animated: true)
                }
                exportSuccessMessage = "Gegevens klaar om te delen"
                #endif
            }
        } catch {
            errorMessage = "Export mislukt: \(error.localizedDescription)"
        }

        isExportingData = false

        if exportSuccessMessage != nil {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { exportSuccessMessage = nil }
            }
        }
    }

    // MARK: - Platform Image Helpers

    #if os(macOS)
    private func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }
    #else
    private func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
    #endif
}

// MARK: - Platform Image Extension

#if os(macOS)
private extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
private extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthViewModel())
    }
    .frame(width: 500, height: 700)
}
