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

    // MARK: State

    @State private var recentTranscripts: [Transcript] = []
    @State private var isLoadingRecent = false
    @State private var loadError: String? = nil
    @State private var selectedTranscriptForNav: Transcript? = nil
    @State private var showAllRecent = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundBlobs
                ScrollView {
                    VStack(spacing: TS.Spacing.lg) {
                        headerSection
                        quickStartSection
                        overviewSection
                        activeProcessingSection
                        recentTranscriptsSection

                        #if os(macOS)
                        YingaFooter()
                        #endif
                    }
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.vertical, TS.Spacing.lg)
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $selectedTranscriptForNav) { transcript in
                TranscriptDetailView(transcript: transcript)
            }
        }
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
                            colors: [Color.brandPrimary.opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 260
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(x: -geo.size.width * 0.3, y: -60)
                    .blur(radius: 60)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandSecondary.opacity(0.14), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
                    .blur(radius: 50)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandAccent.opacity(0.10), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 160
                        )
                    )
                    .frame(width: 320, height: 320)
                    .offset(x: geo.size.width * 0.1, y: geo.size.height * 0.6)
                    .blur(radius: 40)
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
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("SNEL STARTEN")
                .font(TS.Font.microBold)
                .foregroundStyle(Color.labelTertiary)
                .kerning(1.2)

            // CTA hero card
            ctaCard

            // Pill buttons row
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
                    .shadow(color: Color.brandPrimary.opacity(0.38), radius: 16, y: 6)
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

    private var recentTranscriptsSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            HStack {
                Text("Recente transcripties")
                    .font(TS.Font.subheadlineSemibold)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                if isLoadingRecent {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if recentTranscripts.count > 3 {
                    Button(showAllRecent ? "Toon minder" : "Toon meer") {
                        withAnimation(TS.Animation.smooth) {
                            showAllRecent.toggle()
                        }
                    }
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.brandPrimary)
                }
            }

            if let error = loadError {
                errorBanner(error)
            } else if recentTranscripts.isEmpty && !isLoadingRecent {
                emptyRecentState
            } else {
                VStack(spacing: TS.Spacing.sm) {
                    ForEach(showAllRecent ? recentTranscripts : Array(recentTranscripts.prefix(3))) { transcript in
                        HomeSessionCard(
                            transcript: transcript,
                            onTap: {
                                selectedTranscriptForNav = transcript
                            },
                            onDelete: {
                                Task { await deleteTranscript(transcript) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyRecentState: some View {
        VStack(spacing: TS.Spacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.labelTertiary)
            Text("Geen recente transcripties")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
            Text("Start een opname om te beginnen")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(TS.Spacing.xl)
        .modernCard()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusError)
            Text(message)
                .font(TS.Font.footnote)
                .foregroundStyle(Color.statusError)
            Spacer()
            Button("Opnieuw") {
                Task { await loadRecentTranscripts() }
            }
            .font(TS.Font.footnoteSemibold)
            .foregroundStyle(Color.brandPrimary)
        }
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.statusError.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .stroke(Color.statusError.opacity(0.25), lineWidth: 1)
                }
        }
    }

    // MARK: - Helpers

    private func loadRecentTranscripts() async {
        isLoadingRecent = true
        loadError = nil
        do {
            let response = try await APIService.shared.getTranscripts(page: 1, limit: 12, sortBy: "newest")
            recentTranscripts = response.items
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingRecent = false
    }

    private func deleteTranscript(_ transcript: Transcript) async {
        do {
            try await APIService.shared.deleteTranscript(id: transcript.id)
            recentTranscripts.removeAll { $0.id == transcript.id }
        } catch {
            loadError = "Verwijderen mislukt: \(error.localizedDescription)"
        }
    }
}

// MARK: - HomeSessionCard

struct HomeSessionCard: View {

    let transcript: Transcript
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
            menuButton
        }
        .contentShape(RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
        .onTapGesture { onTap() }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Openen", systemImage: "arrow.up.right.square")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Transcriptie verwijderen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) { onDelete() }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Deze transcriptie wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.")
        }
        .onHover { isHovered = $0 }
        .modernCard(isHovered: isHovered)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(transcript.title)
                    .font(TS.Font.subheadlineSemibold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                // Session tag
                Text("Sessie")
                    .font(TS.Font.micro)
                    .foregroundStyle(Color.statusSuccess)
                    .padding(.horizontal, TS.Spacing.xs + 2)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(Color.statusSuccess.opacity(0.12))
                    }

                Spacer(minLength: TS.Spacing.xl)
            }

            HStack(spacing: TS.Spacing.sm) {
                Text(formattedDate)
                    .font(TS.Font.captionMonospaced)
                    .foregroundStyle(Color.labelTertiary)

                Text("Voltooid")
                    .font(TS.Font.micro)
                    .foregroundStyle(Color.statusSuccess)

                if let profile = transcript.profileName, !profile.isEmpty {
                    Text("• \(profile)")
                        .font(TS.Font.micro)
                        .foregroundStyle(Color.labelTertiary)
                        .lineLimit(1)
                }
            }

            if let preview = previewText, !preview.isEmpty {
                Text(preview)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .padding(TS.Spacing.md)
    }

    private var menuButton: some View {
        Menu {
            Button {
                onTap()
            } label: {
                Label("Openen", systemImage: "arrow.up.right.square")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(TS.Spacing.xs)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transcript.date)
    }

    private var previewText: String? {
        if let notule = transcript.notuleHtml, !notule.isEmpty {
            // Strip HTML tags for preview
            return notule
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return transcript.rawTranscription
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(RecordingViewModel())
        .environment(AuthViewModel())
}
