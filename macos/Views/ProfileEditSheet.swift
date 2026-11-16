// ProfileEditSheet.swift
// ThoughtVault
//
// Create or edit a custom notule profile.

import SwiftUI

// MARK: - ProfileEditSheet

struct ProfileEditSheet: View {

    let existingProfile: Profile?
    let onSave: (Profile) async throws -> Void
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
    @State private var sectionNames: String = ""
    @State private var saveError: String?
    @State private var isSaving = false

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

                Section {
                    TextField("Bijv. Onderwerpen, Acties, Open vragen", text: $sectionNames)
                } header: {
                    Text("Secties (optioneel, gescheiden door komma's)")
                } footer: {
                    Text("Lege secties worden weggelaten.")
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
            .safeAreaInset(edge: .bottom) {
                if let saveError {
                    Text(saveError).font(TS.Font.caption).foregroundStyle(Color.statusError)
                        .padding(TS.Spacing.sm)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        let customSys = systemPrompt.trimmingCharacters(in: .whitespaces)
                        let sections = sectionNames.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        }.filter { !$0.isEmpty }
                        let sectionTemplate = sections.isEmpty ? nil : "<h1>[Titel]</h1>\n" + sections.map {
                            let safe = $0.replacingOccurrences(of: "&", with: "&amp;")
                                .replacingOccurrences(of: "<", with: "&lt;")
                                .replacingOccurrences(of: ">", with: "&gt;")
                            return "<section><h2>\(safe)</h2><p>[Brongebonden inhoud]</p></section>"
                        }.joined(separator: "\n")
                        let profile = Profile(
                            id: existingProfile?.id ?? UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            systemPrompt: customSys.isEmpty ? selectedStijl.systemPrompt : customSys,
                            notulePrompt: opdracht.trimmingCharacters(in: .whitespaces),
                            template: sectionTemplate ?? (template.contains("[Brongebonden inhoud]") || template.isEmpty ? nil : template),
                            isDefault: false
                        )
                        isSaving = true
                        saveError = nil
                        Task {
                            do { try await onSave(profile) }
                            catch { saveError = error.localizedDescription }
                            isSaving = false
                        }
                    }
                    .disabled(!isFormValid || isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let profile = existingProfile {
                name = profile.name
                opdracht = profile.notulePrompt ?? ""
                template = profile.template ?? ""
                sectionNames = profile.sectionNames.joined(separator: ", ")
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
