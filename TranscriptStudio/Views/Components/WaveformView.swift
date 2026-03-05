// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Animated waveform visualization with spring physics bars
// using brand colors. Updates at 60 FPS when active.

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {

    /// Audio level values in range 0.0–1.0, one per bar.
    let levels: [Float]

    /// When false, bars animate to a flat idle state.
    let isActive: Bool

    // MARK: - Constants

    private let barCount: Int = 24
    private let barSpacing: CGFloat = 3
    private let minBarHeight: CGFloat = 4
    private let springStiffness: Double = 350
    private let springDamping: Double = 20

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(2, (geometry.size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount))
            let maxHeight = geometry.size.height

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    AnimatedBar(
                        targetHeight: barHeight(index: index, maxHeight: maxHeight),
                        barWidth: barWidth,
                        colorIndex: index,
                        isActive: isActive,
                        springStiffness: springStiffness,
                        springDamping: springDamping
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Height Calculation

    private func barHeight(index: Int, maxHeight: CGFloat) -> CGFloat {
        guard isActive, !levels.isEmpty else {
            // Idle: show subtle flat heartbeat-style minimum
            return minBarHeight + idleHeight(index: index, maxHeight: maxHeight)
        }

        let levelIndex = index % levels.count
        let level = CGFloat(max(0, min(1, levels[levelIndex])))

        // Apply a slight mirroring for visual symmetry
        let mirrorFactor = 1.0 - abs(CGFloat(index) / CGFloat(barCount) - 0.5) * 0.4
        return max(minBarHeight, level * maxHeight * 0.85 * mirrorFactor)
    }

    private func idleHeight(index: Int, maxHeight: CGFloat) -> CGFloat {
        // Subtle sine-shaped idle pattern
        let position = CGFloat(index) / CGFloat(barCount)
        let base = sin(position * .pi) * maxHeight * 0.06
        return max(0, base)
    }
}

// MARK: - AnimatedBar

private struct AnimatedBar: View {

    let targetHeight: CGFloat
    let barWidth: CGFloat
    let colorIndex: Int
    let isActive: Bool
    let springStiffness: Double
    let springDamping: Double

    @State private var animatedHeight: CGFloat = 4

    private var barColor: Color {
        // Alternate between neonBlue and brandPrimary with a slight phase
        let cycle = colorIndex % 6
        switch cycle {
        case 0, 5: return Color.brandPrimary
        case 1, 4: return Color.neonBlue
        case 2, 3: return Color.brandPrimary.opacity(0.75)
        default:   return Color.neonBlue.opacity(0.75)
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                barColor.opacity(isActive ? 1.0 : 0.35),
                barColor.opacity(isActive ? 0.55 : 0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
            .fill(gradient)
            .frame(width: barWidth, height: animatedHeight)
            .onChange(of: targetHeight) { _, newHeight in
                withAnimation(
                    .interpolatingSpring(stiffness: springStiffness, damping: springDamping)
                ) {
                    animatedHeight = newHeight
                }
            }
            .onAppear {
                animatedHeight = targetHeight
            }
    }
}

// MARK: - Preview

#Preview("Active") {
    WaveformView(
        levels: (0..<24).map { _ in Float.random(in: 0.1...0.95) },
        isActive: true
    )
    .frame(height: 80)
    .padding()
    .background(Color.backgroundDark)
    .preferredColorScheme(.dark)
}

#Preview("Idle") {
    WaveformView(
        levels: [],
        isActive: false
    )
    .frame(height: 80)
    .padding()
    .background(Color.backgroundDark)
    .preferredColorScheme(.dark)
}
