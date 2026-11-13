// SettingsView+Studio.swift
// ThoughtVault
//
// macOS Instellingen shell reconstructed from the approved NorthStar
// (docs/design/settings/thoughtvault-settings-verwerking-northstar.png):
// large title, pill tab bar and the Verwerking page. Shared building blocks live
// here; the Verwerking cards are in SettingsView+Verwerking and +VerwerkingSide,
// the cards of the other tabs in SettingsView+Cards.

#if os(macOS)
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case algemeen, verwerking, woordenlijst, notulen, agenda, obsidian, account, geavanceerd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .algemeen:    return "Algemeen"
        case .verwerking:  return "Verwerking"
        case .woordenlijst: return "Woordenlijst"
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
        case .woordenlijst: return "character.book.closed"
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
        .onChange(of: settingsTab) { _, tab in
            AppLog.clickPath.info("Instellingen \(tab.rawValue)")
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HiddenWindowTitle())
    }

    @ViewBuilder
    private func tabContent(_ layout: SettingsLayout) -> some View {
        switch settingsTab {
        case .verwerking:  verwerkingPage(layout)
        case .woordenlijst:
            PersonalCorrectionsView(profiles: profiles)
                .padding(.leading, layout.leading).padding(.trailing, layout.trailing)
                .padding(.vertical, 24)
        case .algemeen:    algemeenCards(layout)
        case .notulen:     notulenCards(layout)
        case .agenda:      agendaCards(layout)
        case .obsidian:    obsidianCards(layout)
        case .account:     accountCards(layout)
        case .geavanceerd: geavanceerdCards(layout)
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

/// Settings card with an icon tile and a heading, as on the Verwerking page.
/// Rows inside get the card switch style; long text wraps.
struct SettingsCard<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                StudioIconTile(systemName: icon, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HomeColor.text)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(HomeColor.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 14) { content }
                .toggleStyle(StudioRowSwitchStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .studioCard()
    }
}

/// Label on the left, the violet switch on the right, for toggles inside cards.
struct StudioRowSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 14) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(StudioSwitchStyle())
        }
    }
}

/// Quiet secondary button of the restyled windows: neutral fill, lighter on
/// hover, pressed scale, dimmed when disabled.
struct StudioQuietButtonStyle: ButtonStyle {
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration, height: height)
    }

    private struct QuietButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(HomeColor.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: height)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovered && isEnabled ? 0.11 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(HomeColor.controlBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovered = $0 }
                .animation(TS.Animation.quick, value: configuration.isPressed)
                .animation(TS.Animation.quick, value: hovered)
        }
    }
}

/// Dark input chrome: field fill, hairline, indigo ring while focused.
struct StudioFieldModifier: ViewModifier {
    var minHeight: CGFloat = 38
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(HomeColor.text)
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.field.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Color.brandSecondary : HomeColor.fieldBorder, lineWidth: focused ? 1.5 : 1))
            .animation(TS.Animation.quick, value: focused)
    }
}

extension View {
    func studioField(minHeight: CGFloat = 38) -> some View { modifier(StudioFieldModifier(minHeight: minHeight)) }
}

/// Small rounded status or kind chip (support status, Intern/Extern).
struct StudioChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// One segment of a pill switch; the selected thumb slides between segments
/// that share the namespace.
struct StudioSegmentButton: View {
    let title: LocalizedStringKey
    let badge: Int
    let selected: Bool
    let thumb: Namespace.ID
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if badge > 0 {
                    Text(badge, format: .number)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.brandPrimary))
                }
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(selected || hovered ? Color.white : HomeColor.text2)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(HomeColor.violet.opacity(0.62))
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioScalePressStyle(scale: 0.97))
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pressed-state scale with reduced-motion fallback.
struct StudioScalePressStyle: ButtonStyle {
    var scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(TS.Animation.quick, value: configuration.isPressed)
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
