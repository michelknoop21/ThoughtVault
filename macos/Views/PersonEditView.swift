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
    @State private var taken: [String] = []
    @State private var nieuweTaak: String = ""

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
        Group {
        #if os(macOS)
        content
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
        #else
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 420, minHeight: 480)
        #endif
        }
        .onAppear { loadFields() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            // Title
            Text(isNewPerson ? "Persoon toevoegen" : "Persoon bewerken")
                .font(TS.Font.title3Semibold)
                .foregroundStyle(Color.labelPrimary)

            #if os(macOS)
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                personFields
            }
            .labelsHidden()

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Taken en verantwoordelijkheden").font(TS.Font.headline)
                takenEditor
            }
            if let person {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    Text("Geschiedenis").font(TS.Font.headline)
                    ScrollView { historyList(person) }.frame(maxHeight: 120)
                }
            }
            #else
            Form {
                personFields
                Section("Taken en verantwoordelijkheden") { takenEditor }
                if let person { Section("Geschiedenis") { historyList(person) } }
            }
            .formStyle(.grouped)
            #endif

            // Save button + feedback
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                if let error = saveError {
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                }

                HStack {
                    #if os(macOS)
                    Button("Annuleer") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    #endif
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

            #if !os(macOS)
            Spacer()
            #endif
        }
        .padding(TS.Spacing.lg)
    }

    private var personFields: some View {
        PersonFormFields(
            naam: $naam, rol: $rol, organisatie: $organisatie,
            aliassen: $aliassen, expertise: $expertise,
            internalStatus: $internalStatus
        )
    }

    // MARK: - Responsibilities and history

    private var takenEditor: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            ForEach(taken, id: \.self) { taak in
                HStack {
                    Text(taak).font(TS.Font.body).foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Button { taken.removeAll { $0 == taak } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Verwijder \(taak)")
                }
            }
            HStack {
                TextField("Nieuwe taak", text: $nieuweTaak)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTaak)
                Button("Toevoegen", action: addTaak)
                    .disabled(nieuweTaak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// Trims and ignores duplicates, case-insensitive.
    private func addTaak() {
        let taak = nieuweTaak.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taak.isEmpty else { return }
        if !taken.contains(where: { $0.caseInsensitiveCompare(taak) == .orderedSame }) { taken.append(taak) }
        nieuweTaak = ""
    }

    private func historyList(_ person: PersonProfile) -> some View {
        HistoryListView(kind: .person, itemId: person.id) { entry in
            do {
                try PersonDirectoryService.shared.restore(entry, to: person)
                loadFields()
                saveError = nil
            } catch {
                saveError = "Herstellen mislukt: \(error.localizedDescription)"
            }
        }
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
        taken = p.responsibilities
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
                // Edit mode: the service keeps the previous version in the history
                try service.update(existing, source: "handmatig") { p in
                    p.name = naam.trimmingCharacters(in: .whitespacesAndNewlines)
                    p.role = rol.trimmingCharacters(in: .whitespacesAndNewlines)
                    p.organization = organisatie.trimmingCharacters(in: .whitespacesAndNewlines)
                    p.aliases = splitAndTrim(aliassen)
                    p.expertiseTags = splitAndTrim(expertise)
                    p.isInternal = internalStatus.boolValue
                    p.responsibilities = taken
                }
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
                newPerson.responsibilities = taken
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
