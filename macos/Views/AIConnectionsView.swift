import SwiftUI

struct AIConnectionsView: View {
    @State private var model = AIConnectionViewModel.shared
    @State private var selected: [String] = ["read"]
    private let rights = [
        ("read", "Transcripts en notulen lezen", "Inhoud ophalen en uitvoer downloaden."),
        ("write", "Notulen en sjablonen wijzigen", "Wijzigingen opslaan en schermen openen."),
        ("record", "Opnames bedienen", "Eenmalig toestaan: starten, pauzeren, hervatten en stoppen. De opname blijft zichtbaar.")
    ]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text("Claude en ChatGPT")
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rights, id: \.0) { scope, title, explanation in
                Toggle(isOn: Binding(
                    get: { (model.connection?.scopes ?? selected).contains(scope) },
                    set: { enabled in
                        var scopes = model.connection?.scopes ?? selected
                        scopes.removeAll { $0 == scope }
                        if enabled { scopes.append(scope) }
                        if model.connection != nil { Task { await model.updatePermissions(scopes) } }
                        else { selected = scopes }
                    }
                )) {
                    VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                        Text(LocalizedStringKey(title))
                        Text(LocalizedStringKey(explanation)).font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(model.busy)
            }
            Button(model.connection == nil ? "Apparaat koppelen via browser" : "Ontkoppelen") {
                Task {
                    if model.connection == nil { await model.pair(scopes: selected) }
                    else { await model.disconnect() }
                }
            }.disabled(model.busy || model.connection == nil && selected.isEmpty)
        } header: {
            Text("AI-koppelingen")
        } footer: {
            Text("Optioneel. Je inhoud blijft op dit apparaat en wordt alleen op verzoek opgehaald. Houd de app geopend voor AI-bediening.")
        }
    }
}
