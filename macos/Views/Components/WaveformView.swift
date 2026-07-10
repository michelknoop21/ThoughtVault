// WaveformView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Neon soundwave rendered by a Metal fragment shader (WaveformShader.metal),
// a 1:1 port of the WebGL reference: 9 mirrored layers, per-pixel additive
// glow, blue->cyan->purple->pink palette on near-black. The shader's wave
// amplitude is scaled by the real mic envelope (AudioEnvelopeProcessor, 30 Hz);
// the view interpolates between the last two samples at display refresh rate so
// motion stays continuous.

import SwiftUI

private let surfaceColor = Color(red: 0.01, green: 0.005, blue: 0.02) // near-black

struct WaveformView: View {
    /// Provider of the processed level history (0..1, newest last).
    let levelsProvider: () -> [Float]
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let idleLevel: Float = 0.0

    var body: some View {
        if reduceMotion {
            staticWaveform
        } else {
            animatedWaveform
        }
    }

    // MARK: Static (Reduce Motion)

    private var staticWaveform: some View {
        Canvas { context, size in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size),
                            cornerRadius: 12, style: .continuous)
            context.fill(rect, with: .color(surfaceColor))
            let midY = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: midY))
            line.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(line, with: .color(Color(red: 0.5, green: 0.3, blue: 0.8).opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }

    // MARK: Animated (Metal shader)

    private var animatedWaveform: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let level = currentLevel(at: time)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surfaceColor)
                    .colorEffect(
                        ShaderLibrary.neonWaveform(
                            .float2(Float(size.width), Float(size.height)),
                            .float(Float(time.truncatingRemainder(dividingBy: 3600))),
                            .float(level)
                        )
                    )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Level

    /// Display-refresh interpolation between the last two 30 Hz envelope
    /// samples; the envelope processor already applies attack/release.
    private func currentLevel(at time: TimeInterval) -> Float {
        guard isActive else { return Self.idleLevel }
        let levels = levelsProvider()
        guard let last = levels.last else { return Self.idleLevel }
        let previous = levels.count >= 2 ? levels[levels.count - 2] : last
        let slot = 1.0 / AudioEnvelopeConfig.publishRateHz
        let progress = Float((time.truncatingRemainder(dividingBy: slot)) / slot)
        return previous * (1 - progress) + last * progress
    }
}
