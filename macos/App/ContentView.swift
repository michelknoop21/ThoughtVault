import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - App Tab

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case record
    case tasks
    case transcripts
    case people
    case settings
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:        return "Home"
        case .record:      return "Opnemen"
        case .tasks:       return "Taken"
        case .transcripts: return "Notulen"
        case .people:      return "Mensen"
        case .settings:    return "Instellingen"
        case .admin:       return "Admin"
        }
    }

    var icon: String {
        switch self {
        case .home:        return "house"
        case .record:      return "mic"
        case .tasks:       return "list.bullet.clipboard"
        case .transcripts: return "doc.text"
        case .people:      return "person.2"
        case .settings:    return "gear"
        case .admin:       return "person.badge.key"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home:        return "house.fill"
        case .record:      return "mic.fill"
        case .tasks:       return "list.bullet.clipboard.fill"
        case .transcripts: return "doc.text.fill"
        case .people:      return "person.2.fill"
        case .settings:    return "gear"
        case .admin:       return "person.badge.key.fill"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .home:        return "1"
        case .record:      return "2"
        case .tasks:       return "3"
        case .transcripts: return "4"
        case .people:      return "5"
        case .settings:    return "6"
        case .admin:       return "7"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(CalendarService.self) private var calendarService

    @State private var selectedTab: AppTab = .home
    /// Set by OnboardingView's first-recording CTA; consumed once to open the recording screen.
    @AppStorage("pendingFirstRecording") private var pendingFirstRecording = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var sidebarCollapsed = false
    @State private var showForceUpdateAlert = false
    @State private var callAlertMeeting: CalendarEvent? = nil
    @State private var callAlertDismissed: Set<String> = []
    @State private var transcriptsNavPath = NavigationPath()
    @State private var seedCandidates: [String] = []
    @State private var showSeedReviewSheet = false

    var body: some View {
        Group {
            // Local mode needs no server, so it bypasses the login gate entirely.
            if authVM.isAuthenticated || recordingVM.isLocalMode {
                authenticatedView
            } else {
                LoginView()
            }
        }
        .task {
            // Local mode is fully offline: skip the backend version check and
            // server profile reload (built-in defaults are loaded on init).
            if !ProcessingMode.isLocalMode {
                await checkMinimumVersion()
                if recordingVM.availableProfiles.isEmpty {
                    await recordingVM.reloadProfiles()
                }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            transcriptsNavPath = NavigationPath()
        }
        .onChange(of: authVM.isAuthenticated) { _, isAuth in
            if isAuth {
                Task { await recordingVM.reloadProfiles() }
                Task { await recordingVM.checkPendingTasks() }
                Task { await calendarService.refreshMicrosoftState() }
                Task { await MicrosoftGraphService.shared.loadTokensFromBackend() }
            }
        }
        .alert("Update vereist", isPresented: $showForceUpdateAlert) {
            Button("Update nu") {
                if let url = URL(string: "https://transcriptstudio.app/download") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    UIApplication.shared.open(url)
                    #endif
                }
            }
        } message: {
            Text("Er is een verplichte update beschikbaar. Update de app om door te gaan.")
        }
    }

    // MARK: - Authenticated View

    @ViewBuilder
    private var authenticatedView: some View {
#if os(macOS)
        macOSView
            .onAppear {
                if pendingFirstRecording {
                    pendingFirstRecording = false
                    selectedTab = .record
                }
            }
            .task { await fetchCalendarIfGranted() }
            .overlay(alignment: .bottomTrailing) {
                if let meeting = callAlertMeeting {
                    CallAlertView(
                        meeting: meeting,
                        onStartRecording: {
                            recordingVM.activeMeeting = meeting
                            callAlertMeeting = nil
                            let isVideoCall = meeting.id.hasPrefix("videocall-")
                            recordingVM.selectedMode = (meeting.meetingURL != nil || isVideoCall) ? .combined : .microphone
                            Task { await recordingVM.startRecording() }
                        },
                        onSnooze: {
                            callAlertMeeting = nil
                            // Will re-appear after 2 minutes via the periodic check
                        },
                        onDismiss: {
                            callAlertDismissed.insert(meeting.id)
                            if meeting.id.hasPrefix("videocall-") {
                                let sessionId = String(meeting.id.dropFirst("videocall-".count))
                                VideoCallDetectionService.shared.dismissSession(sessionId)
                            }
                            callAlertMeeting = nil
                        }
                    )
                    .padding(TS.Spacing.lg)
                    .frame(width: 420)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task {
                while !Task.isCancelled {
                    checkForUpcomingMeeting()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .meetingRecordRequested)) { _ in
                // Start recording directly when user taps OS notification action
                if let meeting = callAlertMeeting {
                    recordingVM.activeMeeting = meeting
                }
                recordingVM.selectedMode = .combined
                Task { await recordingVM.startRecording() }
                callAlertMeeting = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .videoCallDetected)) { notification in
                guard let event = notification.userInfo?["event"] as? CalendarEvent else { return }
                guard !callAlertDismissed.contains(event.id) else { return }
                guard recordingVM.recordingState == .idle else { return }
                withAnimation(TS.Animation.smooth) {
                    callAlertMeeting = event
                }
            }
#else
        iOSView
            .task { await fetchCalendarIfGranted() }
#endif
    }

    private func fetchCalendarIfGranted() async {
        // Microsoft 365 calendar relies on the backend; skip it in local mode.
        // Apple Calendar (EventKit) is local and stays available.
        if !ProcessingMode.isLocalMode {
            await calendarService.refreshMicrosoftState()
            await MicrosoftGraphService.shared.loadTokensFromBackend()
        }

        if calendarService.hasCalendarAccess || calendarService.isMicrosoftConnected {
            await calendarService.fetchUpcomingMeetings()
        }
    }

    private func checkForUpcomingMeeting() {
        let now = Date()
        let meeting = calendarService.upcomingMeetings.first { event in
            !callAlertDismissed.contains(event.id) &&
            event.date > now &&
            event.date.timeIntervalSince(now) <= 5 * 60
        }
        withAnimation(TS.Animation.smooth) {
            callAlertMeeting = meeting
        }
        // Also send OS notification so the alert appears even when app is in background
        if let meeting {
            Task { await MeetingNotificationService.shared.scheduleIfNeeded(for: meeting) }
        }
    }

#if os(macOS)
    private var macOSView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
                .navigationSplitViewColumnWidth(
                    min: sidebarCollapsed ? 52 : 190,
                    ideal: sidebarCollapsed ? 52 : 210,
                    max: sidebarCollapsed ? 52 : 270
                )
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        // Force sidebar always visible — collapse is handled by our custom UI
        .onAppear {
            columnVisibility = .automatic
        }
        .onChange(of: columnVisibility) { _, newValue in
            if newValue == .detailOnly {
                columnVisibility = .automatic
            }
        }
        // Hidden keyboard shortcuts
        .overlay(alignment: .topLeading) {
            keyboardShortcutsOverlay
        }
        // Seed review sheet: presented after recording stops when new attendees are found
        .onChange(of: recordingVM.pendingSeedAttendees) { _, newValue in
            guard let attendees = newValue, !attendees.isEmpty else { return }
            let selfEmail = MicrosoftGraphService.shared.accountEmail
                ?? CalendarService.shared.microsoftAccountEmail
                ?? LocalTranscriptStore.shared.fetchSelfProfile()?.emails.first
            let candidates = PersonDirectoryService.shared.newSeedCandidates(from: attendees, selfEmail: selfEmail)
            recordingVM.pendingSeedAttendees = nil
            guard !candidates.isEmpty else { return }
            seedCandidates = candidates
            showSeedReviewSheet = true
        }
        .sheet(isPresented: $showSeedReviewSheet) {
            SeedReviewSheet(candidates: seedCandidates) {
                showSeedReviewSheet = false
                seedCandidates = []
            }
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Brand stripe at very top
            YingaBar()

            if sidebarCollapsed {
                // Collapsed: icon-only sidebar
                collapsedSidebarContent
            } else {
                // Expanded: full sidebar
                expandedSidebarContent
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
    }

    private var expandedSidebarContent: some View {
        VStack(spacing: 0) {
            // App icon + title
            HStack(spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

                Text("Transcript Studio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.labelPrimary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // User profile section (only show when logged in user data is available)
            if authVM.currentUser != nil {
                userProfileSection
            }

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

            YingaFooter()

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
                .font(TS.Font.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }

    private var collapsedSidebarContent: some View {
        VStack(spacing: 0) {
            // App icon only
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
                .padding(.vertical, 8)

            // Icon-only navigation
            VStack(spacing: 4) {
                ForEach(visibleTabs) { tab in
                    Button { selectedTab = tab } label: {
                        Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 15))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .background {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selectedTab == tab ? Color.brandSecondary : Color.clear)
                                    .shadow(
                                        color: selectedTab == tab ? Color.brandSecondary.opacity(0.3) : .clear,
                                        radius: 4, y: 2
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            .padding(.horizontal, 6)

            Spacer()

            Divider()
                .padding(.vertical, 8)

            // Expand button
            Button {
                withAnimation(TS.Animation.smooth) {
                    sidebarCollapsed = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Menu uitklappen")
            .padding(.bottom, 12)
        }
    }

    private var userProfileSection: some View {
        HStack(spacing: 10) {
            // Avatar circle — neutral so it doesn't read as a selected nav item
            // (selected state owns brandSecondary).
            ZStack {
                Circle()
                    .fill(Color.surfaceTertiary)
                    .frame(width: 32, height: 32)
                Text(authVM.currentUser?.displayFirstName.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.labelSecondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(authVM.currentUser?.displayName ?? "Transcript Studio")
                    .font(TS.Font.footnoteSemibold)
                    .lineLimit(1)
                Text(authVM.currentUser?.email ?? "")
                    .font(TS.Font.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Sidebar collapse button
            Button {
                withAnimation(TS.Animation.smooth) {
                    sidebarCollapsed = true
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
        VStack(spacing: 0) {
            PermissionBanner()
                .padding(.horizontal, TS.Spacing.md)
                .padding(.top, TS.Spacing.sm)

            ProcessingBar()
                .padding(.horizontal, TS.Spacing.md)
                .padding(.top, TS.Spacing.xs)

            tabContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                HomeView(
                    onStartRecording: { _ in
                        selectedTab = .record
                    },
                    onNavigateToTranscripts: {
                        selectedTab = .transcripts
                    }
                )
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

        case .tasks:
            NavigationStack {
                TasksView()
            }
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif

        case .transcripts:
            NavigationStack(path: $transcriptsNavPath) {
                TranscriptsView(
                    transcriptsNavPath: $transcriptsNavPath,
                    onStartRecording: { selectedTab = .record }
                )
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

        case .people:
            NavigationStack {
                PeopleDirectoryView()
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
            // Tab switching ⌘1-5 — only for tabs the user can actually see
            // (prevents e.g. ⌘6 opening Admin in unauthenticated local mode).
            ForEach(visibleTabs) { tab in
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
                    sidebarCollapsed.toggle()
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
                    .foregroundStyle(isSelected ? .white : (isHovered ? Color.brandSecondary : .primary))
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isHovered ? Color.brandSecondary : .primary))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? Color.brandSecondary
                          : (isHovered ? Color.brandSecondary.opacity(0.08) : Color.clear))
                    .shadow(
                        color: isSelected ? Color.brandSecondary.opacity(0.3) : .clear,
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
