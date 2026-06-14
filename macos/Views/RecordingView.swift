// RecordingView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Dual-state recording interface: idle setup view and active recording view.
// Handles microphone/system audio/combined modes, live transcript, task tracking,
// saved recordings list, and reprocess/retry sheet.

import SwiftUI

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

    // MARK: Body

    var body: some View {
        ZStack {
            backgroundBlobs

            if recordingVM.recordingState.isRecording ||
               recordingVM.recordingState == .preparing ||
               recordingVM.recordingState == .stopping {
                activeRecordingView
            } else {
                idleView
            }
        }
        .sheet(item: $selectedReprocessRecording) { recording in
            ReprocessSheet(recording: recording)
                .environment(recordingVM)
                .frame(minWidth: 420, idealWidth: 460, minHeight: 340, idealHeight: 380)
        }
    }

    // MARK: - Background blobs

    private var backgroundBlobs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandPrimary.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 280
                        )
                    )
                    .frame(width: 560, height: 560)
                    .offset(x: geo.size.width * 0.5, y: -80)
                    .blur(radius: 70)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.neonBlue.opacity(0.08), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: -geo.size.width * 0.2, y: geo.size.height * 0.5)
                    .blur(radius: 55)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Idle view

    private var idleView: some View {
        ScrollView {
            VStack(spacing: TS.Spacing.lg) {
                newRecordingCard
                if recordingVM.isYouTubeEnabled {
                    youtubeCard
                }
                offlineStatusBanner
                audioMixFallbackBanner
                errorBanner
                activeTasksList
                savedRecordingsSection
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.lg)
        }
    }

    // MARK: New recording card (combined mode selector + profiles + mic button)

    private var newRecordingCard: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text("Nieuwe opname")
                    .font(TS.Font.title3Semibold)
                    .foregroundStyle(Color.labelPrimary)
                Text("Kies bron en profiel, klik daarna om op te nemen")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.top, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.md)

            VStack(spacing: TS.Spacing.md) {
                recordingTypeSection
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
                        .padding(TS.Spacing.md)
                    } else {
                        HStack(spacing: TS.Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Profielen laden...")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TS.Spacing.md)
                        .task {
                            await recordingVM.reloadProfiles()
                            if recordingVM.availableProfiles.isEmpty {
                                showProfileLoadError = true
                            }
                        }
                    }
                } else {
                    profileSection
                }
                participantsSection
            }
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.sm)

            // Mic button
            VStack(spacing: TS.Spacing.md) {
                Button {
                    Task { await recordingVM.startRecording() }
                } label: {
                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.brandPrimary.opacity(0.07 - Double(i) * 0.02))
                                .frame(
                                    width: CGFloat(80 + i * 28),
                                    height: CGFloat(80 + i * 28)
                                )
                        }
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.brandPrimary, Color.brandPrimaryDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.brandPrimary.opacity(0.40), radius: 20, y: 6)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start opname")

                Text("Klik om op te nemen")
                    .font(TS.Font.footnote)
                .foregroundStyle(Color.labelTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TS.Spacing.xl)
        }
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                .stroke(Color.borderSecondary, lineWidth: 1)
        }
        .sheet(isPresented: $showParticipantPicker) {
            ParticipantPickerSheet(selectedIDs: Bindable(recordingVM).selectedParticipantIDs)
        }
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

    // MARK: YouTube card

    private var youtubeCard: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                HStack(spacing: TS.Spacing.sm) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(Color.red)
                    Text("YouTube-video")
                        .font(TS.Font.headline)
                        .foregroundStyle(Color.labelPrimary)
                }
                Text("Plak een YouTube URL om te transcriberen")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.top, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.md)

            // Google Account Connection
            VStack(spacing: TS.Spacing.sm) {
                if recordingVM.isGoogleConnected {
                    // Connected state
                    HStack {
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
                    // Not connected — show connect button
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
            }
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.sm)

            VStack(spacing: TS.Spacing.md) {
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
                            .shadow(
                                color: Color.brandPrimary.opacity(0.30),
                                radius: 8,
                                y: 3
                            )
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
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.lg)
        }
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1)
        }
    }

    private var recordingTypeSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("Opnametype")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)

            HStack(spacing: TS.Spacing.sm) {
                recordingTypeOption(
                    icon: "person.2.fill",
                    title: "Fysieke meeting",
                    subtitle: "Alleen microfoon",
                    color: Color.brandSecondary,
                    isSelected: recordingVM.selectedMode == .microphone,
                    action: { withAnimation(TS.Animation.smooth) { recordingVM.selectedMode = .microphone } }
                )

                #if os(macOS)
                recordingTypeOption(
                    icon: "video.fill",
                    title: "Videocall",
                    subtitle: "Microfoon + systeemgeluid",
                    color: Color.brandPrimary,
                    isSelected: recordingVM.selectedMode == .combined,
                    action: { withAnimation(TS.Animation.smooth) { recordingVM.selectedMode = .combined } }
                )
                #endif
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            HStack(spacing: TS.Spacing.xs) {
                Text("Profiel")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                if let selectedProfile = recordingVM.selectedProfile {
                    Text(selectedProfile.name)
                        .font(TS.Font.microBold)
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentBgPrimary))
                }
            }

            ProfilePicker(
                profiles: recordingVM.availableProfiles,
                selectedProfile: selectedProfileBinding
            )

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

    private var selectedProfileBinding: Binding<Profile?> {
        Binding(
            get: { recordingVM.selectedProfile },
            set: { recordingVM.selectedProfile = $0 }
        )
    }

    private func recordingTypeOption(icon: String, title: String, subtitle: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    // MARK: Active tasks list

    @ViewBuilder
    private var activeTasksList: some View {
        let tasks = recordingVM.activeTasks
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Verwerkingsoverzicht")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)

                VStack(spacing: TS.Spacing.xs) {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

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

    // MARK: Saved recordings section

    private var savedRecordingsSection: some View {
        let recordings = Array(recordingVM.savedRecordings.prefix(
            savedRecordingsExpanded ? 10 : 3
        ))
        let extraCount = recordingVM.savedRecordings.count - 10

        return VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Button {
                withAnimation(TS.Animation.smooth) {
                    savedRecordingsExpanded.toggle()
                }
            } label: {
                HStack {
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

                    Image(systemName: savedRecordingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)

            if savedRecordingsExpanded {
                if recordings.isEmpty {
                    Text("Geen opgeslagen opnames")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.vertical, TS.Spacing.sm)
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
        .padding(TS.Spacing.sm)
        .modernCard()
    }

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

    private var activeRecordingView: some View {
        ScrollView {
            VStack(spacing: TS.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opname actief")
                            .font(TS.Font.microBold)
                            .foregroundStyle(Color.labelTertiary)
                            .kerning(1.2)
                        timerDisplay
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
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.lg)
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

    private var timerDisplay: some View {
        Text(formattedDuration)
            .font(.system(size: 56, weight: .light, design: .monospaced))
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
        HStack(spacing: TS.Spacing.sm) {
            contextPill(icon: recordingVM.selectedMode.iconName, text: recordingVM.selectedMode.displayName)
            contextPill(icon: "person.fill", text: recordingVM.selectedProfile?.name ?? "Geen profiel")
            if recordingVM.offlineQueue.count > 0 {
                contextPill(icon: "tray.fill", text: "\(recordingVM.offlineQueue.count) in wachtrij")
            }
            Spacer(minLength: 0)
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
                    controlButton(icon: "xmark", label: "Annuleer", color: Color.labelSecondary) {
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
    @State private var useOnDevice = false
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

                Section("Transcriptiemethode") {
                    Toggle(isOn: $useOnDevice) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Op apparaat (Whisper)")
                                .font(TS.Font.bodyMedium)
                            Text("Transcribeer lokaal zonder internetverbinding")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .tint(Color.brandPrimary)
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
            await recordingVM.reprocessRecording(recording, profileId: profile.id, useOnDevice: useOnDevice)
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
