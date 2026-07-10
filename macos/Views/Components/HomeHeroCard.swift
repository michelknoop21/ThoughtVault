// HomeHeroCard.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Home hero CTA: dark violet glass panel where an ambient Siri-waveform
// emanates from a breathing record orb — the app's core moment (speak →
// wave → note) shown at rest. Adapts between a horizontal layout (regular
// width) and a stacked layout (compact width / iPhone).

import SwiftUI

struct HomeHeroCard: View {

    /// Compact = narrow window or iPhone: orb-on-wave stacks above the text.
    var isCompact: Bool
    var onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isBreathing = false

    var body: some View {
        Button(action: onStart) {
            Group {
                if isCompact {
                    VStack(spacing: TS.Spacing.md) {
                        orbOnWave
                        copyBlock(centered: true)
                    }
                } else {
                    HStack(spacing: TS.Spacing.lg) {
                        copyBlock(centered: false)
                        Spacer(minLength: TS.Spacing.md)
                        orbOnWave
                    }
                }
            }
            .padding(.horizontal, isCompact ? TS.Spacing.md : TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background { panel }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(TS.Animation.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Nieuwe opname starten")
    }

    // MARK: Copy

    private func copyBlock(centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            Text("Nieuwe opname")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.labelPrimary)
            Text("Een losse gedachte, gesprek of meeting: ThoughtVault transcribeert lokaal en zet het om in een nette notitie of notule, klaar voor je vault.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
                .lineSpacing(2)
                .multilineTextAlignment(centered ? .center : .leading)
        }
        .frame(maxWidth: centered ? 420 : .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: Orb on wave

    /// The signature element: the Siri-waveform's parabolic envelope peaks at
    /// its center, so placing the orb there makes the wave appear to emanate
    /// from it.
    private var orbOnWave: some View {
        ZStack {
            WaveformView(levelsProvider: Self.idleLevels, isActive: !reduceMotion)
                .frame(width: isCompact ? nil : 280, height: 96)
                .frame(maxWidth: isCompact ? .infinity : 280)
                .opacity(0.9)
                .allowsHitTesting(false)

            recordOrb
        }
        .frame(height: 130)
    }

    /// Synthetic idle "breath" history for the waveform — two incommensurate
    /// sines sampled backwards in time so the wave scrolls without ever
    /// visibly looping.
    private static func idleLevels() -> [Float] {
        let now = Date.timeIntervalSinceReferenceDate
        return (0..<AudioEnvelopeConfig.historyLength).map { i in
            let t = now - Double(AudioEnvelopeConfig.historyLength - 1 - i) / AudioEnvelopeConfig.publishRateHz
            let breath = 0.30 + 0.22 * sin(t * 0.8) * sin(t * 0.13)
            let flutter = 0.06 * sin(t * 2.7)
            return Float(max(0.04, breath + flutter))
        }
    }

    /// Glowing violet record orb — breathes gently unless Reduce Motion is on.
    private var recordOrb: some View {
        ZStack {
            Circle()
                .stroke(Color.brandPrimary.opacity(0.25), lineWidth: 1)
                .frame(width: 108, height: 108)
            Circle()
                .stroke(Color.brandPrimary.opacity(0.14), lineWidth: 1)
                .frame(width: 126, height: 126)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.76, green: 0.53, blue: 1.0),
                                 Color.brandPrimary,
                                 Color.brandPrimaryDark],
                        center: .init(x: 0.32, y: 0.28),
                        startRadius: 4, endRadius: 74
                    )
                )
                .frame(width: 84, height: 84)
                .shadow(color: Color.brandPrimary.opacity(isBreathing ? 0.70 : 0.50), radius: isBreathing ? 30 : 22)
                .shadow(color: Color.brandPrimaryDark.opacity(0.45), radius: 10, y: 6)
                .scaleEffect(isBreathing ? 1.05 : 0.98)
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.brandPrimaryDark.opacity(0.6), radius: 4, y: 2)
        }
        .frame(width: 130, height: 130)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
            value: isBreathing
        )
        .onAppear { if !reduceMotion { isBreathing = true } }
    }

    // MARK: Panel

    private var panel: some View {
        // Dark panel with a violet mesh glow, per the approved mockup.
        RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.118, green: 0.102, blue: 0.227),
                             Color(red: 0.078, green: 0.078, blue: 0.157)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RadialGradient(
                    colors: [Color.brandPrimary.opacity(0.22), .clear],
                    center: .init(x: 0.88, y: -0.2),
                    startRadius: 0, endRadius: 340
                )
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.lg, style: .continuous)
                    .strokeBorder(Color.brandPrimary.opacity(isHovered ? 0.40 : 0.22), lineWidth: 1)
            }
            .shadow(color: Color.brandPrimaryDark.opacity(isHovered ? 0.42 : 0.30), radius: isHovered ? 28 : 22, y: 10)
    }
}

// MARK: - Preview

#Preview("Regular") {
    HomeHeroCard(isCompact: false, onStart: {})
        .padding(32)
        .frame(width: 760)
}

#Preview("Compact") {
    HomeHeroCard(isCompact: true, onStart: {})
        .padding(16)
        .frame(width: 380)
}
