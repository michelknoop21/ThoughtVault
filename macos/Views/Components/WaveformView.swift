// WaveformView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// SiriWave-style neon soundwave rendered by a Metal fragment shader
// (WaveformShader.metal): seven braided strands plus a core line, scrolling the
// full envelope history from right (new) to left (old) over 3 seconds. The
// history comes from AudioEnvelopeProcessor (30 Hz); the view interpolates the
// last two samples at display refresh rate for the live level and integrates
// the phase clock, because a shader is stateless.
//
// The shader returns its own alpha, so the background stays transparent and the
// waveform drops into whatever surface hosts it.

import SwiftUI

/// Phase accumulator for the shader. A reference type in `@State` so ticking it
/// from inside the `TimelineView` body does not invalidate the view — the
/// timeline already re-renders every frame.
private final class WavePhaseClock {
    var phase: Double = 0
    var lastTick: Date?

    /// Integrates `phaseTime += dt * (2.2 + live * 5.5)`: calm when silent,
    /// energetic during loud speech. `dt` is capped at 64 ms so a paused or
    /// backgrounded timeline never causes a jump on resume.
    func advance(to date: Date, live: Float) -> Double {
        let dt = lastTick.map { min(0.064, max(0, date.timeIntervalSince($0))) } ?? 0
        lastTick = date
        phase += dt * (2.2 + Double(live) * 5.5)
        if phase > 1_000_000 { phase -= 1_000_000 }
        return phase
    }
}

struct WaveformView: View {
    /// Provider of the processed level history (0..1, newest last).
    let levelsProvider: () -> [Float]
    let isActive: Bool
    /// Caps the shader framerate. nil = display refresh rate. Decorative
    /// (idle) waves should cap this: 120fps on ProMotion drains the battery.
    var maxFPS: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var clock = WavePhaseClock()

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
            // Seven strands become a blur on small surfaces (the 120x32 widget,
            // the mini variants) — draw only the two outer mirror pairs there.
            // Must stay even: the strand table is ordered in pairs and an odd
            // count leaves one carrier without its phase-offset twin, which
            // reads as a lopsided braid.
            let strandCount: Float = size.height >= 64 ? 7 : 4
            // Freeze the shader when the app is not frontmost; per-pixel glow
            // at display refresh rate is the app's biggest energy consumer.
            TimelineView(.animation(
                minimumInterval: maxFPS.map { 1.0 / $0 },
                // Also freeze when inactive: the wave is a flat line at level 0,
                // so animating it only burns GPU.
                paused: scenePhase != .active || !isActive
            )) { timeline in
                let levels = currentLevels()
                let level = currentLevel(levels, at: timeline.date.timeIntervalSinceReferenceDate)
                let phase = clock.advance(to: timeline.date, live: level)
                // Opaque fill purely so the rounded rect rasterizes; the shader
                // replaces every channel including alpha.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                    .colorEffect(
                        ShaderLibrary.neonWaveform(
                            .float2(Float(size.width), Float(size.height)),
                            .float(Float(phase)),
                            .floatArray(levels),
                            .float(level),
                            .float(strandCount)
                        )
                    )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Level

    /// Full envelope history for the shader, padded to a fixed length so the
    /// wave scrolls in from the right while the buffer is still filling.
    private func currentLevels() -> [Float] {
        let target = AudioEnvelopeConfig.historyLength
        guard isActive else { return Array(repeating: Self.idleLevel, count: target) }
        let levels = levelsProvider()
        if levels.count >= target { return Array(levels.suffix(target)) }
        return Array(repeating: Self.idleLevel, count: target - levels.count) + levels
    }

    /// Display-refresh interpolation between the last two 30 Hz envelope
    /// samples; the envelope processor already applies attack/release.
    private func currentLevel(_ levels: [Float], at time: TimeInterval) -> Float {
        guard isActive, let last = levels.last else { return Self.idleLevel }
        let previous = levels.count >= 2 ? levels[levels.count - 2] : last
        let slot = 1.0 / AudioEnvelopeConfig.publishRateHz
        let progress = Float((time.truncatingRemainder(dividingBy: slot)) / slot)
        return previous * (1 - progress) + last * progress
    }
}
