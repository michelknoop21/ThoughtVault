import SwiftUI

@main
struct TranscriptStudioApp: App {
    @State private var authVM = AuthViewModel()
    @State private var recordingVM = RecordingViewModel()
    @State private var tasksVM = TasksViewModel()
    @State private var updateCheckService = UpdateCheckService()
    let calendarService = CalendarService.shared
    let permissionManager = PermissionManager.shared
    let debugLogger = DebugLogger.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authVM)
                .environment(recordingVM)
                .environment(tasksVM)
                .environment(updateCheckService)
                .environment(calendarService)
                .environment(permissionManager)
                .task {
                    await permissionManager.checkAllPermissions()
                    AudioRecorder.cleanupOldRecordings(
                        protecting: recordingVM.offlineQueue.queuedAudioURLs
                    )
                    await recordingVM.processQueueOnStartupIfNeeded()
                    MeetingNotificationService.shared.setup()
                    await MeetingNotificationService.shared.requestPermission()
                    #if os(macOS)
                    VideoCallDetectionService.shared.startMonitoring()
                    #endif
                }
        }
#if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.automatic)
#endif

#if os(macOS)
        Settings {
            SettingsView()
                .environment(authVM)
                .environment(recordingVM)
                .environment(tasksVM)
                .environment(calendarService)
                .environment(permissionManager)
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(authVM)
                .environment(recordingVM)
                .environment(tasksVM)
                .environment(calendarService)
                .environment(permissionManager)
        } label: {
            MenuBarStatusLabel(recordingVM: recordingVM)
        }
        .menuBarExtraStyle(.menu)
#endif
    }

}

// MARK: - RootView

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @Environment(RecordingViewModel.self) private var recordingVM

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
#if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: recordingVM.recordingState) { _, newState in
            switch newState {
            case .recording, .paused, .preparing, .stopping, .uploading:
                FloatingWidgetController.shared.show(recordingVM: recordingVM)
            case .idle, .error:
                FloatingWidgetController.shared.hide()
            }
        }
#endif
    }

}

// MARK: - MenuBar Content View (macOS)

#if os(macOS)
struct MenuBarContentView: View {
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(AuthViewModel.self) private var authVM
    @Environment(CalendarService.self) private var calendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status header
            HStack {
                Circle()
                    .fill(recordingVM.recordingState == .recording ? Color.red : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
                .padding(.vertical, 4)

            // Recording controls
            switch recordingVM.recordingState {
            case .idle:
                Button {
                    Task { await recordingVM.startRecording() }
                } label: {
                    Label("Start opname", systemImage: "mic.circle.fill")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            case .recording:
                Button {
                    recordingVM.pauseRecording()
                } label: {
                    Label("Pauzeer", systemImage: "pause.circle.fill")
                }

                Divider()

                Button {
                    Task { await recordingVM.stopAndUpload() }
                } label: {
                    Label("Stop en upload", systemImage: "arrow.up.circle.fill")
                }

                Button(role: .destructive) {
                    Task { await recordingVM.cancelRecording() }
                } label: {
                    Label("Annuleer opname", systemImage: "xmark.circle.fill")
                }

            case .paused:
                Button {
                    recordingVM.resumeRecording()
                } label: {
                    Label("Hervat", systemImage: "play.circle.fill")
                }

                Divider()

                Button {
                    Task { await recordingVM.stopAndUpload() }
                } label: {
                    Label("Stop en upload", systemImage: "arrow.up.circle.fill")
                }

                Button(role: .destructive) {
                    Task { await recordingVM.cancelRecording() }
                } label: {
                    Label("Annuleer opname", systemImage: "xmark.circle.fill")
                }

            case .preparing, .stopping, .uploading:
                Text("Bezig...")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

            case .error(let message):
                Text("Fout: \(message)")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)

                Button {
                    Task { await recordingVM.startRecording() }
                } label: {
                    Label("Opnieuw proberen", systemImage: "arrow.clockwise")
                }
            }

            // Upcoming meetings
            if !calendarService.upcomingMeetings.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Aankomende vergaderingen")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                ForEach(calendarService.upcomingMeetings.prefix(3)) { meeting in
                    Button {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let url = meeting.meetingURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(meeting.title)
                                    .lineLimit(1)
                                Text(meetingTimeText(meeting))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: meeting.platform.iconName)
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Transcript Studio", systemImage: "macwindow")
            }

            Button("Afsluiten") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 250)
    }

    private var statusText: String {
        switch recordingVM.recordingState {
        case .idle:
            return authVM.isAuthenticated ? "Niet aan het opnemen" : "Niet ingelogd"
        case .preparing:
            return "Voorbereiden..."
        case .recording:
            return "Opname bezig"
        case .paused:
            return "Gepauzeerd"
        case .stopping:
            return "Stoppen..."
        case .uploading:
            return "Uploaden..."
        case .error:
            return "Fout opgetreden"
        }
    }

    private func meetingTimeText(_ meeting: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: meeting.date)
        let end = formatter.string(from: meeting.endDate)

        if meeting.startsWithin(minutes: 15) {
            return "Begint zo (\(start))"
        }
        return "\(start) – \(end)"
    }

}

// MARK: - MenuBar Status Label (macOS)

struct MenuBarStatusLabel: View {
    let recordingVM: RecordingViewModel

    var body: some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(spacing: 4) {
                menuBarIcon
                    .foregroundStyle(.red)
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }

        case .paused:
            HStack(spacing: 4) {
                menuBarIcon
                    .foregroundStyle(.orange)
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .opacity(0.7)

        case .uploading:
            HStack(spacing: 4) {
                menuBarIcon
                    .foregroundStyle(.blue)
                Image(systemName: "arrow.up")
                    .font(.system(size: 8, weight: .bold))
            }

        case .preparing, .stopping:
            menuBarIcon
                .opacity(0.7)

        case .idle, .error:
            menuBarIcon
        }
    }

    private var menuBarIcon: some View {
        Image("MenuBarIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
    }

    private var formattedDuration: String {
        let total = Int(recordingVM.duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
#endif
