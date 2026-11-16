// ProfilesView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Profile management view: list default and custom profiles,
// create, edit, and delete custom profiles.

import SwiftUI

// MARK: - ProfilesView

struct ProfilesView: View {

    @Environment(RecordingViewModel.self) var recordingVM

    @State var profiles: [Profile] = []
    @State var isLoading: Bool = false
    @State var errorMessage: String? = nil
    @State var showCreateSheet: Bool = false
    @State var profileToEdit: Profile? = nil
    @State var profileToDelete: Profile? = nil
    @State var showDeleteConfirm: Bool = false

    var defaultProfiles: [Profile] { profiles.filter { $0.isDefault == true } }
    var customProfiles: [Profile] { profiles.filter { $0.isDefault != true } }

    var body: some View {
        Group {
#if os(iOS)
        iosBody
#else
        ScrollView {
            VStack(spacing: TS.Spacing.lg) {
                // Default profiles section
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    sectionHeader("Standaard profielen", icon: "star.fill", color: .brandSecondary)

                    VStack(spacing: TS.Spacing.sm) {
                        ForEach(defaultProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isDefault: true,
                                onEdit: nil,
                                onDelete: nil
                            )
                        }
                    }

                    Text("Standaard profielen kunnen niet worden bewerkt of verwijderd.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.horizontal, TS.Spacing.xs)
                }

                // Custom profiles section
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    HStack {
                        sectionHeader("Aangepaste profielen", icon: "slider.horizontal.3", color: .brandPrimary)
                        Spacer()
                        Button {
                            showCreateSheet = true
                        } label: {
                            HStack(spacing: TS.Spacing.xs) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Nieuw")
                                    .font(TS.Font.captionSemibold)
                            }
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, TS.Spacing.sm + 2)
                            .padding(.vertical, TS.Spacing.xs + 1)
                            .background(Color.brandPrimary.opacity(0.10))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if customProfiles.isEmpty {
                        emptyCustomState
                    } else {
                        VStack(spacing: TS.Spacing.sm) {
                            ForEach(customProfiles) { profile in
                                ProfileCard(
                                    profile: profile,
                                    isDefault: false,
                                    onEdit: { profileToEdit = profile },
                                    onDelete: {
                                        profileToDelete = profile
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(TS.Spacing.lg)
        }
        .background(Color.surfaceSecondary.opacity(0.5))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Nieuw profiel", systemImage: "plus")
                }
            }
        }
#endif
        }
        .navigationTitle("Profielen")
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
                    try await createProfile(newProfile)
                    showCreateSheet = false
                },
                onCancel: { showCreateSheet = false }
            )
        }
        .sheet(item: $profileToEdit) { profile in
            ProfileEditSheet(
                existingProfile: profile,
                onSave: { updated in
                    try await replaceProfile(original: profile, with: updated)
                    profileToEdit = nil
                },
                onCancel: { profileToEdit = nil }
            )
        }
        .alert(
            "Er ging iets mis",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("Oké", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(TS.Font.headline)
                .foregroundStyle(Color.labelPrimary)
        }
        .padding(.horizontal, TS.Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyCustomState: some View {
        VStack(spacing: TS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.brandPrimary.opacity(0.6))
            }

            VStack(spacing: TS.Spacing.xs) {
                Text("Geen aangepaste profielen")
                    .font(TS.Font.bodyMedium)
                    .foregroundStyle(Color.labelPrimary)
                Text("Maak een profiel aan om notulen in een eigen stijl te genereren.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showCreateSheet = true
            } label: {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Profiel aanmaken")
                        .font(TS.Font.footnoteSemibold)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TS.Spacing.xl)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfacePrimary.opacity(0.5))
                .strokeBorder(Color.borderPrimary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
    }

    // MARK: - Data Operations

    private func loadProfiles() async {
        isLoading = true
        defer { isLoading = false }
        if ProcessingMode.isLocalMode {
            profiles = LocalProfileStore.choices()
        } else if let remote = try? await APIService.shared.getProfiles() {
            profiles = Profile.currentChoices(remote)
        } else {
            profiles = Profile.defaults
        }
    }

    private func createProfile(_ profile: Profile) async throws {
        if ProcessingMode.isLocalMode {
            try LocalProfileStore.save(profile)
        } else {
            _ = try await APIService.shared.createProfile(
                name: profile.name,
                systemPrompt: profile.systemPrompt ?? "",
                notulePrompt: profile.notulePrompt ?? "",
                template: profile.template
            )
        }
        await loadProfiles()
        await recordingVM.reloadProfiles()
    }

    private func deleteProfile(_ profile: Profile) async {
        do {
            if ProcessingMode.isLocalMode {
                try LocalProfileStore.delete(id: profile.id)
            } else {
                try await APIService.shared.deleteProfile(id: profile.id)
            }
            await loadProfiles()
            await recordingVM.reloadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceProfile(original: Profile, with updated: Profile) async throws {
        if ProcessingMode.isLocalMode {
            try LocalProfileStore.save(updated)
        } else {
            // The backend's update endpoint keeps the same ID, including in old documents.
            try await APIService.shared.updateProfile(updated)
        }
        await loadProfiles()
        await recordingVM.reloadProfiles()
    }

}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfilesView()
    }
    .frame(width: 600, height: 500)
}
