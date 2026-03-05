import SwiftUI

// MARK: - App Tab

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case record
    case transcripts
    case settings
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:        return "Home"
        case .record:      return "Opnemen"
        case .transcripts: return "Notulen"
        case .settings:    return "Instellingen"
        case .admin:       return "Admin"
        }
    }

    var icon: String {
        switch self {
        case .home:        return "house"
        case .record:      return "mic"
        case .transcripts: return "doc.text"
        case .settings:    return "gear"
        case .admin:       return "person.badge.key"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home:        return "house.fill"
        case .record:      return "mic.fill"
        case .transcripts: return "doc.text.fill"
        case .settings:    return "gear"
        case .admin:       return "person.badge.key.fill"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .home:        return "1"
        case .record:      return "2"
        case .transcripts: return "3"
        case .settings:    return "4"
        case .admin:       return "5"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(CalendarService.self) private var calendarService

    @State private var selectedTab: AppTab = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showForceUpdateAlert = false

    var body: some View {
        Group {
            if authVM.isAuthenticated {
                authenticatedView
            } else {
                LoginView()
            }
        }
        .task {
            await checkMinimumVersion()
        }
        .alert("Update vereist", isPresented: $showForceUpdateAlert) {
            Button("Update nu") {
                if let url = URL(string: "https://transcriptstudio.app/download") {
                    NSWorkspace.shared.open(url)
                }
            }
        } message: {
            Text("Er is een verplichte update beschikbaar. Update de app om door te gaan.")
        }
    }

    // MARK: - Authenticated View

    private var authenticatedView: some View {
#if os(macOS)
        macOSView
#else
        iOSView
#endif
    }

#if os(macOS)
    private var macOSView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 270)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        // Hidden keyboard shortcuts
        .overlay(alignment: .topLeading) {
            keyboardShortcutsOverlay
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Brand stripe
            YingaBar()
                .padding(.top, 8)

            // User profile section
            userProfileSection

            Divider()
                .padding(.vertical, 8)

            // Navigation items
            VStack(spacing: 2) {
                ForEach(visibleTabs) { tab in
                    SidebarNavItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Divider()
                .padding(.vertical, 8)

            // Logout button
            Button {
                authVM.logout()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .frame(width: 16)
                    Text("Uitloggen")
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .listStyle(.sidebar)
    }

    private var userProfileSection: some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text(authVM.currentUser?.displayFirstName.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(authVM.currentUser?.displayName ?? "Transcript Studio")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(authVM.currentUser?.email ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Sidebar toggle button
            Button {
                withAnimation(TS.Animation.smooth) {
                    columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var detailView: some View {
        ZStack {
            tabContent(for: selectedTab)
        }
    }
#endif

    // MARK: - iOS View

    private var iOSView: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView(onStartRecording: { _ in
                    selectedTab = .record
                })
            }
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif

        case .record:
            NavigationStack {
                RecordingView()
            }
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif

        case .transcripts:
            NavigationStack {
                TranscriptsView()
            }
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif

        case .settings:
            NavigationStack {
                SettingsView()
            }
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif

        case .admin:
            NavigationStack {
                AdminView()
            }
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif
        }
    }

    // MARK: - Visible Tabs

    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { tab in
            if tab == .admin {
                return authVM.currentUser?.role?.lowercased() == "admin"
            }
            return true
        }
    }

    // MARK: - Keyboard Shortcuts Overlay

    private var keyboardShortcutsOverlay: some View {
        Group {
            // Tab switching ⌘1-5
            ForEach(AppTab.allCases) { tab in
                Button("") { selectedTab = tab }
                    .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                    .opacity(0)
            }
            // Quick record ⌘R
            Button("") { selectedTab = .record }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
#if os(macOS)
            // Sidebar toggle ⇧⌘S
            Button("") {
                withAnimation(TS.Animation.smooth) {
                    columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .opacity(0)
#endif
        }
    }

    // MARK: - Version Check

    private func checkMinimumVersion() async {
        let isSupported = (try? await APIService.shared.checkMinimumVersion()) ?? true
        if !isSupported {
            showForceUpdateAlert = true
        }
    }
}

// MARK: - SidebarNavItem

#if os(macOS)
struct SidebarNavItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isSelected ? .white : (isHovered ? Color.brandPrimary : .primary))
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isHovered ? Color.brandPrimary : .primary))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? Color.brandPrimary
                          : (isHovered ? Color.brandPrimary.opacity(0.08) : Color.clear))
                    .shadow(
                        color: isSelected ? Color.brandPrimary.opacity(0.3) : .clear,
                        radius: 4, y: 2
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(TS.Animation.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#endif
