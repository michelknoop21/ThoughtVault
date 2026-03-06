// HomeView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Main home screen with welcome message, quick-start recording buttons,
// active processing section, and recent transcripts list.

import SwiftUI

// MARK: - HomeView

struct HomeView: View {

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(AuthViewModel.self) var authVM

    // MARK: Closure delegation

    /// Called when a quick-start button or CTA is tapped. Parent is responsible
    /// for navigating to RecordingView and optionally starting recording.
    var onStartRecording: ((RecordingMode) -> Void)?

    /// Called when "Bekijk alles" is tapped to navigate to the Notulen tab.
    var onNavigateToTranscripts: (() -> Void)?

    // MARK: State

    @State private var recentTranscripts: [Transcript] = []
    @State private var isLoadingRecent = false
    @State private var loadError: String? = nil

    // MARK: Body

    var body: some View {
        ZStack {
            backgroundBlobs
            ScrollView {
                VStack(spacing: TS.Spacing.xl) {
                    headerSection

                    quickStartSection

                    overviewSection

                    activeProcessingSection

                    recentTranscriptsSection

                    #if os(macOS)
                    Spacer(minLength: TS.Spacing.lg)
                    YingaFooter()
                    #endif
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
    }

    // MARK: - Subviews

    // MARK: Background blobs

    private var backgroundBlobs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandPrimary.opacity(0.08), Color.clear],
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
                            colors: [Color.brandSecondary.opacity(0.05), Color.clear],
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
            Text(greetingText)
                .font(TS.Font.title2Semibold)
                .foregroundStyle(Color.labelPrimary)

            Text("Wat wil je vandaag transcriberen?")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TS.Spacing.sm)
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
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            ctaCard

            HStack(spacing: TS.Spacing.sm) {
                quickStartPill(
                    mode: .microphone,
                    color: Color.brandSecondary,
                    label: "Fysieke meeting",
                    icon: "person.2.fill"
                )

                #if os(macOS)
                quickStartPill(
                    mode: .combined,
                    color: Color.brandPrimary,
                    label: "Videocall",
                    icon: "video.fill"
                )
                #endif
            }
        }
    }

    private var ctaCard: some View {
        Button {
            onStartRecording?(.microphone)
        } label: {
            HStack(spacing: TS.Spacing.md) {
                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Color.white.opacity(0.25 - Double(i) * 0.07), lineWidth: 1.5)
                            .frame(width: CGFloat(44 + i * 18), height: CGFloat(44 + i * 18))
                    }
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Start nieuwe opname")
                        .font(TS.Font.subheadlineSemibold)
                        .foregroundStyle(.white)
                    Text("Tik om direct te beginnen met opnemen")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brandPrimary, Color.brandPrimaryDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.brandPrimary.opacity(0.20), radius: 12, y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func quickStartPill(mode: RecordingMode, color: Color, label: String, icon: String? = nil) -> some View {
        let symbolName = (icon?.isEmpty == false) ? icon! : mode.iconName
        Button {
            onStartRecording?(mode)
        } label: {
            HStack(spacing: TS.Spacing.xs) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(TS.Font.footnoteSemibold)
            }
            .foregroundStyle(color)
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
            .background {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.10))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(color.opacity(0.28), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Active processing

    private var overviewSection: some View {
        HStack(spacing: TS.Spacing.sm) {
            overviewStat(
                title: "Actieve taken",
                value: "\(recordingVM.activeTasks.filter { $0.status.isActive }.count)",
                icon: "gearshape.2.fill",
                color: Color.brandPrimary
            )
            overviewStat(
                title: "Wachtrij",
                value: "\(recordingVM.offlineQueue.count)",
                icon: "tray.fill",
                color: Color.brandSecondary
            )
            overviewStat(
                title: "Recent",
                value: "\(recentTranscripts.count)",
                icon: "doc.text",
                color: Color.brandOrange
            )
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
                    .foregroundStyle(Color.labelTertiary)
            }
            Text(value)
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.surfacePrimary)
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
            HStack {
                Label("Recente notulen", systemImage: "doc.text")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)

                Spacer()

                if isLoadingRecent {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !recentTranscripts.isEmpty {
                    Button {
                        onNavigateToTranscripts?()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Bekijk alles")
                                .font(TS.Font.footnoteSemibold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.brandPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }

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
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.labelTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nog geen notulen")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        Text("Start een opname om te beginnen")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    Spacer()
                }
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
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                        .fill(Color.surfacePrimary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                        .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
                }
            }
        }
    }

    private func recentTranscriptRow(_ transcript: Transcript) -> some View {
        Button {
            onNavigateToTranscripts?()
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: transcript.notuleHtml != nil ? "doc.text.fill" : "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(transcript.notuleHtml != nil ? Color.brandAccent : Color.labelTertiary)
                    .frame(width: 24)

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

    // MARK: - Helpers

    private func loadRecentTranscripts() async {
        isLoadingRecent = true
        loadError = nil
        do {
            let response = try await APIService.shared.getTranscripts(page: 1, limit: 3, sortBy: "newest")
            recentTranscripts = response.items
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingRecent = false
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(RecordingViewModel())
        .environment(AuthViewModel())
}
