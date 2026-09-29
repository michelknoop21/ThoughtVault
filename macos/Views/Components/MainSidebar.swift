// MainSidebar.swift
// ThoughtVault
//
// macOS sidebar in the approved NorthStar style: wordmark, the existing
// destinations, recent notulen, and settings/admin at the bottom. Collapses to
// a 52 pt icon column (⇧⌘S, DEC-029).

import SwiftUI

/// Recent transcripts: local records first, merged with the server list
/// (skipped in local mode), newest first. Shared by Home and the sidebar.
@MainActor
enum RecentTranscripts {
    static func load(limit: Int) async -> (items: [Transcript], error: String?) {
        let local = LocalTranscriptStore.shared.allTranscripts()
        var server: [Transcript] = []
        var error: String?
        if !ProcessingMode.isLocalMode {
            do {
                server = try await APIService.shared.getTranscripts().items
            } catch let e {
                // Server unavailable is fine; only surface if nothing local.
                if local.isEmpty { error = e.localizedDescription }
            }
        }
        let localIds = Set(local.map(\.taskId))
        let merged = (local + server.filter { !localIds.contains($0.taskId) })
            .sorted { $0.date > $1.date }
        return (Array(merged.prefix(limit)), error)
    }
}

#if os(macOS)
struct MainSidebar: View {
    @Binding var selectedTab: AppTab
    @Binding var collapsed: Bool
    let visibleTabs: [AppTab]
    let onOpenTranscript: (Transcript) -> Void

    @State private var recent: [Transcript] = []

    private static let background = Color(red: 0.043, green: 0.067, blue: 0.145)
    private static let utilityTabs: Set<AppTab> = [.settings, .admin]

    var body: some View {
        Group {
            if collapsed { collapsedContent } else { expandedContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.background.ignoresSafeArea())
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
        .task(id: selectedTab) { recent = await RecentTranscripts.load(limit: 5).items }
    }

    // MARK: Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.78, green: 0.49, blue: 1), Color(red: 0.48, green: 0.25, blue: 0.95)],
                                                    startPoint: .top, endPoint: .bottom))
                Text("ThoughtVault")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .padding(.leading, 13)
            .padding(.trailing, 6)
            .padding(.top, 30)
            // Collapse control sits in the title-bar row, right of the traffic lights.
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(TS.Animation.smooth) { collapsed = true }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Menu inklappen (⇧⌘S)")
                .offset(y: -39)
            }

            VStack(spacing: 2) {
                ForEach(visibleTabs.filter { !Self.utilityTabs.contains($0) }) { tab in
                    SidebarNavItem(tab: tab, isSelected: selectedTab == tab) { selectedTab = tab }
                }
            }
            .padding(.top, 30)

            ViewThatFits(in: .vertical) {
                ForEach([5, 4, 3, 2, 1, 0], id: \.self) { count in
                    recentSection(Array(recent.prefix(count)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 2) {
                ForEach(visibleTabs.filter { Self.utilityTabs.contains($0) }) { tab in
                    SidebarNavItem(tab: tab, isSelected: selectedTab == tab) { selectedTab = tab }
                }
            }
            .padding(.bottom, 12)
        }
        .padding(.leading, 15)
        .padding(.trailing, 13)
    }

    @ViewBuilder
    private func recentSection(_ items: [Transcript]) -> some View {
        if items.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.47, green: 0.51, blue: 0.75).opacity(0.16))
                    .frame(height: 1)
                    .padding(.horizontal, 15)
                    .padding(.top, 35)
                Text("Recent")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.84, green: 0.85, blue: 0.91))
                    .padding(.leading, 15)
                    .padding(.top, 20)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { transcript in
                        recentRow(transcript)
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 13)
            }
        }
    }

    private func recentRow(_ transcript: Transcript) -> some View {
        Button { onOpenTranscript(transcript) } label: {
            HStack(spacing: 12) {
                Image(systemName: transcript.notuleHtml != nil ? "doc.text" : "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.9, green: 0.906, blue: 0.95))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.129, green: 0.145, blue: 0.251)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcript.title)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.93, green: 0.933, blue: 0.965))
                        .lineLimit(1)
                    Text(Self.recentDate(transcript.date))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(red: 0.647, green: 0.663, blue: 0.769))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(transcript.title), \(Self.recentDate(transcript.date))")
    }

    /// "Vandaag 14:07", "Gisteren 16:34", "23 sep 09:12".
    static func recentDate(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if cal.isDateInToday(date) { return "Vandaag \(time)" }
        if cal.isDateInYesterday(date) { return "Gisteren \(time)" }
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "nl_NL")))
        return "\(day.replacingOccurrences(of: ".", with: "")) \(time)"
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        VStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.7, green: 0.45, blue: 1))
                .frame(height: 30)
                .padding(.top, 30)
                .padding(.bottom, 18)
            ForEach(visibleTabs) { tab in
                Button { selectedTab = tab } label: {
                    Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 15))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(selectedTab == tab ? .white : Color(red: 0.9, green: 0.906, blue: 0.95))
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? AnyShapeStyle(SidebarNavItem.selectedFill) : AnyShapeStyle(Color.clear))
                        }
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer()
            Button {
                withAnimation(TS.Animation.smooth) { collapsed = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Menu uitklappen")
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SidebarNavItem

struct SidebarNavItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    static let selectedFill = LinearGradient(colors: [Color(red: 0.42, green: 0.23, blue: 0.79), Color(red: 0.31, green: 0.15, blue: 0.62)],
                                             startPoint: .leading, endPoint: .trailing)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 22, height: 22)
                Text(tab.title)
                    .font(.system(size: 15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : Color(red: 0.9, green: 0.906, blue: 0.95))
            .padding(.leading, 16)
            .frame(height: 45)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Self.selectedFill)
                                     : AnyShapeStyle(isHovered ? Color.white.opacity(0.04) : Color.clear))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color(red: 0.75, green: 0.59, blue: 1).opacity(0.28), lineWidth: 1)
                        }
                    }
                    .shadow(color: isSelected ? Color(red: 0.55, green: 0.31, blue: 0.94).opacity(0.45) : .clear, radius: 11)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(TS.Animation.hover) { isHovered = hovering }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
