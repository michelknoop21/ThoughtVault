// SettingsView+Studio.swift
// ThoughtVault
//
// macOS Instellingen shell reconstructed from the approved NorthStar
// (docs/design/settings/thoughtvault-settings-verwerking-northstar.png):
// large title, pill tab bar and the Verwerking page. The other tabs keep their
// existing forms on the same background. Shared building blocks live here; the
// Verwerking cards are in SettingsView+Verwerking and +VerwerkingSide.

#if os(macOS)
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case algemeen, verwerking, notulen, agenda, obsidian, account, geavanceerd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .algemeen:    return "Algemeen"
        case .verwerking:  return "Verwerking"
        case .notulen:     return "Notulen"
        case .agenda:      return "Agenda"
        case .obsidian:    return "Obsidian"
        case .account:     return "Account"
        case .geavanceerd: return "Geavanceerd"
        }
    }

    var icon: String {
        switch self {
        case .algemeen:    return "gear"
        case .verwerking:  return "waveform"
        case .notulen:     return "doc.text"
        case .agenda:      return "calendar"
        case .obsidian:    return "tray.and.arrow.down"
        case .account:     return "person"
        case .geavanceerd: return "slider.horizontal.3"
        }
    }
}

/// Two columns at the NorthStar width (content 1270); below it the side cards
/// move under the main column.
struct SettingsLayout {
    let w: CGFloat
    var twoColumn: Bool { w >= 1100 }
    let leading: CGFloat = 24
    let trailing: CGFloat = 20
    let rightWidth: CGFloat = 342
    let gap: CGFloat = 28
}

extension SettingsView {

    var settingsStudio: some View {
        GeometryReader { geo in
            let layout = SettingsLayout(w: geo.size.width)
            VStack(alignment: .leading, spacing: 0) {
                Text("Instellingen")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(HomeColor.text)
                    .padding(.leading, layout.leading)
                    .padding(.top, 21)
                    .accessibilityAddTraits(.isHeader)
                studioTabBar
                    .padding(.leading, layout.leading)
                    .padding(.trailing, layout.trailing)
                    .padding(.top, 19)
                tabContent(layout)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(
            LinearGradient(colors: [HomeColor.backgroundTop, HomeColor.backgroundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HiddenWindowTitle())
    }

    @ViewBuilder
    private func tabContent(_ layout: SettingsLayout) -> some View {
        switch settingsTab {
        case .verwerking:  verwerkingPage(layout)
        case .algemeen:    algemeenTab.scrollContentBackground(.hidden)
        case .notulen:     profielTab.scrollContentBackground(.hidden)
        case .agenda:      agendaTab.scrollContentBackground(.hidden)
        case .obsidian:    obsidianTab.scrollContentBackground(.hidden)
        case .account:     accountTab.scrollContentBackground(.hidden)
        case .geavanceerd: geavanceerdTab.scrollContentBackground(.hidden)
        }
    }

    private var studioTabBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { studioTabButton($0) }
            }
            .fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 2)], spacing: 2) {
                ForEach(SettingsTab.allCases) { studioTabButton($0).frame(maxWidth: .infinity) }
            }
        }
        .padding(3)
        .frame(maxWidth: 840, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(HomeColor.side))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(HomeColor.sideBorder, lineWidth: 1))
    }

    private func studioTabButton(_ tab: SettingsTab) -> some View {
        let selected = settingsTab == tab
        return Button { settingsTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon).font(.system(size: 14)).frame(width: 16)
                Text(tab.title).font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : HomeColor.text2)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? HomeColor.violet.opacity(0.62) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

}

// MARK: - Building blocks

extension NotulenProvider {
    /// Tile title on the Verwerking page.
    var studioName: String {
        switch self {
        case .openAI:            return "ChatGPT"
        case .anthropic:         return "Claude"
        case .ollamaCloud:       return "Ollama Cloud"
        case .openAICompatible:  return "OpenAI-compatibel"
        case .ollama:            return "Ollama"
        case .lmStudio:          return "LM Studio"
        case .appleIntelligence: return "Apple Intelligence"
        case .cloud:             return "Server"
        }
    }

    var studioSubtitle: String {
        switch self {
        case .openAI, .anthropic, .ollamaCloud: return "Eigen API-sleutel"
        case .openAICompatible:   return "Eigen HTTPS-adres"
        case .ollama:             return "Lokaal of cloud"
        case .lmStudio:           return "Lokale server"
        case .appleIntelligence:  return "Op dit apparaat"
        case .cloud:              return "Via de ThoughtVault-server"
        }
    }

    var studioIcon: String {
        switch self {
        case .openAI:            return "bubble.left.and.text.bubble.right"
        case .anthropic:         return "asterisk"
        case .ollamaCloud:       return "cloud"
        case .openAICompatible:  return "network"
        case .ollama:            return "shippingbox"
        case .lmStudio:          return "server.rack"
        case .appleIntelligence: return "apple.intelligence"
        case .cloud:             return "cloud"
        }
    }

    /// Providers offered as tiles, in display order.
    static let studioChoices: [NotulenProvider] = [.openAI, .anthropic, .ollama, .openAICompatible, .lmStudio, .appleIntelligence]
}

extension View {
    /// Card surface of the Settings NorthStar.
    func studioCard(fill: Color = HomeColor.card, border: Color = HomeColor.cardBorder, padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: 1))
    }
}

struct StudioIconTile: View {
    let systemName: String
    var size: CGFloat = 46
    var tint: Color = HomeColor.lavender

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(HomeColor.control))
            .accessibilityHidden(true)
    }
}

struct StudioBadge: View {
    let text: String
    var color: Color = HomeColor.ready

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

struct StudioRadio: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(selected ? HomeColor.violet : HomeColor.controlBorder, lineWidth: selected ? 2 : 1.5)
            if selected { Circle().fill(Color.white).frame(width: 7, height: 7) }
        }
        .frame(width: 20, height: 20)
        .background(Circle().fill(selected ? HomeColor.violet : .clear))
        .accessibilityHidden(true)
    }
}

/// Selectable option tile (location and provider choices).
struct StudioChoiceTile: View {
    let selected: Bool
    let icon: String
    let title: String
    let subtitle: String
    var badge: String?
    var vertical = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if vertical {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(HomeColor.text)
                            Spacer(minLength: 4)
                            StudioRadio(selected: selected)
                        }
                        Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(HomeColor.text)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(HomeColor.text3)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: icon).font(.system(size: 22)).foregroundStyle(HomeColor.text).frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(HomeColor.text)
                            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(HomeColor.text3)
                        }
                        Spacer(minLength: 6)
                        StudioRadio(selected: selected)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: vertical ? 88 : 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? HomeColor.violet.opacity(0.14) : HomeColor.field.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? HomeColor.violet : HomeColor.controlBorder, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
