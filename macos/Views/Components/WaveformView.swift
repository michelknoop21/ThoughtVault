import SwiftUI

// 1. Gebruik expliciet Double om de Swift compiler te helpen (voorkomt de type-check timeout)
private struct WaveConfig {
    let frequency: Double
    let speed: Double
    let amplitudeScale: Double
    let phaseOffset: Double
    let lineWidth: Double
    let glowWidth: Double
    let glowOpacity: Double
}

private let gradientStops: [Gradient.Stop] = [
    Gradient.Stop(color: Color(red: 0.08, green: 0.24, blue: 0.70), location: 0.00),
    Gradient.Stop(color: Color(red: 0.31, green: 0.24, blue: 1.00), location: 0.30),
    Gradient.Stop(color: Color(red: 0.63, green: 0.08, blue: 0.78), location: 0.55),
    Gradient.Stop(color: Color(red: 0.16, green: 0.63, blue: 1.00), location: 0.95)
]

private let waveConfigs: [WaveConfig] = [
    WaveConfig(frequency: 1.5, speed: 6.0, amplitudeScale: 1.0,  phaseOffset: 0.0, lineWidth: 2.0, glowWidth: 8.0, glowOpacity: 0.4),
    WaveConfig(frequency: 1.8, speed: 5.2, amplitudeScale: 0.85, phaseOffset: 0.7, lineWidth: 1.5, glowWidth: 6.0, glowOpacity: 0.3),
    WaveConfig(frequency: 1.2, speed: 7.5, amplitudeScale: 0.75, phaseOffset: 1.5, lineWidth: 1.2, glowWidth: 5.0, glowOpacity: 0.25),
    WaveConfig(frequency: 2.0, speed: 4.8, amplitudeScale: 0.65, phaseOffset: 2.1, lineWidth: 1.0, glowWidth: 4.0, glowOpacity: 0.2),
    WaveConfig(frequency: 2.4, speed: 3.8, amplitudeScale: 0.55, phaseOffset: 2.8, lineWidth: 1.0, glowWidth: 4.0, glowOpacity: 0.2),
    WaveConfig(frequency: 0.9, speed: 8.0, amplitudeScale: 0.45, phaseOffset: 3.3, lineWidth: 1.0, glowWidth: 3.0, glowOpacity: 0.15),
    WaveConfig(frequency: 1.6, speed: 5.5, amplitudeScale: 0.35, phaseOffset: 3.9, lineWidth: 0.8, glowWidth: 3.0, glowOpacity: 0.15),
    WaveConfig(frequency: 2.8, speed: 3.5, amplitudeScale: 0.25, phaseOffset: 4.5, lineWidth: 0.8, glowWidth: 2.0, glowOpacity: 0.1)
]

// 2. Een simpele class om de state in bij te houden.
// Omdat dit een reference type is, triggert het updaten hiervan geen zware SwiftUI re-renders.
private class WaveState {
    var smoothedLevel: Double = 0.01
    
    func update(targetRaw: Float, isActive: Bool) {
        let target = isActive ? Double(max(0.01, targetRaw)) : 0.01
        let delta = target - smoothedLevel
        let smoothingFactor: Double = delta > 0 ? 0.2 : 0.05
        smoothedLevel += delta * smoothingFactor
    }
}

struct WaveformView: View {
    let levelProvider: () -> Float
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveState = WaveState()

    var body: some View {
        // Reduce Motion: the continuous 60fps travelling wave is a WCAG 2.3.3
        // trigger. Replace it with a calm static baseline; the LIVE badge and
        // timer still communicate that recording is active.
        if reduceMotion {
            staticWaveform
        } else {
            animatedWaveform
        }
    }

    private var staticWaveform: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let gradient = Gradient(stops: gradientStops)
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                p.addLine(to: CGPoint(x: size.width, y: midY))
            }
            context.stroke(
                path,
                with: .linearGradient(gradient,
                                      startPoint: .zero,
                                      endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .accessibilityHidden(true)
    }

    private var animatedWaveform: some View {
        // 3. TimelineView is cross-platform (macOS/iOS) en perfect voor Canvas animaties
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time: Double = timeline.date.timeIntervalSinceReferenceDate
                
                // Update de state direct tijdens de render pass (snel en efficiënt)
                waveState.update(targetRaw: levelProvider(), isActive: isActive)
                let currentLevel: Double = waveState.smoothedLevel
                
                let _: CGFloat = size.width / 2
                let midY: CGFloat = size.height / 2
                let padding: CGFloat = min(max(4, midY * 0.15), 16)
                let maxAmplitude: CGFloat = midY - padding
                
                guard maxAmplitude > 1 else { return }
                
                let gradientSpeed: Double = 0.5
                let gradientAmplitude: Double = 0.1
                let gradientOffset: Double = sin(time * gradientSpeed) * gradientAmplitude
                
                let animatedStops: [Gradient.Stop] = gradientStops.map { stop in
                    let newLocation: Double = Double(stop.location) + gradientOffset
                    let clamped: Double = min(1.0, max(0.0, newLocation))
                    return Gradient.Stop(color: stop.color, location: clamped)
                }
                let gradient = Gradient(stops: animatedStops)
                
                for (i, config) in waveConfigs.enumerated().reversed() {
                    let wavePhase: Double = (-(time * config.speed)) + config.phaseOffset
                    
                    let wobbleBase: Double = 0.88
                    let wobbleAmp: Double = 0.12
                    let wobbleFreq: Double = 3.0
                    let wobblePhasePerIndex: Double = 1.7
                    let wobble: Double = wobbleBase + wobbleAmp * sin(time * wobbleFreq + Double(i) * wobblePhasePerIndex)
                    
                    let unclampedLevel: Double = currentLevel * config.amplitudeScale * wobble
                    let level: Double = max(0.01, unclampedLevel)
                    
                    let path = Path { path in
                        let step: CGFloat = 2.0
                        let twoPi: CGFloat = .pi * 2.0
                        let width: CGFloat = size.width
                        let height: CGFloat = size.height
                        let midX: CGFloat = width / 2.0
                        let midY: CGFloat = height / 2.0
                        let maxAmp: CGFloat = maxAmplitude
                        let freq: Double = config.frequency
                        let phase: Double = wavePhase
                        let levelCG: CGFloat = CGFloat(level)
                        
                        var first = true
                        for x in stride(from: CGFloat(0), through: width, by: step) {
                            let normalized: CGFloat = (x - midX) / midX
                            let gaussianScale: CGFloat = 2.5
                            let envelope: CGFloat = CGFloat(exp(-pow(Double(normalized * gaussianScale), 2.0)))
                            
                            let xOverWidth: CGFloat = x / width
                            let angle: CGFloat = twoPi * xOverWidth * CGFloat(freq) + CGFloat(phase)
                            let sineVal: CGFloat = sin(angle)
                            
                            let amplitude: CGFloat = envelope * maxAmp * levelCG
                            let y: CGFloat = midY + amplitude * sineVal
                            
                            if first {
                                path.move(to: CGPoint(x: x, y: y))
                                first = false
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    
                    let baseOpacity: Double = 0.9
                    let tailMax: Double = 0.8
                    let tailMin: Double = 0.3
                    let tailScale: Double = 0.5
                    let idxRatio: Double = 1.0 - (Double(i) / Double(waveConfigs.count))
                    let computedTail: Double = min(tailMax, tailMin + idxRatio * tailScale)
                    let opacity: Double = (i == 0) ? baseOpacity : computedTail
                    
                    let width: CGFloat = size.width
                    let gradientStart: CGPoint = .zero
                    let gradientEnd: CGPoint = CGPoint(x: width, y: 0)
                    let linearGradient: GraphicsContext.Shading = .linearGradient(gradient, startPoint: gradientStart, endPoint: gradientEnd)
                    
                    var glowCtx = context
                    glowCtx.blendMode = .plusLighter
                    glowCtx.opacity = config.glowOpacity
                    glowCtx.stroke(
                        path,
                        with: linearGradient,
                        style: StrokeStyle(lineWidth: config.glowWidth, lineCap: .round, lineJoin: .round)
                    )
                    
                    var ctx = context
                    ctx.blendMode = .plusLighter
                    ctx.opacity = opacity
                    ctx.stroke(
                        path,
                        with: linearGradient,
                        style: StrokeStyle(lineWidth: config.lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}
