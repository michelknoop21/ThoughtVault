#if os(macOS)
import SwiftUI
import AppKit

/// Settings rows for the local MCP server (McpServer).
struct McpSettingsSection: View {
    @AppStorage(McpServer.enabledKey) private var enabled = false
    @AppStorage(McpServer.allowWriteKey) private var allowWrite = false
    @State private var copied: String?
    private let server = McpServer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Toggle(isOn: $enabled) { Text("Koppeling aan").font(TS.Font.body) }
                .tint(Color.brandPrimary)
                .onChange(of: enabled) { server.apply() }
            Toggle(isOn: $allowWrite) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wijzigingen toestaan").font(TS.Font.body)
                    Text("Notities, mappen, personen en woordenlijst aanpassen en notulen opnieuw laten maken.")
                        .font(TS.Font.caption).foregroundStyle(Color.labelTertiary)
                }
            }
            .tint(Color.brandPrimary)
            .disabled(!enabled)

            if enabled, !server.status.isEmpty {
                Text(server.status).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }

            // Side by side when the card is wide enough, stacked otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TS.Spacing.sm) { copyButtons }
                VStack(alignment: .leading, spacing: TS.Spacing.sm) { copyButtons }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!enabled)
            if let copied {
                Text(copied == "desktop" ? "Configuratie gekopieerd" : "Opdracht gekopieerd")
                    .font(TS.Font.caption).foregroundStyle(Color.labelTertiary)
            }
        }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = nil
        }
    }

    @ViewBuilder private var copyButtons: some View {
        Button("Kopieer voor Claude Desktop") { copy(desktopConfig, as: "desktop") }
        Button("Kopieer opdracht voor Claude Code") { copy(codeCommand, as: "code") }
    }

    private var executable: String { Bundle.main.executablePath ?? "/Applications/ThoughtVault.app/Contents/MacOS/ThoughtVault" }

    private var desktopConfig: String {
        let config = ["mcpServers": ["thoughtvault": ["command": executable, "args": ["--mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private var codeCommand: String { "claude mcp add thoughtvault -- \"\(executable)\" --mcp" }

    private func copy(_ text: String, as kind: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = kind
    }
}
#endif
