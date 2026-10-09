import SwiftUI

struct CorrectionFields: View {
    @Binding var entry: PersonalCorrection
    var profiles: [Profile]
    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Correcte term")
            TextField("Bijvoorbeeld Yinga", text: $entry.canonical).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            Text("Verkeerde spellingen (komma-gescheiden)")
            TextField("Bijvoorbeeld Jengo, Django", text: Binding(get: { entry.variants.joined(separator: ",") }, set: { entry.variants = $0.components(separatedBy: ",") })).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            Picker("Toepassen op", selection: Binding(get: { entry.scope ?? "" }, set: { entry.scope = $0.isEmpty ? nil : $0 })) {
                Text("Alle opnames").tag("")
                ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            if entry.scope == nil {
                Text("Iedere passende vermelding wordt vervangen. Kies een opnameprofiel als de variant ook een andere betekenis heeft.").font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }
        }
    }
}

struct PersonalCorrectionsView: View {
    var profiles: [Profile]
    @State private var entries: [PersonalCorrection] = []
    @State private var draft: PersonalCorrection?
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Woorden en namen").font(TS.Font.headline)
            Text("Corrigeer een naam één keer en onthoud de juiste spelling voor volgende notulen. Deze lijst blijft op dit apparaat.").font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            ForEach(entries) { entry in
                HStack {
                    Toggle(entry.canonical, isOn: Binding(get: { entry.enabled }, set: { value in var changed = entry; changed.enabled = value; persist(changed) }))
                    VStack(alignment: .leading) {
                        Text(entry.variants.joined(separator: ", "))
                        Text(entry.scope.flatMap { id in profiles.first { $0.id == id }?.name } ?? (entry.scope ?? "Alle opnames")).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Button("Bewerken") { draft = entry }
                    Button("Verwijderen") { do { let next = entries.filter { $0.id != entry.id }; try PersonalCorrections.save(next); entries = next } catch { self.error = error.localizedDescription } }
                }
            }
            if draft == nil { Button("Woord toevoegen") { draft = PersonalCorrection() } }
            if let draft {
                CorrectionFields(entry: Binding(get: { self.draft ?? draft }, set: { self.draft = $0 }), profiles: profiles)
                HStack { Spacer(); Button("Annuleren") { self.draft = nil }; Button("Opslaan") { persist(draft, close: true) }.buttonStyle(PrimaryButtonStyle()) }
            }
            if !error.isEmpty { Text(error).foregroundStyle(Color.red).font(TS.Font.caption) }
        }
        .task { do { entries = try PersonalCorrections.load() } catch { self.error = error.localizedDescription } }
    }
    private func persist(_ entry: PersonalCorrection, close: Bool = false) {
        do {
            var cleaned = entry
            cleaned.canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.variants = entry.variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let next = PersonalCorrections.upsert(entries, entry: cleaned)
            try PersonalCorrections.save(next); entries = next; error = ""
            if close { draft = nil }
        } catch { self.error = error.localizedDescription }
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
        }.padding(TS.Spacing.lg).frame(width: 480).interactiveDismissDisabled(busy)
    }
}
