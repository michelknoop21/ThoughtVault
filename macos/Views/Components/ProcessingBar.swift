// ProcessingBar.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Compact global status bar showing active uploads and processing tasks.
// Displayed at the top of the detail view, visible on all tabs.

import SwiftUI

struct ProcessingBar: View {

    @Environment(RecordingViewModel.self) private var recordingVM

    var body: some View {
        let tasks = recordingVM.activeTasks
        if !tasks.isEmpty {
            VStack(spacing: 2) {
                ForEach(tasks) { task in
                    ProcessingBarItem(task: task)
                }
            }
        }
    }
}

// MARK: - ProcessingBarItem

private struct ProcessingBarItem: View {

    @Environment(RecordingViewModel.self) private var recordingVM
    let task: TranscriptTask

    private var isUploading: Bool { task.status == .uploading }
    private var isFailed: Bool { task.status == .error }
    private var isCompleted: Bool { task.status == .completed }
    private var isProcessing: Bool { !isUploading && !isFailed && !isCompleted }

    var body: some View {
        HStack(spacing: TS.Spacing.sm) {
            // Status indicator
            statusIcon

            // Label
            VStack(alignment: .leading, spacing: 1) {
                Text(task.filename)
                    .font(TS.Font.captionMedium)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                if isFailed, let msg = task.errorMessage {
                    Text(msg)
                        .font(TS.Font.micro)
                        .foregroundStyle(Color.statusError)
                        .lineLimit(1)
                } else {
                    Text(task.status.displayName)
                        .font(TS.Font.micro)
                        .foregroundStyle(statusColor.opacity(0.8))
                }
            }

            Spacer()

            // Progress percentage
            if isUploading {
                Text("\(Int(task.progress * 100))%")
                    .font(TS.Font.microBold)
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
            }

            // Actions
            if isCompleted {
                Button {
                    recordingVM.removeTask(task.taskId)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.statusSuccess)
                }
                .buttonStyle(.plain)
            } else if isFailed {
                Button {
                    recordingVM.removeTask(task.taskId)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.statusError.opacity(0.6))
                }
                .buttonStyle(.plain)
            } else if isUploading {
                Button {
                    recordingVM.cancelUpload(task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .help("Upload annuleren")
            }
        }
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, TS.Spacing.xs + 2)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                    .fill(statusColor.opacity(0.06))

                // Progress track
                if isUploading || isProcessing {
                    GeometryReader { geo in
                        let normalizedProgress = isUploading ? task.progress : task.status.progress
                        RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                            .frame(width: geo.size.width * normalizedProgress)
                            .animation(.linear(duration: 0.3), value: normalizedProgress)
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                .stroke(statusColor.opacity(0.15), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isFailed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.statusError)
        } else if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.statusSuccess)
        } else {
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
        }
    }

    private var statusColor: Color {
        if isFailed { return Color.statusError }
        if isCompleted { return Color.statusSuccess }
        if isUploading { return Color.brandSecondary }
        return Color.brandPrimary
    }
}
