// HomeDecor.swift
// ThoughtVault
//
// Decorative pieces of the macOS Home NorthStar: the record button, the idle
// bar waveform and the mountain illustration behind the greeting.

#if os(macOS)
import SwiftUI

// MARK: - Decorative pieces

/// The round violet record button with its ring and halo.
struct HomeMicButton: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.24, green: 0.17, blue: 0.52).opacity(0.9), Color(red: 0.12, green: 0.10, blue: 0.27).opacity(0.0)],
                                     center: .center, startRadius: 40, endRadius: 66))
                .frame(width: 132, height: 132)
            Circle()
                .strokeBorder(Color(red: 0.36, green: 0.27, blue: 0.72).opacity(0.7), lineWidth: 1)
                .frame(width: 113, height: 113)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.72, green: 0.52, blue: 1.0), Color(red: 0.50, green: 0.28, blue: 0.93)],
                                     center: UnitPoint(x: 0.4, y: 0.3), startRadius: 4, endRadius: 60))
                .frame(width: 89, height: 89)
                .shadow(color: Color(red: 0.55, green: 0.33, blue: 1.0).opacity(0.55), radius: 16)
            Image(systemName: "mic")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 132, height: 132)
        .contentShape(Circle())
    }
}

/// Static bar waveform of the idle card: decorative, no audio behind it.
struct HomeIdleBars: View {
    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 4, barWidth: CGFloat = 2
            let count = Int(size.width / pitch)
            guard count > 1 else { return }
            for i in 0..<count {
                let x = Double(i) / Double(count - 1)
                let envelope = pow(sin(Double.pi * x), 1.4)
                let texture = 0.25 + 0.75 * abs(sin(Double(i) * 1.73) * cos(Double(i) * 0.61 + 0.4))
                let h = max(4, CGFloat(envelope * texture) * size.height)
                let rect = CGRect(x: CGFloat(i) * pitch, y: (size.height - h) / 2, width: barWidth, height: h)
                let bright = 0.45 + 0.55 * envelope
                context.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(Color(red: 0.55 + 0.25 * bright, green: 0.38 + 0.25 * bright, blue: 1.0).opacity(0.35 + 0.6 * bright)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Mountain ridge, moon and glowing path behind the greeting (480 x 190).
struct HomeIllustration: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 480, sy = size.height / 190
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

            // Haze
            context.fill(Path(ellipseIn: CGRect(origin: p(20, -40), size: CGSize(width: 480 * sx, height: 260 * sy))),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.30, green: 0.20, blue: 0.62).opacity(0.45), .clear]),
                                               center: p(260, 90), startRadius: 0, endRadius: 250 * sx))

            // Back ridge
            var back = Path()
            back.move(to: p(0, 160))
            back.addCurve(to: p(170, 95), control1: p(60, 140), control2: p(120, 120))
            back.addCurve(to: p(292, 18), control1: p(215, 72), control2: p(265, 22))
            back.addCurve(to: p(400, 62), control1: p(325, 20), control2: p(360, 60))
            back.addCurve(to: p(480, 58), control1: p(430, 64), control2: p(460, 55))
            back.addLine(to: p(480, 190)); back.addLine(to: p(0, 190)); back.closeSubpath()
            context.fill(back, with: .linearGradient(Gradient(colors: [Color(red: 0.23, green: 0.18, blue: 0.48).opacity(0.85), Color(red: 0.10, green: 0.09, blue: 0.21).opacity(0.0)]),
                                                     startPoint: p(290, 18), endPoint: p(290, 185)))

            // Moon
            var moonContext = context
            moonContext.addFilter(.shadow(color: Color(red: 0.67, green: 0.58, blue: 1.0).opacity(0.8), radius: 18))
            moonContext.fill(Path(ellipseIn: CGRect(x: (168 - 25) * sx, y: (105 - 25) * sy, width: 50 * sx, height: 50 * sy)),
                             with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.90, blue: 1.0), Color(red: 0.73, green: 0.66, blue: 0.95)]),
                                                   startPoint: p(168, 80), endPoint: p(168, 130)))

            // Front ridge (hides the lower half of the moon)
            var front = Path()
            front.move(to: p(0, 178))
            front.addCurve(to: p(150, 122), control1: p(55, 160), control2: p(110, 128))
            front.addCurve(to: p(250, 140), control1: p(190, 116), control2: p(220, 128))
            front.addCurve(to: p(480, 165), control1: p(320, 168), control2: p(420, 160))
            front.addLine(to: p(480, 190)); front.addLine(to: p(0, 190)); front.closeSubpath()
            context.fill(front, with: .linearGradient(Gradient(colors: [Color(red: 0.15, green: 0.12, blue: 0.33), Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.0)]),
                                                      startPoint: p(200, 120), endPoint: p(200, 190)))

            // Glowing path winding towards the moon
            var river = Path()
            river.move(to: p(92, 178))
            river.addCurve(to: p(186, 150), control1: p(130, 170), control2: p(190, 162))
            river.addCurve(to: p(128, 136), control1: p(182, 140), control2: p(130, 146))
            river.addCurve(to: p(178, 124), control1: p(126, 128), control2: p(160, 126))
            var riverContext = context
            riverContext.addFilter(.shadow(color: Color(red: 0.85, green: 0.35, blue: 1.0).opacity(0.9), radius: 5))
            riverContext.stroke(river, with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.30, blue: 1.0), Color(red: 0.90, green: 0.45, blue: 1.0), Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.3)]),
                                                             startPoint: p(92, 178), endPoint: p(178, 124)),
                                style: StrokeStyle(lineWidth: 1.8 * sx, lineCap: .round))
        }
    }
}
#endif
