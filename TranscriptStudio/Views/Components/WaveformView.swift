// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Audio waveform visualization with layered neon sine waves.
// 18 thin waves with X-axis color gradient (blue → violet → magenta → cyan)
// and soft bloom glow create a woven neon fabric effect.

import SwiftUI

// MARK: - Wave Configuration

private struct WaveConfig {
    let frequency: CGFloat
    let speed: CGFloat         // radians per second — each wave travels independently
    let amplitudeScale: CGFloat
    let smoothingUp: CGFloat   // attack speed (0-1, higher = faster response)
    let smoothingDown: CGFloat // release speed
    let phaseOffset: CGFloat   // initial phase offset
    let lineWidth: CGFloat
    let glowWidth: CGFloat     // wider stroke drawn behind for neon glow
    let glowOpacity: CGFloat
    let historyOffset: Int     // how many samples back this wave reads from
}

// MARK: - Gradient color stops (blue → violet → magenta → cyan)

private let gradientStops: [Gradient.Stop] = [
    .init(color: Color(red: 0.08, green: 0.24, blue: 0.70), location: 0.00),  // deep blue
    .init(color: Color(red: 0.16, green: 0.39, blue: 0.94), location: 0.15),  // blue
    .init(color: Color(red: 0.31, green: 0.24, blue: 1.00), location: 0.30),  // blue-violet
    .init(color: Color(red: 0.51, green: 0.12, blue: 0.94), location: 0.45),  // violet
    .init(color: Color(red: 0.63, green: 0.08, blue: 0.78), location: 0.55),  // purple-magenta
    .init(color: Color(red: 0.75, green: 0.12, blue: 0.70), location: 0.70),  // magenta
    .init(color: Color(red: 0.55, green: 0.24, blue: 0.86), location: 0.85),  // magenta-violet
    .init(color: Color(red: 0.16, green: 0.63, blue: 1.00), location: 0.95),  // cyan highlight
    .init(color: Color(red: 0.08, green: 0.47, blue: 0.86), location: 1.00),  // teal
]

// MARK: - WaveformView

struct WaveformView: View {

    /// Closure that provides current audio levels (0.0-1.0) — called each frame
    /// so the waveform always reflects the latest metering data without relying
    /// on SwiftUI observation to re-create the view.
    let levelProvider: () -> [Float]

    /// When false, waves animate at minimal amplitude.
    let isActive: Bool

    // MARK: Constants

    private let idleAmplitude: CGFloat = 0.01

    // 18 waves — thin threads that weave together into a neon fabric
    private let waveConfigs: [WaveConfig] = [
        // Primary — brightest, slightly thicker
        WaveConfig(frequency: 1.5,  speed: 8.5,  amplitudeScale: 1.0,  smoothingUp: 0.70, smoothingDown: 0.20, phaseOffset: 0.0,  lineWidth: 1.5, glowWidth: 8.0,  glowOpacity: 0.30, historyOffset: 0),
        // Blue core threads
        WaveConfig(frequency: 1.8,  speed: 7.0,  amplitudeScale: 0.92, smoothingUp: 0.65, smoothingDown: 0.18, phaseOffset: 0.7,  lineWidth: 1.0, glowWidth: 6.0,  glowOpacity: 0.25, historyOffset: 2),
        WaveConfig(frequency: 1.2,  speed: 10.5, amplitudeScale: 0.88, smoothingUp: 0.62, smoothingDown: 0.17, phaseOffset: 1.5,  lineWidth: 0.8, glowWidth: 5.0,  glowOpacity: 0.22, historyOffset: 3),
        WaveConfig(frequency: 2.0,  speed: 6.8,  amplitudeScale: 0.85, smoothingUp: 0.60, smoothingDown: 0.17, phaseOffset: 2.1,  lineWidth: 0.8, glowWidth: 5.0,  glowOpacity: 0.22, historyOffset: 4),
        // Blue-violet transition
        WaveConfig(frequency: 2.4,  speed: 5.8,  amplitudeScale: 0.80, smoothingUp: 0.58, smoothingDown: 0.16, phaseOffset: 2.8,  lineWidth: 0.8, glowWidth: 5.0,  glowOpacity: 0.20, historyOffset: 5),
        WaveConfig(frequency: 0.9,  speed: 12.0, amplitudeScale: 0.78, smoothingUp: 0.56, smoothingDown: 0.16, phaseOffset: 3.3,  lineWidth: 1.0, glowWidth: 6.0,  glowOpacity: 0.22, historyOffset: 7),
        WaveConfig(frequency: 1.6,  speed: 9.2,  amplitudeScale: 0.74, smoothingUp: 0.54, smoothingDown: 0.15, phaseOffset: 3.9,  lineWidth: 0.6, glowWidth: 4.0,  glowOpacity: 0.18, historyOffset: 8),
        // Violet core
        WaveConfig(frequency: 2.8,  speed: 4.5,  amplitudeScale: 0.70, smoothingUp: 0.52, smoothingDown: 0.15, phaseOffset: 4.5,  lineWidth: 0.8, glowWidth: 5.0,  glowOpacity: 0.20, historyOffset: 9),
        WaveConfig(frequency: 1.1,  speed: 13.0, amplitudeScale: 0.66, smoothingUp: 0.50, smoothingDown: 0.14, phaseOffset: 5.1,  lineWidth: 0.6, glowWidth: 4.0,  glowOpacity: 0.18, historyOffset: 10),
        WaveConfig(frequency: 1.9,  speed: 7.5,  amplitudeScale: 0.62, smoothingUp: 0.48, smoothingDown: 0.14, phaseOffset: 5.7,  lineWidth: 0.8, glowWidth: 5.0,  glowOpacity: 0.18, historyOffset: 11),
        // Purple-magenta accents
        WaveConfig(frequency: 3.0,  speed: 3.8,  amplitudeScale: 0.58, smoothingUp: 0.46, smoothingDown: 0.14, phaseOffset: 6.2,  lineWidth: 0.6, glowWidth: 4.0,  glowOpacity: 0.16, historyOffset: 12),
        WaveConfig(frequency: 0.7,  speed: 14.5, amplitudeScale: 0.54, smoothingUp: 0.44, smoothingDown: 0.13, phaseOffset: 6.8,  lineWidth: 0.6, glowWidth: 4.0,  glowOpacity: 0.16, historyOffset: 14),
        WaveConfig(frequency: 2.2,  speed: 6.0,  amplitudeScale: 0.50, smoothingUp: 0.42, smoothingDown: 0.13, phaseOffset: 7.4,  lineWidth: 0.6, glowWidth: 3.0,  glowOpacity: 0.14, historyOffset: 15),
        // Cyan/electric highlights
        WaveConfig(frequency: 1.4,  speed: 11.0, amplitudeScale: 0.46, smoothingUp: 0.40, smoothingDown: 0.13, phaseOffset: 8.0,  lineWidth: 0.6, glowWidth: 5.0,  glowOpacity: 0.22, historyOffset: 16),
        WaveConfig(frequency: 3.5,  speed: 3.2,  amplitudeScale: 0.42, smoothingUp: 0.38, smoothingDown: 0.12, phaseOffset: 8.6,  lineWidth: 0.5, glowWidth: 3.0,  glowOpacity: 0.14, historyOffset: 17),
        // Deep background threads
        WaveConfig(frequency: 0.6,  speed: 15.5, amplitudeScale: 0.38, smoothingUp: 0.36, smoothingDown: 0.12, phaseOffset: 9.2,  lineWidth: 0.5, glowWidth: 3.0,  glowOpacity: 0.12, historyOffset: 18),
        WaveConfig(frequency: 2.6,  speed: 5.0,  amplitudeScale: 0.34, smoothingUp: 0.34, smoothingDown: 0.11, phaseOffset: 9.8,  lineWidth: 0.4, glowWidth: 2.5,  glowOpacity: 0.10, historyOffset: 20),
        WaveConfig(frequency: 1.7,  speed: 8.0,  amplitudeScale: 0.30, smoothingUp: 0.32, smoothingDown: 0.11, phaseOffset: 10.4, lineWidth: 0.4, glowWidth: 2.5,  glowOpacity: 0.10, historyOffset: 22),
    ]

    private var waveCount: Int { waveConfigs.count }

    // MARK: State — one smoothed level per wave + per-wave jitter seed

    @State private var smoothedLevels: [CGFloat] = Array(repeating: 0.0, count: 18)
    @State private var jitterSeeds: [CGFloat] = (0..<18).map { _ in CGFloat.random(in: 0...1000) }

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

    // MARK: - Level Smoothing (per wave)

    private func updateSmoothedLevels() {
        let time = Date.timeIntervalSinceReferenceDate
        let currentLevels = levelProvider()

        for i in waveConfigs.indices {
            let config = waveConfigs[i]

            let rawLevel: CGFloat
            if isActive, !currentLevels.isEmpty {
                let offset = config.historyOffset
                let endIndex = max(0, currentLevels.count - offset)
                if endIndex > 0 {
                    let count = min(endIndex, 3)
                    let startIndex = endIndex - count
                    let slice = currentLevels[startIndex..<endIndex]
                    let peak = CGFloat(slice.max() ?? 0)
                    let avg = CGFloat(slice.reduce(Float(0), +) / Float(count))
                    rawLevel = max(peak * 0.7 + avg * 0.3, idleAmplitude)
                } else {
                    rawLevel = idleAmplitude
                }
            } else {
                rawLevel = idleAmplitude
            }

            let jitter = 0.85 + 0.30 * (0.5 + 0.5 * sin(time * 3.7 + jitterSeeds[i]))
            let finalTarget = rawLevel * config.amplitudeScale * jitter

            let delta = finalTarget - smoothedLevels[i]
            let rate = delta > 0 ? config.smoothingUp : config.smoothingDown
            smoothedLevels[i] += delta * rate
        }
    }

    // MARK: - Wave Drawing

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let midX = size.width / 2
        let midY = size.height / 2
        let maxAmplitude = midY - 16

        // Horizontal gradient shading: blue → violet → magenta → cyan
        let gradient = Gradient(stops: gradientStops)

        for i in stride(from: waveConfigs.count - 1, through: 0, by: -1) {
            let config = waveConfigs[i]
            let wavePhase = -(time * config.speed) + config.phaseOffset
            let level = smoothedLevels[i]

            let path = Path { path in
                for x in stride(from: 0, through: size.width, by: 1.0) {
                    let normalized = (x - midX) / midX
                    let n2 = normalized * normalized
                    // Quartic envelope: flatter center, wider reach than parabolic
                    let envelope = -(n2 * n2) + 1.0

                    let y = envelope * maxAmplitude * level
                        * sin(2 * .pi * (x / size.width) * config.frequency + wavePhase)
                        + midY

                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            let isPrimary = i == 0
            let opacity = isPrimary ? 0.9 : min(0.8, 0.25 + (1.0 - CGFloat(i) / CGFloat(waveCount)) * 0.55)

            // Glow pass — wider stroke with blur for soft neon bloom
            var glowCtx = context
            glowCtx.blendMode = .plusLighter
            glowCtx.opacity = config.glowOpacity
            glowCtx.addFilter(.blur(radius: config.glowWidth * 0.4))
            glowCtx.stroke(
                path,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: config.glowWidth, lineCap: .round, lineJoin: .round)
            )

            // Main crisp stroke — gradient along X axis
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

#Preview("Active") {
    WaveformView(
        levelProvider: { (0..<60).map { _ in Float.random(in: 0.05...0.9) } },
        isActive: true
    )
    .frame(height: 160)
    .padding()
    .background(Color.surfaceSecondary)
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
