// ProfilesView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Profile management view: list default and custom profiles,
// create, edit, and delete custom profiles.

import SwiftUI

// MARK: - ProfilesView

struct ProfilesView: View {

    @State private var profiles: [Profile] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showCreateSheet: Bool = false
    @State private var profileToEdit: Profile? = nil
    @State private var profileToDelete: Profile? = nil
    @State private var showDeleteConfirm: Bool = false

    var defaultProfiles: [Profile] { profiles.filter { $0.isDefault } }
    var customProfiles: [Profile] { profiles.filter { !$0.isDefault } }

    var body: some View {
        List {
            // Default profiles section
            Section {
                ForEach(defaultProfiles) { profile in
                    profileRow(profile, isDefault: true)
                }
            } header: {
                Text("Standaard profielen")
            } footer: {
                Text("Standaard profielen kunnen niet worden bewerkt of verwijderd.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)
            }

            // Custom profiles section
            Section {
                if customProfiles.isEmpty {
                    HStack {
                        Image(systemName: "plus.circle.dashed")
                            .foregroundStyle(Color.labelTertiary)
                        Text("Nog geen aangepaste profielen. Maak er een aan via de '+' knop.")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .padding(.vertical, TS.Spacing.xs)
                } else {
                    ForEach(customProfiles) { profile in
                        profileRow(profile, isDefault: false)
                    }
                }
            } header: {
                HStack {
                    Text("Aangepaste profielen")
                    Spacer()
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(TS.Font.footnoteMedium)
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Profielen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Nieuw profiel", systemImage: "plus")
                }
            }
        }
        .task { await loadProfiles() }
        .overlay {
            if isLoading {
                ProgressView("Profielen laden...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surfacePrimary.opacity(0.5))
            }
        }
        .alert(
            "Profiel verwijderen?",
            isPresented: $showDeleteConfirm,
            presenting: profileToDelete
        ) { profile in
            Button("Verwijderen", role: .destructive) {
                Task { await deleteProfile(profile) }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { profile in
            Text("Weet je zeker dat je het profiel '\(profile.name)' wilt verwijderen?")
        }
        .sheet(isPresented: $showCreateSheet) {
            ProfileEditSheet(
                existingProfile: nil,
                onSave: { newProfile in
                    Task { await createProfile(newProfile) }
                    showCreateSheet = false
                },
                onCancel: { showCreateSheet = false }
            )
        }
        .sheet(item: $profileToEdit) { profile in
            ProfileEditSheet(
                existingProfile: profile,
                onSave: { updated in
                    // For now treat as create (no update endpoint discovered)
                    Task {
                        await deleteProfile(profile)
                        await createProfile(updated)
                    }
                    profileToEdit = nil
                },
                onCancel: { profileToEdit = nil }
            )
        }
    }

    // MARK: - Profile Row

    private func profileRow(_ profile: Profile, isDefault: Bool) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            // Color dot
            Circle()
                .fill(profileColor(profile))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TS.Spacing.xs) {
                    Text(profile.name)
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.labelPrimary)

                    if isDefault {
                        Text("Standaard")
                            .font(TS.Font.microSemibold)
                            .foregroundStyle(Color.brandSecondary)
                            .padding(.horizontal, TS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.brandSecondary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                Text(profile.systemPrompt)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isDefault {
                HStack(spacing: TS.Spacing.xs) {
                    Button {
                        profileToEdit = profile
                    } label: {
                        Image(systemName: "pencil")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        profileToDelete = profile
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.statusError.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, TS.Spacing.xs)
    }

    private func profileColor(_ profile: Profile) -> Color {
        switch profile.id {
        case "zakelijk":  return Color.brandPrimary
        case "informeel": return Color.brandAccent
        case "technisch": return Color.brandSecondary
        default:          return Color.brandOrange
        }
    }

    // MARK: - Data Operations

    private func loadProfiles() async {
        isLoading = true
        defer { isLoading = false }
        if let remote = try? await APIService.shared.getProfiles() {
            profiles = remote
        } else {
            // Fallback to built-in defaults
            profiles = Profile.defaults
        }
    }

    private func createProfile(_ profile: Profile) async {
        do {
            let created = try await APIService.shared.createProfile(
                name: profile.name,
                systemPrompt: profile.systemPrompt,
                notulePrompt: profile.notulePrompt,
                template: profile.template
            )
            profiles.append(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProfile(_ profile: Profile) async {
        do {
            try await APIService.shared.deleteProfile(id: profile.id)
            profiles.removeAll { $0.id == profile.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ProfileEditSheet

struct ProfileEditSheet: View {

    let existingProfile: Profile?
    let onSave: (Profile) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var systemPrompt: String = ""
    @State private var notulePrompt: String = ""
    @State private var template: String = ""

    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty
        && !notulePrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam van het profiel", text: $name)
                        .font(TS.Font.body)
                } header: {
                    Text("Naam")
                }

                Section {
                    TextEditor(text: $systemPrompt)
                        .font(TS.Font.footnote)
                        .frame(minHeight: 80)
                } header: {
                    Text("Systeemprompt")
                } footer: {
                    Text("Beschrijft de rol en stijl van de AI-notulist.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                Section {
                    TextEditor(text: $notulePrompt)
                        .font(TS.Font.footnote)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notulenprompt")
                } footer: {
                    Text("Instructies voor de inhoud en structuur van de notulen.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                Section {
                    TextEditor(text: $template)
                        .font(TS.Font.footnote)
                        .frame(minHeight: 60)
                } header: {
                    Text("Sjabloon (optioneel)")
                } footer: {
                    Text("Optioneel HTML-sjabloon voor de notulenopmaak.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingProfile == nil ? "Nieuw profiel" : "Profiel bewerken")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        let profile = Profile(
                            id: existingProfile?.id ?? UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespaces),
                            notulePrompt: notulePrompt.trimmingCharacters(in: .whitespaces),
                            template: template.isEmpty ? nil : template.trimmingCharacters(in: .whitespaces),
                            isDefault: false
                        )
                        onSave(profile)
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let profile = existingProfile {
                name = profile.name
                systemPrompt = profile.systemPrompt
                notulePrompt = profile.notulePrompt
                template = profile.template ?? ""
            }
        }
        .frame(minWidth: 460, minHeight: 520)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfilesView()
    }
    .frame(width: 600, height: 500)
}
