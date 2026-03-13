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

    var defaultProfiles: [Profile] { profiles.filter { $0.isDefault == true } }
    var customProfiles: [Profile] { profiles.filter { $0.isDefault != true } }

    var body: some View {
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

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
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
        if let remote = try? await APIService.shared.getProfiles() {
            profiles = remote
        } else {
            profiles = Profile.defaults
        }
    }

    private func createProfile(_ profile: Profile) async {
        do {
            let created = try await APIService.shared.createProfile(
                name: profile.name,
                systemPrompt: profile.systemPrompt ?? "",
                notulePrompt: profile.notulePrompt ?? "",
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

// MARK: - Profile Card

private struct ProfileCard: View {
    let profile: Profile
    let isDefault: Bool
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var isHovered = false

    private var iconName: String {
        profile.icon ?? profileIcon(for: profile.id)
    }

    private var accentColor: Color {
        profileAccent(for: profile.id)
    }

    var body: some View {
        HStack(spacing: TS.Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accentColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TS.Spacing.sm) {
                    Text(profile.name)
                        .font(TS.Font.bodySemibold)
                        .foregroundStyle(Color.labelPrimary)

                    if isDefault {
                        Text("Standaard")
                            .font(TS.Font.microSemibold)
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, TS.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                Text(profile.description ?? profile.systemPrompt ?? "")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Actions
            if !isDefault {
                HStack(spacing: TS.Spacing.xs) {
                    actionButton(icon: "pencil", color: .labelSecondary) {
                        onEdit?()
                    }
                    actionButton(icon: "trash", color: .statusError.opacity(0.7)) {
                        onDelete?()
                    }
                }
                .opacity(isHovered ? 1 : 0.5)
            }
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfacePrimary)
                .shadow(
                    color: .black.opacity(isHovered ? 0.08 : 0.04),
                    radius: isHovered ? 8 : 4,
                    y: isHovered ? 2 : 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(
                    isHovered ? accentColor.opacity(0.3) : Color.borderPrimary.opacity(0.5),
                    lineWidth: 1
                )
        }
        .onHover { hovering in
            withAnimation(TS.Animation.hover) { isHovered = hovering }
        }
    }

    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Color.surfaceSecondary.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func profileIcon(for id: String) -> String {
        switch id {
        case "zakelijk":  return "briefcase.fill"
        case "informeel": return "bubble.left.and.bubble.right.fill"
        case "technisch": return "wrench.and.screwdriver.fill"
        default:          return "doc.text.fill"
        }
    }

    private func profileAccent(for id: String) -> Color {
        switch id {
        case "zakelijk":  return .brandPrimary
        case "informeel": return .brandAccent
        case "technisch": return .brandSecondary
        default:          return .brandOrange
        }
    }
}

// MARK: - ProfileEditSheet

struct ProfileEditSheet: View {

    let existingProfile: Profile?
    let onSave: (Profile) -> Void
    let onCancel: () -> Void

    private static let defaultSystemPrompt = "Je bent een professionele notulist die vergaderingen nauwkeurig en beknopt samenvat in het Nederlands."

    enum Stijl: String, CaseIterable, Identifiable {
        case zakelijk = "Zakelijk"
        case informeel = "Informeel"
        case technisch = "Technisch"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .zakelijk: return "briefcase.fill"
            case .informeel: return "bubble.left.and.bubble.right.fill"
            case .technisch: return "wrench.and.screwdriver.fill"
            }
        }

        var systemPrompt: String {
            switch self {
            case .zakelijk:
                return "Je bent een professionele notulist die zakelijke vergaderingen nauwkeurig en beknopt samenvat."
            case .informeel:
                return "Je bent een vriendelijke assistent die gesprekken in begrijpelijke taal samenvat."
            case .technisch:
                return "Je bent een technische notulist gespecialiseerd in software ontwikkeling en IT-projecten."
            }
        }

        var description: String {
            switch self {
            case .zakelijk: return "Formele toon, geschikt voor directie en management"
            case .informeel: return "Vlotte, leesbare toon voor team-overleggen"
            case .technisch: return "Technisch jargon, focus op architectuur en code"
            }
        }
    }

    @State private var name: String = ""
    @State private var opdracht: String = ""
    @State private var selectedStijl: Stijl = .zakelijk
    @State private var showAdvanced: Bool = false
    @State private var systemPrompt: String = ""
    @State private var template: String = ""

    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !opdracht.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Check if this profile was created with separate system/notule prompts (advanced mode)
    private var isAdvancedProfile: Bool {
        guard let profile = existingProfile else { return false }
        let sys = profile.systemPrompt ?? ""
        return !sys.isEmpty && !Stijl.allCases.contains(where: { $0.systemPrompt == sys }) && sys != Self.defaultSystemPrompt
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bijv. Brainstorm, Standup, Klantgesprek", text: $name)
                        .font(TS.Font.body)
                } header: {
                    Text("Naam")
                }

                Section {
                    HStack(spacing: TS.Spacing.sm) {
                        ForEach(Stijl.allCases) { stijl in
                            Button {
                                withAnimation(TS.Animation.hover) { selectedStijl = stijl }
                            } label: {
                                VStack(spacing: TS.Spacing.xs) {
                                    Image(systemName: stijl.icon)
                                        .font(.system(size: 18, weight: .medium))
                                    Text(stijl.rawValue)
                                        .font(TS.Font.captionSemibold)
                                    Text(stijl.description)
                                        .font(TS.Font.micro)
                                        .foregroundStyle(Color.labelTertiary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, TS.Spacing.sm)
                                .padding(.horizontal, TS.Spacing.xs)
                                .foregroundStyle(selectedStijl == stijl ? Color.brandPrimary : Color.labelSecondary)
                                .background {
                                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                                        .fill(selectedStijl == stijl ? Color.brandPrimary.opacity(0.10) : Color.clear)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                                        .stroke(
                                            selectedStijl == stijl ? Color.brandPrimary.opacity(0.4) : Color.borderPrimary.opacity(0.3),
                                            lineWidth: selectedStijl == stijl ? 1.5 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Stijl")
                } footer: {
                    Text("Bepaalt de toon en schrijfstijl van de notulen.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                Section {
                    TextEditor(text: $opdracht)
                        .font(TS.Font.footnote)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if opdracht.isEmpty {
                                Text("Bijv: Maak een beknopte samenvatting met actiepunten en besluiten. Gebruik een informele toon.")
                                    .font(TS.Font.footnote)
                                    .foregroundStyle(Color.labelTertiary.opacity(0.5))
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Wat moet er in de notulen staan?")
                } footer: {
                    Text("Beschrijf in je eigen woorden wat de AI moet doen. Bijv: welke onderdelen (besluiten, actiepunten, samenvatting), de gewenste toon (formeel/informeel), en hoeveel detail.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                // Advanced toggle
                Section {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: TS.Spacing.md) {
                            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                                Text("Rol van de AI")
                                    .font(TS.Font.captionSemibold)
                                    .foregroundStyle(Color.labelSecondary)
                                TextEditor(text: $systemPrompt)
                                    .font(TS.Font.footnote)
                                    .frame(minHeight: 60)
                                    .overlay(alignment: .topLeading) {
                                        if systemPrompt.isEmpty {
                                            Text(Self.defaultSystemPrompt)
                                                .font(TS.Font.footnote)
                                                .foregroundStyle(Color.labelTertiary.opacity(0.5))
                                                .padding(.top, 8)
                                                .padding(.leading, 4)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                Text("Laat leeg voor de standaard rol. Vul in als je een specifieke persoonlijkheid of expertise wilt.")
                                    .font(TS.Font.caption)
                                    .foregroundStyle(Color.labelTertiary)
                            }

                            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                                Text("HTML-sjabloon")
                                    .font(TS.Font.captionSemibold)
                                    .foregroundStyle(Color.labelSecondary)
                                TextEditor(text: $template)
                                    .font(TS.Font.footnote)
                                    .frame(minHeight: 50)
                                Text("Optioneel. Laat leeg voor de standaard opmaak.")
                                    .font(TS.Font.caption)
                                    .foregroundStyle(Color.labelTertiary)
                            }
                        }
                        .padding(.top, TS.Spacing.xs)
                    } label: {
                        Text("Geavanceerde opties")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
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
                        // Use custom system prompt from advanced section, or fall back to selected style
                        let customSys = systemPrompt.trimmingCharacters(in: .whitespaces)
                        let finalSystemPrompt = customSys.isEmpty ? selectedStijl.systemPrompt : customSys
                        let profile = Profile(
                            id: existingProfile?.id ?? UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            systemPrompt: finalSystemPrompt,
                            notulePrompt: opdracht.trimmingCharacters(in: .whitespaces),
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
                opdracht = profile.notulePrompt ?? ""
                template = profile.template ?? ""
                // Detect which style matches the existing system prompt
                let sys = profile.systemPrompt ?? ""
                if let matchedStijl = Stijl.allCases.first(where: { $0.systemPrompt == sys }) {
                    selectedStijl = matchedStijl
                    systemPrompt = ""
                } else {
                    systemPrompt = sys
                    showAdvanced = !sys.isEmpty
                }
            }
        }
        .frame(minWidth: 460, minHeight: 480)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfilesView()
    }
    .frame(width: 600, height: 500)
}
