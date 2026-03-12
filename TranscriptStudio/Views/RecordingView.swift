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

    @State private var showReprocessSheet = false
    @State private var selectedReprocessRecording: SavedRecording? = nil
    @State private var savedRecordingsExpanded = false
    @State private var addNoteText = ""
    @State private var showNoteField = false
    @State private var showCancelConfirm = false
    @State private var showProfileLoadError = false

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
        .sheet(isPresented: $showReprocessSheet) {
            ReprocessSheet(recording: selectedReprocessRecording)
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
                uploadProgressView
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
                Text("NIEUWE OPNAME")
                    .font(TS.Font.microBold)
                    .foregroundStyle(Color.brandPrimary)
                    .kerning(1.5)
                Text("Kies bron en profiel, tik daarna om op te nemen")
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
                                    try? await Task.sleep(nanoseconds: 10_000_000_000)
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
                            try? await Task.sleep(nanoseconds: 10_000_000_000)
                            if recordingVM.availableProfiles.isEmpty {
                                showProfileLoadError = true
                            }
                        }
                    }
                } else {
                    profileSection
                }
            }
            .padding(.horizontal, TS.Spacing.md)
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

                Text("Tik om op te nemen")
                    .font(TS.Font.footnote)
                .foregroundStyle(Color.labelTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TS.Spacing.xl)
        }
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                .fill(Color.surfacePrimary)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                .stroke(Color.borderSecondary, lineWidth: 1)
        }
    }

    private var recordingTypeSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("Opnametype")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)

            VStack(spacing: TS.Spacing.sm) {
                recordingTypeOption(
                    icon: "person.2.fill",
                    title: "Fysieke meeting",
                    subtitle: "Gebruik alleen je microfoon",
                    color: Color.brandSecondary,
                    isSelected: recordingVM.selectedMode == .microphone,
                    action: { withAnimation(TS.Animation.smooth) { recordingVM.selectedMode = .microphone } }
                )

                #if os(macOS)
                recordingTypeOption(
                    icon: "video.fill",
                    title: "Videocall",
                    subtitle: "Neem microfoon en systeemgeluid op",
                    color: Color.brandPrimary,
                    isSelected: recordingVM.selectedMode == .combined,
                    action: { withAnimation(TS.Animation.smooth) { recordingVM.selectedMode = .combined } }
                )
                #endif
            }
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfaceSecondary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
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
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfaceSecondary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
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
            HStack(spacing: TS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TS.Font.body)
                        .foregroundStyle(Color.labelPrimary)
                    Text(subtitle)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.md)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(isSelected ? Color.accentBgPrimary.opacity(0.45) : Color.surfacePrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .stroke(isSelected ? Color.brandPrimary.opacity(0.45) : Color.borderPrimary.opacity(0.4), lineWidth: 1)
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

    // MARK: Upload progress

    @ViewBuilder
    private var uploadProgressView: some View {
        if case .uploading = recordingVM.recordingState {
            HStack(spacing: TS.Spacing.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Uploaden... \(Int(recordingVM.uploadProgress * 100))%")
                    .font(TS.Font.footnoteMedium)
                    .foregroundStyle(Color.brandSecondary)
                Spacer()
                Button {
                    recordingVM.cancelUpload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.brandSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Upload annuleren")
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.accentBgSecondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.brandSecondary.opacity(0.25), lineWidth: 1)
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
        HStack(spacing: TS.Spacing.sm) {
            // Status icon
            ZStack {
                if task.status == .error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.statusError)
                } else if task.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.statusSuccess)
                } else {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.filename)
                    .font(TS.Font.footnoteMedium)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                if task.status == .error, let errMsg = task.errorMessage {
                    Text(errMsg)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                        .lineLimit(2)
                } else {
                    Text(task.status.displayName)
                        .font(TS.Font.caption)
                        .foregroundStyle(task.status.isActive ? Color.brandPrimary : Color.labelSecondary)
                }
            }

            Spacer()

            StatusBadge(status: task.status)
        }
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.surfaceSecondary)
        }
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
            showReprocessSheet = true
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
                showReprocessSheet = true
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
                levelProvider: { recordingVM.audioLevels },
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
                .fill(Color.surfacePrimary)
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
                .fill(Color.surfacePrimary)
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
                    Text("LIVE TRANSCRIPTIE")
                        .font(TS.Font.microBold)
                        .foregroundStyle(Color.brandPrimary)
                        .kerning(1.0)
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
                .fill(Color.surfacePrimary)
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

    let recording: SavedRecording?

    @State private var selectedProfile: Profile? = nil
    @State private var useOnDevice = false
    @State private var isProcessing = false

    var isRetryMode: Bool { recording == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isRetryMode {
                        Label(
                            "Mislukte upload opnieuw proberen",
                            systemImage: "arrow.clockwise.circle.fill"
                        )
                        .foregroundStyle(Color.brandOrange)
                    } else {
                        Label(
                            "Opname opnieuw verwerken",
                            systemImage: "waveform.circle.fill"
                        )
                        .foregroundStyle(Color.brandPrimary)

                        if let rec = recording {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rec.filename)
                                    .font(TS.Font.footnoteMedium)
                                Text(rec.formattedDate)
                                    .font(TS.Font.caption)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                        }
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
            .navigationTitle(isRetryMode ? "Opnieuw proberen" : "Opnieuw verwerken")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRetryMode ? "Probeer opnieuw" : "Start verwerking") {
                        startReprocess()
                    }
                    .disabled(isProcessing)
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
            if isRetryMode {
                await recordingVM.retryLastFailedUpload()
            } else if let rec = recording {
                await recordingVM.reprocessRecording(rec, profileId: profile.id, useOnDevice: useOnDevice)
            }
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
