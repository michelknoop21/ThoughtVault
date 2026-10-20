// HomeView+Studio.swift
// ThoughtVault
//
// macOS Home screen, reconstructed from the approved Home NorthStar
// (docs/design/home/thoughtvault-home-northstar-approved.png, 2026-09-29):
// search bar and account menu, greeting header with the mountain illustration,
// the "Nieuwe opname" card, recent notulen, and a right column with today's
// agenda, quick capture and a short brand note (HomeView+Card/+Panels/+Side.swift,
// Components/HomeDecor.swift).
// Geometry values are the NorthStar's, measured at a 1567 x 972 window.
// Every control maps onto existing behaviour; product gaps are left out.

#if os(macOS)
import SwiftUI

/// Colours sampled from the approved Home NorthStar.
enum HomeColor {
    static let backgroundTop = Color(red: 0.078, green: 0.094, blue: 0.157)
    static let backgroundBottom = Color(red: 0.059, green: 0.075, blue: 0.133)
    static let field = Color(red: 0.106, green: 0.129, blue: 0.212)
    static let fieldBorder = Color(red: 0.20, green: 0.23, blue: 0.36)
    static let card = Color(red: 0.075, green: 0.094, blue: 0.165)
    static let cardTop = Color(red: 0.086, green: 0.102, blue: 0.188)
    static let cardBorder = Color(red: 0.25, green: 0.24, blue: 0.45).opacity(0.75)
    static let panel = Color(red: 0.090, green: 0.122, blue: 0.192)
    static let panelBorder = Color(red: 0.16, green: 0.20, blue: 0.29)
    static let control = Color(red: 0.110, green: 0.141, blue: 0.200)
    static let controlBorder = Color(red: 0.20, green: 0.24, blue: 0.33)
    static let side = Color(red: 0.047, green: 0.067, blue: 0.114)
    static let sideBorder = Color(red: 0.12, green: 0.14, blue: 0.22)
    static let list = Color(red: 0.055, green: 0.075, blue: 0.129)
    static let listBorder = Color(red: 0.14, green: 0.16, blue: 0.24)
    static let divider = Color(red: 0.13, green: 0.15, blue: 0.22)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.97)
    static let text2 = Color(red: 0.72, green: 0.74, blue: 0.84)
    static let text3 = Color(red: 0.58, green: 0.61, blue: 0.72)
    static let kicker = Color(red: 0.56, green: 0.57, blue: 0.78)
    static let lavender = Color(red: 0.72, green: 0.62, blue: 1.0)
    static let violet = Color(red: 0.49, green: 0.30, blue: 0.99)
    static let ready = Color(red: 0.30, green: 0.80, blue: 0.47)
    static let warning = Color(red: 0.98, green: 0.69, blue: 0.24)
}

/// Two columns at the NorthStar width; below it the right column's cards move
/// under the recording card and the card's microphone panel moves under its
/// controls.
struct HomeLayout {
    let w: CGFloat
    var twoColumn: Bool { w >= 1180 }
    var leading: CGFloat { twoColumn ? 23 : 20 }
    var trailing: CGFloat { twoColumn ? 11 : 20 }
    let rightWidth: CGFloat = 295
    let gap: CGFloat = 23
    var mainWidth: CGFloat { w - leading - trailing - (twoColumn ? rightWidth + gap : 0) }
    var cardPanelBeside: Bool { mainWidth >= 780 }
    var showTagline: Bool { mainWidth >= 820 }
    /// Below the tagline width the illustration shrinks so the moon stays
    /// clear of the greeting.
    var illustrationScale: CGFloat { showTagline ? 1 : min(1, max(0.45, (mainWidth - 430) / 340)) }
}

extension HomeView {

    var homeStudio: some View {
        GeometryReader { geo in
            let layout = HomeLayout(w: geo.size.width)
            VStack(spacing: 0) {
                topBar(layout)
                    .padding(.top, 17)
                HStack(alignment: .top, spacing: layout.gap) {
                    ScrollView(.vertical) {
                        mainColumn(layout)
                            .frame(width: layout.mainWidth, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    if layout.twoColumn {
                        ScrollView(.vertical) {
                            homeSideColumn
                                .padding(.top, 21)
                                .padding(.bottom, 20)
                        }
                        .scrollIndicators(.never)
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: layout.rightWidth)
                    }
                }
                .padding(.leading, layout.leading)
                .padding(.trailing, layout.trailing)
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
        .task { await PermissionManager.shared.checkAllPermissions() }
    }

    // MARK: Top bar

    private func topBar(_ layout: HomeLayout) -> some View {
        HStack(spacing: 0) {
            searchField
                .padding(.leading, layout.twoColumn ? 3 : 0)
                .frame(width: layout.twoColumn ? layout.mainWidth - 16 : nil)
            Spacer(minLength: 16)
            accountMenu
                .padding(.trailing, layout.twoColumn ? 14 : 0)
        }
        .padding(.leading, layout.leading)
        .padding(.trailing, layout.trailing)
        .frame(height: 51)
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(HomeColor.text2)
            TextField("", text: $searchQuery, prompt: Text("Zoek in je notulen\u{2026}").foregroundStyle(HomeColor.text3))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(HomeColor.text)
                .onSubmit {
                    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !query.isEmpty else { return }
                    onSearch?(query)
                }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 51, maxHeight: 51)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeColor.field.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.fieldBorder, lineWidth: 1))
    }

    private var initials: String {
        let parts = (authVM.currentUser?.name ?? "").split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(firstName.prefix(1)) : letters
    }

    private var accountMenu: some View {
        Menu {
            Button("Instellingen") { onOpenSettings?() }
            if authVM.isAuthenticated {
                Divider()
                Button("Uitloggen", role: .destructive) { authVM.logout() }
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if initials.isEmpty {
                        Image(systemName: "person").font(.system(size: 15))
                    } else {
                        Text(initials.uppercased()).font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(red: 0.153, green: 0.165, blue: 0.298)))
                .overlay(Circle().strokeBorder(Color(red: 0.30, green: 0.30, blue: 0.52).opacity(0.6), lineWidth: 1))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HomeColor.text2)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Account")
    }

    // MARK: Main column

    private func mainColumn(_ layout: HomeLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(layout)
                .padding(.top, 10)
            recordingCard(layout)
            if !layout.twoColumn {
                compactSideCards(layout)
                    .padding(.top, 20)
            }
            homeActiveProcessing
            homeRecentSection
                .padding(.top, 31)
                .padding(.bottom, 24)
        }
    }

    // MARK: Header

    private func header(_ layout: HomeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            HomeIllustration()
                .frame(width: 480, height: 190)
                .scaleEffect(layout.illustrationScale, anchor: .topTrailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 2, y: 3)
                .accessibilityHidden(true)
            if layout.showTagline {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Spreek. Denk. Bewaar.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.74, green: 0.69, blue: 0.93))
                    Text("ThoughtVault zet je gesprekken om in heldere notities, taken en inzichten.")
                        .font(.system(size: 12.5))
                        .lineSpacing(4)
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 182, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 90)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(dateKicker)
                    .font(.system(size: 11.5, weight: .semibold))
                    .kerning(1.9)
                    .textCase(.uppercase)
                    .foregroundStyle(HomeColor.kicker)
                    .frame(height: 13)
                (Text(firstName.isEmpty ? greeting + "." : greeting + ", ")
                    .foregroundStyle(Color(red: 0.94, green: 0.94, blue: 0.97))
                 + Text(firstName.isEmpty ? "" : firstName + ".")
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.74, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.40, blue: 0.97)],
                                                    startPoint: .leading, endPoint: .trailing)))
                    .font(.system(size: layout.mainWidth < 700 ? 34 : 41, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 10)
                Text("\u{201C}Goede idee\u{00EB}n beginnen vaak met een gesprek.\u{201D}")
                    .font(.system(size: 18))
                    .foregroundStyle(HomeColor.text2)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color(red: 0.36, green: 0.38, blue: 0.52))
                    .frame(width: 43, height: 1)
                    .padding(.top, 22)
            }
            .padding(.leading, 17)
            .padding(.top, 42)
        }
        .frame(height: 200, alignment: .top)
    }
}
#endif
