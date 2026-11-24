// CorrectionEditor.swift
// ThoughtVault
//
// Fields and edit panel for one glossary entry, in the layout of PersonEditView.

import SwiftUI

struct CorrectionFields: View {
    static let noteLimit = 200
    @Binding var entry: PersonalCorrection
    var profiles: [Profile]

    var body: some View {
        SettingFieldRow("Juiste schrijfwijze") {
            TextField("Juiste schrijfwijze", text: $entry.canonical, prompt: Text("Bijvoorbeeld Yinga"))
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
        }
        SettingFieldRow("Fout gehoorde spellingen (optioneel)",
                        hint: "Meestal niet nodig. ThoughtVault vindt vergelijkbare woorden zelf. Vul alleen in wat altijd vervangen moet worden.") {
            TextField("Fout gehoorde spellingen", text: Binding(get: { entry.variants.joined(separator: ", ") },
                                                                set: { entry.variants = $0.components(separatedBy: ",") }),
                      prompt: Text("Bijvoorbeeld Jengo, Django"))
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
        }
        if let learned = entry.learned, !learned.isEmpty {
            SettingFieldRow("Automatisch geleerd", hint: "Gevonden op basis van de context. Vast maken vervangt de spelling voortaan altijd.") {
                ForEach(learned, id: \.self) { spelling in
                    HStack(spacing: TS.Spacing.sm) {
                        Text(spelling)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.brandPrimary.opacity(0.12)))
                        Spacer()
                        Button("Vast maken") { makeFixed(spelling) }
                        Button("Verwijderen", role: .destructive) { removeLearned(spelling) }
                            .foregroundStyle(Color.statusError)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        SettingFieldRow("Toelichting (optioneel)", hint: "Nog \(Self.noteLimit - (entry.note?.utf16.count ?? 0)) tekens") {
            TextField("Toelichting", text: noteBinding, prompt: Text("Bijvoorbeeld Klant uit Utrecht"))
                .textFieldStyle(.roundedBorder)
        }
        SettingFieldRow("Toepassen op", hint: entry.scope == nil ? "Iedere passende vermelding wordt vervangen. Kies een opnameprofiel als de spelling ook een andere betekenis heeft." : nil) {
            Picker("Toepassen op", selection: Binding(get: { entry.scope ?? "" }, set: { entry.scope = $0.isEmpty ? nil : $0 })) {
                Text("Alle opnames").tag("")
                ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            .labelsHidden()
        }
    }

    private func makeFixed(_ spelling: String) {
        removeLearned(spelling)
        entry.variants = entry.variants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } + [spelling]
    }
    private func removeLearned(_ spelling: String) {
        let rest = (entry.learned ?? []).filter { $0 != spelling }
        entry.learned = rest.isEmpty ? nil : rest
    }
    /// Blocks input beyond the limit and the characters the glossary does not allow.
    private var noteBinding: Binding<String> {
        Binding(
            get: { entry.note ?? "" },
            set: { value in
                let clean = String(value.unicodeScalars.filter { !"\r\n<>".unicodeScalars.contains($0) })
                entry.note = clean.isEmpty ? nil : String(clean.prefix(Self.noteLimit))
            }
        )
    }
}

/// Edit panel for one glossary entry: fields, delete and version history.
struct CorrectionEditor: View {
    @State var entry: PersonalCorrection
    var profiles: [Profile]
    var isNew: Bool
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""

    private var title: String { isNew ? "Term toevoegen" : "Term bewerken" }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text(title).font(TS.Font.title3Semibold).foregroundStyle(Color.labelPrimary)
            ScrollView {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    CorrectionFields(entry: $entry, profiles: profiles)
                    SettingFieldRow("Status") { Toggle("Gebruiken in notulen", isOn: $entry.enabled) }
                    if !isNew {
                        SettingFieldRow("Geschiedenis") { history }
                    }
                }
            }
            .frame(maxHeight: 460)
            footer
        }
        .padding(TS.Spacing.lg)
        .frame(width: 520)
        #else
        NavigationStack {
            Form {
                Section { CorrectionFields(entry: $entry, profiles: profiles) }
                Section { Toggle("Gebruiken in notulen", isOn: $entry.enabled) }
                if !isNew {
                    Section("Geschiedenis") { history }
                    Section { Button("Verwijderen", role: .destructive) { remove() } }
                }
                if !error.isEmpty { Text(error).foregroundStyle(Color.statusError).font(TS.Font.caption) }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Opslaan") { save() } }
            }
        }
        #endif
    }

    private var history: some View {
        HistoryListView(kind: .term, itemId: entry.id) { restore($0) }
    }

    #if os(macOS)
    private var footer: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            if !error.isEmpty { Text(error).font(TS.Font.caption).foregroundStyle(Color.statusError) }
            HStack {
                Button("Annuleer") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if !isNew {
                    Button("Verwijderen") { remove() }
                        .buttonStyle(SecondaryButtonStyle())
                        .foregroundStyle(Color.statusError)
                }
                Spacer()
                Button(isNew ? "Term toevoegen" : "Wijzigingen opslaan") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    #endif

    private func save() {
        do {
            let removed = removedLearned
            var cleaned = entry
            cleaned.canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.variants = entry.variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            cleaned.note = note.isEmpty ? nil : note
            try PersonalCorrections.saveRecording(cleaned, source: "handmatig")
            // A learned spelling removed by hand must not be learned again.
            let kept = Set((cleaned.learned ?? []) + cleaned.variants)
            for spelling in removed where !kept.contains(spelling) {
                try PersonalCorrections.addDismissed(PersonalCorrections.learnedKey(canonical: cleaned.canonical, heard: spelling))
            }
            onChange(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    /// Learned spellings of the stored version that are no longer learned.
    private var removedLearned: [String] {
        let stored = (try? PersonalCorrections.load())?.first { $0.id == entry.id }?.learned ?? []
        return stored.filter { !(entry.learned ?? []).contains($0) }
    }
    private func remove() {
        do { try PersonalCorrections.delete(id: entry.id, source: "handmatig"); onChange(); dismiss() } catch { self.error = error.localizedDescription }
    }
    private func restore(_ version: HistoryEntry) {
        do {
            try PersonalCorrections.restore(version)
            onChange()
            if let fresh = try PersonalCorrections.load().first(where: { $0.id == entry.id }) { entry = fresh; error = "" } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
