// CallAlertView.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Overlay alert displayed when an upcoming calendar meeting is detected.
// Shows meeting info with platform branding and quick action buttons.

import SwiftUI

// MARK: - CallAlertView

struct CallAlertView: View {

    let meeting: CalendarEvent
    let onStartRecording: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false
    @State private var isSnoozing: Bool = false

    var body: some View {
        alertCard
            .scaleEffect(isVisible ? 1.0 : 0.92)
            .opacity(isVisible ? 1.0 : 0.0)
            .offset(y: isVisible ? 0 : 16)
            .onAppear {
                withAnimation(TS.Animation.gentle) {
                    isVisible = true
                }
            }
    }

    // MARK: - Alert Card

    private var alertCard: some View {
        VStack(spacing: 0) {
            // Platform accent bar
            platformBar

            VStack(spacing: TS.Spacing.md) {
                // Header
                HStack(spacing: TS.Spacing.sm) {
                    platformIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vergadering begint straks")
                            .font(TS.Font.microSemibold)
                            .foregroundStyle(platformColor.opacity(0.8))
                        Text(meeting.title)
                            .font(TS.Font.headlineBold)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Melding sluiten")
                }

                // Meeting details
                HStack(spacing: TS.Spacing.lg) {
                    meetingDetailCell(
                        icon: "clock",
                        value: meeting.formattedTime,
                        label: "Starttijd"
                    )
                    meetingDetailCell(
                        icon: "calendar",
                        value: meeting.calendarTitle,
                        label: "Agenda"
                    )
                    meetingDetailCell(
                        icon: "desktopcomputer",
                        value: meeting.platform.rawValue,
                        label: "Platform"
                    )
                }
                .padding(TS.Spacing.sm)
                .background(Color.surfaceSecondary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))

                // Action buttons
                HStack(spacing: TS.Spacing.sm) {
                    // Dismiss
                    Button("Negeer") {
                        withAnimation(TS.Animation.smooth) {
                            isVisible = false
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            onDismiss()
                        }
                    }
                    .buttonStyle(AlertSecondaryButtonStyle())

                    // Snooze
                    Button {
                        isSnoozing = true
                        withAnimation(TS.Animation.smooth) {
                            isVisible = false
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            onSnooze()
                        }
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "bell.slash")
                            Text("Herinnering")
                        }
                    }
                    .buttonStyle(AlertSecondaryButtonStyle())
                    .disabled(isSnoozing)

                    Spacer()

                    // Start recording
                    Button {
                        withAnimation(TS.Animation.smooth) {
                            isVisible = false
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            onStartRecording()
                        }
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "mic.fill")
                            Text("Start opname")
                        }
                    }
                    .buttonStyle(AlertPrimaryButtonStyle())
                }
            }
            .padding(TS.Spacing.md)
        }
        .background(Color.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.lg))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.lg)
                .stroke(platformColor.opacity(0.20), lineWidth: 1)
        }
    }

    // MARK: - Platform Accent Bar

    private var platformBar: some View {
        Rectangle()
            .fill(platformColor)
            .frame(height: 3)
    }

    // MARK: - Platform Icon

    private var platformIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TS.Radius.sm)
                .fill(platformColor.opacity(0.12))
                .frame(width: 44, height: 44)

            Image(systemName: meeting.platform.iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(platformColor)
        }
    }

    // MARK: - Meeting Detail Cell

    private func meetingDetailCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
            Text(value)
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
            Text(label)
                .font(TS.Font.micro)
                .foregroundStyle(Color.labelTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Platform Color

    private var platformColor: Color {
        switch meeting.platform {
        case .teams: return Color.platformTeams
        case .zoom:  return Color.platformZoom
        case .meet:  return Color.platformMeet
        case .other: return Color.brandSecondary
        }
    }
}

// MARK: - Alert-Specific Compact Button Styles

/// Compact secondary button for the call alert overlay.
private struct AlertSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TS.Font.footnoteSemibold)
            .foregroundStyle(Color.brandPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.brandPrimary.opacity(configuration.isPressed ? 0.12 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(0.35), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(TS.Animation.quick, value: configuration.isPressed)
    }
}

/// Compact primary button for the call alert overlay.
private struct AlertPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TS.Font.footnoteSemibold)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.brandPrimary.opacity(0.30), radius: 8, y: 3)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(TS.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    let sampleEvent = CalendarEvent(
        id: "preview-event",
        title: "Weekly Design Review — Sprint 24",
        date: Date().addingTimeInterval(300),
        endDate: Date().addingTimeInterval(3900),
        meetingURL: URL(string: "https://teams.microsoft.com/join/meeting"),
        platform: .teams,
        calendarTitle: "Work"
    )

    CallAlertView(
        meeting: sampleEvent,
        onStartRecording: {},
        onSnooze: {},
        onDismiss: {}
    )
    .padding()
    .frame(width: 420)
    .background(Color.surfaceSecondary)
}
