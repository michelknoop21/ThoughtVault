// PersonEditView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Add/edit form for a directory person (isSelf == false).
// Mirrors ProfileSettingsView field-for-field with LabeledContent rows.
// Adds tri-state isInternal Picker (D-01) and comma-separated expertiseTags (D-06).

import SwiftUI

// MARK: - InternalStatus

/// Maps the tri-state Bool? to a stable Picker-friendly enum.
private enum InternalStatus: Int, CaseIterable {
    case intern   = 1
    case extern_  = 0    // rawValue 0 = false
    case onbekend = 2    // rawValue 2 = nil

    var label: String {
        switch self {
        case .intern:   return "Intern"
        case .extern_:  return "Extern"
        case .onbekend: return "Onbekend"
        }
    }

    var boolValue: Bool? {
        switch self {
        case .intern:   return true
        case .extern_:  return false
        case .onbekend: return nil
        }
    }

    static func from(_ value: Bool?) -> InternalStatus {
        switch value {
        case true:  return .intern
        case false: return .extern_
        case nil:   return .onbekend
        }
    }
}

// MARK: - PersonEditView

struct PersonEditView: View {

    // MARK: - Input

    /// nil = new person mode; non-nil = edit mode.
    let person: PersonProfile?
    let onSave: (PersonProfile) -> Void

    // MARK: - State

    @State private var naam: String = ""
    @State private var rol: String = ""
    @State private var organisatie: String = ""
    @State private var aliassen: String = ""
    @State private var expertise: String = ""
    @State private var internalStatus: InternalStatus = .onbekend

    @State private var isSaving: Bool = false
    @State private var showSaved: Bool = false
    @State private var saveError: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var isNewPerson: Bool { person == nil }

    /// Action keeps the same name through the flow: the modal titled
    /// "Persoon toevoegen" gets a "Persoon toevoegen" button, not "Wijzigingen opslaan".
    private var saveLabel: String { isNewPerson ? "Persoon toevoegen" : "Wijzigingen opslaan" }

    private var canSave: Bool {
        !isSaving && !naam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear { loadFields() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            // Title
            Text(isNewPerson ? "Persoon toevoegen" : "Persoon bewerken")
                .font(TS.Font.title3Semibold)
                .foregroundStyle(Color.labelPrimary)

            // Form — label-above rows (SettingFieldRow) so the wide
            // comma-separated inputs aren't cramped, matching Instellingen.
            Form {
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

                SettingFieldRow("Aliassen", hint: "Meerdere kommagescheiden") {
                    TextField("Michel, Knoop, MK", text: $aliassen)
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

                SettingFieldRow("Intern / extern") {
                    Picker("", selection: $internalStatus) {
                        ForEach(InternalStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }
            .formStyle(.grouped)

            // Save button + feedback
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                if let error = saveError {
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                }

                HStack {
                    Button {
                        savePerson()
                    } label: {
                        if isSaving {
                            HStack(spacing: TS.Spacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(saveLabel)
                            }
                        } else if showSaved {
                            HStack(spacing: TS.Spacing.xs) {
                                Image(systemName: "checkmark")
                                Text("Opgeslagen")
                            }
                        } else {
                            Text(saveLabel)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
                }
            }

            Spacer()
        }
        .padding(TS.Spacing.lg)
    }

    // MARK: - Load

    private func loadFields() {
        guard let p = person else { return }
        naam = p.name
        rol = p.role
        organisatie = p.organization
        aliassen = p.aliases.joined(separator: ", ")
        expertise = p.expertiseTags.joined(separator: ", ")
        internalStatus = InternalStatus.from(p.isInternal)
    }

    // MARK: - Save

    private func savePerson() {
        isSaving = true
        saveError = nil

        let splitAndTrim: (String) -> [String] = { input in
            input.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let service = PersonDirectoryService.shared

        do {
            if let existing = person {
                // Edit mode — mutate and update
                existing.name = naam.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.role = rol.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.organization = organisatie.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.aliases = splitAndTrim(aliassen)
                existing.expertiseTags = splitAndTrim(expertise)
                existing.isInternal = internalStatus.boolValue
                try service.update(existing)
                finishSave(person: existing)
            } else {
                // New person mode
                let newPerson = PersonProfile(
                    name: naam.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: rol.trimmingCharacters(in: .whitespacesAndNewlines),
                    organization: organisatie.trimmingCharacters(in: .whitespacesAndNewlines),
                    aliases: splitAndTrim(aliassen),
                    expertiseTags: splitAndTrim(expertise),
                    isSelf: false,
                    isInternal: internalStatus.boolValue
                )
                try service.add(newPerson)
                finishSave(person: newPerson)
            }
        } catch {
            isSaving = false
            saveError = "Opslaan mislukt: \(error.localizedDescription)"
        }
    }

    private func finishSave(person: PersonProfile) {
        isSaving = false
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showSaved = false
                onSave(person)
            }
        }
    }
}
