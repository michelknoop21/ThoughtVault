// ProfileSettingsView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Settings section for viewing and editing the user's self-profile (PersonProfile singleton).
// Distinct from the notule-Profielen section (D-08).

import SwiftUI

// MARK: - ProfileSettingsView

struct ProfileSettingsView: View {

    // MARK: - State

    @State private var naam: String = ""
    @State private var rol: String = ""
    @State private var organisatie: String = ""
    @State private var aliassen: String = ""
    @State private var meetingTypes: String = ""
    @State private var expertise: String = ""

    @State private var isSaving: Bool = false
    @State private var showSaved: Bool = false
    @State private var saveError: String? = nil

    // MARK: - Body

    var body: some View {
        Section {
            profileContent
        } header: {
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text("Profiel")
                Text("Over jou")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .onAppear {
            loadProfile()
        }
    }

    // MARK: - Profile Content

    @ViewBuilder
    private var profileContent: some View {
        if naam.isEmpty && rol.isEmpty && organisatie.isEmpty && aliassen.isEmpty && meetingTypes.isEmpty && expertise.isEmpty {
            emptyState
        } else {
            formFields
        }
        saveButton
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("Geen profiel ingevuld")
                .font(TS.Font.bodyMedium)
                .foregroundStyle(Color.labelPrimary)
            Text("Vul je naam, rol en organisatie in zodat TranscriptStudio actiepunten aan jou kan koppelen.")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
            formFields
        }
    }

    // MARK: - Form Fields

    private var formFields: some View {
        // Label-above rows (SettingFieldRow) keep these fields full-width and
        // aligned with every other Instellingen tab.
        VStack(spacing: TS.Spacing.sm) {
            SettingFieldRow("Naam") {
                TextField("Naam", text: $naam)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Rol / Functie") {
                TextField("Rol / Functie", text: $rol)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Organisatie") {
                TextField("Organisatie", text: $organisatie)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Hoe noemen collega's jou?", hint: "Meerdere kommagescheiden") {
                TextField("Michel, Knoop, MK", text: $aliassen)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Typische vergadertypen", hint: "Meerdere kommagescheiden") {
                TextField("Wekelijks overleg, Klantgesprek", text: $meetingTypes)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }

            SettingFieldRow("Expertise / onderwerpen", hint: "Meerdere kommagescheiden") {
                TextField("grafisch ontwerp, marketing, IT", text: $expertise)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            if let error = saveError {
                Text(error)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusError)
            }

            HStack {
                Button {
                    saveProfile()
                } label: {
                    if isSaving {
                        HStack(spacing: TS.Spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Profiel opslaan")
                        }
                    } else if showSaved {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "checkmark")
                            Text("Opgeslagen")
                        }
                    } else {
                        Text("Profiel opslaan")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Load

    private func loadProfile() {
        guard let profile = LocalTranscriptStore.shared.fetchSelfProfile() else { return }
        naam = profile.name
        rol = profile.role
        organisatie = profile.organization
        aliassen = profile.aliases.joined(separator: ", ")
        meetingTypes = profile.meetingTypes.joined(separator: ", ")
        expertise = profile.expertiseTags.joined(separator: ", ")
    }

    // MARK: - Save

    private func saveProfile() {
        isSaving = true
        saveError = nil

        let splitAndTrim: (String) -> [String] = { input in
            input.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        do {
            try LocalTranscriptStore.shared.upsertSelfProfile(
                name: naam.trimmingCharacters(in: .whitespacesAndNewlines),
                role: rol.trimmingCharacters(in: .whitespacesAndNewlines),
                organization: organisatie.trimmingCharacters(in: .whitespacesAndNewlines),
                aliases: splitAndTrim(aliassen),
                meetingTypes: splitAndTrim(meetingTypes),
                expertiseTags: splitAndTrim(expertise)
            )
            isSaving = false
            showSaved = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    showSaved = false
                }
            }
        } catch {
            isSaving = false
            saveError = "Kon profiel niet opslaan. Probeer het opnieuw."
        }
    }
}
