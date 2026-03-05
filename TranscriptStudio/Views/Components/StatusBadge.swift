// StatusBadge.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
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
                .foregroundStyle(foregroundColor)
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
            SpinningProgressView(color: foregroundColor)
        }
    }

    // MARK: - Colors

    private var foregroundColor: Color {
        switch status {
        case .completed:          return Color.statusSuccess
        case .error:              return Color.statusError
        case .pending, .queued:   return Color.statusWarning
        default:                  return Color.brandSecondary
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

// MARK: - SpinningProgressView

/// Lightweight spinning indicator that avoids ProgressView's heavyweight behavior
/// in small badge contexts.
private struct SpinningProgressView: View {
    let color: Color

    @State private var isRotating: Bool = false

    var body: some View {
        Image(systemName: "arrow.2.circlepath")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(
                .linear(duration: 1.0).repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear { isRotating = true }
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
