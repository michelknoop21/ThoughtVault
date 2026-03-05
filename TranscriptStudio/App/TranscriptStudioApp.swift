import SwiftUI

@main
struct TranscriptStudioApp: App {
    @State private var authVM = AuthViewModel()
    @State private var recordingVM = RecordingViewModel()
    let calendarService = CalendarService.shared
    let debugLogger = DebugLogger.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authVM)
                .environment(recordingVM)
                .environment(calendarService)
                .task {
                    AudioRecorder.cleanupOldRecordings(
                        protecting: recordingVM.offlineQueue.queuedAudioURLs
                    )
                    await recordingVM.processQueueOnStartupIfNeeded()
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
                .environment(calendarService)
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(authVM)
                .environment(recordingVM)
                .environment(calendarService)
        } label: {
            MenuBarStatusLabel(recordingVM: recordingVM)
        }
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
#endif
    }

}

// MARK: - MenuBar Content View (macOS)

#if os(macOS)
struct MenuBarContentView: View {
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(AuthViewModel.self) private var authVM

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

            Divider()
                .padding(.vertical, 4)

            Button("Afsluiten") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 220)
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
}

// MARK: - MenuBar Status Label (macOS)

struct MenuBarStatusLabel: View {
    let recordingVM: RecordingViewModel

    var body: some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }

        case .paused:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .opacity(0.7)

        case .uploading:
            Image(systemName: "arrow.up.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

        case .preparing, .stopping:
            Image(systemName: "waveform.circle")
                .symbolRenderingMode(.hierarchical)
                .opacity(0.7)

        case .idle, .error:
            Image(systemName: "waveform.circle")
                .symbolRenderingMode(.hierarchical)
        }
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
