// RecordingWidgetView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Compact floating recording widget panel. Shows current recording state,
// live waveform, duration timer, and stop/upload action button.

import SwiftUI

// MARK: - RecordingWidgetView

struct RecordingWidgetView: View {

    @Environment(RecordingViewModel.self) var recordingVM

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: TS.Spacing.sm) {
            // Status indicator
            statusIndicator

            // Waveform
            WaveformView(
                levels: recordingVM.audioLevels,
                isActive: recordingVM.recordingState == .recording
            )
            .frame(width: 60, height: 28)

            // Duration
            Text(formattedDuration)
                .font(TS.Font.captionMonospaced)
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(minWidth: 46, alignment: .leading)

            // State label
            stateLabel

            Spacer(minLength: TS.Spacing.xs)

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm + 2)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                RoundedRectangle(cornerRadius: TS.Radius.xl, style: .continuous)
                    .fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: TS.Radius.xl, style: .continuous)
                    .fill(Color.backgroundDark.opacity(0.90))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.xl, style: .continuous)
                .stroke(
                    recordingVM.recordingState == .recording
                        ? Color.brandPrimary.opacity(0.40)
                        : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(TS.Animation.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch recordingVM.recordingState {
        case .recording:
            PulsingRecordingDot(size: 8)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.statusWarning)
        case .uploading:
            ProgressView(value: recordingVM.uploadProgress)
                .progressViewStyle(.circular)
                .tint(Color.neonBlue)
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .stopping, .preparing:
            ProgressView()
                .tint(.white)
                .controlSize(.small)
                .frame(width: 16, height: 16)
        default:
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: - State Label

    private var stateLabel: some View {
        Text(stateLabelText)
            .font(TS.Font.microSemibold)
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
    }

    private var stateLabelText: String {
        switch recordingVM.recordingState {
        case .idle:       return "Gereed"
        case .preparing:  return "Voorbereiden..."
        case .recording:  return "Opname"
        case .paused:     return "Gepauzeerd"
        case .stopping:   return "Stoppen..."
        case .uploading:  return "Uploaden \(Int(recordingVM.uploadProgress * 100))%"
        case .error(let msg): return String(msg.prefix(20))
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(spacing: TS.Spacing.xs) {
                // Pause
                Button {
                    recordingVM.pauseRecording()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                // Stop & Upload
                stopButton
            }

        case .paused:
            HStack(spacing: TS.Spacing.xs) {
                // Resume
                Button {
                    recordingVM.resumeRecording()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                // Stop & Upload
                stopButton
            }

        case .uploading:
            Button {
                // No cancel during upload — show info
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.neonBlue)
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }

    private var stopButton: some View {
        Button {
            let vm = recordingVM
            Task { @MainActor in await vm.stopAndUpload() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Stop")
                    .font(TS.Font.microSemibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, TS.Spacing.sm)
            .padding(.vertical, TS.Spacing.xs)
            .background(Color.statusError)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duration Formatting

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
}

// MARK: - Preview

#Preview("Recording") {
    RecordingWidgetView()
        .environment(RecordingViewModel())
        .frame(width: 320)
        .padding()
        .background(Color.backgroundDark)
        .preferredColorScheme(.dark)
}
