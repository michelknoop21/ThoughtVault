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
    /// Fields for a new person taken from a conversation suggestion.
    var prefill: PersonSuggestion? = nil
    /// Meeting type of the conversation the prefill came from (same as PersonMatcher.autoApply).
    var prefillMeetingType: String = ""
    /// Called right after a new person was stored, before the saved confirmation delay.
    var onAdded: ((PersonProfile) -> Void)? = nil
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
    /// Bumped after each save so the history list reloads.
    @State private var historyRefresh = 0
    @State private var saveError: String? = nil
    /// Loaded once in loadFields(); the lookup decodes every record's participants.
    @State private var conversations: [TranscriptRecord] = []

    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var sheetWidth: CGFloat = 880
    @State private var maxBodyHeight: CGFloat = 640
    @State private var bodyHeight: CGFloat = 400
    #endif

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
        macContent
            .onAppear {
                // A sheet does not shrink to its window; size it from the window instead.
                if let rect = (NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain })?.contentLayoutRect {
                    sheetWidth = min(880, max(520, rect.width - 40))
                    maxBodyHeight = max(220, rect.height - 230)
                }
            }
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

            Form {
                personFields
                Section("Taken en verantwoordelijkheden") { takenEditor }
                if let person { Section("Geschiedenis") { historyList(person) } }
                if person != nil { Section("Gesprekken") { conversationList } }
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
                    saveButton
                }
            }

            Spacer()
        }
        .padding(TS.Spacing.lg)
    }

    private var saveButton: some View {
        Button {
            savePerson()
        } label: {
            if showSaved {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "checkmark")
                    Text("Opgeslagen")
                }
            } else if isSaving {
                HStack(spacing: TS.Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text(saveLabel)
                }
            } else {
                Text(saveLabel)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canSave)
    }

    #if os(macOS)
    // MARK: - macOS sheet

    /// Header, two columns (fields | tasks, history, conversations) that become
    /// one column when the sheet is narrow, and the buttons bottom right.
    private var macContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                PersonInitials(name: naam, color: HomeColor.lavender, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNewPerson ? "Persoon toevoegen" : "Persoon bewerken")
                        .font(.system(size: 22, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    let subtitle = [naam, rol, organisatie]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 14)).foregroundStyle(HomeColor.text2).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(.vertical) {
                Group {
                    if sheetWidth >= 816 {
                        HStack(alignment: .top, spacing: 28) {
                            fieldsColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                            sideColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            fieldsColumn
                            sideColumn
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .frame(height: min(bodyHeight, maxBodyHeight))

            Divider().overlay(HomeColor.divider)
            HStack(spacing: 12) {
                if let error = saveError {
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Annuleer") { dismiss() }
                    .buttonStyle(StudioQuietButtonStyle(height: 40))
                    .keyboardShortcut(.cancelAction)
                saveButton
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        .frame(width: sheetWidth)
        .foregroundStyle(HomeColor.text)
        .background(HomeColor.backgroundTop)
    }

    private var fieldsColumn: some View {
        VStack(alignment: .leading, spacing: 10) { personFields }
            .labelsHidden()
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Taken en verantwoordelijkheden").font(.system(size: 15, weight: .semibold))
                takenEditor
            }
            if let person {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Geschiedenis").font(.system(size: 15, weight: .semibold))
                    historyList(person, timeline: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Gesprekken").font(.system(size: 15, weight: .semibold))
                    conversationList
                }
            }
        }
    }
    #endif

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
            // The macOS sheet body scrolls as a whole.
            takenRows
            HStack {
                TextField("Nieuwe taak", text: $nieuweTaak)
                    .personFieldStyle()
                    .onSubmit(addTaak)
                Button("Toevoegen", action: addTaak)
                    #if os(macOS)
                    .buttonStyle(StudioQuietButtonStyle(height: 38))
                    #endif
                    .disabled(nieuweTaak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var takenRows: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            ForEach(Array(taken.enumerated()), id: \.offset) { index, taak in
                HStack {
                    Text(taak).font(TS.Font.body).foregroundStyle(Color.labelPrimary)
                    Spacer()
                    #if os(macOS)
                    Button { taken.remove(at: index) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 26, height: 26)
                    }
                    .buttonStyle(StudioIconButtonStyle())
                    .accessibilityLabel("Verwijder \(taak)")
                    #else
                    Button { taken.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Verwijder \(taak)")
                    #endif
                }
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

    private func historyList(_ person: PersonProfile, timeline: Bool = false) -> some View {
        HistoryListView(kind: .person, itemId: person.id, timeline: timeline) { entry in
            do {
                try PersonDirectoryService.shared.restore(entry, to: person)
                loadFields()
                saveError = nil
            } catch {
                saveError = "Herstellen mislukt: \(error.localizedDescription)"
            }
        }
        .id(historyRefresh)
    }

    /// Recordings this person was linked to, newest first.
    private var conversationList: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            if conversations.isEmpty {
                Text("Nog geen gekoppelde gesprekken")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
            ForEach(conversations, id: \.taskId) { record in
                HStack(alignment: .firstTextBaseline, spacing: TS.Spacing.sm) {
                    Text(record.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "nl_NL"))))
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                    Text(record.title)
                        .font(TS.Font.body)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Load

    private func loadFields() {
        guard let p = person else {
            if let s = prefill {
                naam = s.name
                rol = s.role
                organisatie = s.organization
                aliassen = s.heardAs.joined(separator: ", ")
                expertise = s.topics.joined(separator: ", ")
                taken = s.responsibilities
            }
            return
        }
        naam = p.name
        rol = p.role
        organisatie = p.organization
        aliassen = p.aliases.joined(separator: ", ")
        expertise = p.expertiseTags.joined(separator: ", ")
        internalStatus = InternalStatus.from(p.isInternal)
        taken = p.responsibilities
        conversations = LocalTranscriptStore.shared.records(linkedTo: p.id)
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
                let meetingType = prefillMeetingType.trimmingCharacters(in: .whitespacesAndNewlines)
                if prefill != nil, !meetingType.isEmpty { newPerson.meetingTypes = [meetingType] }
                try service.add(newPerson)
                onAdded?(newPerson)
                finishSave(person: newPerson)
            }
        } catch {
            isSaving = false
            saveError = "Opslaan mislukt: \(error.localizedDescription)"
        }
    }

    private func finishSave(person: PersonProfile) {
        // A new person stays saving until onSave, so a second tap cannot add it twice.
        isSaving = isNewPerson
        showSaved = true
        historyRefresh += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showSaved = false
                isSaving = false
                onSave(person)
            }
        }
    }
}
