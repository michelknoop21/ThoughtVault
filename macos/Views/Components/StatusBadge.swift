// StatusBadge.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Compact colored badge displaying a TranscriptTask's current status
// with appropriate icon and color coding.

import SwiftUI

// MARK: - StatusBadge

struct StatusBadge: View {

    let status: TaskStatus

    var body: some View {
        HStack(spacing: 5) {
            statusIndicator
            Text(status.displayName)
                .font(TS.Font.microSemibold)
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, TS.Spacing.xs)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.xs)
                .stroke(borderColor, lineWidth: 0.5)
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.statusSuccess)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.statusError)

        case .pending, .queued:
            Image(systemName: "clock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.statusWarning)

        default:
            // Active spinning progress for all other states
            SpinningProgressView(color: iconColor)
        }
    }

    // MARK: - Colors

    /// Vivid color for the icon/spinner (graphical object, 3:1 bar).
    private var iconColor: Color {
        switch status {
        case .completed:          return Color.statusSuccess
        case .error:              return Color.statusError
        case .pending, .queued:   return Color.statusWarning
        default:                  return Color.brandSecondary
        }
    }

    /// Darker, AA-passing color for the label text on the tinted background.
    private var textColor: Color {
        switch status {
        case .completed:          return Color.statusSuccessText
        case .error:              return Color.statusErrorText
        case .pending, .queued:   return Color.statusWarningText
        default:                  return Color.statusInfoText
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .completed:          return Color.statusSuccess.opacity(0.10)
        case .error:              return Color.statusError.opacity(0.10)
        case .pending, .queued:   return Color.statusWarning.opacity(0.10)
        default:                  return Color.brandSecondary.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch status {
        case .completed:          return Color.statusSuccess.opacity(0.25)
        case .error:              return Color.statusError.opacity(0.25)
        case .pending, .queued:   return Color.statusWarning.opacity(0.25)
        default:                  return Color.brandSecondary.opacity(0.25)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TS.Spacing.sm) {
        HStack(spacing: TS.Spacing.sm) {
            StatusBadge(status: .pending)
            StatusBadge(status: .uploading)
            StatusBadge(status: .converting)
        }
        HStack(spacing: TS.Spacing.sm) {
            StatusBadge(status: .transcribing)
            StatusBadge(status: .processingWebhook)
            StatusBadge(status: .generatingLocal)
        }
        HStack(spacing: TS.Spacing.sm) {
            StatusBadge(status: .completed)
            StatusBadge(status: .error)
            StatusBadge(status: .queued)
        }
    }
    .padding()
}
