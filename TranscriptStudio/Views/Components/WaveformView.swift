// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Siri-style waveform based on the SCSiriWaveformView algorithm by Stefan Ceriu.
// Five overlapping sine waves with parabolic envelope and continuous phase travel.

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {

    /// Audio level values in range 0.0-1.0 (newest last).
    let levels: [Float]

    /// When false, waves animate at minimal amplitude.
    let isActive: Bool

    // MARK: Constants

    private let numberOfWaves = 5
    private let frequency: CGFloat = 1.5
    private let idleAmplitude: CGFloat = 0.01
    private let primaryLineWidth: CGFloat = 2.5
    private let secondaryLineWidth: CGFloat = 1.0

    // MARK: State

    @State private var smoothedLevel: CGFloat = 0.01

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // Phase travels left at ~9 rad/sec (0.15 * 60fps)
            let phase = -time * 9.0

            Canvas { context, size in
                drawWaves(context: context, size: size, phase: phase)
            }
            .onChange(of: time) {
                updateSmoothedLevel()
            }
        }
    }

    // MARK: - Level Smoothing

    private func updateSmoothedLevel() {
        let targetLevel: CGFloat
        if isActive, !levels.isEmpty {
            let count = min(levels.count, 10)
            let avg = levels.suffix(count).reduce(Float(0), +) / Float(count)
            targetLevel = max(CGFloat(avg), idleAmplitude)
        } else {
            targetLevel = idleAmplitude
        }
        smoothedLevel += (targetLevel - smoothedLevel) * 0.12
    }

    // MARK: - Wave Drawing

    private func drawWaves(context: GraphicsContext, size: CGSize, phase: Double) {
        let midX = size.width / 2
        let midY = size.height / 2
        let maxAmplitude = midY - 4

        for i in 0..<numberOfWaves {
            let progress = 1.0 - CGFloat(i) / CGFloat(numberOfWaves)
            let normedAmplitude = (1.5 * progress - 0.4) * smoothedLevel

            let path = Path { path in
                for x in stride(from: 0, through: size.width, by: 1.0) {
                    let normalized = (x - midX) / midX
                    let scaling = -(normalized * normalized) + 1.0

                    let y = scaling * maxAmplitude * normedAmplitude
                        * sin(2 * .pi * (x / size.width) * frequency + phase)
                        + midY

                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            let isPrimary = (i == 0)
            let lineWidth = isPrimary ? primaryLineWidth : secondaryLineWidth
            let alpha = min(1.0, (CGFloat(i) / CGFloat(numberOfWaves)) / 3.0 + 1.0 / 3.0)
            let multiplier = isPrimary ? 1.0 : alpha

            let waveColor: Color
            switch i {
            case 0:
                waveColor = Color.brandPrimary.opacity(multiplier)
            case 1:
                waveColor = Color(red: 0.80, green: 0.0, blue: 0.60).opacity(multiplier)
            case 2:
                waveColor = Color(red: 0.60, green: 0.0, blue: 0.80).opacity(multiplier)
            case 3:
                waveColor = Color.neonBlue.opacity(multiplier * 0.7)
            default:
                waveColor = Color(red: 0.40, green: 0.20, blue: 1.0).opacity(multiplier * 0.5)
            }

            var ctx = context
            if !isPrimary {
                ctx.blendMode = .plusLighter
            }
            ctx.stroke(
                path,
                with: .color(waveColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
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
