// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Flowing organic sine wave visualization with multiple layered curves
// in blue/purple/pink with soft glow. Reacts to audio levels.

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {

    /// Audio level values in range 0.0–1.0.
    let levels: [Float]

    /// When false, waves animate at minimal amplitude.
    let isActive: Bool

    // MARK: - Computed

    /// Average audio level for wave amplitude
    private var averageLevel: CGFloat {
        guard isActive, !levels.isEmpty else { return 0.05 }
        let avg = levels.reduce(Float(0), +) / Float(levels.count)
        return CGFloat(max(0.05, min(1.0, avg)))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawWaves(context: context, size: size, time: time)
            }
        }
    }

    // MARK: - Wave Drawing

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let level = averageLevel

        // Wave configurations: (frequency, amplitude multiplier, phase offset, speed, color)
        let waves: [(freq: Double, amp: Double, phase: Double, speed: Double, color: Color, lineWidth: CGFloat, blur: CGFloat)] = [
            // Background glow layer (wide, blurred)
            (freq: 1.2, amp: 0.28, phase: 0.0,  speed: 0.6, color: Color.neonBlue.opacity(0.12), lineWidth: 8, blur: 12),
            (freq: 1.5, amp: 0.22, phase: 1.2,  speed: 0.8, color: Color.brandPrimary.opacity(0.08), lineWidth: 6, blur: 10),

            // Mid layers (subtle fill)
            (freq: 1.0, amp: 0.32, phase: 0.5,  speed: 0.5, color: Color.neonBlue.opacity(0.15), lineWidth: 3, blur: 4),
            (freq: 1.8, amp: 0.18, phase: 2.0,  speed: 0.9, color: Color(red: 0.45, green: 0.35, blue: 0.95).opacity(0.12), lineWidth: 2.5, blur: 3),

            // Sharp foreground waves
            (freq: 1.3, amp: 0.30, phase: 0.0,  speed: 0.7, color: Color.neonBlue.opacity(0.65), lineWidth: 2.0, blur: 0),
            (freq: 1.6, amp: 0.22, phase: 1.0,  speed: 0.85, color: Color(red: 0.35, green: 0.45, blue: 0.90).opacity(0.55), lineWidth: 1.8, blur: 0),
            (freq: 2.0, amp: 0.15, phase: 2.5,  speed: 1.1, color: Color(red: 0.55, green: 0.30, blue: 0.85).opacity(0.45), lineWidth: 1.5, blur: 0),
            (freq: 1.1, amp: 0.25, phase: 3.5,  speed: 0.55, color: Color.brandPrimary.opacity(0.30), lineWidth: 1.5, blur: 0),
        ]

        for wave in waves {
            var ctx = context

            if wave.blur > 0 {
                ctx.addFilter(.blur(radius: wave.blur))
            }

            let path = wavePath(
                size: size,
                frequency: wave.freq,
                amplitudeMultiplier: wave.amp * Double(level),
                phaseOffset: wave.phase,
                speed: wave.speed,
                time: time
            )

            ctx.stroke(
                path,
                with: .color(wave.color),
                style: StrokeStyle(lineWidth: wave.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func wavePath(
        size: CGSize,
        frequency: Double,
        amplitudeMultiplier: Double,
        phaseOffset: Double,
        speed: Double,
        time: Double
    ) -> Path {
        let midY = size.height / 2
        let amplitude = size.height * amplitudeMultiplier
        let steps = Int(size.width)

        return Path { path in
            for x in 0...steps {
                let progress = Double(x) / Double(steps)
                // Envelope: taper at edges for organic shape
                let envelope = sin(progress * .pi)
                let envShaped = pow(envelope, 0.8)

                // Composite sine for organic movement
                let phase1 = progress * frequency * 2.0 * .pi + time * speed + phaseOffset
                let phase2 = progress * frequency * 1.3 * .pi + time * speed * 0.7 + phaseOffset * 1.5
                let wave = sin(phase1) * 0.7 + sin(phase2) * 0.3

                let y = midY + wave * amplitude * envShaped

                if x == 0 {
                    path.move(to: CGPoint(x: CGFloat(x), y: y))
                } else {
                    path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                }
            }
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
