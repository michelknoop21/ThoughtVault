import SwiftUI

struct LibraryNavigation: View {
    @Binding var selection: String
    var transcripts: [Transcript]
    var selectedIDs: Set<String>
    var refresh: () async -> Void
    @State private var editor: LibraryEntry?
    @State private var showLabels = false
    @State private var confirmLabeling = false
    @State private var error: String?
    private var library: LibraryOrganization { .shared }
    private var labeling: AutomaticLabels { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            ScrollView(.horizontal) {
                HStack {
                    Button("Alle notulen") { selection = "all" }
                    Button("Zonder map") { selection = "unfiled" }
                    Menu("Mappen") {
                        Button("Nieuwe map…") { editor = LibraryEntry(name: "", kind: "folder") }
                        ForEach(library.folders) { entry in folderMenu(entry) }
                    }
                    Menu("Slimme mappen") {
                        Button("Nieuwe slimme map…") {
                            do { try library.adoptLabels(transcripts.flatMap(\.tags)); editor = LibraryEntry(name: "", kind: "smart") }
                            catch { self.error = error.localizedDescription }
                        }
                        ForEach(library.smartFolders) { entry in folderMenu(entry) }
                    }
                    Button("Labels beheren…") {
                        do { try library.adoptLabels(transcripts.flatMap(\.tags)); showLabels = true }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(library.folders + library.smartFolders) { entry in
                        Button(entry.name) { selection = entry.id }
                            .accessibilityAddTraits(selection == entry.id ? .isSelected : [])
                            .dropDestination(for: String.self) { ids, _ in
                                guard entry.kind == "folder" else { return false }
                                do { try LocalTranscriptStore.shared.move(taskIDs: ids, to: entry.id); Task { await refresh() }; return true }
                                catch { self.error = error.localizedDescription; return false }
                            }
                    }
                }
            }
            if selection != "all" {
                HStack {
                    Image(systemName: "folder")
                    Text(selection == "unfiled" ? String(localized: "Zonder map") : library.entries.first { $0.id == selection }?.name ?? "")
                }.font(TS.Font.footnoteMedium)
            }
            if !selectedIDs.isEmpty {
                HStack {
                    LibraryMoveMenu(taskIDs: transcripts.filter { selectedIDs.contains($0.id) }.map(\.taskId), refresh: refresh)
                    Button("Bestaande notulen labelen…") { confirmLabeling = true }
                        .disabled(labeling.busy || library.labels.filter(\.automatic).isEmpty)
                }
            }
            if labeling.busy {
                HStack {
                    ProgressView(value: Double(labeling.completed), total: Double(max(1, labeling.total)))
                    Text("\(labeling.completed) / \(labeling.total)")
                    Button("Annuleren") { labeling.cancel() }.disabled(labeling.cancelled)
                }
            }
            if labeling.busy && labeling.cancelled {
                Text("De huidige AI-aanvraag wordt afgerond. Het resultaat wordt niet opgeslagen.").font(TS.Font.footnoteMedium)
            }
            if let error = error ?? library.error ?? labeling.error {
                Text(error).foregroundStyle(Color.statusError).font(TS.Font.footnoteMedium)
            }
            let failed = transcripts.filter { LocalTranscriptStore.shared.record(forTaskId: $0.taskId)?.autoLabelError != nil }
            if !failed.isEmpty {
                Button("Automatisch labelen opnieuw proberen (\(failed.count))") {
                    Task { await labeling.run(taskIDs: failed.map(\.taskId)); await refresh() }
                }.disabled(labeling.busy)
            }
        }
        .padding(TS.Spacing.sm)
        .sheet(item: $editor) { entry in LibraryEntryEditor(entry: entry) }
        .sheet(isPresented: $showLabels) { LibraryLabelsView() }
        .confirmationDialog("Bestaande notulen labelen?", isPresented: $confirmLabeling, titleVisibility: .visible) {
            Button("Label \(selectedIDs.count) notulen") {
                let ids = transcripts.filter { selectedIDs.contains($0.id) }.map(\.taskId)
                Task { await labeling.run(taskIDs: ids); await refresh() }
            }
        } message: {
            Text("De ingestelde AI-provider verwerkt de titel en notuletekst. Handmatige labels blijven bewaard. Afgeronde resultaten blijven behouden bij annuleren.")
        }
    }

    @ViewBuilder private func folderMenu(_ entry: LibraryEntry) -> some View {
        Menu(entry.name) {
            Button("Openen") { selection = entry.id }
            Button("Wijzigen…") { editor = entry }
            Button("Verwijderen", role: .destructive) {
                do { try library.remove(entry); if selection == entry.id { selection = "unfiled" } }
                catch { self.error = error.localizedDescription }
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard entry.kind == "folder" else { return false }
            do { try LocalTranscriptStore.shared.move(taskIDs: ids, to: entry.id); Task { await refresh() }; return true }
            catch { self.error = error.localizedDescription; return false }
        }
    }
}

struct LibraryMoveMenu: View {
    var taskIDs: [String]
    var refresh: () async -> Void
    @State private var error: String?
    var body: some View {
        Menu("Verplaats naar…") {
            Button("Zonder map") { move(nil) }
            ForEach(LibraryOrganization.shared.folders) { entry in Button(entry.name) { move(entry.id) } }
        }
        .disabled(taskIDs.isEmpty)
        .alert("Verplaatsen mislukt", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func move(_ id: String?) {
        do { try LocalTranscriptStore.shared.move(taskIDs: taskIDs, to: id); Task { await refresh() } }
        catch { self.error = error.localizedDescription }
    }
}

struct LibraryEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: LibraryEntry
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Naam", text: $entry.name).disabled(entry.kind == "label" && LibraryOrganization.shared.labels.contains { $0.id == entry.id })
                if entry.kind == "label" {
                    TextField("Omschrijving", text: $entry.description, axis: .vertical)
                    Toggle("Automatisch toekennen", isOn: $entry.automatic)
                    Text("De ingestelde AI-provider gebruikt deze omschrijving. Labels blijven handmatig corrigeerbaar.")
                }
                if entry.kind == "smart" {
                    Text("Toon notulen met minstens één van deze labels.")
                    ForEach(LibraryOrganization.shared.labels) { label in
                        Toggle(label.name, isOn: Binding(get: { entry.labelIDs.contains(label.id) }, set: { value in
                            entry.labelIDs.removeAll { $0 == label.id }; if value { entry.labelIDs.append(label.id) }
                        }))
                    }
                }
                if let error { Text(error).foregroundStyle(Color.statusError) }
            }
            .navigationTitle(entry.kind == "label" ? "Labelinstellingen" : "Map bewerken")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        do { try LibraryOrganization.shared.save(entry); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (entry.kind == "smart" && entry.labelIDs.isEmpty))
                }
            }
        }.frame(minWidth: 300, minHeight: 320)
    }
}

private struct LibraryLabelsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editor: LibraryEntry?
    var body: some View {
        NavigationStack {
            List(LibraryOrganization.shared.labels) { label in
                Button(label.name) { editor = label }
            }
            .navigationTitle("Labels beheren")
            .toolbar {
                Button("Nieuw label…") { editor = LibraryEntry(name: "", kind: "label") }
                Button("Klaar") { dismiss() }
            }
            .sheet(item: $editor) { entry in LibraryEntryEditor(entry: entry) }
        }.frame(minWidth: 300, minHeight: 300)
    }
}
