// HomeView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Main home screen with welcome message, quick-start recording buttons,
// active processing section, and recent transcripts list. macOS renders the
// approved Home NorthStar (HomeView+Studio.swift, HomeView+Panels.swift);
// iOS renders the approved iOS NorthStar (HomeView+iOS.swift).

import SwiftUI

// MARK: - HomeView

struct HomeView: View {

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(AuthViewModel.self) var authVM
    @Environment(UpdateCheckService.self) var updateCheck

    // MARK: Closure delegation

    /// Called when a quick-start button or CTA is tapped. Parent is responsible
    /// for navigating to RecordingView and optionally starting recording.
    var onStartRecording: ((RecordingMode) -> Void)?

    /// Called when "Bekijk alles" is tapped to navigate to the Notulen tab.
    var onNavigateToTranscripts: (() -> Void)?

    /// Opens one transcript in the Notulen tab.
    var onOpenTranscript: ((Transcript) -> Void)?

    /// Opens the Notulen tab filtered on the query.
    var onSearch: ((String) -> Void)?

    /// Opens the settings tab (account menu).
    var onOpenSettings: (() -> Void)?

    /// Starts recording a meeting from today's agenda (iOS Home).
    var onStartMeeting: ((CalendarEvent) -> Void)?

    // MARK: State

    @AppStorage("checkForUpdates") var checkForUpdates = true
    @AppStorage("dismissedUpdateVersion") var dismissedUpdateVersion = ""

    // Internal (not private): shared with the macOS layout in HomeView+Studio/+Panels.
    @State var recentTranscripts: [Transcript] = []
    @State var isLoadingRecent = false
    @State var loadError: String? = nil
    @State var recentFilter: HomeRecentFilter = .all
    @State var searchQuery = ""

    // MARK: Body

    var body: some View {
        Group {
#if os(macOS)
            homeStudio
#else
            iosBody
#endif
        }
        .task { await loadRecentTranscripts() }
        #if os(macOS)
        .task {
            if checkForUpdates { await updateCheck.checkForUpdate() }
        }
        #endif
    }

    var dateKicker: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "nl_NL")
        df.dateFormat = "EEEE d MMMM"
        return df.string(from: Date())
    }

    var firstName: String {
        if let name = authVM.currentUser?.name,
           let first = name.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        if let email = authVM.currentUser?.email,
           let local = email.split(separator: "@").first, !local.isEmpty {
            return String(local)
        }
        return ""
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Goedemorgen" }
        if hour < 18 { return "Goedemiddag" }
        return "Goedenavond"
    }

    // MARK: - Helpers

    func loadRecentTranscripts() async {
        isLoadingRecent = true
        loadError = nil
        // macOS filters the list (Alle / Opnames / Notulen), so it loads more.
        #if os(macOS)
        let result = await RecentTranscripts.load(limit: 30)
        #else
        let result = await RecentTranscripts.load(limit: 3)
        #endif
        recentTranscripts = result.items
        loadError = result.error
        isLoadingRecent = false
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(RecordingViewModel())
        .environment(AuthViewModel())
        .environment(UpdateCheckService())
}

struct AppUpdateBanner: View {
    let version: String
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(UpdateCheckService.self) private var updateCheck
    @AppStorage("dismissedUpdateVersion") private var dismissedUpdateVersion = ""


    private var updateBannerButtonLabel: String {
        if updateCheck.isDownloading {
            let pct = Int((updateCheck.downloadProgress * 100).rounded())
            return pct > 0 ? "\(pct)%" : "Downloaden…"
        }
        return "Nu bijwerken"
    }

    var body: some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Versie \(version) is beschikbaar")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(.white)
                if recordingVM.updateIsBusy { Text("Bijwerken kan zodra opnemen en verwerken klaar zijn.").font(TS.Font.caption) }
                if let error = updateCheck.errorMessage { Text(error).font(TS.Font.caption) }
            }

            Spacer()

            if let url = updateCheck.downloadURL {
                Button {
                    #if os(macOS)
                    Task { await updateCheck.downloadAndOpen() }
                    #else
                    UIApplication.shared.open(url)
                    #endif
                } label: {
                    Text(updateBannerButtonLabel)
                        .font(TS.Font.captionSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, TS.Spacing.xs)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.22))
                        }
                }
                .buttonStyle(.plain)
                .disabled(updateCheck.isDownloading || recordingVM.updateIsBusy)
            }

            Button {
                withAnimation(TS.Animation.quick) {
                    dismissedUpdateVersion = version
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.brandPrimary, Color.brandPrimaryDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

}
