// RecordingView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Recording screen state and the pieces shared by both platform layouts
// (RecordingView+Studio/+Inspector on macOS, RecordingView+iOS on iOS): banners,
// YouTube section, processing and saved-recordings lists, and the reprocess sheet.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - RecordingView

struct RecordingView: View {

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM

    // MARK: State

    @State var selectedReprocessRecording: SavedRecording? = nil
    @State private var savedRecordingsExpanded = false
    // Internal (not private): shared with the macOS studio in RecordingView+Studio.swift.
    @State var showNoteField = false
    @State var showCancelConfirm = false
    @State private var recordingToDelete: SavedRecording?
    @State var showProfileLoadError = false
    @State var showParticipantPicker = false
    @State var showImporter = false
    @State var showYouTubeSection = false
    @State var showSavedRecordings = false
    @AppStorage("preferOnDeviceTranscription") var preferOnDeviceTranscription = false

    // MARK: Body

    var body: some View {
        Group {
#if os(macOS)
            studioView
#else
            iosBody
#endif
        }
#if DEBUG
        .onAppear {
            if DebugScreenshotSeed.isEnabled, IOSDebug.open == "notebook", RecordingFeatures.enabled {
                recordingVM.recordingTitleMode = "manual"
                recordingVM.recordingTitle = "Wekelijkse projectafstemming"
                recordingVM.recordingState = .paused
                recordingVM.quickNote = "De pilot start met twee teams.\n- [ ] Testomgeving klaarzetten — Alex\n- [ ] Planning voor de pilot rondsturen — Michel\n- [x] Toegang controleren"
                showNoteField = true
            }
        }
#endif
    }

    var recordingIdentityFields: some View {
        @Bindable var vm = recordingVM
        return VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Picker("Titel", selection: $vm.recordingTitleMode) {
                Text("Automatisch na verwerking").tag("automatic")
                Text("Eigen titel").tag("manual")
                if vm.currentCalendarMeeting != nil { Text("Titel van agendameeting").tag("meeting") }
            }
            .onChange(of: vm.recordingTitleMode) { _, mode in
                if mode == "meeting", let meeting = vm.currentCalendarMeeting { vm.activeMeeting = meeting }
            }
            if vm.recordingTitleMode == "manual" {
                TextField("Titel van deze opname", text: $vm.recordingTitle)
                    .textFieldStyle(.roundedBorder)
            } else if vm.recordingTitleMode == "meeting", let meeting = vm.currentCalendarMeeting {
                Label(meeting.title, systemImage: "calendar")
                Text("Gekoppeld aan deze agenda-afspraak")
                    .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }
        }
    }

    func reprocessSheet(for recording: SavedRecording) -> some View {
        ReprocessSheet(recording: recording)
            .environment(recordingVM)
#if os(macOS)
            .frame(minWidth: 360, idealWidth: 460, minHeight: 340, idealHeight: 440)
#endif
    }

    // MARK: YouTube inline section

    @ViewBuilder
    var youtubeInlineSection: some View {
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

    func unifiedBottomBar(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                VStack(spacing: TS.Spacing.md) {
                    verwerkingPanel
                    savedRecordingsPanel
                }
            } else {
                HStack(alignment: .top, spacing: TS.Spacing.md) {
                    verwerkingPanel
                    savedRecordingsPanel
                }
            }
        }
    }

    // Processing panel
    @ViewBuilder private var verwerkingPanel: some View {
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

    // MARK: Offline status banner

    @ViewBuilder
    var offlineStatusBanner: some View {
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
    var errorBanner: some View {
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
    var audioMixFallbackBanner: some View {
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
                    Text(task.statusLabel)
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
        return "\(task.filename), \(task.statusLabel)"
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
                recordingToDelete = recording
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
        .confirmationDialog("Opname verwijderen?", isPresented: Binding(
            get: { recordingToDelete?.id == recording.id },
            set: { if !$0 { recordingToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) {
                withAnimation(TS.Animation.smooth) { recordingVM.deleteSavedRecording(recording) }
                recordingToDelete = nil
            }
            Button("Annuleren", role: .cancel) { recordingToDelete = nil }
        } message: {
            Text("Het audiobestand wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.")
        }
    }

    var formattedDuration: String {
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

    @ViewBuilder var noteFieldCard: some View {
        if RecordingFeatures.enabled {
            RecordingNotebook(text: Bindable(recordingVM).quickNote)
        } else {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Text("Snelle notitie")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)
            TextField("Bijv. actiepunt of context...", text: Bindable(recordingVM).quickNote, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(TS.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .fill(Color.surfaceSecondary)
                }
            Text("Wordt lokaal bewaard en meegenomen in de notulen.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
            Button("Bewaar notitie") {
                recordingVM.saveQuickNoteDraft()
                showNoteField = false
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(recordingVM.quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
    }
}

// MARK: - ReprocessSheet

private struct ReprocessSheet: View {

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.dismiss) private var dismiss

    let recording: SavedRecording

    @State private var selectedProfile: Profile? = nil
    @State private var isProcessing = false
    @State private var optimizeAudio = false

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

                if RecordingFeatures.enabled { Section {
                    Toggle("Audio optimaliseren", isOn: $optimizeAudio)
                    Text("Verbetert het volume op een tijdelijke kopie. Het origineel blijft bewaard; herstel van beschadigde spraak is niet gegarandeerd.")
                        .font(TS.Font.caption)
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
            await recordingVM.reprocessRecording(recording, profileId: profile.id, useOnDevice: true, optimizeAudio: optimizeAudio)
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

/// The same persisted text format is used by recording, retries and exports.
struct RecordingNotebook: View {
    @Binding var text: String
    @State private var tab = "actions"
    @State private var expanded = true
    @State private var newAction = ""
    private var document: QuickNoteDocument { QuickNoteDocument(text) }

    private func edit(_ change: (inout QuickNoteDocument) -> Void) {
        var draft = document
        change(&draft)
        text = draft.text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            HStack {
                Label("Kladblok", systemImage: "square.and.pencil").font(TS.Font.bodyBold)
                Spacer()
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Kladblok inklappen" : "Kladblok uitklappen")
            }
            if expanded {
                Picker("Kladblokonderdeel", selection: $tab) {
                    Text("Notities").tag("notes")
                    Text("Actiepunten").tag("actions")
                }
                .pickerStyle(.segmented)
                if tab == "notes" {
                    TextEditor(text: Binding(get: { document.notes }, set: { value in edit { $0.notes = value } }))
                        .font(TS.Font.body).frame(minHeight: 120, maxHeight: 180)
                        .accessibilityLabel("Eigen notities")
                } else {
                    ForEach(document.items.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: TS.Spacing.sm) {
                            Button { edit { $0.items[index].done.toggle() } } label: {
                                Image(systemName: document.items[index].done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 21))
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel(document.items[index].done ? "Actiepunt weer openen" : "Actiepunt afronden")
                            .accessibilityValue(document.items[index].done ? "Afgerond" : "Open")
                            TextField("Actiepunt", text: Binding(get: { document.items.indices.contains(index) ? document.items[index].text : "" },
                                set: { value in edit { if $0.items.indices.contains(index) { $0.items[index].text = value } } }), axis: .vertical)
                                .textFieldStyle(.plain).lineLimit(1...6)
                                .strikethrough(document.items[index].done)
                                .foregroundStyle(document.items[index].done ? Color.labelSecondary : Color.labelPrimary)
                            Button { edit { $0.items.remove(at: index) } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                .accessibilityLabel("Actiepunt verwijderen")
                        }
                    }
                    HStack(alignment: .top) {
                        TextField("Nieuw actiepunt…", text: $newAction, axis: .vertical)
                            .textFieldStyle(.plain).onSubmit(addAction)
                        Button("Toevoegen", action: addAction)
                            .disabled(newAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack { footer; Spacer(); count }
                    VStack(alignment: .leading, spacing: 4) { footer; count }
                }
                .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(TS.Spacing.md)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: TS.Radius.md).stroke(Color.borderPrimary))
    }
    private var footer: some View { Text("Blijft bij deze opname bewaard") }
    private var count: some View { Text("\(document.items.filter(\.done).count) van \(document.items.count) afgerond") }
    private func addAction() {
        let value = newAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        edit { $0.items.append(.init(text: value, done: false)) }
        newAction = ""
    }
}
