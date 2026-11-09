import SwiftUI

struct CorrectionFields: View {
    static let noteLimit = 200
    @Binding var entry: PersonalCorrection
    var profiles: [Profile]
    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Correcte term")
            TextField("Bijvoorbeeld Yinga", text: $entry.canonical).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            Text("Verkeerde spellingen (komma-gescheiden)")
            TextField("Bijvoorbeeld Jengo, Django", text: Binding(get: { entry.variants.joined(separator: ",") }, set: { entry.variants = $0.components(separatedBy: ",") })).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            Text("Toelichting (optioneel)")
            TextField("Bijvoorbeeld Klant uit Utrecht", text: noteBinding).textFieldStyle(.roundedBorder)
            Text("Nog \(Self.noteLimit - (entry.note?.utf16.count ?? 0)) tekens").font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            Picker("Toepassen op", selection: Binding(get: { entry.scope ?? "" }, set: { entry.scope = $0.isEmpty ? nil : $0 })) {
                Text("Alle opnames").tag("")
                ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            if entry.scope == nil {
                Text("Iedere passende vermelding wordt vervangen. Kies een opnameprofiel als de variant ook een andere betekenis heeft.").font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }
        }
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

struct PersonalCorrectionsView: View {
    var profiles: [Profile]
    @State private var entries: [PersonalCorrection] = []
    @State private var editing: PersonalCorrection?
    @State private var query = ""
    @State private var error = ""
    #if os(macOS)
    @State private var selection: String?
    #endif

    private var shown: [PersonalCorrection] {
        let sorted = entries.sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { ([$0.canonical, $0.note ?? ""] + $0.variants).contains { $0.localizedCaseInsensitiveContains(q) } }
    }
    private var counter: String { entries.count == 1 ? "1 term" : "\(entries.count) termen" }
    private func variantsText(_ entry: PersonalCorrection) -> String {
        entry.variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    private func scopeName(_ entry: PersonalCorrection) -> String {
        entry.scope.map { id in profiles.first { $0.id == id }?.name ?? id } ?? "Alle profielen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Corrigeer een naam één keer en onthoud de juiste spelling voor volgende notulen. Deze lijst blijft op dit apparaat.")
                .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            HStack {
                Text(counter).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                Spacer()
                Button("Term toevoegen") { editing = PersonalCorrection(variants: []) }
            }
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    Text("Nog geen termen. Voeg een term toe of corrigeer een woord in een notule.").foregroundStyle(Color.labelSecondary)
                }.padding(.vertical, TS.Spacing.md)
            } else {
                list
            }
            if !error.isEmpty { Text(error).foregroundStyle(Color.red).font(TS.Font.caption) }
        }
        .searchable(text: $query, prompt: "Zoek in woordenlijst")
        .task { reload() }
        .sheet(item: $editing) { entry in
            CorrectionEditor(entry: entry, profiles: profiles, isNew: !entries.contains { $0.id == entry.id }, onChange: reload)
        }
    }

    #if os(macOS)
    private var list: some View {
        Table(shown, selection: $selection) {
            TableColumn("Term") { Text($0.canonical).fontWeight(.semibold) }
            TableColumn("Herkend als") { Text(variantsText($0)) }
            TableColumn("Toelichting") { Text($0.note ?? "") }
            TableColumn("Profiel") { Text(scopeName($0)) }
            TableColumn("Aan") { entry in
                Toggle("Aan", isOn: Binding(get: { entry.enabled }, set: { value in var changed = entry; changed.enabled = value; save(changed) }))
                    .labelsHidden()
            }.width(50)
        }
        .frame(minHeight: 280)
        .onChange(of: selection) { _, id in
            guard let id, let entry = entries.first(where: { $0.id == id }) else { return }
            editing = entry
            selection = nil
        }
    }
    #else
    private var list: some View {
        List(shown) { entry in
            Button { editing = entry } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.canonical).fontWeight(.semibold)
                    if !variantsText(entry).isEmpty { Text("Herkend als \(variantsText(entry))").font(TS.Font.caption).foregroundStyle(Color.labelSecondary) }
                    if let note = entry.note, !note.isEmpty { Text(note).font(TS.Font.caption).foregroundStyle(Color.labelSecondary) }
                }
            }.buttonStyle(.plain)
        }
        .frame(minHeight: 320)
    }
    #endif

    private func reload() {
        do { entries = try PersonalCorrections.load(); error = "" } catch { self.error = error.localizedDescription }
    }
    private func save(_ entry: PersonalCorrection) {
        do { entries = try PersonalCorrections.saveRecording(entry, source: "handmatig"); error = "" } catch { self.error = error.localizedDescription }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TS.Spacing.md) {
                Text(isNew ? "Term toevoegen" : "Term bewerken").font(TS.Font.headline)
                CorrectionFields(entry: $entry, profiles: profiles)
                if !isNew {
                    Text("Geschiedenis").font(TS.Font.headline)
                    HistoryListView(kind: .term, itemId: entry.id) { restore($0) }
                }
                if !error.isEmpty { Text(error).foregroundStyle(Color.red).font(TS.Font.caption) }
                HStack {
                    if !isNew { Button("Verwijderen", role: .destructive) { remove() } }
                    Spacer()
                    Button("Annuleren") { dismiss() }
                    Button("Opslaan") { save() }.buttonStyle(PrimaryButtonStyle())
                }
            }.padding(TS.Spacing.lg)
        }
        #if os(macOS)
        .frame(width: 480, height: 560)
        #endif
    }

    private func save() {
        do {
            var cleaned = entry
            cleaned.canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.variants = entry.variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            cleaned.note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            try PersonalCorrections.saveRecording(cleaned, source: "handmatig")
            onChange(); dismiss()
        } catch { self.error = error.localizedDescription }
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct WordCorrectionSheet: View {
    @State var entry: PersonalCorrection
    var profiles: [Profile]
    var apply: (PersonalCorrection, Bool) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var remember = true
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Woord corrigeren").font(TS.Font.headline)
            CorrectionFields(entry: $entry, profiles: profiles)
            Toggle("Onthouden voor volgende opnames", isOn: $remember)
            if !error.isEmpty { Text(error).foregroundStyle(Color.red).font(TS.Font.caption) }
            HStack {
                Spacer(); Button("Annuleren") { dismiss() }.disabled(busy)
                Button("Corrigeren") {
                    busy = true; error = ""
                    Task {
                        do { try await apply(entry, remember); dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
            }
        }.padding(TS.Spacing.lg).frame(width: 480).interactiveDismissDisabled(busy)
    }
}
