// WaveformView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Siri-style waveform (SCSiriWaveformView algorithm): 5 overlapping sine waves
// with a parabolic envelope that tapers to zero at the edges, drawn at 60fps in
// the ThoughtVault lavender → violet → indigo gradient.

import SwiftUI

// Mutable reference type so the 60fps render pass can update the smoothed level
// without triggering SwiftUI re-renders.
private class WaveState {
    var smoothedLevel: Double = 0.01

    func update(targetRaw: Float, isActive: Bool) {
        let target = isActive ? Double(max(0.01, targetRaw)) : 0.01
        // Spring-like interpolation; slightly faster attack than decay.
        let delta = target - smoothedLevel
        smoothedLevel += delta * (delta > 0 ? 0.18 : 0.10)
    }
}

private let brandGradient = Gradient(colors: [
    Color(red: 0.847, green: 0.565, blue: 0.941),   // lavender #D890F0
    Color(red: 0.565, green: 0.282, blue: 0.941),   // violet   #9048F0
    Color(red: 0.376, green: 0.282, blue: 0.941)    // indigo   #6048F0
])

struct WaveformView: View {
    let levelProvider: () -> Float
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveState = WaveState()

    private let numberOfWaves = 5
    private let frequency: Double = 1.5
    private let primaryLineWidth: CGFloat = 2.5
    private let secondaryLineWidth: CGFloat = 1.0

    var body: some View {
        // Reduce Motion: the continuous 60fps travelling wave is a WCAG 2.3.3
        // trigger. Replace it with a calm static baseline; the LIVE badge and
        // timer still communicate that recording is active.
        if reduceMotion {
            staticWaveform
        } else {
            animatedWaveform
        }
    }

    private var staticWaveform: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                p.addLine(to: CGPoint(x: size.width, y: midY))
            }
            context.stroke(
                path,
                with: .linearGradient(brandGradient,
                                      startPoint: .zero,
                                      endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .accessibilityHidden(true)
    }

    private var animatedWaveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let phase = -time * 9.0

                waveState.update(targetRaw: levelProvider(), isActive: isActive)
                let level = CGFloat(waveState.smoothedLevel)

                let midX = size.width / 2
                let midY = size.height / 2
                let maxAmplitude = midY - min(max(4, midY * 0.12), 14)
                guard maxAmplitude > 1, midX > 0 else { return }

                let shading: GraphicsContext.Shading = .linearGradient(
                    brandGradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )

                // Back-to-front so the primary wave draws on top.
                for i in stride(from: numberOfWaves - 1, through: 0, by: -1) {
                    let progress = 1.0 - CGFloat(i) / CGFloat(numberOfWaves)
                    let normedAmplitude = (1.5 * progress - 0.4) * level
                    // Slight per-wave phase offset keeps layers distinct but coherent.
                    let wavePhase = phase + Double(i) * 0.35

                    let path = Path { p in
                        var first = true
                        for x in stride(from: CGFloat(0), through: size.width, by: 2.0) {
                            let normalized = (x - midX) / midX
                            // Parabolic envelope: 1 at center, 0 at the edges —
                            // the organic diamond silhouette that reads as "Siri".
                            let envelope = -(normalized * normalized) + 1.0
                            let angle = 2 * CGFloat.pi * (x / size.width) * CGFloat(frequency) + CGFloat(wavePhase)
                            let y = envelope * maxAmplitude * normedAmplitude * sin(angle) + midY
                            if first { p.move(to: CGPoint(x: x, y: y)); first = false }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }

                    let isPrimary = (i == 0)
                    let alpha = min(1.0, (Double(i) / Double(numberOfWaves)) / 3.0 + 1.0 / 3.0)

                    if isPrimary {
                        // Soft glow under the primary wave.
                        var glow = context
                        glow.blendMode = .plusLighter
                        glow.opacity = 0.35
                        glow.stroke(path, with: shading,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                        context.stroke(path, with: shading,
                                       style: StrokeStyle(lineWidth: primaryLineWidth, lineCap: .round, lineJoin: .round))
                    } else {
                        var ctx = context
                        ctx.blendMode = .plusLighter
                        ctx.opacity = alpha
                        ctx.stroke(path, with: shading,
                                   style: StrokeStyle(lineWidth: secondaryLineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }
}
