// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Siri-style audio waveform with 18 layered neon sine waves.
// Identical rendering at any canvas size — amplitude scales automatically.
// Uses parabolic envelope, per-wave phase travel, and bloom glow.

import SwiftUI

// MARK: - Wave Configuration

private struct WaveConfig {
    let frequency: CGFloat
    let speed: CGFloat         // radians per second — continuous phase travel
    let amplitudeScale: CGFloat
    let smoothingUp: CGFloat   // attack speed (0-1, higher = snappier)
    let smoothingDown: CGFloat // release speed
    let phaseOffset: CGFloat   // initial phase stagger
    let lineWidth: CGFloat
    let glowWidth: CGFloat     // wider stroke for neon bloom
    let glowOpacity: CGFloat
    let historyOffset: Int     // samples back in level buffer this wave reads from
}

// MARK: - Gradient color stops (blue → violet → magenta → cyan)

private let gradientStops: [Gradient.Stop] = [
    .init(color: Color(red: 0.08, green: 0.24, blue: 0.70), location: 0.00),
    .init(color: Color(red: 0.16, green: 0.39, blue: 0.94), location: 0.15),
    .init(color: Color(red: 0.31, green: 0.24, blue: 1.00), location: 0.30),
    .init(color: Color(red: 0.51, green: 0.12, blue: 0.94), location: 0.45),
    .init(color: Color(red: 0.63, green: 0.08, blue: 0.78), location: 0.55),
    .init(color: Color(red: 0.75, green: 0.12, blue: 0.70), location: 0.70),
    .init(color: Color(red: 0.55, green: 0.24, blue: 0.86), location: 0.85),
    .init(color: Color(red: 0.16, green: 0.63, blue: 1.00), location: 0.95),
    .init(color: Color(red: 0.08, green: 0.47, blue: 0.86), location: 1.00),
]

// MARK: - Wave config set (18 waves — identical rendering at any canvas size)

private let fullWaveConfigs: [WaveConfig] = [
    // Primary — brightest, slightly thicker
    WaveConfig(frequency: 1.5,  speed: 9.0,  amplitudeScale: 1.0,  smoothingUp: 0.35, smoothingDown: 0.12, phaseOffset: 0.0,  lineWidth: 1.8, glowWidth: 10.0, glowOpacity: 0.35, historyOffset: 0),
    // Blue core
    WaveConfig(frequency: 1.8,  speed: 7.2,  amplitudeScale: 0.92, smoothingUp: 0.30, smoothingDown: 0.10, phaseOffset: 0.7,  lineWidth: 1.2, glowWidth: 7.0,  glowOpacity: 0.28, historyOffset: 2),
    WaveConfig(frequency: 1.2,  speed: 11.5, amplitudeScale: 0.88, smoothingUp: 0.28, smoothingDown: 0.10, phaseOffset: 1.5,  lineWidth: 1.0, glowWidth: 6.0,  glowOpacity: 0.25, historyOffset: 3),
    WaveConfig(frequency: 2.0,  speed: 6.8,  amplitudeScale: 0.85, smoothingUp: 0.26, smoothingDown: 0.09, phaseOffset: 2.1,  lineWidth: 1.0, glowWidth: 6.0,  glowOpacity: 0.25, historyOffset: 4),
    // Blue-violet
    WaveConfig(frequency: 2.4,  speed: 5.8,  amplitudeScale: 0.80, smoothingUp: 0.24, smoothingDown: 0.09, phaseOffset: 2.8,  lineWidth: 0.9, glowWidth: 5.0,  glowOpacity: 0.22, historyOffset: 5),
    WaveConfig(frequency: 0.9,  speed: 13.0, amplitudeScale: 0.76, smoothingUp: 0.22, smoothingDown: 0.08, phaseOffset: 3.3,  lineWidth: 1.0, glowWidth: 6.0,  glowOpacity: 0.24, historyOffset: 7),
    WaveConfig(frequency: 1.6,  speed: 9.5,  amplitudeScale: 0.72, smoothingUp: 0.22, smoothingDown: 0.08, phaseOffset: 3.9,  lineWidth: 0.8, glowWidth: 4.5,  glowOpacity: 0.20, historyOffset: 8),
    // Violet core
    WaveConfig(frequency: 2.8,  speed: 4.5,  amplitudeScale: 0.68, smoothingUp: 0.20, smoothingDown: 0.08, phaseOffset: 4.5,  lineWidth: 0.9, glowWidth: 5.0,  glowOpacity: 0.22, historyOffset: 9),
    WaveConfig(frequency: 1.1,  speed: 14.0, amplitudeScale: 0.64, smoothingUp: 0.20, smoothingDown: 0.07, phaseOffset: 5.1,  lineWidth: 0.7, glowWidth: 4.0,  glowOpacity: 0.18, historyOffset: 10),
    WaveConfig(frequency: 1.9,  speed: 7.8,  amplitudeScale: 0.60, smoothingUp: 0.18, smoothingDown: 0.07, phaseOffset: 5.7,  lineWidth: 0.8, glowWidth: 5.0,  glowOpacity: 0.20, historyOffset: 11),
    // Purple-magenta accents
    WaveConfig(frequency: 3.0,  speed: 3.8,  amplitudeScale: 0.56, smoothingUp: 0.18, smoothingDown: 0.07, phaseOffset: 6.2,  lineWidth: 0.7, glowWidth: 4.0,  glowOpacity: 0.18, historyOffset: 12),
    WaveConfig(frequency: 0.7,  speed: 15.0, amplitudeScale: 0.52, smoothingUp: 0.16, smoothingDown: 0.06, phaseOffset: 6.8,  lineWidth: 0.7, glowWidth: 4.0,  glowOpacity: 0.16, historyOffset: 14),
    WaveConfig(frequency: 2.2,  speed: 6.2,  amplitudeScale: 0.48, smoothingUp: 0.16, smoothingDown: 0.06, phaseOffset: 7.4,  lineWidth: 0.7, glowWidth: 3.5,  glowOpacity: 0.16, historyOffset: 15),
    // Cyan highlights
    WaveConfig(frequency: 1.4,  speed: 11.5, amplitudeScale: 0.44, smoothingUp: 0.14, smoothingDown: 0.06, phaseOffset: 8.0,  lineWidth: 0.7, glowWidth: 5.0,  glowOpacity: 0.22, historyOffset: 16),
    WaveConfig(frequency: 3.5,  speed: 3.2,  amplitudeScale: 0.40, smoothingUp: 0.14, smoothingDown: 0.05, phaseOffset: 8.6,  lineWidth: 0.6, glowWidth: 3.0,  glowOpacity: 0.14, historyOffset: 17),
    // Deep background
    WaveConfig(frequency: 0.6,  speed: 16.0, amplitudeScale: 0.36, smoothingUp: 0.12, smoothingDown: 0.05, phaseOffset: 9.2,  lineWidth: 0.5, glowWidth: 3.0,  glowOpacity: 0.12, historyOffset: 18),
    WaveConfig(frequency: 2.6,  speed: 5.2,  amplitudeScale: 0.32, smoothingUp: 0.12, smoothingDown: 0.05, phaseOffset: 9.8,  lineWidth: 0.5, glowWidth: 2.5,  glowOpacity: 0.10, historyOffset: 20),
    WaveConfig(frequency: 1.7,  speed: 8.5,  amplitudeScale: 0.28, smoothingUp: 0.10, smoothingDown: 0.04, phaseOffset: 10.4, lineWidth: 0.4, glowWidth: 2.5,  glowOpacity: 0.10, historyOffset: 22),
]

// MARK: - WaveformView

struct WaveformView: View {

    /// Closure providing current audio levels (0.0-1.0) — called each frame
    let levelProvider: () -> [Float]

    /// When false, waves animate at minimal idle amplitude
    let isActive: Bool

    // MARK: Constants

    private let idleAmplitude: CGFloat = 0.01

    // MARK: State

    @State private var smoothedLevels: [CGFloat] = Array(repeating: 0.01, count: 18)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawWaves(context: context, size: size, time: time)
            }
            .onChange(of: time) {
                updateSmoothedLevels()
            }
        }
    }

    // MARK: - Level Smoothing

    private func updateSmoothedLevels() {
        let time = Date.timeIntervalSinceReferenceDate
        let currentLevels = levelProvider()
        let activeConfigs = fullWaveConfigs

        for i in activeConfigs.indices {
            let config = activeConfigs[i]

            // Read from level buffer with per-wave history offset
            let rawLevel: CGFloat
            if isActive, !currentLevels.isEmpty {
                let offset = config.historyOffset
                let endIndex = max(0, currentLevels.count - offset)
                if endIndex > 0 {
                    let count = min(endIndex, 4)
                    let startIndex = endIndex - count
                    let slice = currentLevels[startIndex..<endIndex]
                    let peak = CGFloat(slice.max() ?? 0)
                    let avg = CGFloat(slice.reduce(Float(0), +) / Float(count))
                    // Emphasize peaks for more dynamic response
                    rawLevel = max(peak * 0.8 + avg * 0.2, idleAmplitude)
                } else {
                    rawLevel = idleAmplitude
                }
            } else {
                rawLevel = idleAmplitude
            }

            // Organic micro-movement: subtle amplitude modulation
            let wobble = 0.88 + 0.24 * sin(time * 4.3 + Double(i) * 1.7)
            let finalTarget = rawLevel * config.amplitudeScale * wobble

            let delta = finalTarget - smoothedLevels[i]
            let rate = delta > 0 ? config.smoothingUp : config.smoothingDown
            smoothedLevels[i] += delta * rate
        }
    }

    // MARK: - Wave Drawing

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let midX = size.width / 2
        let midY = size.height / 2
        // Proportional padding — works at any canvas size (4px min, 15% of half-height max)
        let padding = min(max(4, midY * 0.15), 16)
        let maxAmplitude = midY - padding

        guard maxAmplitude > 1 else { return }

        let gradient = Gradient(stops: gradientStops)
        let activeConfigs = fullWaveConfigs
        let step: CGFloat = 1.0

        // Draw back-to-front for proper layering
        for i in stride(from: activeConfigs.count - 1, through: 0, by: -1) {
            let config = activeConfigs[i]
            let wavePhase = -(time * config.speed) + config.phaseOffset
            let level = i < smoothedLevels.count ? smoothedLevels[i] : idleAmplitude

            let path = Path { path in
                var first = true
                var x: CGFloat = 0
                while x <= size.width {
                    let normalized = (x - midX) / midX
                    // Parabolic envelope: natural Siri-style diamond silhouette
                    let envelope = -(normalized * normalized) + 1.0

                    let y = envelope * maxAmplitude * level
                        * sin(2 * .pi * (x / size.width) * config.frequency + wavePhase)
                        + midY

                    if first {
                        path.move(to: CGPoint(x: x, y: y))
                        first = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    x += step
                }
            }

            let isPrimary = i == 0
            let opacity = isPrimary ? 0.9 : min(0.8, 0.3 + (1.0 - CGFloat(i) / CGFloat(activeConfigs.count)) * 0.5)

            // Glow pass — bloom effect
            var glowCtx = context
            glowCtx.blendMode = .plusLighter
            glowCtx.opacity = config.glowOpacity
            glowCtx.addFilter(.blur(radius: config.glowWidth * 0.4))
            glowCtx.stroke(
                path,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: config.glowWidth, lineCap: .round, lineJoin: .round)
            )

            // Main crisp stroke
            var ctx = context
            ctx.blendMode = .plusLighter
            ctx.opacity = opacity
            ctx.stroke(
                path,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: config.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Preview

#Preview("Active — Large") {
    WaveformView(
        levelProvider: { (0..<60).map { _ in Float.random(in: 0.05...0.9) } },
        isActive: true
    )
    .frame(height: 160)
    .padding()
    .background(Color.surfaceSecondary)
}

#Preview("Active — Widget") {
    WaveformView(
        levelProvider: { (0..<60).map { _ in Float.random(in: 0.1...0.8) } },
        isActive: true
    )
    .frame(width: 120, height: 32)
    .padding()
    .background(Color.backgroundDark)
}

#Preview("Idle") {
    WaveformView(
        levelProvider: { [] },
        isActive: false
    )
    .frame(height: 160)
    .padding()
    .background(Color.surfaceSecondary)
}
