// SettingsView+Studio.swift
// ThoughtVault
//
// macOS Instellingen shell reconstructed from the approved NorthStar
// (docs/design/settings/thoughtvault-settings-verwerking-northstar.png):
// large title, pill tab bar and the Verwerking page. The building blocks shared
// with iOS live in Components/StudioComponents.swift; the Verwerking cards are in
// SettingsView+Verwerking and +VerwerkingSide, the cards of the other tabs in
// SettingsView+Cards.

#if os(macOS)
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case algemeen, verwerking, woordenlijst, notulen, huisstijlen, agenda, obsidian, account, geavanceerd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .algemeen:    return "Algemeen"
        case .verwerking:  return "Verwerking"
        case .woordenlijst: return "Woordenlijst"
        case .notulen:     return "Notulen"
        case .huisstijlen: return "Huisstijlen"
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
        case .huisstijlen: return "paintpalette"
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
        case .huisstijlen: DocumentBrandingView()
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

// MARK: - Building blocks (macOS only: StudioSwitchStyle is in RecordingView+Studio)

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
#endif
