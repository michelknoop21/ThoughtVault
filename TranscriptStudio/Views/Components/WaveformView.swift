// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Siri-style waveform based on the SCSiriWaveformView algorithm by Stefan Ceriu.
// Five overlapping sine waves with independent phase, frequency and amplitude response.

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
    let color: Color
    let isPrimary: Bool
    let historyOffset: Int     // how many samples back this wave reads from
}

// MARK: - WaveformView

struct WaveformView: View {

    /// Audio level values in range 0.0-1.0 (newest last).
    let levels: [Float]

    /// When false, waves animate at minimal amplitude.
    let isActive: Bool

    // MARK: Constants

    private let idleAmplitude: CGFloat = 0.03

    private let waveConfigs: [WaveConfig] = [
        WaveConfig(frequency: 1.5,  speed: 9.0,  amplitudeScale: 1.0,  smoothingUp: 0.70, smoothingDown: 0.20, phaseOffset: 0.0,  lineWidth: 3.0, glowWidth: 8.0,  glowOpacity: 0.20, color: Color.brandPrimary,                          isPrimary: true,  historyOffset: 0),
        WaveConfig(frequency: 1.8,  speed: 7.2,  amplitudeScale: 0.82, smoothingUp: 0.60, smoothingDown: 0.18, phaseOffset: 1.2,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.18, color: Color(red: 0.3, green: 0.4, blue: 1.0),     isPrimary: false, historyOffset: 5),
        WaveConfig(frequency: 1.2,  speed: 11.5, amplitudeScale: 0.70, smoothingUp: 0.55, smoothingDown: 0.16, phaseOffset: 2.8,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.16, color: Color(red: 0.5, green: 0.2, blue: 1.0),     isPrimary: false, historyOffset: 10),
        WaveConfig(frequency: 2.1,  speed: 5.8,  amplitudeScale: 0.55, smoothingUp: 0.50, smoothingDown: 0.15, phaseOffset: 4.1,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.15, color: Color.neonBlue,                              isPrimary: false, historyOffset: 15),
        WaveConfig(frequency: 0.9,  speed: 13.0, amplitudeScale: 0.40, smoothingUp: 0.45, smoothingDown: 0.15, phaseOffset: 5.5,  lineWidth: 1.5, glowWidth: 5.0,  glowOpacity: 0.15, color: Color(red: 0.2, green: 0.5, blue: 1.0),     isPrimary: false, historyOffset: 20),
    ]

    // MARK: State — one smoothed level per wave + per-wave jitter seed

    @State private var smoothedLevels: [CGFloat] = [0.03, 0.03, 0.03, 0.03, 0.03]
    @State private var jitterSeeds: [CGFloat] = (0..<5).map { _ in CGFloat.random(in: 0...1000) }

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

        for i in waveConfigs.indices {
            let config = waveConfigs[i]

            let rawLevel: CGFloat
            if isActive, !levels.isEmpty {
                // Each wave reads from a different time offset in the levels array
                let offset = config.historyOffset
                let endIndex = max(0, levels.count - offset)
                if endIndex > 0 {
                    let count = min(endIndex, 3)
                    let startIndex = endIndex - count
                    let slice = levels[startIndex..<endIndex]
                    let peak = CGFloat(slice.max() ?? 0)
                    let avg = CGFloat(slice.reduce(Float(0), +) / Float(count))
                    let base = max(peak * 0.7 + avg * 0.3, idleAmplitude)
                    // Compress dynamic range so quiet sounds are more visible
                    rawLevel = pow(base, 0.6)
                } else {
                    rawLevel = idleAmplitude
                }
            } else {
                rawLevel = idleAmplitude
            }

            // Per-wave amplitude jitter for natural variation
            let jitter = 0.85 + 0.30 * (0.5 + 0.5 * sin(time * 3.7 + jitterSeeds[i]))
            let target = rawLevel * config.amplitudeScale * jitter

            // Idle sine breathing so waves move independently even in silence
            let idleBreathing = idleAmplitude * (0.5 + 0.5 * sin(time * (1.2 + Double(i) * 0.3) + jitterSeeds[i]))
            let finalTarget = max(target, idleBreathing)

            let delta = finalTarget - smoothedLevels[i]
            let rate = delta > 0 ? config.smoothingUp : config.smoothingDown
            smoothedLevels[i] += delta * rate
        }
    }

    // MARK: - Wave Drawing

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let midX = size.width / 2
        let midY = size.height / 2
        let maxAmplitude = midY - 4

        for (i, config) in waveConfigs.enumerated() {
            let wavePhase = -(time * config.speed) + config.phaseOffset
            let level = smoothedLevels[i]

            let path = Path { path in
                for x in stride(from: 0, through: size.width, by: 1.0) {
                    let normalized = (x - midX) / midX
                    let envelope = -(normalized * normalized) + 1.0

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

            let opacity = config.isPrimary ? 1.0 : min(1.0, (CGFloat(i) / CGFloat(waveConfigs.count)) / 3.0 + 1.0 / 3.0)

            // Glow pass — wider, translucent stroke behind the main line
            var glowCtx = context
            if !config.isPrimary {
                glowCtx.blendMode = .plusLighter
            }
            glowCtx.stroke(
                path,
                with: .color(config.color.opacity(config.glowOpacity)),
                style: StrokeStyle(lineWidth: config.glowWidth, lineCap: .round, lineJoin: .round)
            )

            // Main stroke
            var ctx = context
            if !config.isPrimary {
                ctx.blendMode = .plusLighter
            }
            ctx.stroke(
                path,
                with: .color(config.color.opacity(opacity)),
                style: StrokeStyle(lineWidth: config.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Preview

#Preview("Active") {
    WaveformView(
        levels: (0..<60).map { _ in Float.random(in: 0.05...0.9) },
        isActive: true
    )
    .frame(height: 160)
    .padding()
    .background(Color.surfaceSecondary)
}

#Preview("Idle") {
    WaveformView(
        levels: [],
        isActive: false
    )
    .frame(height: 160)
    .padding()
    .background(Color.surfaceSecondary)
}
