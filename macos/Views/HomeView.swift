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
        .task {
            for await _ in NotificationCenter.default.notifications(named: LocalTranscriptStore.didChange) {
                await loadRecentTranscripts()
            }
        }
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

#if os(macOS)
struct AppUpdateBanner: View {
    let version: String
    var dismissible = true
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(UpdateCheckService.self) private var updateCheck
    @AppStorage("dismissedUpdateVersion") private var dismissedUpdateVersion = ""
    @State private var showDetails = false

    var body: some View {
        HStack(spacing: TS.Spacing.md) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Color.brandLink)
                .frame(width: 44, height: 44)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: TS.Radius.sm))
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text(recordingVM.updateIsBusy ? "Update klaar. Je opname gaat voor." : "ThoughtVault \(version) is beschikbaar")
                    .font(TS.Font.footnoteSemibold)
                Text(recordingVM.updateIsBusy ? "Bijwerken kan zodra opnemen en verwerken klaar zijn." : "Werk bij wanneer het jou uitkomt.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer(minLength: TS.Spacing.sm)
            Button("Bekijk update") { showDetails = true }
                .buttonStyle(PrimaryButtonStyle())
            if dismissible {
                Button { withAnimation(TS.Animation.quick) { dismissedUpdateVersion = version } } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Updatemelding verbergen")
            }
        }
        .padding(TS.Spacing.md)
        .background(Color.cardDark, in: RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: TS.Radius.md).strokeBorder(Color.brandLink.opacity(0.3)))
        .sheet(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: TS.Spacing.lg) {
                HStack {
                    Image(systemName: "arrow.down.circle").font(.system(size: 40, weight: .light)).foregroundStyle(Color.brandLink)
                    Spacer()
                    Button { showDetails = false } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                        .buttonStyle(.plain).accessibilityLabel("Sluiten")
                }
                Text("Een nieuwe ThoughtVault staat klaar.").font(TS.Font.title2)
                Text("Versie \(version)").font(TS.Font.caption).foregroundStyle(Color.brandLink)
                if updateCheck.usesInstallerDownload {
                    Text("Download het installatiebestand voor jouw Mac. Daarna rond je de installatie zelf af.")
                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("1. Download het DMG-bestand.")
                        Text("2. Sluit ThoughtVault af.")
                        Text("3. Open de DMG en sleep ThoughtVault naar Programma’s. Kies ‘Vervang’.")
                    }.font(TS.Font.footnote).foregroundStyle(Color.labelSecondary)
                } else {
                    Text("De updater begeleidt je bij het downloaden en installeren. ThoughtVault sluit daarvoor kort af.")
                }
                if recordingVM.updateIsBusy {
                    Text("Rond eerst je opname en verwerking af. Je kunt daarna bijwerken.")
                        .font(TS.Font.footnote).foregroundStyle(Color.labelSecondary)
                }
                if let error = updateCheck.errorMessage {
                    Text(error).font(TS.Font.footnote).foregroundStyle(Color.statusErrorText).accessibilityAddTraits(.updatesFrequently)
                }
                HStack {
                    Button("Later") { showDetails = false }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button(updateCheck.isDownloading ? "Download controleren…" : updateCheck.usesInstallerDownload ? "Download voor macOS" : "Nu bijwerken") {
                        Task { await updateCheck.downloadAndOpen() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(recordingVM.updateIsBusy || updateCheck.isDownloading)
                }
            }
            .padding(TS.Spacing.xl)
            .frame(width: 480)
        }
    }
}
#endif
