// TasksView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Active backend tasks overview with auto-refresh, cancel, and delete support.

import SwiftUI

// MARK: - TasksView

struct TasksView: View {

    // MARK: Dependencies

    @Environment(TasksViewModel.self) var tasksVM
    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.scenePhase) private var scenePhase

    // MARK: State

    @State var taskToCancel: TranscriptTask? = nil
    @State var taskToDelete: TranscriptTask? = nil

    // MARK: Body

    var body: some View {
        Group {
#if os(iOS)
        iosBody
#else
        GeometryReader { geo in
            // Width-tier responsive layout: compact stacks task rows vertically,
            // wide windows get a capped, centered column.
            let isCompact = geo.size.width < 640
            VStack(spacing: 0) {
                // Error banner
                if let error = tasksVM.errorMessage {
                    errorBanner(error, isCompact: isCompact)
                }

                // In local mode, tasks come from recordingVM (no server).
                // In cloud mode, merge both sources.
                let fetchedIDs = Set(tasksVM.activeTasks.map(\.taskId))
                let allTasks = ProcessingMode.isLocalMode
                    ? recordingVM.activeTasks
                    : (tasksVM.activeTasks + recordingVM.activeTasks.filter { !fetchedIDs.contains($0.taskId) })

                if tasksVM.isLoading && allTasks.isEmpty {
                    // First load
                    ProgressView("Taken laden...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if allTasks.isEmpty {
                    emptyState
                } else {
                    taskList(tasks: allTasks, isCompact: isCompact)
                }
            }
        }
#endif
        }
        .navigationTitle("Taken")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    if ProcessingMode.isLocalMode {
                        // No server to refresh in local mode; tasks update live.
                    } else {
                        Task { await tasksVM.loadActiveTasks() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Vernieuwen")
                .disabled(tasksVM.isLoading)
            }
        }
        .task {
            if !ProcessingMode.isLocalMode {
                tasksVM.startAutoRefresh()
            }
        }
        .onDisappear {
            tasksVM.stopAutoRefresh()
        }
        // Pause the 10s network poll while the app is backgrounded; the radio
        // wakeups drain the battery without the user seeing any update.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !ProcessingMode.isLocalMode { tasksVM.startAutoRefresh() }
            } else {
                tasksVM.stopAutoRefresh()
            }
        }
        // Cancel confirmation
        .alert(
            "Taak annuleren",
            isPresented: Binding(
                get: { taskToCancel != nil },
                set: { if !$0 { taskToCancel = nil } }
            )
        ) {
            Button("Annuleer taak", role: .destructive) {
                if let task = taskToCancel {
                    if task.taskId.hasPrefix("local-") {
                        recordingVM.cancelLocalProcessing(task.taskId)
                    } else {
                        Task { await tasksVM.cancelTask(task.taskId) }
                    }
                }
                taskToCancel = nil
            }
            Button("Terug", role: .cancel) {
                taskToCancel = nil
            }
        } message: {
            if let task = taskToCancel {
                Text("Weet je zeker dat je \"\(task.filename)\" wilt annuleren?")
            }
        }
        // Delete confirmation
        .alert(
            "Taak verwijderen",
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            )
        ) {
            Button("Verwijderen", role: .destructive) {
                if let task = taskToDelete {
                    if task.taskId.hasPrefix("local-") {
                        recordingVM.removeTask(task.taskId)
                    } else {
                        Task { await tasksVM.deleteTask(task.taskId) }
                    }
                }
                taskToDelete = nil
            }
            Button("Annuleer", role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            if let task = taskToDelete {
                Text("Weet je zeker dat je \"\(task.filename)\" wilt verwijderen? Dit kan niet ongedaan worden gemaakt.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TS.Spacing.md) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Color.labelTertiary)

            Text("Geen actieve taken")
                .font(TS.Font.title3Semibold)
                .foregroundStyle(Color.labelPrimary)

            Text("Wanneer je een opname start of een audiobestand importeert, verschijnt de voortgang hier.")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String, isCompact: Bool) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusError)
            Text(message)
                .font(TS.Font.footnote)
                .foregroundStyle(Color.statusError)
                .lineLimit(2)
            Spacer()
            Button {
                tasksVM.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.labelTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(TS.Spacing.sm)
        .background(Color.statusError.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
        .padding(.horizontal, isCompact ? TS.Spacing.md : TS.Spacing.lg)
        .padding(.top, TS.Spacing.sm)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Task List

    private func taskList(tasks: [TranscriptTask], isCompact: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: TS.Spacing.sm) {
                ForEach(tasks) { task in
                    TaskRow(
                        task: task,
                        isCompact: isCompact,
                        onCancel: { taskToCancel = task },
                        onDelete: { taskToDelete = task }
                    )
                }
            }
            .padding(.horizontal, isCompact ? TS.Spacing.md : TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.sm)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - TaskRow

private struct TaskRow: View {

    let task: TranscriptTask
    let isCompact: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if isCompact {
                // Narrow width: identity + actions on top, status + progress below.
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    HStack(spacing: TS.Spacing.md) {
                        identitySection
                        Spacer()
                        actionButtons
                    }

                    HStack(spacing: TS.Spacing.sm) {
                        StatusBadge(status: task.status)

                        if showsProgress {
                            ProgressView(value: progressValue)
                                .progressViewStyle(.linear)
                                .tint(Color.brandSecondary)
                                .frame(maxWidth: 160)
                        }

                        Spacer()
                    }
                }
            } else {
                HStack(spacing: TS.Spacing.md) {
                    identitySection

                    Spacer()

                    // Center: status badge + progress
                    VStack(alignment: .trailing, spacing: 4) {
                        StatusBadge(status: task.status)

                        if showsProgress {
                            ProgressView(value: progressValue)
                                .progressViewStyle(.linear)
                                .tint(Color.brandSecondary)
                                .frame(width: 100)
                        }
                    }

                    actionButtons
                }
            }
        }
        .padding(TS.Spacing.md)
        .modernCard(isHovered: isHovered)
        .onHover { hovering in
            withAnimation(TS.Animation.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Sections

    /// Status icon + filename + metadata (shared between compact and regular layouts).
    private var identitySection: some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: statusIconName)
                .font(.system(size: 16))
                .foregroundStyle(statusIconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.filename.isEmpty ? "Naamloze opname" : task.filename)
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                HStack(spacing: TS.Spacing.xs) {
                    if let createdAt = task.createdAt {
                        Text(relativeTimeString(from: createdAt))
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    if let username = task.username, !username.isEmpty {
                        Text("·")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.brandSecondary)
                        Text(username)
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.brandSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: TS.Spacing.xs) {
            if task.status.isActive && !task.taskId.hasPrefix("local-regen-") {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.statusWarning)
                }
                .buttonStyle(.plain)
                .help("Annuleren")
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.statusError)
            }
            .buttonStyle(.plain)
            .help("Verwijderen")
        }
    }

    // MARK: - Helpers

    private var showsProgress: Bool {
        task.status.isActive && task.status != .pending && task.status != .queued
    }

    private var progressValue: Double { task.displayProgress }

    private var statusIconName: String {
        switch task.status {
        case .completed:                    return "checkmark.circle.fill"
        case .error:                        return "exclamationmark.triangle.fill"
        case .pending, .queued:             return "clock.fill"
        case .uploading:                    return "arrow.up.circle.fill"
        case .downloading:                  return "arrow.down.circle.fill"
        case .transcribing, .transcribed:   return "text.bubble.fill"
        case .converting:                   return "waveform"
        case .processingWebhook:            return "doc.text.fill"
        case .generatingLocal:              return "cpu.fill"
        }
    }

    private var statusIconColor: Color {
        switch task.status {
        case .completed:            return Color.statusSuccess
        case .error:                return Color.statusError
        case .pending, .queued:     return Color.statusWarning
        default:                    return Color.brandSecondary
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Zojuist"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) \(minutes == 1 ? "minuut" : "minuten") geleden"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) uur geleden"
        } else {
            let days = Int(interval / 86400)
            return "\(days) \(days == 1 ? "dag" : "dagen") geleden"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TasksView()
    }
    .environment(TasksViewModel())
    .environment(RecordingViewModel())
}
