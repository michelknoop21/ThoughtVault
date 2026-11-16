// ObsidianLinkBanner.swift
// ThoughtVault
//
// One message for a broken Obsidian vault link (instead of an error per notule),
// plus the shared vault folder picker used by the banner and Settings.

import SwiftUI

struct ObsidianLinkBanner: View {
    /// Opens a picker owned by the host (Settings); nil attaches the banner's own picker.
    var onChoose: (() -> Void)? = nil

    @AppStorage(ObsidianService.enabledKey) private var enabled = false
    @State private var picking = false
    @State private var pickError: String?

    var body: some View {
        if let onChoose {
            content(choose: onChoose)
        } else {
            content { picking = true }
                .obsidianVaultPicker(isPresented: $picking) { pickError = $0 }
        }
    }

    @ViewBuilder
    private func content(choose: @escaping () -> Void) -> some View {
        let status = ObsidianStatus.shared
        if enabled && status.linkBroken {
            box(color: Color.statusError, icon: "exclamationmark.triangle.fill") {
                Text("De koppeling met je Obsidian-vault werkt niet meer. Je notules staan wel in ThoughtVault.")
                if let pickError { Text(pickError).foregroundStyle(Color.statusError) }
                HStack(spacing: TS.Spacing.sm) {
                    Button("Vault opnieuw kiezen", action: choose)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Obsidian uitzetten") { status.turnOff() }
                        .buttonStyle(.borderless)
                }
            }
        } else if enabled && status.notAVault {
            box(color: Color.statusWarning, icon: "exclamationmark.circle.fill") {
                HStack(alignment: .top) {
                    Text("Deze map lijkt geen Obsidian-vault: er staat geen .obsidian-map in.")
                    Spacer(minLength: 0)
                    Button { status.notAVault = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Melding sluiten")
                }
            }
        }
    }

    private func box<C: View>(color: Color, icon: String, @ViewBuilder _ body: () -> C) -> some View {
        HStack(alignment: .top, spacing: TS.Spacing.sm) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: TS.Spacing.sm) { body() }
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelPrimary)
            Spacer(minLength: 0)
        }
        .padding(TS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous).fill(color.opacity(0.08)))
    }
}

extension View {
    /// Vault folder picker shared by Settings and the banner. A pick goes through
    /// `ObsidianStatus.choose` (clears a broken link, flags a folder without `.obsidian`).
    /// `onResult` gets nil on success or a short error text.
    func obsidianVaultPicker(isPresented: Binding<Bool>, onResult: @escaping (String?) -> Void = { _ in }) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                try ObsidianStatus.shared.choose(url)
                onResult(nil)
            } catch {
                onResult("Map-koppeling mislukt: \(error.localizedDescription)")
            }
        }
        .modifier(ObsidianDefaultDirectory())
    }
}

/// Opens the picker in Obsidian's iCloud folder on macOS when it exists; silently
/// does nothing otherwise (older macOS, no Obsidian iCloud folder, sandbox denies the check).
private struct ObsidianDefaultDirectory: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *), let dir = Self.obsidianICloudFolder {
            content.fileDialogDefaultDirectory(dir)
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if os(macOS)
    /// `~/Library/Mobile Documents/iCloud~md~obsidian/Documents` of the real home
    /// (the sandboxed home is the app container, so read it from the passwd entry).
    static var obsidianICloudFolder: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let url = URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    #endif
}
