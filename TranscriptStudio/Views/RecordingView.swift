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
            VStack(spacing: TS.Spacing.xl) {
                idleModeSelector
                idleProfileSelector
                idleStartButton
                uploadProgressView
                errorBanner
                activeTasksList
                savedRecordingsSection
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.lg)
        }
    }

    // MARK: Mode selector

    private var idleModeSelector: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("NIEUWE OPNAME")
                .font(TS.Font.microBold)
                .foregroundStyle(Color.labelTertiary)
                .kerning(1.2)

            Text("Opnamemodus")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)

            HStack(spacing: TS.Spacing.xs) {
                modePill(.microphone, color: Color.brandPrimary)
                #if os(macOS)
                modePill(.systemAudio, color: Color.brandSecondary)
                modePill(.combined, color: Color.brandAccent)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func modePill(_ mode: RecordingMode, color: Color) -> some View {
        let isSelected = recordingVM.selectedMode == mode
        Button {
            withAnimation(TS.Animation.smooth) {
                recordingVM.selectedMode = mode
            }
        } label: {
            HStack(spacing: TS.Spacing.xs) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 13, weight: .semibold))
                Text(mode.displayName)
                    .font(TS.Font.footnoteSemibold)
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(color)
                        .shadow(color: color.opacity(0.35), radius: 6, y: 2)
                } else {
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.10))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(color.opacity(0.28), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Profile selector

    private var idleProfileSelector: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("Profiel")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TS.Spacing.xs) {
                    ForEach(recordingVM.availableProfiles) { profile in
                        let isSelected = recordingVM.selectedProfile?.id == profile.id
                        Button {
                            recordingVM.selectedProfile = profile
                        } label: {
                            HStack(spacing: TS.Spacing.xs) {
                                Image(systemName: profileIcon(for: profile.id))
                                    .font(.system(size: 11, weight: .medium))
                                Text(profile.name)
                                    .font(TS.Font.footnoteMedium)
                            }
                            .foregroundStyle(isSelected ? Color.brandPrimary : Color.labelSecondary)
                            .padding(.horizontal, TS.Spacing.sm)
                            .padding(.vertical, TS.Spacing.xs + 2)
                            .background {
                                RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                                    .fill(isSelected
                                          ? Color.accentBgPrimary
                                          : Color.surfaceSecondary)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                                            .stroke(
                                                isSelected
                                                ? Color.brandPrimary.opacity(0.35)
                                                : Color.borderPrimary,
                                                lineWidth: 1
                                            )
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileIcon(for profileId: String) -> String {
        switch profileId.lowercased() {
        case "zakelijk": return "briefcase.fill"
        case "informeel": return "bubble.left.and.bubble.right.fill"
        case "technisch": return "wrench.and.screwdriver.fill"
        default: return "person.fill"
        }
    }

    // MARK: Start button

    private var idleStartButton: some View {
        VStack(spacing: TS.Spacing.md) {
            Button {
                Task { await recordingVM.startRecording() }
            } label: {
                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                Color.brandPrimary.opacity(0.15 - Double(i) * 0.04),
                                lineWidth: 1.5
                            )
                            .frame(
                                width: CGFloat(80 + i * 24),
                                height: CGFloat(80 + i * 24)
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
                        .shadow(color: Color.brandPrimary.opacity(0.45), radius: 20, y: 6)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Text("Tik om op te nemen")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TS.Spacing.md)
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
    }

    // MARK: - Active recording view

    private var activeRecordingView: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            liveIndicator
            timerDisplay
            waveformDisplay
            liveTranscriptPanel
            recordingControls

            Spacer()
        }
        .padding(.horizontal, TS.Spacing.lg)
    }

    // MARK: Live indicator

    private var liveIndicator: some View {
        HStack(spacing: TS.Spacing.xs) {
            PulsingRecordingDot(size: 8)
            Text("LIVE")
                .font(TS.Font.microBold)
                .foregroundStyle(Color.statusError)
                .kerning(1.5)
        }
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, TS.Spacing.xs)
        .background {
            Capsule()
                .fill(Color.statusError.opacity(0.10))
                .overlay {
                    Capsule()
                        .stroke(Color.statusError.opacity(0.30), lineWidth: 1)
                }
        }
    }

    // MARK: Timer display

    private var timerDisplay: some View {
        Text(formattedDuration)
            .font(.system(size: 56, weight: .thin, design: .monospaced))
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
        WaveformView(
            levels: recordingVM.audioLevels,
            isActive: recordingVM.recordingState == .recording
        )
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: Live transcript panel

    private var liveTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Label("Live transcriptie", systemImage: "text.bubble")
                .font(TS.Font.captionSemibold)
                .foregroundStyle(Color.labelSecondary)

            ScrollView {
                let text = recordingVM.liveTranscriptText
                if text.isEmpty {
                    Text("Transcriptie wordt gegenereerd terwijl u opneemt...")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(text)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 80)
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                        .stroke(Color.borderPrimary.opacity(0.5), lineWidth: 1)
                }
        }
    }

    // MARK: Recording controls

    @ViewBuilder
    private var recordingControls: some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(spacing: TS.Spacing.lg) {
                controlButton(
                    icon: "pause.fill",
                    label: "Pauze",
                    color: Color.brandOrange
                ) {
                    recordingVM.pauseRecording()
                }

                controlButton(
                    icon: "note.text.badge.plus",
                    label: "Notitie",
                    color: Color.brandSecondary
                ) {
                    showNoteField.toggle()
                }

                controlButton(
                    icon: "stop.fill",
                    label: "Stop",
                    color: Color.statusError,
                    isPrimary: true
                ) {
                    Task { await recordingVM.stopAndUpload() }
                }
            }

        case .paused:
            HStack(spacing: TS.Spacing.lg) {
                controlButton(
                    icon: "play.fill",
                    label: "Hervat",
                    color: Color.brandAccent
                ) {
                    recordingVM.resumeRecording()
                }

                controlButton(
                    icon: "arrow.up.circle.fill",
                    label: "Verstuur",
                    color: Color.brandPrimary,
                    isPrimary: true
                ) {
                    Task { await recordingVM.stopAndUpload() }
                }

                controlButton(
                    icon: "xmark.circle.fill",
                    label: "Annuleer",
                    color: Color.statusError
                ) {
                    Task { await recordingVM.cancelRecording() }
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
                    Circle()
                        .fill(isPrimary ? color : color.opacity(0.12))
                        .frame(width: 56, height: 56)
                        .shadow(
                            color: isPrimary ? color.opacity(0.40) : Color.clear,
                            radius: 10,
                            y: 4
                        )

                    Image(systemName: icon)
                        .font(.system(size: isPrimary ? 22 : 20, weight: .semibold))
                        .foregroundStyle(isPrimary ? .white : color)
                }

                Text(label)
                    .font(TS.Font.captionMedium)
                    .foregroundStyle(color)
            }
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
