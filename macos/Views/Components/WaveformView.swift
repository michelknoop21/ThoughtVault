// WaveformView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Light-thread waveform (approved Opnemen NorthStar). A bundle of thin lines
// drawn on a Canvas: every line is a sum of three gaussian bellies whose centre
// and width drift slowly, each belly reading the envelope history at its own
// delay (0 / 90 / 180 ms) so syllables show up as shifting peaks instead of the
// whole bundle pumping. The main line is brighter and glows; the support lines
// are scaled, slightly phase-shifted copies (ribbon look). Colour runs magenta
// → violet → lavender → cool blue along x.
//
// The history comes from AudioEnvelopeProcessor (30 Hz, 3 s). Travel speed is
// constant; loudness raises it by at most 25 %. Mirrors
// windows/src/components/recording/WaveformVisualizer.tsx.

import SwiftUI

/// Drift/travel accumulator. A reference type in `@State` so ticking it from
/// inside the `TimelineView` body does not invalidate the view.
private final class WavePhaseClock {
    var drift: Double = 0
    var travel: Double = 0
    var time: Double = 0
    var lastTick: Date?

    /// `dt` is capped at 64 ms so a paused or backgrounded timeline never jumps.
    func advance(to date: Date, level: Float) {
        let dt = lastTick.map { min(0.064, max(0, date.timeIntervalSince($0))) } ?? 0
        lastTick = date
        time += dt
        drift += dt
        travel += dt * 2 * .pi * WaveConfig.travelHz * (1 + WaveConfig.energyBoost * Double(level))
        if travel > 1_000_000 { travel -= 1_000_000 }
    }
}

/// Tuning values; keep in sync with the Windows visualizer.
enum WaveConfig {
    static let heightFrac: Double = 0.38
    static let knee: Double = 2.2
    static let taperPow: Double = 1.1
    static let carrierCycles: Double = 2.3
    static let travelHz: Double = 0.3
    static let energyBoost: Double = 0.25
    static let breath: Double = 0.012
    static let glow: CGFloat = 16
    static let driftCenter: Double = 0.04
    static let driftWidth: Double = 0.2

    struct Belly { let c, w, delayMs, f, amp: Double }
    static let bellies: [Belly] = [
        Belly(c: 0.32, w: 0.14, delayMs: 0, f: 0.037, amp: 1.0),
        Belly(c: 0.52, w: 0.13, delayMs: 90, f: 0.053, amp: 0.8),
        Belly(c: 0.73, w: 0.13, delayMs: 180, f: 0.071, amp: 0.6),
    ]

    static let gradient = Gradient(stops: [
        .init(color: Color(red: 1.00, green: 0.31, blue: 0.82), location: 0),
        .init(color: Color(red: 0.75, green: 0.31, blue: 1.00), location: 0.30),
        .init(color: Color(red: 0.92, green: 0.78, blue: 1.00), location: 0.50),
        .init(color: Color(red: 0.67, green: 0.35, blue: 1.00), location: 0.72),
        .init(color: Color(red: 0.35, green: 0.55, blue: 1.00), location: 1),
    ])

    struct Line { let width, alpha, k, phase: Double; let main: Bool }

    /// Deterministic per-line parameters; the last line is the main curve.
    static func lines(count: Int) -> [Line] {
        func hash(_ n: Double) -> Double { let x = sin(n * 127.1 + 311.7) * 43758.5453; return x - floor(x) }
        return (0..<count).map { j in
            let jd = Double(j)
            if j == count - 1 { return Line(width: 2.4, alpha: 1, k: 1, phase: 0, main: true) }
            return Line(width: 0.7 + 0.8 * hash(jd), alpha: 0.35 + 0.4 * hash(jd + 7),
                        k: 0.3 + 0.7 * (jd / Double(max(1, count - 2))), phase: (hash(jd + 3) - 0.5) * 0.9, main: false)
        }
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
            // A dozen threads blur together on small surfaces (the 120x32 widget).
            let lineCount = geo.size.height >= 64 ? 12 : 4
            TimelineView(.animation(
                minimumInterval: maxFPS.map { 1.0 / $0 },
                paused: scenePhase != .active || !isActive
            )) { timeline in
                let levels = currentLevels()
                let level = levels.last ?? 0
                let _ = reduceMotion ? () : clock.advance(to: timeline.date, level: level)
                Canvas { context, size in
                    Self.draw(in: &context, size: size, levels: levels, clock: clock,
                              lines: WaveConfig.lines(count: lineCount), frozen: reduceMotion)
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
                             clock: WavePhaseClock, lines: [WaveConfig.Line], frozen: Bool) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let tau = 2 * Double.pi
        let cy = h / 2, maxH = h * WaveConfig.heightFrac
        let level = Double(levels.last ?? 0)
        // Reduce Motion: shape frozen, only the height follows the level.
        let td = frozen ? 0 : clock.drift, tr = frozen ? 0 : clock.travel, time = frozen ? 0 : clock.time

        let bellies = WaveConfig.bellies.enumerated().map { i, b -> (c: Double, w: Double, amp: Double) in
            let di = Double(i)
            return (b.c + WaveConfig.driftCenter * sin(tau * b.f * td + di * 2.1),
                    b.w * (1 + WaveConfig.driftWidth * sin(tau * b.f * 0.83 * td + di * 1.3)),
                    b.amp * (frozen ? level : envelope(levels, delayMs: b.delayMs)))
        }

        let step: CGFloat = 2
        let n = Int(w / step) + 1
        let quiet = 0.55 + 0.45 * min(1, level * 2)
        let shading = GraphicsContext.Shading.linearGradient(
            WaveConfig.gradient, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))

        var ctx = context
        ctx.blendMode = .plusLighter
        for (j, line) in lines.enumerated() {
            var path = Path()
            for p in 0..<n {
                let x = Double(p) / Double(n - 1)
                let taper = pow(max(0, sin(Double.pi * x)), WaveConfig.taperPow)
                var s = 0.0
                for (i, b) in bellies.enumerated() {
                    let z = (x - b.c) / b.w
                    let k = line.main ? 1 : line.k * (1 + 0.25 * sin(tau * 0.05 * td + Double(j + i)))
                    s += b.amp * k * exp(-0.5 * z * z)
                        * sin(tau * WaveConfig.carrierCycles * (x - b.c) - tr + line.phase * (1 + Double(i) * 0.4))
                }
                let y = tanh(s * WaveConfig.knee) * maxH * taper
                    + h * WaveConfig.breath * sin(tau * 1.3 * x + time * 0.9 + Double(j) * 0.3) * taper
                let pt = CGPoint(x: CGFloat(p) * step, y: cy - y)
                if p == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            var lc = ctx
            lc.opacity = line.main ? 1 : line.alpha * quiet
            if line.main {
                lc.addFilter(.shadow(color: Color(red: 0.93, green: 0.4, blue: 1).opacity(0.95), radius: WaveConfig.glow * 0.7))
            } else if j % 3 == 0 {
                lc.addFilter(.shadow(color: Color(red: 0.75, green: 0.31, blue: 1).opacity(0.7), radius: 4))
            }
            lc.stroke(path, with: shading, style: StrokeStyle(lineWidth: line.width, lineCap: .round, lineJoin: .round))
        }
    }
}
