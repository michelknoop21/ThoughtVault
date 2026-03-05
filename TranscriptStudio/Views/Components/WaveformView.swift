// WaveformView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Flowing organic multi-layered wave visualization with neon glow,
// deep blue/cyan/purple/magenta palette. Reacts to audio levels.

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {

    /// Audio level values in range 0.0–1.0.
    let levels: [Float]

    /// When false, waves animate at minimal amplitude.
    let isActive: Bool

    // MARK: - Computed

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

        // --- Layer 1: Deep background glow (very wide, heavy blur) ---
        let glowLayers: [(freq: Double, amp: Double, phase: Double, speed: Double, color: Color, lineWidth: CGFloat, blur: CGFloat)] = [
            (freq: 0.6, amp: 0.35, phase: 0.0,  speed: 0.3, color: Color(red: 0.05, green: 0.10, blue: 0.60).opacity(0.18), lineWidth: 18, blur: 28),
            (freq: 0.8, amp: 0.30, phase: 1.5,  speed: 0.4, color: Color(red: 0.15, green: 0.05, blue: 0.55).opacity(0.15), lineWidth: 14, blur: 22),
            (freq: 1.0, amp: 0.28, phase: 0.8,  speed: 0.35, color: Color(red: 0.0, green: 0.45, blue: 0.85).opacity(0.12), lineWidth: 12, blur: 20),
        ]

        // --- Layer 2: Mid glow (moderate blur, richer colors) ---
        let midLayers: [(freq: Double, amp: Double, phase: Double, speed: Double, color: Color, lineWidth: CGFloat, blur: CGFloat)] = [
            (freq: 1.2, amp: 0.32, phase: 0.0,  speed: 0.55, color: Color(red: 0.0, green: 0.60, blue: 1.0).opacity(0.18), lineWidth: 7, blur: 10),
            (freq: 1.5, amp: 0.25, phase: 1.2,  speed: 0.7,  color: Color(red: 0.40, green: 0.15, blue: 0.90).opacity(0.14), lineWidth: 6, blur: 8),
            (freq: 0.9, amp: 0.30, phase: 2.5,  speed: 0.45, color: Color(red: 0.0, green: 0.76, blue: 1.0).opacity(0.16), lineWidth: 5, blur: 7),
            (freq: 1.8, amp: 0.20, phase: 0.3,  speed: 0.8,  color: Color(red: 0.70, green: 0.0, blue: 0.60).opacity(0.10), lineWidth: 5, blur: 6),
        ]

        // --- Layer 3: Sharp foreground waves (no blur, vivid) ---
        let sharpLayers: [(freq: Double, amp: Double, phase: Double, speed: Double, color: Color, lineWidth: CGFloat, blur: CGFloat)] = [
            (freq: 1.0, amp: 0.34, phase: 0.0,  speed: 0.5,  color: Color(red: 0.0, green: 0.70, blue: 1.0).opacity(0.70), lineWidth: 2.2, blur: 0),
            (freq: 1.3, amp: 0.28, phase: 0.8,  speed: 0.65, color: Color(red: 0.20, green: 0.40, blue: 1.0).opacity(0.60), lineWidth: 2.0, blur: 0),
            (freq: 1.6, amp: 0.22, phase: 1.5,  speed: 0.80, color: Color(red: 0.45, green: 0.25, blue: 0.95).opacity(0.55), lineWidth: 1.8, blur: 0),
            (freq: 2.0, amp: 0.16, phase: 2.2,  speed: 1.0,  color: Color(red: 0.55, green: 0.15, blue: 0.85).opacity(0.50), lineWidth: 1.5, blur: 0),
            (freq: 1.1, amp: 0.30, phase: 3.0,  speed: 0.55, color: Color(red: 0.0, green: 0.55, blue: 0.95).opacity(0.55), lineWidth: 1.8, blur: 0),
            (freq: 1.7, amp: 0.18, phase: 4.0,  speed: 0.90, color: Color(red: 0.80, green: 0.0, blue: 0.50).opacity(0.35), lineWidth: 1.5, blur: 0),
        ]

        // --- Layer 4: Bright accent highlights (thin, high-frequency shimmer) ---
        let accentLayers: [(freq: Double, amp: Double, phase: Double, speed: Double, color: Color, lineWidth: CGFloat, blur: CGFloat)] = [
            (freq: 2.4, amp: 0.12, phase: 0.5,  speed: 1.3,  color: Color(red: 0.0, green: 0.90, blue: 1.0).opacity(0.45), lineWidth: 1.2, blur: 0),
            (freq: 2.8, amp: 0.10, phase: 1.8,  speed: 1.5,  color: Color(red: 0.70, green: 0.30, blue: 1.0).opacity(0.35), lineWidth: 1.0, blur: 0),
            (freq: 3.2, amp: 0.08, phase: 3.2,  speed: 1.7,  color: Color(red: 0.90, green: 0.0, blue: 0.45).opacity(0.30), lineWidth: 0.8, blur: 0),
        ]

        let allLayers = glowLayers + midLayers + sharpLayers + accentLayers

        for wave in allLayers {
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

                // Envelope: smooth taper at edges with steeper falloff
                let envelope = sin(progress * .pi)
                let envShaped = pow(envelope, 0.65)

                // Triple-harmonic composite for complex organic motion
                let phase1 = progress * frequency * 2.0 * .pi + time * speed + phaseOffset
                let phase2 = progress * frequency * 1.3 * .pi + time * speed * 0.7 + phaseOffset * 1.5
                let phase3 = progress * frequency * 3.1 * .pi + time * speed * 1.3 + phaseOffset * 0.8
                let wave = sin(phase1) * 0.55 + sin(phase2) * 0.30 + sin(phase3) * 0.15

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
