// WaveformView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Siri-style waveform (SCSiriWaveformView algorithm): 5 overlapping sine waves
// with a parabolic envelope that tapers to zero at the edges, drawn at 60fps in
// the ThoughtVault lavender → violet → indigo gradient.

import SwiftUI

// Mutable reference type so the 60fps render pass can update the smoothed level
// without triggering SwiftUI re-renders.
//
// Dynamics pipeline (classic meter design):
//  1. AGC: track a rolling noise floor (snaps down, rises slowly) and rolling
//     peak (snaps up, decays slowly), then normalize the raw level to that
//     window so the wave always uses the full 0…1 range — loud rooms and
//     quiet voices both show clear peaks and valleys.
//  2. Expansion: ^1.7 curve pushes lows down and lets peaks pop (the recorder's
//     dB mapping is compressive, this restores visible tone dynamics).
//  3. Envelope: fast attack / slow release, so peaks hit instantly and fall
//     away smoothly.
private class WaveState {
    var smoothedLevel: Double = 0.01

    private var rollingFloor: Double = 0.10
    private var rollingPeak: Double = 0.55

    func update(targetRaw: Float, isActive: Bool) {
        guard isActive else {
            smoothedLevel += (0.01 - smoothedLevel) * 0.08
            return
        }
        let raw = Double(max(0, targetRaw))

        // Noise floor: snap down to new minima, drift up slowly otherwise.
        if raw < rollingFloor { rollingFloor = raw }
        else { rollingFloor += (raw - rollingFloor) * 0.004 }

        // Peak: snap up to new maxima, decay slowly otherwise.
        if raw > rollingPeak { rollingPeak = raw }
        else { rollingPeak += (raw - rollingPeak) * 0.008 }

        // Normalize against the rolling window (keep a minimum span so a
        // constant signal doesn't explode into full-scale noise).
        let span = max(rollingPeak - rollingFloor, 0.18)
        let normalized = min(1.0, max(0.0, (raw - rollingFloor) / span))

        // Expansion for visible tone dynamics.
        let target = max(0.02, pow(normalized, 1.7))

        // Fast attack, slow release.
        let delta = target - smoothedLevel
        smoothedLevel += delta * (delta > 0 ? 0.55 : 0.10)
    }
}

private let brandGradient = Gradient(colors: [
    Color(red: 0.847, green: 0.565, blue: 0.941),   // lavender #D890F0
    Color(red: 0.565, green: 0.282, blue: 0.941),   // violet   #9048F0
    Color(red: 0.376, green: 0.282, blue: 0.941)    // indigo   #6048F0
])

struct WaveformView: View {
    let levelProvider: () -> Float
    let isActive: Bool
    /// Optional spectrum source: per-wave band amplitudes + normalized centroid.
    /// When nil (idle hero, no live recording) the wave falls back to level-only.
    var spectrumProvider: (() -> (bands: [Float], centroid: Float))? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveState = WaveState()

    private let numberOfWaves = 5
    private let frequency: Double = 1.5
    private let primaryLineWidth: CGFloat = 2.5
    private let secondaryLineWidth: CGFloat = 1.0

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
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                p.addLine(to: CGPoint(x: size.width, y: midY))
            }
            context.stroke(
                path,
                with: .linearGradient(brandGradient,
                                      startPoint: .zero,
                                      endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .accessibilityHidden(true)
    }

    private var animatedWaveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let phase = -time * 9.0

                waveState.update(targetRaw: levelProvider(), isActive: isActive)
                let level = CGFloat(waveState.smoothedLevel)

                // Spectral data drives pitch response: per-wave band amplitude and
                // a centroid that modulates the travelling-wave frequency (low voice
                // = broad slow wave, high tone = tight fast wave).
                let spectrum = spectrumProvider?()
                let bands = spectrum?.bands ?? []
                let centroid = spectrum.map { Double($0.centroid) } ?? 0.5
                let effectiveFrequency = frequency * (0.5 + centroid * 2.0)

                let midX = size.width / 2
                let midY = size.height / 2
                let maxAmplitude = midY - min(max(4, midY * 0.12), 14)
                guard maxAmplitude > 1, midX > 0 else { return }

                let shading: GraphicsContext.Shading = .linearGradient(
                    brandGradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )

                // Back-to-front so the primary wave draws on top.
                for i in stride(from: numberOfWaves - 1, through: 0, by: -1) {
                    let progress = 1.0 - CGFloat(i) / CGFloat(numberOfWaves)
                    // Per-wave amplitude: overall level gated by this wave's band
                    // energy when spectral data is available.
                    let bandGain: CGFloat = i < bands.count ? CGFloat(0.35 + 1.3 * bands[i]) : 1.0
                    let normedAmplitude = (1.5 * progress - 0.4) * level * bandGain
                    // Slight per-wave phase offset keeps layers distinct but coherent.
                    let wavePhase = phase + Double(i) * 0.35

                    let path = Path { p in
                        var first = true
                        for x in stride(from: CGFloat(0), through: size.width, by: 2.0) {
                            let normalized = (x - midX) / midX
                            // Parabolic envelope: 1 at center, 0 at the edges —
                            // the organic diamond silhouette that reads as "Siri".
                            let envelope = -(normalized * normalized) + 1.0
                            let angle = 2 * CGFloat.pi * (x / size.width) * CGFloat(effectiveFrequency) + CGFloat(wavePhase)
                            let y = envelope * maxAmplitude * normedAmplitude * sin(angle) + midY
                            if first { p.move(to: CGPoint(x: x, y: y)); first = false }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }

                    let isPrimary = (i == 0)
                    let alpha = min(1.0, (Double(i) / Double(numberOfWaves)) / 3.0 + 1.0 / 3.0)

                    if isPrimary {
                        // Soft glow under the primary wave.
                        var glow = context
                        glow.blendMode = .plusLighter
                        glow.opacity = 0.35
                        glow.stroke(path, with: shading,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                        context.stroke(path, with: shading,
                                       style: StrokeStyle(lineWidth: primaryLineWidth, lineCap: .round, lineJoin: .round))
                    } else {
                        var ctx = context
                        ctx.blendMode = .plusLighter
                        ctx.opacity = alpha
                        ctx.stroke(path, with: shading,
                                   style: StrokeStyle(lineWidth: secondaryLineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }
}
