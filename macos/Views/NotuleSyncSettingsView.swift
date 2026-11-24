import SwiftUI

struct NotuleSyncSettingsView: View {
    private var sync: NotuleSyncService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Toggle("Synchroniseer notulen via iCloud", isOn: Binding(
                get: { sync.enabled },
                set: { value in Task { await sync.setEnabled(value) } }
            ))
            .tint(Color.brandPrimary)
            Text("Notulen, transcripties, titels en tags worden gesynchroniseerd met je eigen Apple-account. Zet dit aan op je Mac én iPhone. Audio blijft op het oorspronkelijke apparaat.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
            if sync.enabled {
                Text("Bewerken en verwijderen werkt door op je andere apparaten. Offline wijzigingen worden later verstuurd. Bij gelijktijdige wijzigingen bewaren we een extra versie met ‘bewerkingsconflict’ in de titel.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
                if let error = sync.errorMessage {
                    Text(error).font(TS.Font.footnote).foregroundStyle(Color.statusError)
                        .textSelection(.enabled)
                } else if sync.busy {
                    HStack { ProgressView().controlSize(.small); Text("Synchroniseren…") }
                } else if sync.pendingCount > 0 {
                    Text("Wijzigingen wachten op synchronisatie.").font(TS.Font.footnote)
                } else if let date = sync.lastSync {
                    Text("Laatst gesynchroniseerd: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(TS.Font.footnote)
                } else {
                    Text("iCloud wordt verbonden…").font(TS.Font.footnote)
                }
                Button("Synchroniseer nu") { Task { await sync.syncNow() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(sync.busy)
            } else {
                Text("Uitschakelen bewaart je notulen op dit apparaat en in iCloud.")
                    .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }
        }
    }
}
