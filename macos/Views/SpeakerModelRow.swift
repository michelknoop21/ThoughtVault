// SpeakerModelRow.swift
// ThoughtVault
//
// Speaker detection on the Verwerking page (macOS and iOS): fetch, stop or remove its models.
// Without them a transcript stays plain text, as before.

import SwiftUI

struct SpeakerModelRow: View {
    private let store = SpeakerModelStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    private static let buttonHeight: CGFloat = 30
    #else
    private static let buttonHeight: CGFloat = 44
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Herken wie wanneer spreekt").font(.system(size: 14, weight: .semibold)).foregroundStyle(HomeColor.text)
            Text("Na de opname krijgt de transcriptie per stem een spreker. Dat gebeurt op dit apparaat; het model is 21 MB.")
                .font(.system(size: 13)).foregroundStyle(HomeColor.text3)
                .fixedSize(horizontal: false, vertical: true)
            action.transition(.opacity).id(stateKey)
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: stateKey)
    }

    private var stateKey: String {
        switch store.state {
        case .missing: "missing"
        case .downloading: "downloading"
        case .installed: "installed"
        case .failed: "failed"
        }
    }

    @ViewBuilder private var action: some View {
        switch store.state {
        case .missing:
            Button { store.download() } label: { Label("Download", systemImage: "arrow.down.to.line") }
                .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
        case .downloading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).accessibilityLabel("Downloaden")
                Text("Downloaden").font(.system(size: 12.5)).foregroundStyle(HomeColor.text2)
                Button("Stop") { store.cancel() }
                    .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
            }
        case .installed:
            HStack(spacing: 10) {
                StudioBadge(text: String(localized: "In gebruik"), color: HomeColor.lavender)
                Button("Verwijder") { store.remove() }
                    .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Downloaden lukte niet: \(reason)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 12.5)).foregroundStyle(HomeColor.warning)
                .fixedSize(horizontal: false, vertical: true)
                Button("Opnieuw") { store.download() }
                    .buttonStyle(StudioQuietButtonStyle(height: Self.buttonHeight))
            }
        }
    }
}
