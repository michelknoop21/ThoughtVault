// ProcessingView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Full-screen animated processing interface showing circular progress,
// status messages, live transcript preview, and auto-transition to result view.

import SwiftUI

// MARK: - ProcessingView

struct ProcessingView: View {

    let task: TranscriptTask
    let onDismiss: () -> Void
    let onRetryViaCloud: (() -> Void)?

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var navigateToResult: Bool = false
    @State private var showError: Bool = false
    @State private var isFetchingResult: Bool = false
    @State private var fetchedTask: TranscriptTask?
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var isStalled = false
    @State private var lastStatusChange = Date()
    @State private var stalledCheckTask: Task<Void, Never>? = nil

    private var displayTask: TranscriptTask {
        fetchedTask ?? task
    }

    var body: some View {
        Group {
            if navigateToResult, let resultTask = fetchedTask ?? (hasResultContent(task) ? task : nil) {
                NotuleResultView(task: resultTask, onDismiss: onDismiss)
            } else {
                processingContent
            }
        }
        .onChange(of: task.status) { _, newStatus in
            lastStatusChange = Date()
            isStalled = false
            handleStatusChange(newStatus)
        }
        .onChange(of: task.notuleHtml) { _, html in
            if html?.isEmpty == false && task.status == .completed {
                scheduleNavigation()
            }
        }
        .onChange(of: task.rawTranscription) { _, raw in
            if raw?.isEmpty == false && task.status == .completed {
                scheduleNavigation()
            }
        }
        .onAppear {
            if task.status == .error {
                showError = true
            }
            if task.status == .completed {
                if hasResultContent(task) {
                    scheduleNavigation()
                } else {
                    Task { await fetchResultFromServer() }
                }
            }
            stalledCheckTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    if task.status != .completed && task.status != .error {
                        let elapsed = Date().timeIntervalSince(lastStatusChange)
                        if elapsed > 120 {
                            await MainActor.run { isStalled = true }
                        }
                    }
                }
            }
        }
        .onDisappear {
            stalledCheckTask?.cancel()
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        ZStack {
            // Background — glass-on-soft-gray, matching the rest of the app
            // (was a bespoke dark-SaaS gradient that broke brand + the light→dark→light arc).
            LinearGradient(
                colors: [Color.surfaceSecondary, Color.surfacePrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle brand glow behind the content
            Circle()
                .fill(Color.brandPrimary.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 60)

            VStack(spacing: TS.Spacing.xl) {
                Spacer()

                // Step checklist
                progressStepChecklist

                // Status message
                VStack(spacing: TS.Spacing.sm) {
                    Text(processingMessage(for: displayTask.status))
                        .font(TS.Font.title3Semibold)
                        .foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.center)
                        .animation(TS.Animation.smooth, value: displayTask.status)

                    if displayTask.status == .uploading {
                        Text("\(Int(displayTask.progress * 100))%")
                            .font(TS.Font.captionMonospaced)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }

                // Transcript preview panel
                transcriptPreviewPanel

                if isStalled {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(Color.brandOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verwerking lijkt vast te zitten")
                                .font(TS.Font.footnoteMedium)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Laatste update was meer dan 2 minuten geleden")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        Spacer()
                        Button("Sluiten") {
                            onDismiss()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(TS.Spacing.md)
                    .background(Color.brandOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.md)
                            .stroke(Color.brandOrange.opacity(0.30), lineWidth: 1)
                    }
                }

                Spacer()

                // Error overlay (shown inline at bottom)
                if showError || displayTask.status == .error {
                    errorPanel
                }
            }
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.xl)
        }
        // Persistent escape during normal processing — the task keeps running in the
        // background via activeTasks, so the user is never trapped on a long file.
        // Hidden while stalled/errored, which surface their own dismiss affordance.
        .overlay(alignment: .topTrailing) {
            if !isStalled && displayTask.status != .error && displayTask.status != .completed {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                        Text("Verder op achtergrond")
                    }
                    .font(TS.Font.footnoteMedium)
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.vertical, TS.Spacing.sm)
                    .background(Color.surfacePrimary, in: Capsule())
                    .overlay(Capsule().stroke(Color.borderPrimary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Sluit dit scherm; de verwerking gaat door op de achtergrond")
                .padding(TS.Spacing.lg)
            }
        }
    }

    // MARK: - Progress Step Checklist

    private var progressStepChecklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: TS.Spacing.xs) {
                PulsingRecordingDot(size: 6)
                Text("Voortgang")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
            }
            .padding(.bottom, TS.Spacing.md)

            // Steps
            progressStep(
                icon: "arrow.up.circle.fill",
                label: "Audio uploaden",
                state: stepState(for: .uploading)
            )
            stepConnector(completed: displayTask.status.progress > 0.15)
            progressStep(
                icon: "waveform.badge.magnifyingglass",
                label: "Audio converteren",
                state: stepState(for: .converting)
            )
            stepConnector(completed: displayTask.status.progress > 0.25)
            progressStep(
                icon: "bubble.left.fill",
                label: "Spraak naar tekst",
                state: stepState(for: .transcribing)
            )
            stepConnector(completed: displayTask.status.progress > 0.60)
            progressStep(
                icon: "sparkles",
                label: "AI notulen structureren",
                state: stepState(for: .processingWebhook)
            )
        }
        .padding(TS.Spacing.md)
        .background(Color.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md)
                .stroke(Color.borderPrimary, lineWidth: 1)
        }
    }

    private enum StepState {
        case pending, active, completed
    }

    private func stepState(for step: TaskStatus) -> StepState {
        let current = displayTask.status
        if current == .error { return current.progress >= step.progress ? .completed : .pending }
        if current == .completed { return .completed }
        if current.progress > step.progress { return .completed }
        if current == step || (step == .processingWebhook && (current == .queued || current == .generatingLocal)) { return .active }
        if step == .transcribing && current == .transcribed { return .completed }
        return .pending
    }

    private func progressStep(icon: String, label: String, state: StepState) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(stepColor(state).opacity(0.15))
                    .frame(width: 32, height: 32)
                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.statusSuccess)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(stepColor(state))
                }
            }

            Text(label)
                .font(TS.Font.footnoteMedium)
                .foregroundStyle(state == .pending ? Color.labelTertiary : Color.labelPrimary)

            Spacer()

            if state == .active {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Color.brandPrimary)
            }
        }
    }

    private func stepConnector(completed: Bool) -> some View {
        HStack {
            Rectangle()
                .fill(completed ? Color.statusSuccess.opacity(0.5) : Color.borderPrimary)
                .frame(width: 2, height: 16)
                .padding(.leading, 15) // center under the 32px circle
            Spacer()
        }
    }

    private func stepColor(_ state: StepState) -> Color {
        switch state {
        case .completed: return Color.statusSuccess
        case .active: return Color.brandPrimary
        case .pending: return Color.labelTertiary
        }
    }

    // MARK: - Circular Progress Ring

    private var circularProgressRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                .frame(width: 140, height: 140)

            // Progress arc
            Circle()
                .trim(from: 0, to: displayTask.status.progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.brandPrimary, Color.neonBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))
                .animation(TS.Animation.gentle, value: displayTask.status.progress)

            // Center icon
            Group {
                if isFetchingResult {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: statusIcon(for: displayTask.status))
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            displayTask.status == .error
                                ? Color.statusError
                                : Color.neonBlue
                        )
                }
            }
            .animation(TS.Animation.smooth, value: displayTask.status)
        }
    }

    // MARK: - Transcript Preview Panel

    private var transcriptPreviewPanel: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Color.brandSecondary)
                Text("Transcriptie")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
            }

            if let transcription = displayTask.rawTranscription, !transcription.isEmpty {
                // Actual transcription text
                ScrollView {
                    Text(transcription)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TS.Spacing.sm)
                }
                .frame(maxHeight: 160)
            } else {
                // Shimmer skeleton
                shimmerSkeleton
            }
        }
        .padding(TS.Spacing.md)
        .background(Color.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md)
                .stroke(Color.borderPrimary, lineWidth: 1)
        }
    }

    // MARK: - Shimmer Skeleton

    private var shimmerSkeleton: some View {
        VStack(spacing: TS.Spacing.sm) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.labelTertiary.opacity(0.12),
                                Color.labelTertiary.opacity(0.28),
                                Color.labelTertiary.opacity(0.12)
                            ],
                            startPoint: UnitPoint(x: shimmerPhase, y: 0),
                            endPoint: UnitPoint(x: shimmerPhase + 1, y: 0)
                        )
                    )
                    .frame(height: 12)
                    .frame(maxWidth: index == 3 ? .infinity * 0.6 : .infinity)
            }
        }
        .onAppear {
            // Reduce Motion: keep the skeleton bars static, no sweeping shimmer (WCAG 2.3.3).
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
    }

    // MARK: - Error Panel

    private var errorPanel: some View {
        VStack(spacing: TS.Spacing.md) {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusError)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verwerking mislukt")
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.labelPrimary)
                    if let errorMessage = displayTask.errorMessage {
                        Text(errorMessage)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
            }

            HStack(spacing: TS.Spacing.sm) {
                Button("Sluiten") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                if let retryViaCloud = onRetryViaCloud {
                    Button("Probeer via cloud") {
                        retryViaCloud()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(TS.Spacing.md)
        .background(Color.statusError.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md)
                .stroke(Color.statusError.opacity(0.30), lineWidth: 1)
        }
    }

    // MARK: - Dutch Status Messages

    private func processingMessage(for status: TaskStatus) -> String {
        switch status {
        case .pending:           return "Wachten op verwerking..."
        case .uploading:         return "Audio wordt geüpload..."
        case .downloading:       return "YouTube video wordt gedownload..."
        case .converting:        return "Audio wordt verwerkt..."
        case .transcribing:      return "Spraak wordt omgezet naar tekst..."
        case .transcribed:       return "Transcriptie voltooid"
        case .queued:            return "Wachtrij: notulen worden gegenereerd..."
        case .processingWebhook: return "Notulen worden opgesteld..."
        case .generatingLocal:   return "Notulen worden lokaal gegenereerd..."
        case .completed:         return "Verwerking voltooid!"
        case .error:             return "Er is een fout opgetreden"
        }
    }

    private func statusIcon(for status: TaskStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .error:     return "exclamationmark.triangle.fill"
        default:         return "waveform"
        }
    }

    // MARK: - State Handling

    private func handleStatusChange(_ status: TaskStatus) {
        if status == .error {
            showError = true
        }
        if status == .completed {
            if hasResultContent(task) {
                scheduleNavigation()
            } else {
                Task { await fetchResultFromServer() }
            }
        }
    }

    private func scheduleNavigation() {
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                navigateToResult = true
            }
        }
    }

    private func fetchResultFromServer() async {
        await MainActor.run { isFetchingResult = true }

        // First attempt
        if let result = try? await APIService.shared.getTaskStatus(taskId: task.taskId) {
            if hasResultContent(result) {
                await MainActor.run {
                    fetchedTask = result
                    isFetchingResult = false
                }
                scheduleNavigation()
                return
            }
        }

        // One automatic retry after 2-second delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if let result = try? await APIService.shared.getTaskStatus(taskId: task.taskId) {
            await MainActor.run {
                fetchedTask = result
                isFetchingResult = false
            }
            if hasResultContent(result) {
                scheduleNavigation()
            }
        } else {
            await MainActor.run { isFetchingResult = false }
        }
    }

    private func hasResultContent(_ task: TranscriptTask) -> Bool {
        let hasNotule = !(task.notuleHtml ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRaw = !(task.rawTranscription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasNotule || hasRaw
    }
}

// MARK: - Preview

#Preview {
    let previewTask = TranscriptTask(
        id: "preview",
        taskId: "preview-task",
        status: .transcribing,
        rawTranscription: "Dit is een preview van de transcriptietekst die tijdens de verwerking wordt weergegeven."
    )
    ProcessingView(
        task: previewTask,
        onDismiss: {},
        onRetryViaCloud: nil
    )
    .environment(RecordingViewModel())
    .frame(width: 500, height: 700)
}
