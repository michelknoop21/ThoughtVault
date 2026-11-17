import SwiftUI

struct PersonalCorrectionsView: View {
    var profiles: [Profile]
    @State private var entries: [PersonalCorrection] = []
    @State private var editing: PersonalCorrection?
    @State private var query = ""
    @State private var error = ""

    private var shown: [PersonalCorrection] {
        let sorted = entries.sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { ([$0.canonical, $0.note ?? ""] + $0.heardAs).contains { $0.localizedCaseInsensitiveContains(q) } }
    }
    private var counter: String { entries.count == 1 ? "1 term" : "\(entries.count) termen" }
    private func variantsText(_ entry: PersonalCorrection) -> String { entry.heardAs.joined(separator: ", ") }
    private func scopeName(_ entry: PersonalCorrection) -> String {
        entry.scope.map { id in profiles.first { $0.id == id }?.name ?? id } ?? "Alle profielen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Voer de juiste schrijfwijze in. ThoughtVault zoekt in elke opname zelf naar woorden die erop lijken. Deze lijst blijft op dit apparaat.")
                .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            HStack {
                Text(counter).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                Spacer()
                Button("Term toevoegen") { editing = PersonalCorrection(variants: []) }.buttonStyle(SecondaryButtonStyle())
            }
            if entries.isEmpty {
                Text("Nog geen termen. Voeg een term toe of corrigeer een woord in een notule.")
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.vertical, TS.Spacing.md)
            } else {
                TextField("Zoeken", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                list
            }
            if !error.isEmpty { Text(error).foregroundStyle(Color.red).font(TS.Font.caption) }
        }
        #if os(macOS)
        .frame(maxWidth: 900, alignment: .leading)
        #endif
        .task {
            reload()
            #if DEBUG
            // Screenshot hook: `-TVDebugOpen term` opens the editor of the first term with learned spellings.
            if UserDefaults.standard.string(forKey: "TVDebugOpen") == "term" { editing = entries.first { $0.learned != nil } }
            #endif
        }
        .sheet(item: $editing) { entry in
            CorrectionEditor(entry: entry, profiles: profiles, isNew: !entries.contains { $0.id == entry.id }, onChange: reload)
        }
    }

    #if os(macOS)
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: TS.Spacing.sm) {
                ForEach(shown) { entry in row(entry) }
            }
        }
        .frame(minHeight: 280)
    }

    private func row(_ entry: PersonalCorrection) -> some View {
        HStack(alignment: .top, spacing: TS.Spacing.md) {
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                HStack(spacing: TS.Spacing.sm) {
                    Text(entry.canonical).font(TS.Font.bodySemibold).foregroundStyle(HomeColor.text)
                    StudioBadge(text: scopeName(entry), color: HomeColor.lavender)
                }
                let variants = entry.variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let learned = entry.learned ?? []
                if !variants.isEmpty || !learned.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(variants, id: \.self) { StudioBadge(text: $0) }
                        ForEach(learned, id: \.self) { StudioBadge(text: $0, color: HomeColor.text3).help("Automatisch geleerd") }
                    }
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(TS.Font.caption).foregroundStyle(HomeColor.text3)
                }
            }
            Spacer(minLength: TS.Spacing.sm)
            Toggle("Aan", isOn: Binding(get: { entry.enabled }, set: { value in var changed = entry; changed.enabled = value; save(changed) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .opacity(entry.enabled ? 1 : 0.55)
        .studioCard(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture { editing = entry }
        .contextMenu { Button("Bewerken") { editing = entry } }
        .accessibilityAction(named: "Bewerken") { editing = entry }
    }
    #else
    private var list: some View {
        // Plain rows: the settings subpage Form already scrolls.
        VStack(alignment: .leading, spacing: TS.Spacing.sm) { ForEach(shown) { entry in
            Button { editing = entry } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.canonical).fontWeight(.semibold)
                        if !entry.enabled { Text("Uit").font(TS.Font.caption) }
                    }
                    if !variantsText(entry).isEmpty { Text("Herkend als \(variantsText(entry))").font(TS.Font.caption).foregroundStyle(Color.labelSecondary) }
                    if let note = entry.note, !note.isEmpty { Text(note).font(TS.Font.caption).foregroundStyle(Color.labelSecondary) }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(entry.enabled ? Color.labelPrimary : Color.labelSecondary)
        } }
    }
    #endif

    private func reload() {
        do { entries = try PersonalCorrections.load(); error = "" } catch { self.error = error.localizedDescription }
    }
    private func save(_ entry: PersonalCorrection) {
        do { entries = try PersonalCorrections.saveRecording(entry, source: "handmatig"); error = "" } catch { self.error = error.localizedDescription }
    }
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
        }.padding(TS.Spacing.lg)
        #if os(macOS)
        .frame(width: 480)
        #endif
        .interactiveDismissDisabled(busy)
    }
}
