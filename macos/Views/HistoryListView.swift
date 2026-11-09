// HistoryListView.swift
// ThoughtVault
//
// Earlier versions of one person or glossary entry, newest first, each with a
// "Herstel" button. The caller performs the restore; the list reloads afterwards.

import SwiftUI

struct HistoryListView: View {
    let kind: HistoryKind
    let itemId: String
    let onRestore: (HistoryEntry) -> Void

    @State private var versions: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            if versions.isEmpty {
                Text("Nog geen eerdere versies")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
            ForEach(versions) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateText(entry.date)).font(TS.Font.body).foregroundStyle(Color.labelPrimary)
                        Text(Self.sourceText(entry.source)).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Button("Herstel") {
                        onRestore(entry)
                        reload()
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: itemId) { reload() }
    }

    private func reload() { versions = ContextHistory.versions(kind: kind, itemId: itemId) }

    static func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "nl_NL")))
    }

    static func sourceText(_ source: String) -> String {
        if source.hasPrefix("gesprek:") { return "Uit gesprek" }
        if source.hasPrefix("voorstel:") { return "Voorstel" }
        return source == "herstel" ? "Hersteld" : "Handmatig"
    }
}
