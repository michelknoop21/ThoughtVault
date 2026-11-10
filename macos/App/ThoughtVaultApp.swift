import SwiftUI
import SwiftData

/// The XCTest bundle is injected into this sandboxed app, so a test run shares the real
/// app container, keychain and defaults. Under tests the real app must not start and
/// on-disk data must live in a throwaway directory.
enum AppEnvironment {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    static var isDebugSnapshot: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "TVDebugSnapshot") != nil
        #else
        return false
        #endif
    }

    /// Application Support normally; a unique temp directory per test run.
    static let supportDirectory: URL = isRunningTests
        ? FileManager.default.temporaryDirectory.appending(path: "ThoughtVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        : URL.applicationSupportDirectory
}

@main
enum AppEntry {
    @MainActor static func main() {
        if AppEnvironment.isRunningTests { TestHostApp.main() } else { ThoughtVaultApp.main() }
    }
}

/// Empty host for the test bundle: no view models, store, sync or permission requests.
struct TestHostApp: App {
    var body: some Scene { WindowGroup { EmptyView() } }
}

struct ThoughtVaultApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var supportVM = SupportViewModel()
    @State private var authVM = AuthViewModel()
    @State private var recordingVM = RecordingViewModel()
    @State private var tasksVM = TasksViewModel()
    @State private var updateCheckService = UpdateCheckService()
    let calendarService = CalendarService.shared
    let permissionManager = PermissionManager.shared
    let debugLogger = DebugLogger.shared

    init() {
        #if os(macOS)
        AppLog.endSessionOnTermination()
        #endif
        // Before any view reads UserDefaults: adopt iCloud-synced provider
        // settings (Ollama Cloud URL/model/provider from the Mac).
        SettingsSyncService.shared.start()
        try? PersonalVocabulary.migrateLegacyTerms()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // ThoughtVault is a dark-first brand; the design system ships dark-only.
                .preferredColorScheme(.dark)
                .environment(authVM)
                .environment(recordingVM)
                .environment(tasksVM)
                .environment(updateCheckService)
                .environment(supportVM)
                .environment(calendarService)
                .environment(permissionManager)
                .modelContainer(LocalTranscriptStore.shared.container)
                .task {
                    #if os(macOS)
                    while !Task.isCancelled {
                        if UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true {
                            await updateCheckService.checkForUpdate()
                        }
                        do { try await Task.sleep(for: .seconds(6 * 60 * 60)) } catch { return }
                    }
                    #endif
                }
                .task {
                    #if DEBUG
                    if IOSDebug.supportSeed || IOSDebug.supportSettingsSnapshot {
                        DebugScreenshotSeed.seedSupport(supportVM)
                        return
                    }
                    #endif
                    guard !AppEnvironment.isDebugSnapshot else { return }
                    // Install the failure hook before startup work or support network awaits.
                    recordingVM.onFailure = { stage, message in
                        Task { await supportVM.report(stage: stage, shown: message, error: message) }
                    }
                    if let outcome = supportVM.beginSessionIfNeeded() {
                        #if os(iOS)
                        supportVM.reconcileSession(isBackground: scenePhase == .background)
                        #endif
                        recordingVM.syncSessionStage()
                        if case .crashed(let stage) = outcome {
                            await supportVM.reportCrash(runningStage: stage.flatMap(SupportStage.init(rawValue:)))
                        }
                        await SupportRelay.shared.flush()
                    }
                    #if os(macOS)
                    updateCheckService.installationStateChanged = { recordingVM.updateInstalling = $0 }
                    updateCheckService.isBusy = { recordingVM.updateIsBusy }
                    #endif
                    await permissionManager.checkAllPermissions()
                    #if os(macOS)
                    let activeSystemAudio = recordingVM.systemAudioCapture.currentOutputURL
                    #else
                    let activeSystemAudio: URL? = nil
                    #endif
                    let recovered = RecordingRecovery.recoverOrphans(recordingVM.audioRecorder.getOrphanedRecordings(excluding: [activeSystemAudio]))
                    if !recovered.isEmpty { recordingVM.loadSavedRecordings() }
                    AudioRecorder.cleanupOldRecordings(
                        protecting: recordingVM.offlineQueue.queuedAudioURLs,
                        knownRecordingNames: Set(LocalTranscriptStore.shared.allRecords().map(\.filename))
                    )
                    await recordingVM.processQueueOnStartupIfNeeded()
                    MeetingNotificationService.shared.setup()
                    await MeetingNotificationService.shared.requestPermission()
                    #if os(macOS)
                    VideoCallDetectionService.shared.startMonitoring()
                    #endif
                }
                .task {
                    guard !AppEnvironment.isDebugSnapshot else { return }
                    await supportVM.startPolling()
                }
                .onChange(of: NetworkMonitor.shared.isConnected) { _, connected in
                    guard !AppEnvironment.isDebugSnapshot else { return }
                    if connected && !IOSDebug.supportSeed { Task { await SupportRelay.shared.flush() } }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard !AppEnvironment.isDebugSnapshot else { return }
                    if phase == .active {
                        #if os(iOS)
                        // Startup must read the previous marker before any resume can replace it.
                        if supportVM.hasBegunSession {
                            supportVM.reconcileSession(isBackground: false)
                            recordingVM.syncSessionStage()
                        }
                        #endif
                        Task { await supportVM.refreshUnread() }
                    }
                    #if os(iOS)
                    if phase == .background { supportVM.reconcileSession(isBackground: true) }
                    #endif
                }
        }
#if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.automatic)
        .commands { PrintCommands() }
#endif

#if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
                .environment(supportVM)
                .environment(updateCheckService)
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
    @AppStorage(SupportIdentity.nameKey) private var supportName = ""
    @AppStorage(SupportIdentity.emailKey) private var supportEmail = ""
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @Environment(RecordingViewModel.self) private var recordingVM
    @State private var debugSupportPresented = false

    var body: some View {
        Group {
            if IOSDebug.supportSeed {
                Color.clear
            } else if SupportIdentity.showsGate(name: supportName, email: supportEmail, arguments: ProcessInfo.processInfo.arguments) {
                SupportIdentityView()
                    #if DEBUG
                    .task {
                        Task { for _ in 0..<5 { try? await Task.sleep(for: .seconds(1)); DebugScreenshotSeed.sizeWindow() } }
                        await DebugScreenshotSeed.snapshotAndQuit()
                    }
                    #endif
            } else if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $debugSupportPresented) { SupportCenterView() }
        .task { debugSupportPresented = IOSDebug.supportSeed }
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
