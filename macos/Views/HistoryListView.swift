// HistoryListView.swift
// ThoughtVault
//
// Earlier versions of one person or glossary entry, newest first, each with a
// "Herstel" button. The caller performs the restore; the list reloads afterwards.

import SwiftUI

struct HistoryListView: View {
    let kind: HistoryKind
    let itemId: String
    /// Small timeline (dot per version) instead of plain rows; macOS person sheet.
    var timeline = false
    let onRestore: (HistoryEntry) -> Void

    @State private var versions: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            if versions.isEmpty {
                Text("Nog geen eerdere versies")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
            #if os(macOS)
            if timeline {
                ForEach(Array(versions.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(index == 0 ? Color.brandPrimary : HomeColor.controlBorder)
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                            .accessibilityHidden(true)
                        (Text(Self.dateText(entry.date)).foregroundStyle(HomeColor.text)
                            + Text(" · ").foregroundStyle(HomeColor.text3)
                            + Text(Self.sourceText(entry.source)).foregroundStyle(HomeColor.text2))
                            .font(.system(size: 13.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Herstel") {
                            onRestore(entry)
                            reload()
                        }
                        .buttonStyle(StudioQuietButtonStyle(height: 28))
                    }
                }
            }
            #endif
            ForEach(timeline ? [] : versions) { entry in
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
