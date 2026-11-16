// ParakeetModelRows.swift
// ThoughtVault
//
// One row per Parakeet model on the Verwerking page (macOS and iOS): pick it,
// see whether it suits this device, and download, stop, remove or retry.
// Selecting a model, or finishing its download, stores it as `parakeetModel`.

import SwiftUI

struct ParakeetModelRows: View {
    @AppStorage(ParakeetCatalog.defaultsKey) private var stored = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recommended = ParakeetModelStore.recommended
    private let store = ParakeetModelStore.shared

    private var selectedID: String { ParakeetCatalog.selectedID(stored: stored, recommended: recommended) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ParakeetCatalog.all) { model in
                ParakeetModelRow(model: model, recommended: model.id == recommended.id,
                                 selected: model.id == selectedID, store: store) {
                    stored = model.id
                }
                .onChange(of: store.state(model.id)) { old, new in
                    if case .downloading = old, new == .installed { stored = model.id }
                }
            }
            Text("Parakeet-modellen van NVIDIA, licentie CC BY 4.0")
                .font(.system(size: 12)).foregroundStyle(HomeColor.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedID)
    }
}

private struct ParakeetModelRow: View {
    let model: ParakeetModel
    let recommended: Bool
    let selected: Bool
    let store: ParakeetModelStore
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: ParakeetModelStore.State { store.state(model.id) }
    private var installed: Bool { state == .installed }
    /// An installed model stays usable even if the device no longer qualifies.
    private var blocker: ParakeetCatalog.Blocker? { installed ? nil : ParakeetModelStore.blocker(model) }

    #if os(macOS)
    private static var recommendedText: String { String(localized: "Aangeraden voor deze Mac") }
    private static let buttonHeight: CGFloat = 30
    #else
    private static var recommendedText: String { String(localized: "Aangeraden voor dit toestel") }
    private static let buttonHeight: CGFloat = 44
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: select) {
                HStack(alignment: .top, spacing: 14) {
                    StudioRadio(selected: selected).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(HomeColor.text)
                        if recommended || (selected && installed) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) { badges }
                                VStack(alignment: .leading, spacing: 6) { badges }
                            }
                        }
                        if let blocker {
                            blockerText(blocker)
                                .font(.system(size: 13)).foregroundStyle(HomeColor.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(verbatim: "\(model.sizeText) · \(NSLocalizedString(model.languages, comment: ""))")
                            .font(.system(size: 13)).foregroundStyle(HomeColor.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(StudioScalePressStyle(scale: 0.97))
            .disabled(blocker != nil)
            .accessibilityAddTraits(selected ? .isSelected : [])

            action
                .padding(.leading, 34)
                .transition(.opacity)
                .id(stateKey)
        }
        .padding(.vertical, 10)
        .opacity(blocker == nil ? 1 : 0.6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: stateKey)
    }

    @ViewBuilder private var badges: some View {
        if recommended { StudioBadge(text: Self.recommendedText) }
        if selected && installed { StudioBadge(text: String(localized: "In gebruik"), color: HomeColor.lavender) }
    }

    private func blockerText(_ blocker: ParakeetCatalog.Blocker) -> Text {
        switch blocker {
        #if os(macOS)
        case .system(let version): Text("Vraagt macOS \(version) of nieuwer.")
        #else
        case .system(let version): Text("Vraagt iOS \(version) of nieuwer.")
        #endif
        case .memory(let gb): Text("Te weinig geheugen: vraagt \(gb) GB.")
        case .storage(let mb): Text("Te weinig vrije opslag: vraagt \(ParakeetModel.sizeText(mb)).")
        }
    }

    /// Changes only when the kind of state changes, not with every progress tick.
    private var stateKey: String {
        switch state {
        case .missing: "missing"
        case .downloading: "downloading"
        case .installed: "installed"
        case .failed: "failed"
        }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .missing:
            Button { store.download(model.id) } label: {
                Label("Download", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
            .disabled(blocker != nil)
        case .downloading(let fraction):
            HStack(spacing: 10) {
                ProgressView(value: fraction)
                    .tint(HomeColor.violet)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)
                    .accessibilityLabel("Downloaden")
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(HomeColor.text2)
                    .fixedSize()
                Button("Stop") { store.cancel(model.id) }
                    .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
            }
        case .installed:
            Button("Verwijder") { store.remove(model.id) }
                .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Downloaden lukte niet: \(reason)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 12.5)).foregroundStyle(HomeColor.warning)
                .fixedSize(horizontal: false, vertical: true)
                Button("Opnieuw") { store.download(model.id) }
                    .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
            }
        }
    }
}
