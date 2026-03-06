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
    let color: Color
    let isPrimary: Bool
}

// MARK: - WaveformView

struct WaveformView: View {

    /// Audio level values in range 0.0-1.0 (newest last).
    let levels: [Float]

    /// When false, waves animate at minimal amplitude.
    let isActive: Bool

    // MARK: Constants

    private let idleAmplitude: CGFloat = 0.01

    private let waveConfigs: [WaveConfig] = [
        WaveConfig(frequency: 1.5,  speed: 9.0,  amplitudeScale: 1.0,  smoothingUp: 0.35, smoothingDown: 0.08, phaseOffset: 0.0,  lineWidth: 2.5, color: Color.brandPrimary,                                isPrimary: true),
        WaveConfig(frequency: 1.8,  speed: 7.2,  amplitudeScale: 0.82, smoothingUp: 0.25, smoothingDown: 0.10, phaseOffset: 1.2,  lineWidth: 1.0, color: Color(red: 0.80, green: 0.0, blue: 0.60),          isPrimary: false),
        WaveConfig(frequency: 1.2,  speed: 11.5, amplitudeScale: 0.70, smoothingUp: 0.18, smoothingDown: 0.06, phaseOffset: 2.8,  lineWidth: 1.0, color: Color(red: 0.60, green: 0.0, blue: 0.80),          isPrimary: false),
        WaveConfig(frequency: 2.1,  speed: 5.8,  amplitudeScale: 0.55, smoothingUp: 0.40, smoothingDown: 0.12, phaseOffset: 4.1,  lineWidth: 1.0, color: Color.neonBlue,                                    isPrimary: false),
        WaveConfig(frequency: 0.9,  speed: 13.0, amplitudeScale: 0.40, smoothingUp: 0.15, smoothingDown: 0.05, phaseOffset: 5.5,  lineWidth: 1.0, color: Color(red: 0.40, green: 0.20, blue: 1.0),          isPrimary: false),
    ]

    // MARK: State — one smoothed level per wave

    @State private var smoothedLevels: [CGFloat] = [0.01, 0.01, 0.01, 0.01, 0.01]

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
        let rawLevel: CGFloat
        if isActive, !levels.isEmpty {
            // Use fewer recent samples for snappier response
            let count = min(levels.count, 4)
            let recent = levels.suffix(count)
            // Weighted toward the most recent sample
            let peak = CGFloat(recent.max() ?? 0)
            let avg = CGFloat(recent.reduce(Float(0), +) / Float(count))
            rawLevel = max(peak * 0.7 + avg * 0.3, idleAmplitude)
        } else {
            rawLevel = idleAmplitude
        }

        for i in waveConfigs.indices {
            let target = rawLevel * waveConfigs[i].amplitudeScale
            let delta = target - smoothedLevels[i]
            let rate = delta > 0 ? waveConfigs[i].smoothingUp : waveConfigs[i].smoothingDown
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
                    // Parabolic envelope: tapers to zero at edges
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
