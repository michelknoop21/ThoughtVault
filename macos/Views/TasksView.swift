// TasksView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Active backend tasks overview with auto-refresh, cancel, and delete support.

import SwiftUI

// MARK: - TasksView

struct TasksView: View {

    // MARK: Dependencies

    @Environment(TasksViewModel.self) private var tasksVM

    // MARK: State

    @State private var taskToCancel: TranscriptTask? = nil
    @State private var taskToDelete: TranscriptTask? = nil

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = tasksVM.errorMessage {
                errorBanner(error)
            }

            if tasksVM.isLoading && tasksVM.activeTasks.isEmpty {
                // First load
                ProgressView("Taken laden...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasksVM.activeTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .navigationTitle("Taken")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await tasksVM.loadActiveTasks() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Vernieuwen")
                .disabled(tasksVM.isLoading)
            }
        }
        .task {
            tasksVM.startAutoRefresh()
        }
        .onDisappear {
            tasksVM.stopAutoRefresh()
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
                    Task { await tasksVM.cancelTask(task.taskId) }
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
                    Task { await tasksVM.deleteTask(task.taskId) }
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

            Text("Wanneer je een opname uploadt, verschijnt de voortgang hier.")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
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
        .padding(.horizontal, TS.Spacing.md)
        .padding(.top, TS.Spacing.sm)
    }

    // MARK: - Task List

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: TS.Spacing.sm) {
                ForEach(tasksVM.activeTasks) { task in
                    TaskRow(
                        task: task,
                        onCancel: { taskToCancel = task },
                        onDelete: { taskToDelete = task }
                    )
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
        }
    }
}

// MARK: - TaskRow

private struct TaskRow: View {

    let task: TranscriptTask
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: TS.Spacing.md) {
            // Left: status icon + filename
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

            Spacer()

            // Center: status badge + progress
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: task.status)

                if task.status.isActive && task.status != .pending && task.status != .queued {
                    ProgressView(value: task.status.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.brandSecondary)
                        .frame(width: 100)
                }
            }

            // Right: action buttons
            HStack(spacing: TS.Spacing.xs) {
                if task.status.isActive {
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
        .padding(TS.Spacing.md)
        .modernCard(isHovered: isHovered)
        .onHover { hovering in
            withAnimation(TS.Animation.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Helpers

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
}
