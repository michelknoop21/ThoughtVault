// WaveformView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Light-thread waveform (approved Opnemen NorthStar). A bundle of thin lines
// drawn on a Canvas: every line is a sum of three gaussian bellies whose centre
// and width drift slowly, each belly reading the envelope history at its own
// delay (0 / 70 / 140 ms) so syllables show up as shifting peaks instead of the
// whole bundle pumping. The main line is brighter and glows; the support lines
// are scaled, slightly phase-shifted copies (ribbon look). Colour runs magenta
// → violet → lavender → cool blue along x.
//
// The history comes from AudioEnvelopeProcessor (30 Hz, 3 s), which already
// applies attack/release. The Canvas only maps that stable level to geometry.

import SwiftUI

/// Drift/travel accumulator. A reference type in `@State` so ticking it from
/// inside the `TimelineView` body does not invalidate the view.
private final class WavePhaseClock {
    var drift: Double = 0
    var travel: Double = 0
    var lastTick: Date?

    /// `dt` is capped at 64 ms so a paused or backgrounded timeline never jumps.
    func advance(to date: Date, level: Float) {
        let dt = lastTick.map { min(0.064, max(0, date.timeIntervalSince($0))) } ?? 0
        lastTick = date
        drift += dt
        travel += dt * 2 * .pi * WaveConfig.travelHz * (1 + WaveConfig.energyBoost * Double(level))
        if travel > 1_000_000 { travel -= 1_000_000 }
    }
}

/// macOS Studio waveform tuning; the compact widget uses the same geometry.
enum WaveConfig {
    static let heightFrac: Double = 0.40
    static let taperPow: Double = 1.1
    static let carrierCycles: Double = 3.0
    static let travelHz: Double = 0.3
    static let energyBoost: Double = 1.8
    static let glow: CGFloat = 16
    static let driftCenter: Double = 0.04
    static let driftWidth: Double = 0.2

    struct Belly { let c, w, delayMs, f, amp: Double }
    static let bellies: [Belly] = [
        Belly(c: 0.31, w: 0.16, delayMs: 0, f: 0.037, amp: 1.0),
        Belly(c: 0.53, w: 0.15, delayMs: 70, f: 0.053, amp: 0.95),
        Belly(c: 0.73, w: 0.15, delayMs: 140, f: 0.071, amp: 0.78),
    ]

    static let gradient = Gradient(stops: [
        .init(color: Color(red: 0.94, green: 0.25, blue: 0.77).opacity(0), location: 0),
        .init(color: Color(red: 0.94, green: 0.25, blue: 0.77).opacity(0.7), location: 0.08),
        .init(color: Color(red: 0.96, green: 0.30, blue: 0.88), location: 0.25),
        .init(color: Color(red: 0.72, green: 0.39, blue: 0.98), location: 0.51),
        .init(color: Color(red: 0.57, green: 0.40, blue: 1.00), location: 0.77),
        .init(color: Color(red: 0.36, green: 0.53, blue: 1.00).opacity(0.7), location: 0.92),
        .init(color: Color(red: 0.36, green: 0.53, blue: 1.00).opacity(0), location: 1),
    ])
    static let mainGradient = Gradient(stops: [
        .init(color: Color(red: 0.96, green: 0.34, blue: 0.84).opacity(0), location: 0),
        .init(color: Color(red: 0.96, green: 0.34, blue: 0.84).opacity(0.7), location: 0.08),
        .init(color: Color(red: 1.00, green: 0.43, blue: 0.91), location: 0.27),
        .init(color: Color(red: 1.00, green: 0.77, blue: 1.00), location: 0.36),
        .init(color: Color(red: 0.75, green: 0.44, blue: 1.00), location: 0.47),
        .init(color: Color(red: 0.89, green: 0.70, blue: 1.00), location: 0.64),
        .init(color: Color(red: 0.53, green: 0.47, blue: 1.00), location: 0.79),
        .init(color: Color(red: 0.36, green: 0.53, blue: 1.00).opacity(0), location: 1),
    ])

    struct Line { let width, alpha, k, phase, offset: Double; let main: Bool }

    static let desktopLines: [Line] = [
        Line(width: 0.7, alpha: 0.44, k: 0.76, phase: -0.90, offset: -1.0, main: false),
        Line(width: 0.9, alpha: 0.68, k: 0.88, phase: -0.51, offset: -0.65, main: false),
        Line(width: 1.1, alpha: 0.80, k: 0.96, phase: -0.23, offset: -0.31, main: false),
        Line(width: 1.1, alpha: 0.80, k: 0.96, phase: 0.24, offset: 0.31, main: false),
        Line(width: 0.9, alpha: 0.68, k: 0.88, phase: 0.54, offset: 0.65, main: false),
        Line(width: 0.7, alpha: 0.44, k: 0.76, phase: 0.94, offset: 1.0, main: false),
        Line(width: 2.2, alpha: 1, k: 1, phase: 0, offset: 0, main: true),
    ]
    static let widgetLines: [Line] = [desktopLines[1], desktopLines[2], desktopLines[4], desktopLines[6]]

    /// The native envelope already gates noise and shapes the response. Keep
    /// quiet speech visible, with headroom for strand spread in compact views.
    static func visualEnergy(_ level: Float) -> Double {
        let x = Double(min(1, max(0, level.isFinite ? level : 0)))
        return 0.9 * x
    }
}

struct WaveformView: View {
    /// Provider of the processed level history (0..1, newest last).
    let levelsProvider: () -> [Float]
    let isActive: Bool
    /// Caps the frame rate. nil = display refresh rate.
    var maxFPS: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var clock = WavePhaseClock()

    var body: some View {
        GeometryReader { geo in
            let lines = geo.size.height >= 64 ? WaveConfig.desktopLines : WaveConfig.widgetLines
            TimelineView(.animation(
                minimumInterval: maxFPS.map { 1.0 / $0 },
                paused: scenePhase != .active || !isActive
            )) { timeline in
                let levels = currentLevels()
                let level = levels.last ?? 0
                let _ = reduceMotion ? () : clock.advance(to: timeline.date, level: level)
                // Capture values, not the mutable clock reference: Canvas must
                // receive a different input on every animation tick.
                let drift = clock.drift, travel = clock.travel
                Canvas { context, size in
                    Self.draw(in: &context, size: size, levels: levels,
                              drift: drift, travel: travel,
                              lines: lines, frozen: reduceMotion)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Full envelope history, padded to a fixed length while the buffer fills.
    private func currentLevels() -> [Float] {
        let target = AudioEnvelopeConfig.historyLength
        guard isActive else { return Array(repeating: 0, count: target) }
        let levels = levelsProvider()
        if levels.count >= target { return Array(levels.suffix(target)) }
        return Array(repeating: 0, count: target - levels.count) + levels
    }

    /// History sampled `delayMs` in the past, linearly interpolated.
    private static func envelope(_ h: [Float], delayMs: Double) -> Double {
        guard !h.isEmpty else { return 0 }
        let f = Double(h.count - 1) - delayMs / (1000 / AudioEnvelopeConfig.publishRateHz)
        let i0 = max(0, Int(floor(f))), i1 = min(h.count - 1, i0 + 1), u = f - floor(f)
        return Double(h[i0]) * (1 - u) + Double(h[i1]) * u
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, levels: [Float],
                             drift: Double, travel: Double,
                             lines: [WaveConfig.Line], frozen: Bool) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let tau = 2 * Double.pi
        let compact = h < 64
        let cy = h / 2, maxH = h * WaveConfig.heightFrac * (compact ? 0.7 : 1)
        let level = WaveConfig.visualEnergy(levels.last ?? 0)
        // Reduce Motion: shape frozen, only the height follows the level.
        let td = frozen ? 0 : drift, tr = frozen ? 0 : travel

        let bellies = WaveConfig.bellies.enumerated().map { i, b -> (c: Double, w: Double, amp: Double) in
            let di = Double(i)
            return (b.c + WaveConfig.driftCenter * sin(tau * b.f * td + di * 2.1),
                    b.w * (1 + WaveConfig.driftWidth * sin(tau * b.f * 0.83 * td + di * 1.3)),
                    b.amp * (frozen ? level : WaveConfig.visualEnergy(Float(envelope(levels, delayMs: b.delayMs)))))
        }

        let step: CGFloat = compact ? 0.5 : 2
        let n = Int(w / step) + 1
        let quiet = 0.55 + 0.45 * min(1, level * 2)
        let shading = GraphicsContext.Shading.linearGradient(
            WaveConfig.gradient, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))
        let mainShading = GraphicsContext.Shading.linearGradient(
            WaveConfig.mainGradient, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))

        var ctx = context
        ctx.blendMode = .normal
        for (j, line) in lines.enumerated() {
            var path = Path()
            for p in 0..<n {
                let x = Double(p) / Double(n - 1)
                let taper = pow(max(0, sin(Double.pi * x)), WaveConfig.taperPow)
                var s = 0.0
                var spread = 0.0
                var weight = 0.0
                for (i, b) in bellies.enumerated() {
                    let z = (x - b.c) / b.w
                    let belly = exp(-0.5 * z * z)
                    weight += belly
                    let localGain = line.main ? 1 : 1 + 0.18 * sin(Double((j + 1) * (i + 2)) * 1.3)
                    // A shared carrier origin prevents overlapping lobes from
                    // cancelling speech peaks as their centres drift.
                    s += b.amp * line.k * localGain * belly
                        * sin(tau * WaveConfig.carrierCycles * x - tr + Double(i) * 0.35 + line.phase * (1 + Double(i) * 0.7))
                    spread += b.amp * belly * (i == 1 ? -0.8 : 1)
                }
                // Normalize overlap without flattening loud peaks with tanh.
                let y = s / max(1, weight) * maxH * taper
                    + maxH * level * line.offset * 0.40 * spread * taper
                let pt = CGPoint(x: CGFloat(p) * step, y: cy - y)
                if p == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            if line.main || (j >= 1 && j <= 4) {
                var glow = ctx
                let glowGain = 0.1 + 0.9 * min(1, level / 0.3)
                glow.opacity = (line.main ? 0.75 : (j == 2 || j == 3 ? 0.32 : 0.20)) * glowGain
                glow.blendMode = .plusLighter
                glow.addFilter(.blur(radius: compact ? 3 : (line.main ? WaveConfig.glow : 7)))
                glow.stroke(path, with: line.main ? mainShading : shading,
                            style: StrokeStyle(lineWidth: compact ? 5 : (line.main ? 20 : 8), lineCap: .round, lineJoin: .round))
            }
            var lc = ctx
            lc.opacity = line.main ? 1 : line.alpha * quiet
            lc.stroke(path, with: line.main ? mainShading : shading,
                      style: StrokeStyle(lineWidth: line.width * (compact ? 0.72 : 1), lineCap: .round, lineJoin: .round))
        }
    }
}
