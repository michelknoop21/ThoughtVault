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
                Text("Lokale MCP")
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
            Button(model.connection == nil ? "Lokale MCP inschakelen" : "Ontkoppelen") {
                Task {
                    if model.connection == nil { await model.pair(scopes: selected) }
                    else { await model.disconnect() }
                }
            }.disabled(model.busy || model.connection == nil && selected.isEmpty)
            if model.connection != nil {
                Text("http://127.0.0.1:11218/mcp").font(.caption).textSelection(.enabled)
                Button("Kopieer MCP-configuratie") { model.copyConfiguration() }
            }
        } header: {
            Text("AI-koppelingen")
        } footer: {
            Text("Optioneel. Je inhoud blijft op dit apparaat en wordt alleen op verzoek opgehaald. Alleen bereikbaar op deze Mac, zonder account. Gebruik een MCP-client met lokale HTTP-ondersteuning en houd ThoughtVault geopend.")
        }
    }
}
