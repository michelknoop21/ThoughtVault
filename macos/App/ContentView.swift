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
    @State private var pendingTranscript: Transcript? = nil
    /// Query from the Home search field, handed to Notulen once.
    @State private var homeSearch = ""

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
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .transcripts { homeSearch = "" }
            transcriptsNavPath = NavigationPath()
            if let transcript = pendingTranscript {
                transcriptsNavPath.append(transcript)
                pendingTranscript = nil
            }
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
            .onAppear {
                if pendingFirstRecording {
                    pendingFirstRecording = false
                    selectedTab = .record
                }
            }
            .task { await fetchCalendarIfGranted() }
            .task {
                if let tab = IOSDebug.string("TVDebugTab").flatMap(AppTab.init(rawValue:)) { selectedTab = tab }
                if IOSDebug.open == "transcript", let first = LocalTranscriptStore.shared.allTranscripts().first {
                    openTranscript(first)
                }
                if IOSDebug.open == "record" { await recordingVM.startRecording() }
                if IOSDebug.open == "task" || IOSDebug.open == "processing" {
                    await recordingVM.startRecording()
                    try? await Task.sleep(for: .seconds(4))
                    await recordingVM.stopAndUpload()
                }
            }
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
                    min: sidebarCollapsed ? 52 : 238,
                    ideal: sidebarCollapsed ? 52 : 238,
                    max: sidebarCollapsed ? 52 : 270
                )
        } detail: {
            detailView
                .background(Color.backgroundDark)
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
        MainSidebar(
            selectedTab: $selectedTab,
            collapsed: $sidebarCollapsed,
            visibleTabs: visibleTabs,
            onOpenTranscript: openTranscript
        )
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

    /// Opens a transcript from a recent list in the Notulen tab.
    private func openTranscript(_ transcript: Transcript) {
        if selectedTab == .transcripts {
            transcriptsNavPath = NavigationPath()
            transcriptsNavPath.append(transcript)
        } else {
            pendingTranscript = transcript
            selectedTab = .transcripts
        }
    }

    // MARK: - iOS View

    /// The approved iOS NorthStar has five tabs; Mensen and Admin live in
    /// Instellingen (SettingsView).
    private static let iOSTabs: [AppTab] = [.home, .record, .transcripts, .tasks, .settings]

    private var iOSView: some View {
        TabView(selection: $selectedTab) {
            ForEach(Self.iOSTabs) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tint(Color(red: 0.72, green: 0.50, blue: 1.0))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView(
                    onStartRecording: startRecordingFromHome,
                    onNavigateToTranscripts: {
                        selectedTab = .transcripts
                    },
                    onOpenTranscript: openTranscriptFromHome,
                    onSearch: { query in
                        homeSearch = query
                        selectedTab = .transcripts
                    },
                    onOpenSettings: { selectedTab = .settings },
                    onStartMeeting: startMeetingFromHome
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
                    onStartRecording: { selectedTab = .record },
                    initialSearch: homeSearch
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

    /// Home's record controls start right away on macOS (approved Home
    /// NorthStar); iOS keeps navigating to the recording screen.
    private func startRecordingFromHome(_ mode: RecordingMode) {
        selectedTab = .record
#if os(macOS)
        guard recordingVM.recordingState == .idle else { return }
        recordingVM.selectedMode = mode
        Task { await recordingVM.startRecording() }
#endif
    }

    private func openTranscriptFromHome(_ transcript: Transcript) {
        openTranscript(transcript)
    }

    /// "Start opname" on a meeting in today's agenda (iOS Home): same start as
    /// the macOS call alert, microphone only on iOS.
    private func startMeetingFromHome(_ meeting: CalendarEvent) {
        guard recordingVM.recordingState == .idle else { return }
        recordingVM.activeMeeting = meeting
        recordingVM.selectedMode = .microphone
        selectedTab = .record
        Task { await recordingVM.startRecording() }
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
