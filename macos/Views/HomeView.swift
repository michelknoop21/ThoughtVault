// HomeView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Main home screen with welcome message, quick-start recording buttons,
// active processing section, and recent transcripts list.

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

    // MARK: State

    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("dismissedUpdateVersion") private var dismissedUpdateVersion = ""

    @State private var recentTranscripts: [Transcript] = []
    @State private var isLoadingRecent = false
    @State private var loadError: String? = nil

    // MARK: Body

    var body: some View {
        ZStack {
            backgroundBlobs
            ScrollView {
                VStack(spacing: TS.Spacing.xl) {
                    #if os(macOS)
                    if checkForUpdates,
                       let version = updateCheck.availableVersion,
                       dismissedUpdateVersion != version {
                        updateBanner(version: version)
                    }
                    #endif

                    headerSection

                    quickStartSection

                    overviewSection

                    activeProcessingSection

                    recentTranscriptsSection
                }
                .padding(.horizontal, TS.Spacing.lg)
                .padding(.vertical, TS.Spacing.lg)
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadRecentTranscripts() }
        #if os(macOS)
        .task {
            if checkForUpdates { await updateCheck.checkForUpdate() }
        }
        #endif
    }

    // MARK: - Subviews

    // MARK: Background blobs

    private var backgroundBlobs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandPrimary.opacity(0.16), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 300
                        )
                    )
                    .frame(width: 600, height: 600)
                    .offset(x: -geo.size.width * 0.3, y: -100)
                    .blur(radius: 80)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandSecondary.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.5)
                    .blur(radius: 70)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Text(dateKicker)
                .font(TS.Font.microBold)
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.labelTertiary)

            (Text(greetingText + ". ").foregroundStyle(Color.labelPrimary)
                + Text("Klaar om te denken?").foregroundStyle(
                    LinearGradient(colors: [Color.brandLavender, Color.brandPrimary, Color.brandSecondary],
                                   startPoint: .leading, endPoint: .trailing)))
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text("Alles wat hier wordt opgenomen, blijft op dit apparaat.")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TS.Spacing.sm)
    }

    private var dateKicker: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "nl_NL")
        df.dateFormat = "EEEE d MMMM"
        return df.string(from: Date())
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName: String = {
            if let name = authVM.currentUser?.name,
               let first = name.split(separator: " ").first, !first.isEmpty {
                return String(first)
            }
            if let email = authVM.currentUser?.email,
               let local = email.split(separator: "@").first, !local.isEmpty {
                return String(local)
            }
            return ""
        }()
        let greeting: String
        if hour < 12 {
            greeting = "Goedemorgen"
        } else if hour < 18 {
            greeting = "Goedemiddag"
        } else {
            greeting = "Goedenavond"
        }
        return firstName.isEmpty ? greeting : "\(greeting), \(firstName)"
    }

    // MARK: Quick start

    private var quickStartSection: some View {
        // One primary start affordance. The mode/profile are chosen on the next
        // screen (RecordingView), so the previous duplicate pills — which all just
        // opened the record tab anyway — were removed.
        ctaCard
    }

    private var ctaCard: some View {
        Button {
            onStartRecording?(.microphone)
        } label: {
            HStack(spacing: TS.Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nieuwe opname")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.labelPrimary)
                    Text("Klik op de knop en ThoughtVault neemt op, transcribeert en notuleert — volledig lokaal.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: TS.Spacing.md)

                recordOrb
            }
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.lg)
            .background {
                // Dark panel with a violet mesh glow, per the approved mockup.
                RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.118, green: 0.102, blue: 0.227),
                                     Color(red: 0.078, green: 0.078, blue: 0.157)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RadialGradient(
                            colors: [Color.brandPrimary.opacity(0.22), .clear],
                            center: .init(x: 0.88, y: -0.2),
                            startRadius: 0, endRadius: 340
                        )
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                            .strokeBorder(Color.brandPrimary.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: Color.brandPrimaryDark.opacity(0.30), radius: 22, y: 10)
            }
        }
        .buttonStyle(.plain)
    }

    /// Glowing violet record orb — the visual heart of the app.
    private var recordOrb: some View {
        ZStack {
            Circle()
                .stroke(Color.brandPrimary.opacity(0.25), lineWidth: 1)
                .frame(width: 108, height: 108)
            Circle()
                .stroke(Color.brandPrimary.opacity(0.14), lineWidth: 1)
                .frame(width: 126, height: 126)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.76, green: 0.53, blue: 1.0),
                                 Color.brandPrimary,
                                 Color.brandPrimaryDark],
                        center: .init(x: 0.32, y: 0.28),
                        startRadius: 4, endRadius: 74
                    )
                )
                .frame(width: 84, height: 84)
                .shadow(color: Color.brandPrimary.opacity(0.55), radius: 24)
                .shadow(color: Color.brandPrimaryDark.opacity(0.45), radius: 10, y: 6)
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.brandPrimaryDark.opacity(0.6), radius: 4, y: 2)
        }
        .frame(width: 130, height: 130)
    }

    // MARK: Active processing

    @ViewBuilder
    private var overviewSection: some View {
        let activeCount = recordingVM.activeTasks.filter { $0.status.isActive }.count
        let queueCount = recordingVM.offlineQueue.count
        let recentCount = recentTranscripts.count
        // Hide the stat row entirely on an empty/fresh account — a "0 / 0 / 0"
        // hero-metric grid reads as broken rather than informative.
        if activeCount > 0 || queueCount > 0 || recentCount > 0 {
            HStack(spacing: TS.Spacing.sm) {
                overviewStat(
                    title: "Actieve taken",
                    value: "\(activeCount)",
                    icon: "gearshape.2.fill",
                    color: Color.brandPrimary
                )
                overviewStat(
                    title: "Wachtrij",
                    value: "\(queueCount)",
                    icon: "tray.fill",
                    color: Color.brandSecondary
                )
                overviewStat(
                    title: "Recent",
                    value: "\(recentCount)",
                    icon: "doc.text",
                    color: Color.brandOrange
                )
            }
        }
    }

    private func overviewStat(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(TS.Font.microBold)
                    .foregroundStyle(Color.labelSecondary)
            }
            Text(value)
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var activeProcessingSection: some View {
        let activeTasks = recordingVM.activeTasks.filter { $0.status.isActive }
        if !activeTasks.isEmpty {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Label("Bezig met verwerken", systemImage: "gearshape.2.fill")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)

                VStack(spacing: TS.Spacing.xs) {
                    ForEach(activeTasks) { task in
                        activeTaskRow(task)
                    }
                }
            }
        }
    }

    private func activeTaskRow(_ task: TranscriptTask) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.borderPrimary, lineWidth: 2)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: task.status.progress)
                    .stroke(
                        Color.brandPrimary,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                    .animation(TS.Animation.smooth, value: task.status.progress)

                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.filename)
                    .font(TS.Font.footnoteMedium)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                Text(task.status.displayName)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.brandPrimary)
            }

            Spacer()

            Text("\(Int(task.status.progress * 100))%")
                .font(TS.Font.captionMonospaced)
                .foregroundStyle(Color.labelSecondary)
        }
        .padding(TS.Spacing.sm)
        .modernCard()
    }

    // MARK: Recent transcripts

    @ViewBuilder
    private var recentTranscriptsSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            VaultSectionHeader(
                title: "Recente notulen",
                actionTitle: recentTranscripts.isEmpty ? nil : "Alles bekijken \u{2192}",
                action: { onNavigateToTranscripts?() }
            )

            if let error = loadError {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusError)
                        .font(.system(size: 13))
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                        .lineLimit(1)
                    Spacer()
                    Button("Opnieuw") {
                        Task { await loadRecentTranscripts() }
                    }
                    .font(TS.Font.captionSemibold)
                    .foregroundStyle(Color.brandPrimary)
                }
                .padding(TS.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(Color.statusError.opacity(0.06))
                }
            } else if recentTranscripts.isEmpty && !isLoadingRecent {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.brandPrimary)
                        Text("Nog geen notulen")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                    }
                    Text("Start je eerste opname en ThoughtVault zet je gesprek automatisch om in een heldere notule met samenvatting, actiepunten en besluiten.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        onStartRecording?(.microphone)
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Maak je eerste opname")
                                .font(TS.Font.footnoteSemibold)
                        }
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, TS.Spacing.md)
                        .padding(.vertical, TS.Spacing.sm)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.brandPrimary.opacity(0.10))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(Color.brandPrimary.opacity(0.28), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, TS.Spacing.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TS.Spacing.md)
                .modernCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentTranscripts.prefix(3).enumerated()), id: \.element.id) { index, transcript in
                        if index > 0 {
                            Divider()
                                .padding(.leading, TS.Spacing.xl + TS.Spacing.sm)
                        }
                        recentTranscriptRow(transcript)
                    }
                }
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs)
                .vaultPanel()
            }
        }
    }

    private func recentTranscriptRow(_ transcript: Transcript) -> some View {
        Button {
            onNavigateToTranscripts?()
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                VaultIconTile(systemName: transcript.notuleHtml != nil ? "doc.text" : "waveform")

                VStack(alignment: .leading, spacing: 2) {
                    Text(transcript.title)
                        .font(TS.Font.footnoteMedium)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                    Text(relativeDate(transcript.date))
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                VaultChip(text: transcript.notuleHtml != nil ? "Afgerond" : "Transcript",
                          tone: transcript.notuleHtml != nil ? .ok : .neutral)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm + 2)
        }
        .buttonStyle(.plain)
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 {
            return "\(max(Int(interval / 60), 1)) min geleden"
        } else if interval < 86400 {
            return "\(Int(interval / 3600)) uur geleden"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "nl_NL")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    // MARK: Update banner

    private var updateBannerButtonLabel: String {
        if updateCheck.isDownloading {
            let pct = Int((updateCheck.downloadProgress * 100).rounded())
            return pct > 0 ? "\(pct)%" : "Downloaden…"
        }
        return "Download"
    }

    private func updateBanner(version: String) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Versie \(version) is beschikbaar")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(.white)
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
                .disabled(updateCheck.isDownloading)
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

    // MARK: - Helpers

    private func loadRecentTranscripts() async {
        isLoadingRecent = true
        loadError = nil

        // Local records first — always available without the server.
        let local = LocalTranscriptStore.shared.allTranscripts()

        var server: [Transcript] = []
        if !ProcessingMode.isLocalMode {
            do {
                server = try await APIService.shared.getTranscripts().items
            } catch {
                // Server unavailable is fine; only surface if nothing local.
                if local.isEmpty { loadError = error.localizedDescription }
            }
        }

        let localIds = Set(local.map(\.taskId))
        let merged = (local + server.filter { !localIds.contains($0.taskId) })
            .sorted { $0.date > $1.date }
        recentTranscripts = Array(merged.prefix(3))
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
