// ProcessingView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
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

    @State private var navigateToResult: Bool = false
    @State private var showError: Bool = false
    @State private var isFetchingResult: Bool = false
    @State private var fetchedTask: TranscriptTask?
    @State private var shimmerPhase: CGFloat = -1.0

    private var displayTask: TranscriptTask {
        fetchedTask ?? task
    }

    var body: some View {
        Group {
            if navigateToResult, let resultTask = fetchedTask ?? (task.notuleHtml != nil ? task : nil) {
                NotuleResultView(task: resultTask, onDismiss: onDismiss)
            } else {
                processingContent
            }
        }
        .onChange(of: task.status) { _, newStatus in
            handleStatusChange(newStatus)
        }
        .onChange(of: task.notuleHtml) { _, html in
            if html != nil && task.status == .completed {
                scheduleNavigation()
            }
        }
        .onAppear {
            if task.status == .error {
                showError = true
            }
            if task.status == .completed {
                if task.notuleHtml != nil {
                    scheduleNavigation()
                } else {
                    Task { await fetchResultFromServer() }
                }
            }
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color.backgroundDark,
                    Color(red: 0.10, green: 0.08, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle glow behind ring
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
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .animation(TS.Animation.smooth, value: displayTask.status)

                    Text("\(Int(displayTask.status.progress * 100))%")
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.neonBlue.opacity(0.7))
                }

                // Transcript preview panel
                transcriptPreviewPanel

                Spacer()

                // Error overlay (shown inline at bottom)
                if showError || displayTask.status == .error {
                    errorPanel
                }
            }
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.bottom, TS.Spacing.xl)
        }
    }

    // MARK: - Progress Step Checklist

    private var progressStepChecklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: TS.Spacing.xs) {
                PulsingRecordingDot(size: 6)
                Text("VOORTGANG")
                    .font(TS.Font.microBold)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .kerning(1.5)
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
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
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
                .foregroundStyle(state == .pending ? Color.white.opacity(0.4) : Color.white.opacity(0.9))

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
                .fill(completed ? Color.statusSuccess.opacity(0.5) : Color.white.opacity(0.10))
                .frame(width: 2, height: 16)
                .padding(.leading, 15) // center under the 32px circle
            Spacer()
        }
    }

    private func stepColor(_ state: StepState) -> Color {
        switch state {
        case .completed: return Color.statusSuccess
        case .active: return Color.brandPrimary
        case .pending: return Color.white.opacity(0.3)
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
                    .foregroundStyle(Color.neonBlue.opacity(0.7))
                Text("Transcriptie")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
            }

            if let transcription = displayTask.rawTranscription, !transcription.isEmpty {
                // Actual transcription text
                ScrollView {
                    Text(transcription)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.white.opacity(0.85))
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
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
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
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.08)
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
                        .foregroundStyle(.white)
                    if let errorMessage = displayTask.errorMessage {
                        Text(errorMessage)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.white.opacity(0.65))
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
            if task.notuleHtml != nil {
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
            if result.notuleHtml != nil {
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
            if result.notuleHtml != nil {
                scheduleNavigation()
            }
        } else {
            await MainActor.run { isFetchingResult = false }
        }
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
