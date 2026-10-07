// PersonEditView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Add/edit form for a directory person (isSelf == false).
// Form fields live in the shared PersonFormFields component (also used by
// ProfileSettingsView), including the tri-state isInternal Picker (D-01).

import SwiftUI

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
                PersonFormFields(
                    naam: $naam,
                    rol: $rol,
                    organisatie: $organisatie,
                    aliassen: $aliassen,
                    expertise: $expertise,
                    internalStatus: $internalStatus
                )
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
            var seen = Set<String>()
            return input.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
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
