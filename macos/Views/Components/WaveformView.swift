// ThoughtVault light-thread styling with the SiriWave Classic curve.
// Adapted from kopiro/siriwave (MIT); see docs/licenses/siriwave-MIT.txt.
// AudioEnvelopeProcessor supplies real loudness and frequency bands.

import SwiftUI

/// Continuous travel accumulator. A reference type in `@State` so ticking it from
/// inside the `TimelineView` body does not invalidate the view.
final class WavePhaseClock {
    var travel: Double = 0
    var lastTick: Date?

    /// `dt` is capped at 64 ms so a paused or backgrounded timeline never jumps.
    func advance(to date: Date, level: Float) {
        let dt = lastTick.map { min(0.064, max(0, date.timeIntervalSince($0))) } ?? 0
        lastTick = date
        travel += dt * 2 * .pi * WaveConfig.travelHz * (1 + WaveConfig.energyBoost * Double(level))
    }
}

/// macOS Studio waveform tuning; the compact widget uses the same geometry.
enum WaveConfig {
    static let heightFrac: Double = 0.40
    static let travelHz: Double = 0.65
    static let energyBoost: Double = 0.8
    static let glow: CGFloat = 10

    /// SiriWave Classic: graph domain -2...2, fourth-power attenuation.
    /// Keep height bounded; spectra shape support strands, never gate loudness.
    static func displacement(x: Double, amplitude: Double, gain: Double,
                             travel: Double, index: Int, frequency: Double,
                             line: Line, frozen: Bool) -> Double {
        let graphX = 4 * x - 2
        let attenuation = pow(4 / (4 + pow(graphX, 4)), 4)
        let strandGain = line.main ? 1 : 0.25 + 0.75 * gain
        let speed = line.main ? 1 : 0.82 + Double(index) * 0.065
        let phase = frozen ? 0 : travel * speed
        return attenuation * amplitude * line.k * strandGain
            * sin(frequency * graphX - phase + line.phase)
    }

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

    struct Line { let width, alpha, k, phase: Double; let main: Bool }

    static let desktopLines: [Line] = [
        Line(width: 0.7, alpha: 0.44, k: 0.76, phase: -0.90, main: false),
        Line(width: 0.9, alpha: 0.68, k: 0.88, phase: -0.51, main: false),
        Line(width: 1.1, alpha: 0.80, k: 0.96, phase: -0.23, main: false),
        Line(width: 1.1, alpha: 0.80, k: 0.96, phase: 0.24, main: false),
        Line(width: 0.9, alpha: 0.68, k: 0.88, phase: 0.54, main: false),
        Line(width: 0.7, alpha: 0.44, k: 0.76, phase: 0.94, main: false),
        Line(width: 2.2, alpha: 1, k: 1, phase: 0, main: true),
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
    var bandsProvider: (() -> [Float])? = nil
    var animatesInBackground = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var clock = WavePhaseClock()

    var body: some View {
        GeometryReader { geo in
            let lines = geo.size.height >= 64 ? WaveConfig.desktopLines : WaveConfig.widgetLines
            TimelineView(.animation(
                minimumInterval: maxFPS.map { 1.0 / $0 },
                paused: (!animatesInBackground && scenePhase != .active) || !isActive
            )) { timeline in
                let levels = currentLevels()
                let level = levels.last ?? 0
                let bands = isActive ? bandsProvider?() ?? [] : []
                let _ = reduceMotion ? () : clock.advance(to: timeline.date, level: level)
                // Capture values, not the mutable clock reference: Canvas must
                // receive a different input on every animation tick.
                let travel = clock.travel
                Canvas { context, size in
                    Self.draw(in: &context, size: size, levels: levels, bands: bands,
                              travel: travel,
                              lines: lines, frozen: reduceMotion)
                }
            }
        }
        .clipped()
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

    private static func draw(in context: inout GraphicsContext, size: CGSize, levels: [Float], bands: [Float],
                             travel: Double,
                             lines: [WaveConfig.Line], frozen: Bool) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let compact = h < 64
        let cy = h / 2, maxH = h * WaveConfig.heightFrac
        let level = WaveConfig.visualEnergy(levels.last ?? 0)
        let peakBand = bands.max() ?? 0
        let step: CGFloat = compact ? 0.5 : 2
        let n = max(2, Int(ceil(w / step)) + 1)
        let quiet = 0.55 + 0.45 * min(1, level * 2)
        let shading = GraphicsContext.Shading.linearGradient(
            WaveConfig.gradient, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))
        let mainShading = GraphicsContext.Shading.linearGradient(
            WaveConfig.mainGradient, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))

        var ctx = context
        ctx.blendMode = .normal
        for (j, line) in lines.enumerated() {
            let bandIndex = min(bands.count - 1, j * bands.count / max(1, lines.count - 1))
            let bandEnd = min(bands.count, max(bandIndex + 1, (j + 1) * bands.count / max(1, lines.count - 1)))
            let gain = line.main || bands.isEmpty ? 1 : peakBand > 0 ? Double((bands[bandIndex..<bandEnd].max() ?? 0) / peakBand) : 0
            let frequency = frozen ? 3.4 : line.main ? 3.4 : 2.8 + Double(max(0, bandIndex)) * 0.22
            let delayed = frozen ? level : WaveConfig.visualEnergy(Float(envelope(levels, delayMs: Double(j) * 25)))
            let amplitude = level == 0 ? 0 : line.main ? level : 0.65 * level + 0.35 * delayed
            var path = Path()
            for p in 0..<n {
                let x = Double(p) / Double(n - 1)
                let y = WaveConfig.displacement(x: x, amplitude: amplitude, gain: gain,
                                              travel: travel, index: j, frequency: frequency,
                                              line: line, frozen: frozen)
                let pt = CGPoint(x: x * w, y: cy - y * maxH)
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
