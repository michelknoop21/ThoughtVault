// AccountView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Account management view with user info, GDPR data export,
// account deletion, and logout functionality.

import SwiftUI

// MARK: - AccountView

struct AccountView: View {

    @Environment(AuthViewModel.self) var authVM

    @State private var showDeleteAccountConfirm: Bool = false
    @State private var showDeleteConfirmStep2: Bool = false
    @State private var deleteConfirmText: String = ""
    @State private var showLogoutConfirm: Bool = false
    @State private var isExportingData: Bool = false
    @State private var exportSuccessMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var isDeletingAccount: Bool = false

    private let requiredDeleteText = "VERWIJDER"

    var body: some View {
        List {
            profileSection
            gdprSection
            dangerZoneSection
        }
        .listStyle(.inset)
        .navigationTitle("Account")
        .alert(
            "Uitloggen",
            isPresented: $showLogoutConfirm
        ) {
            Button("Uitloggen", role: .destructive) { authVM.logout() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Weet je zeker dat je wilt uitloggen?")
        }
        .sheet(isPresented: $showDeleteAccountConfirm) {
            deleteAccountSheet
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
                                    colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        Text(String(user.email.prefix(1)).uppercased())
                            .font(TS.Font.title3Bold)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let name = user.name, !name.isEmpty {
                            Text(name)
                                .font(TS.Font.headlineBold)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        Text(user.email)
                            .font(TS.Font.body)
                            .foregroundStyle(Color.labelSecondary)
                        if let role = user.role {
                            Text(role.capitalized)
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

            Button {
                showLogoutConfirm = true
            } label: {
                Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(Color.statusError)
                    .font(TS.Font.bodyMedium)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Gebruiker")
        }
    }

    // MARK: - GDPR Section

    private var gdprSection: some View {
        Section {
            // Data export
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
            Button {
                showDeleteAccountConfirm = true
            } label: {
                HStack {
                    Label("Account verwijderen", systemImage: "trash.fill")
                        .foregroundStyle(Color.statusError)
                        .font(TS.Font.bodyMedium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Gevarenzone")
        } footer: {
            Text("Accountverwijdering is permanent en kan niet ongedaan worden gemaakt. Al je transcripties en gegevens worden definitief verwijderd.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - Delete Account Sheet

    private var deleteAccountSheet: some View {
        NavigationStack {
            VStack(spacing: TS.Spacing.xl) {
                Spacer()

                // Warning icon
                ZStack {
                    Circle()
                        .fill(Color.statusError.opacity(0.10))
                        .frame(width: 80, height: 80)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.statusError)
                }

                VStack(spacing: TS.Spacing.sm) {
                    Text("Account definitief verwijderen")
                        .font(TS.Font.title3Bold)
                        .foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.center)

                    Text("Deze actie is onomkeerbaar. Al je transcripties, profielen en account­gegevens worden permanent verwijderd.")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TS.Spacing.lg)
                }

                // Confirmation input
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    Text("Typ **\(requiredDeleteText)** om te bevestigen:")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelSecondary)

                    TextField(requiredDeleteText, text: $deleteConfirmText)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .padding(TS.Spacing.sm + 2)
                        .background(Color.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                        .overlay {
                            RoundedRectangle(cornerRadius: TS.Radius.sm)
                                .stroke(
                                    deleteConfirmText == requiredDeleteText
                                        ? Color.statusError.opacity(0.5)
                                        : Color.borderPrimary,
                                    lineWidth: 1
                                )
                        }
                }
                .padding(.horizontal, TS.Spacing.xl)

                // Delete button
                Button {
                    Task { await deleteAccount() }
                } label: {
                    Group {
                        if isDeletingAccount {
                            HStack(spacing: TS.Spacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                                Text("Verwijderen...")
                            }
                        } else {
                            Text("Account definitief verwijderen")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: true))
                .disabled(deleteConfirmText != requiredDeleteText || isDeletingAccount)
                .padding(.horizontal, TS.Spacing.xl)

                Spacer()
            }
            .navigationTitle("Account verwijderen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") {
                        deleteConfirmText = ""
                        showDeleteAccountConfirm = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 520)
    }

    // MARK: - Data Export

    private func exportUserData() async {
        isExportingData = true
        exportSuccessMessage = nil
        errorMessage = nil

        // Give the user feedback that the export is happening.
        // In a real implementation this would call an API endpoint.
        do {
            try await Task.sleep(nanoseconds: 1_500_000_000)

            // Build a simple JSON export of available local data
            let exportData: [String: Any] = [
                "export_date": ISO8601DateFormatter().string(from: Date()),
                "email": authVM.currentUser?.email ?? authVM.userEmail,
                "name": authVM.currentUser?.name ?? "",
                "note": "Neem contact op met support@prezent.nl voor een volledig GDPR data-export inclusief alle transcripties."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "transcriptstudio_gegevens.json"
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url {
                    try jsonData.write(to: url)
                    exportSuccessMessage = "Gegevens opgeslagen als \(url.lastPathComponent)"
                }
            }
        } catch {
            errorMessage = "Export mislukt: \(error.localizedDescription)"
        }

        isExportingData = false

        // Clear success message after delay
        if exportSuccessMessage != nil {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { exportSuccessMessage = nil }
            }
        }
    }

    // MARK: - Account Deletion

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        // In a production implementation this calls DELETE /tstudio/api/account
        // For now simulate the operation and log out.
        do {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            // await APIService.shared.deleteAccount()
            await MainActor.run {
                showDeleteAccountConfirm = false
                authVM.logout()
            }
        } catch {
            errorMessage = "Verwijderen mislukt: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthViewModel())
    }
    .frame(width: 500, height: 600)
}
