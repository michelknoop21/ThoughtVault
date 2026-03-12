// RecordingWidgetView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Compact floating recording widget panel. Shows current recording state,
// live waveform, duration timer, and stop/upload action button.
// Designed as a premium pill overlay (≈320×56px) with brand glow and
// generous touch targets.

import SwiftUI

// MARK: - RecordingWidgetView

struct RecordingWidgetView: View {

    @Environment(RecordingViewModel.self) var recordingVM

    @State private var isHovered: Bool = false

    private var isRecording: Bool { recordingVM.recordingState == .recording }
    private var isPaused: Bool { recordingVM.recordingState == .paused }

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator + state label
            statusBadge

            // Waveform — wider for better visual feedback
            WaveformView(
                levels: recordingVM.audioLevels,
                isActive: isRecording
            )
            .frame(width: 120, height: 32)
            .opacity(isPaused ? 0.4 : 1.0)

            // Duration — prominent monospaced timer
            Text(formattedDuration)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.labelPrimary)
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)

            // Divider before controls
            if isRecording || isPaused || recordingVM.recordingState == .uploading {
                dividerBar
            }

            // Action buttons — larger touch targets
            actionButtons
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background { pillBackground }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    isRecording
                        ? Color.brandPrimary.opacity(0.50)
                        : isPaused
                            ? Color.statusWarning.opacity(0.40)
                            : Color.borderPrimary.opacity(0.4),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.30), radius: 20, y: 6)
        .shadow(
            color: isRecording
                ? Color.brandPrimary.opacity(0.15)
                : Color.clear,
            radius: 24, y: 0
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(TS.Animation.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: - Pill Background

    @ViewBuilder
    private var pillBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .fill(.ultraThinMaterial)
        } else {
            Capsule()
                .fill(.ultraThickMaterial)
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            statusIndicator
            Text(stateLabelText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(statusLabelColor)
                .textCase(.uppercase)
                .kerning(0.8)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusBadgeBackground)
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch recordingVM.recordingState {
        case .recording:
            PulsingRecordingDot(size: 7)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.statusWarning)
        case .uploading:
            ProgressView()
                .tint(Color.neonBlue)
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .stopping, .preparing:
            ProgressView()
                .tint(Color.labelSecondary)
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        default:
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.labelTertiary)
        }
    }

    private var statusLabelColor: Color {
        switch recordingVM.recordingState {
        case .recording: return Color.brandPrimary
        case .paused: return Color.statusWarning
        case .uploading: return Color.neonBlue
        default: return Color.labelSecondary
        }
    }

    private var statusBadgeBackground: Color {
        switch recordingVM.recordingState {
        case .recording: return Color.brandPrimary.opacity(0.12)
        case .paused: return Color.statusWarning.opacity(0.12)
        case .uploading: return Color.neonBlue.opacity(0.12)
        default: return Color.labelSecondary.opacity(0.08)
        }
    }

    private var stateLabelText: String {
        switch recordingVM.recordingState {
        case .idle:       return "Gereed"
        case .preparing:  return "Start..."
        case .recording:  return "Rec"
        case .paused:     return "Pauze"
        case .stopping:   return "Stop..."
        case .uploading:  return "\(Int(recordingVM.uploadProgress * 100))%"
        case .error(let msg): return String(msg.prefix(12))
        }
    }

    // MARK: - Divider

    private var dividerBar: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.labelTertiary.opacity(0.3))
            .frame(width: 1, height: 20)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(spacing: 6) {
                widgetIconButton(
                    icon: "pause.fill",
                    color: Color.labelPrimary,
                    accessibilityLabel: "Pauzeer opname"
                ) {
                    recordingVM.pauseRecording()
                }
                stopButton
            }

        case .paused:
            HStack(spacing: 6) {
                widgetIconButton(
                    icon: "play.fill",
                    color: Color.statusSuccess,
                    accessibilityLabel: "Hervat opname"
                ) {
                    recordingVM.resumeRecording()
                }
                stopButton
            }

        case .uploading:
            uploadIndicator

        default:
            EmptyView()
        }
    }

    private func widgetIconButton(
        icon: String,
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var stopButton: some View {
        Button {
            let vm = recordingVM
            Task { @MainActor in await vm.stopAndUpload() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Stop")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.statusError)
                    .shadow(color: Color.statusError.opacity(0.35), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop opname en upload")
    }

    private var uploadIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.neonBlue)

            // Upload progress ring
            ZStack {
                Circle()
                    .stroke(Color.neonBlue.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: recordingVM.uploadProgress)
                    .stroke(Color.neonBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)

            widgetIconButton(
                icon: "xmark",
                color: Color.labelSecondary,
                accessibilityLabel: "Upload annuleren"
            ) {
                recordingVM.cancelUpload()
            }
        }
        .padding(.horizontal, 4)
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
        .frame(width: 360)
        .padding()
        .background(Color.backgroundDark)
        .preferredColorScheme(.dark)
}
