// RecordingActivityWidget.swift
// RecordingActivityWidget
// com.buildmind.ThoughtVault
//
// iOS Live Activity widget for Dynamic Island and lock screen banner.
// Shows real-time recording status with neon waveform visualization.

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget Entry Point

@main
struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock screen / banner live activity view
            LockScreenRecordingView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded — shown when user presses the Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.isPaused ? Color.orange : Color.red)
                            .frame(width: 10, height: 10)

                        if context.state.isPaused {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Text(timerInterval: context.state.startDate...Date.distantFuture, countsDown: false)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.profileName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    NeonWaveformBars(levels: context.state.waveformLevels)
                        .frame(height: 36)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
            } compactLeading: {
                // MARK: Compact leading — red recording dot
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isPaused ? Color.orange : Color.red)
                        .frame(width: 8, height: 8)

                    if context.state.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            } compactTrailing: {
                // MARK: Compact trailing — mini waveform or pause icon
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                } else {
                    MiniWaveformBars(levels: context.state.waveformLevels)
                        .frame(width: 32, height: 16)
                }
            } minimal: {
                // MARK: Minimal — just the recording dot
                Circle()
                    .fill(context.state.isPaused ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Lock Screen / Banner View

struct LockScreenRecordingView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Left: recording indicator + timer + profile name
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(context.state.isPaused ? Color.orange : Color.red)
                        .frame(width: 9, height: 9)

                    if context.state.isPaused {
                        Text("Gepauzeerd")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    } else {
                        Text(timerInterval: context.state.startDate...Date.distantFuture, countsDown: false)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }

                Text(context.attributes.profileName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            // Right: waveform (hidden when paused)
            if !context.state.isPaused {
                NeonWaveformBars(levels: context.state.waveformLevels)
                    .frame(width: 120, height: 36)
            } else {
                // Paused placeholder to maintain layout height
                Image(systemName: "pause.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange.opacity(0.8))
                    .frame(width: 120, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.07, green: 0.09, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - NeonWaveformBars (8 bars, full size)

struct NeonWaveformBars: View {
    let levels: [Float]

    /// Vibrant neon colors from the reference image: neon blue → deep purple → magenta
    private let neonColors: [Color] = [
        Color(red: 0.0, green: 0.8, blue: 1.0), // neon blue
        Color(red: 0.1, green: 0.6, blue: 1.0),
        Color(red: 0.3, green: 0.4, blue: 1.0),
        Color(red: 0.5, green: 0.2, blue: 1.0), // deep purple
        Color(red: 0.7, green: 0.1, blue: 1.0),
        Color(red: 0.8, green: 0.0, blue: 1.0), // magenta
        Color(red: 0.9, green: 0.0, blue: 0.8),
        Color(red: 1.0, green: 0.0, blue: 0.6)  // hot pink
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<8, id: \.self) { index in
                let level = CGFloat(index < levels.count ? levels[index] : 0.0)
                let color = neonColors[index]
                NeonWaveformBar(level: level, color: color)
            }
        }
    }
}

struct NeonWaveformBar: View {
    let level: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let minHeight: CGFloat = 5
            let barHeight = max(minHeight, geo.size.height * pow(level, 0.7)) // Boost visibility

            ZStack(alignment: .center) {
                // Intense outer glow
                Capsule()
                    .fill(color.opacity(0.4))
                    .blur(radius: 6)
                    .frame(width: geo.size.width + 4, height: barHeight + 6)
                
                // Mid glow
                Capsule()
                    .fill(color.opacity(0.6))
                    .blur(radius: 2)
                    .frame(width: geo.size.width + 1, height: barHeight + 2)

                // Sharp neon core
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), color, color.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width, height: barHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: level)
        }
    }
}

// MARK: - MiniWaveformBars (4 bars, compact Dynamic Island)

struct MiniWaveformBars: View {
    let levels: [Float]

    private var sampledLevels: [Float] {
        guard levels.count >= 4 else { return [0.3, 0.5, 0.4, 0.6] }
        return [levels[0], levels[2], levels[4], levels[6]]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                let level = CGFloat(sampledLevels[index])
                let color = index < 2 ? Color(red: 0.0, green: 0.8, blue: 1.0) : Color(red: 0.8, green: 0.0, blue: 1.0)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.5), color],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: max(4, 16 * pow(level, 0.6)))
                    .shadow(color: color.opacity(0.8), radius: 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: level)
            }
        }
    }
}
