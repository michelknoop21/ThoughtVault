// RecordingView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Dual-state recording interface: idle setup view and active recording view.
// Handles microphone/system audio/combined modes, live transcript, task tracking,
// saved recordings list, and reprocess/retry sheet.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - RecordingView

struct RecordingView: View {

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM

    // MARK: State

    @State private var selectedReprocessRecording: SavedRecording? = nil
    @State private var savedRecordingsExpanded = false
    @State private var addNoteText = ""
    @State private var showNoteField = false
    @State private var showCancelConfirm = false
    @State private var showProfileLoadError = false
    @State private var showParticipantPicker = false
    @State private var showImporter = false
    @State private var showYouTubeSection = false

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            // Width-tier responsive layout mirroring HomeView: compact below 640pt.
            let isCompact = geo.size.width < 640
            Group {
                if recordingVM.recordingState.isRecording ||
                   recordingVM.recordingState == .preparing ||
                   recordingVM.recordingState == .stopping {
                    activeRecordingView(isCompact: isCompact)
                } else {
                    idleView(isCompact: isCompact)
                }
            }
        }
        .sheet(item: $selectedReprocessRecording) { recording in
            ReprocessSheet(recording: recording)
                .environment(recordingVM)
                .frame(minWidth: 420, idealWidth: 460, minHeight: 340, idealHeight: 380)
        }
    }

    // MARK: - Idle view (split layout)

    private func idleView(isCompact: Bool) -> some View {
        ScrollView {
            VStack(spacing: TS.Spacing.lg) {
                // Banners float above the layout as inline alerts
                offlineStatusBanner
                audioMixFallbackBanner
                errorBanner

                if isCompact {
                    // Narrow window: stack vertically — config first, then record center
                    VStack(spacing: TS.Spacing.lg) {
                        configSidebar
                        recordCenter
                    }
                } else {
                    // Wide window: side-by-side split layout
                    HStack(alignment: .top, spacing: TS.Spacing.lg) {
                        configSidebar
                            .frame(width: 280)
                        recordCenter
                    }
                }

                unifiedBottomBar
            }
            .padding(.horizontal, isCompact ? TS.Spacing.md : TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.lg)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showParticipantPicker) {
            ParticipantPickerSheet(selectedIDs: Bindable(recordingVM).selectedParticipantIDs)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await recordingVM.importAudioFile(url) }
            }
        }
    }

    // MARK: Config sidebar

    private var configSidebar: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.lg) {
            // Section: Bron
            configGroup(title: "Bron") {
                VStack(spacing: TS.Spacing.xs) {
                    recordingTypeOption(
                        icon: "person.2.fill",
                        title: "Fysieke meeting",
                        subtitle: "Alleen microfoon",
                        color: Color.brandSecondary,
                        isSelected: recordingVM.selectedMode == .microphone,
                        isVertical: true,
                        action: { withAnimation(TS.Animation.smooth) { recordingVM.selectedMode = .microphone } }
                    )

                    #if os(macOS)
                    recordingTypeOption(
                        icon: "video.fill",
                        title: "Videocall",
                        subtitle: "Microfoon + systeemgeluid",
                        color: Color.brandPrimary,
                        isSelected: recordingVM.selectedMode == .combined,
                        isVertical: true,
                        action: { withAnimation(TS.Animation.smooth) { recordingVM.selectedMode = .combined } }
                    )
                    #endif
                }
            }

            // Section: Profiel
            configGroup(title: "Profiel") {
                if recordingVM.availableProfiles.isEmpty {
                    if showProfileLoadError {
                        VStack(spacing: TS.Spacing.sm) {
                            HStack(spacing: TS.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.brandOrange)
                                Text("Profielen konden niet geladen worden")
                                    .font(TS.Font.caption)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                            Button {
                                showProfileLoadError = false
                                Task {
                                    await recordingVM.reloadProfiles()
                                    if recordingVM.availableProfiles.isEmpty {
                                        showProfileLoadError = true
                                    }
                                }
                            } label: {
                                Text("Opnieuw proberen")
                                    .font(TS.Font.captionMedium)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: TS.Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Profielen laden...")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .task {
                            await recordingVM.reloadProfiles()
                            if recordingVM.availableProfiles.isEmpty {
                                showProfileLoadError = true
                            }
                        }
                    }
                } else {
                    VStack(spacing: TS.Spacing.xs) {
                        ForEach(recordingVM.availableProfiles) { profile in
                            profileSidebarChip(profile)
                        }
                    }

                    if let description = recordingVM.selectedProfile?.description, !description.isEmpty {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: profileIcon(for: recordingVM.selectedProfile?.id ?? ""))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.brandPrimary)
                            Text(description)
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelTertiary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, TS.Spacing.xs)
                    }

                    Toggle(isOn: Bindable(recordingVM).usePremium) {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.brandPrimary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Premium model")
                                    .font(TS.Font.footnoteSemibold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text("Betere kwaliteit, langzamer")
                                    .font(TS.Font.micro)
                                    .foregroundStyle(Color.labelTertiary)
                            }
                        }
                    }
                    .tint(Color.brandPrimary)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }

            // Section: Deelnemers
            configGroup(title: "Deelnemers") {
                participantsSection
            }

            // Section: Importeren
            configGroup(title: "Importeren") {
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.brandPrimary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Audiobestand")
                                .font(TS.Font.footnoteSemibold)
                                .foregroundStyle(Color.labelPrimary)
                            Text("WAV, MP3, M4A — tot 500 MB")
                                .font(TS.Font.micro)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(TS.Spacing.sm)
                    .background {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .fill(Color.surfaceSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(TS.Spacing.lg)
        .vaultPanel(radius: TS.Radius.lg)
    }

    // MARK: Config group container

    private func configGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Color.labelTertiary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Profile sidebar chip (full-width, vertical list)

    private func profileSidebarChip(_ profile: Profile) -> some View {
        let isSelected = recordingVM.selectedProfile?.id == profile.id
        return Button {
            withAnimation(TS.Animation.smooth) {
                recordingVM.selectedProfile = profile
            }
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                Circle()
                    .fill(isSelected ? Color.white : Color.brandSecondary.opacity(0.5))
                    .frame(width: 6, height: 6)

                Text(profile.name)
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(isSelected ? Color.white : Color.labelPrimary)
                    .lineLimit(1)

                if profile.isDefault == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.brandSecondary.opacity(0.5))
                }

                Spacer()
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm + 2)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.brandSecondary, Color.brandSecondary.opacity(0.80)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.brandSecondary.opacity(0.30), radius: 6, y: 2)
                } else {
                    Capsule()
                        .fill(Color.surfaceSecondary)
                        .overlay {
                            Capsule()
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Record center

    private var recordCenter: some View {
        VStack(spacing: TS.Spacing.lg) {
            // Status label
            Text("KLAAR OM OP TE NEMEN")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(Color.labelTertiary)

            // Mic button
            Button {
                Task { await recordingVM.startRecording() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.brandPrimary.opacity(0.25), lineWidth: 1)
                        .frame(width: 108, height: 108)
                    Circle()
                        .stroke(Color.brandPrimary.opacity(0.14), lineWidth: 1)
                        .frame(width: 128, height: 128)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.76, green: 0.53, blue: 1.0),
                                         Color.brandPrimary,
                                         Color.brandPrimaryDark],
                                center: .init(x: 0.32, y: 0.28),
                                startRadius: 4, endRadius: 72
                            )
                        )
                        .frame(width: 84, height: 84)
                        .shadow(color: Color.brandPrimary.opacity(0.55), radius: 24)
                        .shadow(color: Color.brandPrimaryDark.opacity(0.45), radius: 10, y: 6)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: Color.brandPrimaryDark.opacity(0.6), radius: 4, y: 2)
                }
                .frame(width: 132, height: 132)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start opname")

            // Context summary
            HStack(spacing: TS.Spacing.xs) {
                Image(systemName: recordingVM.selectedMode.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(recordingVM.selectedMode.displayName)
                Text("·")
                Text(recordingVM.selectedProfile?.name ?? "Geen profiel")
                if recordingVM.usePremium {
                    Text("·")
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                    Text("Premium")
                }
            }
            .font(TS.Font.caption)
            .foregroundStyle(Color.labelSecondary)

            // Secondary actions
            HStack(spacing: TS.Spacing.lg) {
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text("Importeer bestand")
                            .font(TS.Font.footnote)
                    }
                    .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)

                if recordingVM.isYouTubeEnabled {
                    Button {
                        showYouTubeSection.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.red)
                            Text("YouTube-video")
                                .font(TS.Font.footnote)
                        }
                        .foregroundStyle(showYouTubeSection ? Color.brandLink : Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // YouTube section (expandable inline)
            if showYouTubeSection && recordingVM.isYouTubeEnabled {
                youtubeInlineSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(TS.Spacing.xl)
        .frame(maxWidth: .infinity)
        .vaultPanel(radius: TS.Radius.lg)
    }

    // MARK: YouTube inline section

    @ViewBuilder
    private var youtubeInlineSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            // Google account connection status
            if recordingVM.isGoogleConnected {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusSuccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google verbonden")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelPrimary)
                        if let email = recordingVM.googleUserEmail {
                            Text(email)
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    Spacer()
                    Button("Ontkoppel") {
                        Task { await recordingVM.disconnectGoogle() }
                    }
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
                }
                .padding(TS.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(Color.statusSuccess.opacity(0.08))
                }
            } else {
                Button {
                    Task { await recordingVM.connectGoogle() }
                } label: {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundStyle(Color.brandPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verbind Google Account")
                                .font(TS.Font.footnoteSemibold)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Nodig voor YouTube transcriptie")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(TS.Spacing.sm)
                    .background {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .fill(Color.surfaceSecondary)
                    }
                }
                .buttonStyle(.plain)

                if let error = recordingVM.googleAuthError {
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.brandOrange)
                }
            }

            // URL input
            TextField("Plak een YouTube URL...", text: Binding(
                get: { recordingVM.youtubeURL },
                set: { recordingVM.youtubeURL = $0 }
            ))
            .textFieldStyle(.plain)
            .font(TS.Font.body)
            .padding(.horizontal, TS.Spacing.sm + 2)
            .padding(.vertical, TS.Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.surfaceSecondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .stroke(Color.borderPrimary.opacity(0.5), lineWidth: 1)
            }

            if let error = recordingVM.youtubeError {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.brandOrange)
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if recordingVM.captionsNotAvailable {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.brandOrange)
                    Text("Geen ondertiteling beschikbaar. Video wordt gedownload en getranscribeerd via Whisper (dit kan enkele minuten duren).")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await recordingVM.submitYouTubeURL() }
            } label: {
                HStack(spacing: TS.Spacing.sm) {
                    if recordingVM.isSubmittingYouTube {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    }
                    Text(recordingVM.isSubmittingYouTube ? "Bezig..." : "Transcriberen")
                        .font(TS.Font.bodySemibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TS.Spacing.sm + 2)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.brandPrimary.opacity(0.30), radius: 8, y: 3)
                }
            }
            .buttonStyle(.plain)
            .disabled(
                recordingVM.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || recordingVM.isSubmittingYouTube
            )
            .opacity(
                recordingVM.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || recordingVM.isSubmittingYouTube ? 0.5 : 1.0
            )
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfaceSecondary.opacity(0.5))
        }
    }

    // MARK: Unified bottom bar (processing + saved recordings side by side)

    private var unifiedBottomBar: some View {
        HStack(alignment: .top, spacing: TS.Spacing.md) {
            // Processing panel
            if !recordingVM.activeTasks.isEmpty {
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.labelSecondary)
                        Text("Verwerking")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text("\(recordingVM.activeTasks.count)")
                            .font(TS.Font.microBold)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentBgPrimary))
                    }

                    VStack(spacing: TS.Spacing.xs) {
                        ForEach(recordingVM.activeTasks) { task in
                            taskRow(task)
                        }
                    }
                }
                .padding(TS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .vaultPanel(radius: TS.Radius.md)
            }

            // Saved recordings panel
            savedRecordingsPanel
        }
    }

    // MARK: Saved recordings panel

    private var savedRecordingsPanel: some View {
        let isCollapsible = recordingVM.savedRecordings.count > 3
        let isShown = !isCollapsible || savedRecordingsExpanded
        let recordings = Array(recordingVM.savedRecordings.prefix(
            savedRecordingsExpanded ? 10 : 3
        ))
        let extraCount = recordingVM.savedRecordings.count - 10

        return VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.labelSecondary)
                Text("Opgeslagen opnames")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)

                if !recordingVM.savedRecordings.isEmpty {
                    Text("\(recordingVM.savedRecordings.count)")
                        .font(TS.Font.microBold)
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentBgPrimary))
                }

                Spacer()

                Button {
                    recordingVM.openRecordingsFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .help("Toon in Finder")

                if isCollapsible {
                    Button {
                        withAnimation(TS.Animation.smooth) {
                            savedRecordingsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: savedRecordingsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isShown {
                if recordings.isEmpty {
                    if savedRecordingsExpanded {
                        Text("Geen opgeslagen opnames")
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.labelTertiary)
                            .padding(.vertical, TS.Spacing.sm)
                    }
                } else {
                    VStack(spacing: TS.Spacing.xs) {
                        ForEach(recordings) { recording in
                            savedRecordingRow(recording)
                        }

                        if extraCount > 0 {
                            Text("En \(extraCount) meer...")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelTertiary)
                                .padding(.vertical, TS.Spacing.xs)
                        }
                    }
                }
            }
        }
        .padding(TS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vaultPanel(radius: TS.Radius.md)
    }

    // MARK: Participants section

    private var participantsSection: some View {
        let count = recordingVM.selectedParticipantIDs.count
        return Button {
            showParticipantPicker = true
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brandPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Deelnemers")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelPrimary)
                    Text(count == 0
                         ? "Optioneel · agenda-deelnemers worden automatisch toegevoegd"
                         : "\(count) gekozen")
                        .font(TS.Font.micro)
                        .foregroundStyle(Color.labelTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(TS.Font.microBold)
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentBgPrimary))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.surfaceSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: YouTube card (removed — now inline in record center as youtubeInlineSection)

    private func recordingTypeOption(icon: String, title: String, subtitle: String, color: Color, isSelected: Bool, isVertical: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isVertical {
                // Sidebar-style: horizontal layout, icon left, text right
                HStack(spacing: TS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? color : color.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? .white : color)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(subtitle)
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.labelTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
                .padding(.vertical, TS.Spacing.sm)
                .padding(.horizontal, TS.Spacing.sm)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(isSelected ? Color.accentBgSecondary : Color.surfaceSecondary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .stroke(
                            isSelected ? Color.brandSecondary.opacity(0.5) : Color.borderPrimary.opacity(0.4),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            } else {
                // Original card-style: centered icon above text
                VStack(spacing: TS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? color : color.opacity(0.10))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isSelected ? .white : color)
                    }

                    VStack(spacing: 2) {
                        Text(title)
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(subtitle)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TS.Spacing.md)
                .padding(.horizontal, TS.Spacing.sm)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(isSelected ? Color.accentBgSecondary : Color.surfaceSecondary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .stroke(
                            isSelected ? Color.brandSecondary.opacity(0.5) : Color.borderPrimary.opacity(0.4),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func profileIcon(for profileId: String) -> String {
        switch profileId.lowercased() {
        case "zakelijk": return "briefcase.fill"
        case "informeel": return "bubble.left.and.bubble.right.fill"
        case "technisch": return "wrench.and.screwdriver.fill"
        default: return "person.fill"
        }
    }

    // (uploadProgressView removed — upload progress now shown in ProcessingBar)

    // MARK: Offline status banner

    @ViewBuilder
    private var offlineStatusBanner: some View {
        if let message = recordingVM.offlineStatusMessage {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(Color.brandOrange)
                Text(message)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                Button {
                    recordingVM.offlineStatusMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.brandOrange.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.brandOrange.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.brandOrange.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if case .error(let message) = recordingVM.recordingState {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.statusError)
                Text(message)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.statusError)
                    .multilineTextAlignment(.leading)
                Spacer()
                if let failed = recordingVM.lastFailedRecording {
                    Button("Opnieuw") {
                        recordingVM.clearError()
                        selectedReprocessRecording = failed
                    }
                    .font(TS.Font.captionMedium)
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    recordingVM.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.statusError.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foutmelding sluiten")
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
    }

    // MARK: Audio mix fallback banner

    @ViewBuilder
    private var audioMixFallbackBanner: some View {
        if recordingVM.audioMixFallbackOccurred {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.brandOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Systeemaudio kon niet worden samengevoegd")
                        .font(TS.Font.footnoteMedium)
                        .foregroundStyle(Color.labelPrimary)
                    Text("De opname bevat alleen microfoongeluid. Systeemaudio is niet meegenomen.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
                Spacer()
                Button {
                    recordingVM.audioMixFallbackOccurred = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Waarschuwing sluiten")
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.brandOrange.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.brandOrange.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: Active tasks list (removed — now part of unifiedBottomBar)

    private func taskRow(_ task: TranscriptTask) -> some View {
        // One affordance per row: a single status icon + filename + one status line.
        HStack(spacing: TS.Spacing.sm) {
            ZStack {
                switch task.status {
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.statusError)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.statusSuccess)
                default:
                    SpinningProgressView(color: Color.brandSecondary, size: 16)
                }
            }
            .frame(width: 22)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.filename)
                    .font(TS.Font.footnoteMedium)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                if task.status == .error, let errMsg = task.errorMessage {
                    Text(errMsg)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusErrorText)
                        .lineLimit(2)
                } else {
                    Text(task.status.displayName)
                        .font(TS.Font.caption)
                        .foregroundStyle(task.status.isActive ? Color.brandPrimary : Color.labelSecondary)
                }
            }

            Spacer()
        }
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.surfaceSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: task))
    }

    /// Single, complete VoiceOver announcement for a task row (filename + status,
    /// or filename + error message), replacing the three separate reads the
    /// stacked icon/subtitle/badge produced.
    private static func accessibilityLabel(for task: TranscriptTask) -> String {
        if task.status == .error, let errMsg = task.errorMessage, !errMsg.isEmpty {
            return "\(task.filename), fout: \(errMsg)"
        }
        return "\(task.filename), \(task.status.displayName)"
    }

    // MARK: Saved recordings section (removed — now part of unifiedBottomBar as savedRecordingsPanel)

    private func savedRecordingRow(_ recording: SavedRecording) -> some View {
        Button {
            selectedReprocessRecording = recording
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.brandSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.filename)
                        .font(TS.Font.captionMedium)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                    Text("\(recording.formattedDate)  ·  \(recording.formattedSize)")
                        .font(TS.Font.micro)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandPrimary)
            }
            .padding(.vertical, TS.Spacing.xs)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                selectedReprocessRecording = recording
                } label: {
                Label("Opnieuw verwerken", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(TS.Animation.smooth) {
                    recordingVM.deleteSavedRecording(recording)
                }
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
    }

    // MARK: - Active recording view

    private func activeRecordingView(isCompact: Bool) -> some View {
        ScrollView {
            VStack(spacing: TS.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opname actief")
                            .font(TS.Font.microBold)
                            .foregroundStyle(Color.labelTertiary)
                            .kerning(1.2)
                        timerDisplay(isCompact: isCompact)
                    }
                    Spacer()
                    liveIndicator
                }

                sessionContextCard
                waveformDisplay

                if showNoteField {
                    noteFieldCard
                }

                liveTranscriptPanel
                recordingControls
            }
            .padding(.horizontal, isCompact ? TS.Spacing.md : TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.lg)
            // Capped, centered column on wide windows; the waveform keeps the
            // full width of this column.
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Opname annuleren?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Annuleer opname", role: .destructive) {
                Task { await recordingVM.cancelRecording() }
            }
            Button("Doorgaan met opnemen", role: .cancel) {}
        } message: {
            Text("Je huidige opname wordt verwijderd. Dit kan niet ongedaan worden gemaakt.")
        }
    }

    // MARK: Live indicator

    private var liveIndicator: some View {
        HStack(spacing: TS.Spacing.xs) {
            PulsingRecordingDot(size: 8)
            Text("LIVE")
                .font(TS.Font.microBold)
                .foregroundStyle(Color.brandPrimary)
                .kerning(1.5)
        }
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, TS.Spacing.xs)
        .background {
            Capsule()
                .fill(Color.brandPrimary.opacity(0.10))
                .overlay {
                    Capsule()
                        .stroke(Color.brandPrimary.opacity(0.25), lineWidth: 1)
                }
        }
    }

    // MARK: Timer display

    private func timerDisplay(isCompact: Bool) -> some View {
        // Smaller timer on compact widths so an hour-long timestamp still fits
        // next to the LIVE pill at ~380pt.
        Text(formattedDuration)
            .font(.system(size: isCompact ? 42 : 56, weight: .light, design: .monospaced))
            .foregroundStyle(Color.labelPrimary)
            .monospacedDigit()
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

    // MARK: Waveform

    private var waveformDisplay: some View {
        VStack(spacing: TS.Spacing.sm) {
            WaveformView(
                  levelProvider: {
                      let levels = recordingVM.audioLevels
                      if let last = levels.last { return last }
                      // Fallback to RMS if no last sample available
                      let count = Float(levels.count)
                      guard count > 0 else { return 0 }
                      let sumSquares = levels.reduce(0) { $0 + $1 * $1 }
                      return sqrt(sumSquares / count)
                  },
                  isActive: recordingVM.recordingState == .recording
            )
            .frame(height: 160)
            .frame(maxWidth: .infinity)

            Text(recordingVM.recordingState == .paused ? "Opname is gepauzeerd" : "Live audioniveau")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
        }
    }

    private var sessionContextCard: some View {
        // Pills sit in one row when there's room; on narrow widths they stack
        // vertically instead of truncating their labels.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TS.Spacing.sm) {
                contextPills
            }
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                contextPills
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contextPills: some View {
        contextPill(icon: recordingVM.selectedMode.iconName, text: recordingVM.selectedMode.displayName)
        contextPill(icon: "person.fill", text: recordingVM.selectedProfile?.name ?? "Geen profiel")
        if recordingVM.offlineQueue.count > 0 {
            contextPill(icon: "tray.fill", text: "\(recordingVM.offlineQueue.count) in wachtrij")
        }
    }

    private func contextPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(TS.Font.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(Color.labelSecondary)
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.surfaceSecondary))
    }

    private var noteFieldCard: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Text("Snelle notitie")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)
            TextField("Bijv. actiepunt of context...", text: $addNoteText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(TS.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(Color.surfaceSecondary)
                }
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
        }
    }

    // MARK: Live transcript panel

    private var liveTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            HStack(spacing: TS.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 32, height: 32)
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live transcriptie")
                        .font(TS.Font.subheadlineSemibold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("Op apparaat")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                PulsingRecordingDot(size: 7)
            }

            let text = recordingVM.liveTranscriptText
            if text.isEmpty {
                Text("Luisteren...")
                    .font(TS.Font.body)
                    .foregroundStyle(Color.labelTertiary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(4)
            }
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.5), lineWidth: 1)
        }
    }

    // MARK: Recording controls

    @ViewBuilder
    private var recordingControls: some View {
        switch recordingVM.recordingState {
        case .recording:
            VStack(spacing: TS.Spacing.sm) {
                primaryActionButton(icon: "stop.fill", label: "Stop en verwerk opname") {
                    Task { await recordingVM.stopAndUpload() }
                }
                HStack(spacing: TS.Spacing.md) {
                    controlButton(icon: "pause.fill", label: "Pauze", color: Color.labelSecondary) {
                        recordingVM.pauseRecording()
                    }
                    controlButton(icon: showNoteField ? "pencil.slash" : "pencil", label: showNoteField ? "Sluit notitie" : "Notitie", color: Color.labelSecondary) {
                        showNoteField.toggle()
                    }
                }
            }

        case .paused:
            VStack(spacing: TS.Spacing.sm) {
                primaryActionButton(icon: "arrow.up.circle.fill", label: "Verstuur huidige opname") {
                    Task { await recordingVM.stopAndUpload() }
                }
                HStack(spacing: TS.Spacing.md) {
                    controlButton(icon: "play.fill", label: "Hervat", color: Color.labelSecondary) {
                        recordingVM.resumeRecording()
                    }
                    // Destructive: tinted apart from the neutral "Hervat" so a
                    // misclick after pausing doesn't read as an equal sibling.
                    controlButton(icon: "xmark", label: "Annuleer", color: Color.statusError) {
                        showCancelConfirm = true
                    }
                }
            }

        default:
            HStack(spacing: TS.Spacing.md) {
                ProgressView()
                Text("Even geduld...")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
    }

    private func primaryActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(TS.Font.footnoteSemibold)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brandPrimary, Color.brandPrimaryDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func controlButton(
        icon: String,
        label: String,
        color: Color,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: TS.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(isPrimary ? color : Color.surfaceSecondary)
                        .frame(width: 56, height: 48)
                        .shadow(
                            color: isPrimary ? color.opacity(0.35) : Color.black.opacity(0.06),
                            radius: isPrimary ? 8 : 4,
                            y: 2
                        )

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isPrimary ? .white : color)
                }

                Text(label)
                    .font(TS.Font.captionMedium)
                    .foregroundStyle(color)
                    .kerning(0.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ReprocessSheet

private struct ReprocessSheet: View {

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.dismiss) private var dismiss

    let recording: SavedRecording

    @State private var selectedProfile: Profile? = nil
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "Opname opnieuw verwerken",
                        systemImage: "waveform.circle.fill"
                    )
                    .foregroundStyle(Color.brandPrimary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(recording.filename)
                            .font(TS.Font.footnoteMedium)
                        Text(recording.formattedDate)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                Section("Profiel") {
                    ForEach(recordingVM.availableProfiles) { profile in
                        Button {
                            selectedProfile = profile
                        } label: {
                            HStack {
                                Text(profile.name)
                                    .foregroundStyle(Color.labelPrimary)
                                Spacer()
                                if selectedProfile?.id == profile.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.brandPrimary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .formStyle(.grouped)
            .navigationTitle("Opnieuw verwerken")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start verwerking") {
                        startReprocess()
                    }
                    .disabled(isProcessing || selectedProfile == nil)
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .overlay {
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.2)
                        ProgressView("Bezig...")
                            .padding(TS.Spacing.lg)
                            .background {
                                RoundedRectangle(cornerRadius: TS.Radius.md)
                                    .fill(.regularMaterial)
                            }
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            selectedProfile = recordingVM.availableProfiles.first
        }
    }

    private func startReprocess() {
        guard let profile = selectedProfile else { return }
        isProcessing = true
        Task {
            await recordingVM.reprocessRecording(recording, profileId: profile.id, useOnDevice: true)
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview("Idle") {
    RecordingView()
        .environment(RecordingViewModel())
}
