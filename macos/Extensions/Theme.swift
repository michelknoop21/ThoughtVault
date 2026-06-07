// Theme.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Centralized design token system. All spacing, radii, typography,
// and animations live here under the TS namespace.

import SwiftUI

// MARK: - TS Namespace

/// Top-level namespace for all TranscriptStudio design tokens.
enum TS {

    // MARK: - Spacing (8px base grid)

    enum Spacing {
        /// 4pt — micro gaps, icon padding
        static let xs: CGFloat  = 4
        /// 8pt — base unit, default inner padding
        static let sm: CGFloat  = 8
        /// 16pt — standard section padding
        static let md: CGFloat  = 16
        /// 24pt — large section gaps
        static let lg: CGFloat  = 24
        /// 32pt — page-level vertical rhythm
        static let xl: CGFloat  = 32
        /// 48pt — hero-section spacing
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 6pt — small tags, badges
        static let xs: CGFloat  = 6
        /// 12pt — cards, input fields
        static let sm: CGFloat  = 12
        /// 16pt — modals, sheets
        static let md: CGFloat  = 16
        /// 20pt — large cards, panels
        static let lg: CGFloat  = 20
        /// 25pt — pill shapes, fully rounded elements
        static let xl: CGFloat  = 25
    }

    // MARK: - Typography

    /// Semantic font tokens using SwiftUI text styles for automatic Dynamic Type support.
    /// Organized by size tier, each providing multiple weight variants.
    enum Font {

        // MARK: Micro (~10pt) — tiny badges, counts

        /// ~10pt regular
        static let micro: SwiftUI.Font             = .system(.caption2)
        /// ~10pt medium
        static let microMedium: SwiftUI.Font       = .system(.caption2, design: .default, weight: .medium)
        /// ~10pt semibold
        static let microSemibold: SwiftUI.Font     = .system(.caption2, design: .default, weight: .semibold)
        /// ~10pt bold
        static let microBold: SwiftUI.Font         = .system(.caption2, design: .default, weight: .bold)

        // MARK: Caption (~12pt) — metadata, timestamps

        /// ~12pt regular
        static let caption: SwiftUI.Font           = .system(.caption)
        /// ~12pt medium
        static let captionMedium: SwiftUI.Font     = .system(.caption, design: .default, weight: .medium)
        /// ~12pt semibold
        static let captionSemibold: SwiftUI.Font   = .system(.caption, design: .default, weight: .semibold)
        /// ~12pt bold
        static let captionBold: SwiftUI.Font       = .system(.caption, design: .default, weight: .bold)
        /// ~12pt monospaced — timestamps, codes
        static let captionMonospaced: SwiftUI.Font = .system(.caption, design: .monospaced, weight: .regular)

        // MARK: Footnote (~13pt) — secondary labels, nav items

        /// ~13pt regular
        static let footnote: SwiftUI.Font          = .system(.footnote)
        /// ~13pt medium
        static let footnoteMedium: SwiftUI.Font    = .system(.footnote, design: .default, weight: .medium)
        /// ~13pt semibold
        static let footnoteSemibold: SwiftUI.Font  = .system(.footnote, design: .default, weight: .semibold)
        /// ~13pt bold
        static let footnoteBold: SwiftUI.Font      = .system(.footnote, design: .default, weight: .bold)
        /// ~13pt monospaced
        static let footnoteMonospaced: SwiftUI.Font = .system(.footnote, design: .monospaced, weight: .regular)

        // MARK: Callout (~16pt) — secondary body text

        /// ~16pt regular
        static let callout: SwiftUI.Font           = .system(.callout)
        /// ~16pt medium
        static let calloutMedium: SwiftUI.Font     = .system(.callout, design: .default, weight: .medium)
        /// ~16pt semibold
        static let calloutSemibold: SwiftUI.Font   = .system(.callout, design: .default, weight: .semibold)

        // MARK: Body (~17pt) — primary body content

        /// ~17pt regular
        static let body: SwiftUI.Font              = .system(.body)
        /// ~17pt medium
        static let bodyMedium: SwiftUI.Font        = .system(.body, design: .default, weight: .medium)
        /// ~17pt semibold
        static let bodySemibold: SwiftUI.Font      = .system(.body, design: .default, weight: .semibold)
        /// ~17pt bold
        static let bodyBold: SwiftUI.Font          = .system(.body, design: .default, weight: .bold)
        /// ~17pt monospaced — code display
        static let bodyMonospaced: SwiftUI.Font    = .system(.body, design: .monospaced, weight: .regular)

        // MARK: Subheadline (~15pt) — section subheaders, emphasized labels

        /// ~15pt regular
        static let subheadline: SwiftUI.Font       = .system(.subheadline)
        /// ~15pt medium
        static let subheadlineMedium: SwiftUI.Font = .system(.subheadline, design: .default, weight: .medium)
        /// ~15pt semibold
        static let subheadlineSemibold: SwiftUI.Font = .system(.subheadline, design: .default, weight: .semibold)
        /// ~15pt bold
        static let subheadlineBold: SwiftUI.Font   = .system(.subheadline, design: .default, weight: .bold)

        // MARK: Headline (~17pt semibold system default) — card headers

        /// System headline (auto bold)
        static let headline: SwiftUI.Font          = .system(.headline, design: .rounded)
        /// Headline bold explicit
        static let headlineBold: SwiftUI.Font      = .system(.headline, design: .rounded, weight: .bold)

        // MARK: Title3 (~20pt) — view section titles

        /// ~20pt regular rounded
        static let title3: SwiftUI.Font            = .system(.title3, design: .rounded)
        /// ~20pt semibold rounded
        static let title3Semibold: SwiftUI.Font    = .system(.title3, design: .rounded, weight: .semibold)
        /// ~20pt bold rounded
        static let title3Bold: SwiftUI.Font        = .system(.title3, design: .rounded, weight: .bold)

        // MARK: Title2 (~22pt) — major section titles

        /// ~22pt regular rounded
        static let title2: SwiftUI.Font            = .system(.title2, design: .rounded)
        /// ~22pt semibold rounded
        static let title2Semibold: SwiftUI.Font    = .system(.title2, design: .rounded, weight: .semibold)
        /// ~22pt bold rounded
        static let title2Bold: SwiftUI.Font        = .system(.title2, design: .rounded, weight: .bold)

        // MARK: Title (~28pt) — screen titles

        /// ~28pt regular rounded
        static let title: SwiftUI.Font             = .system(.title, design: .rounded)
        /// ~28pt semibold rounded
        static let titleSemibold: SwiftUI.Font     = .system(.title, design: .rounded, weight: .semibold)
        /// ~28pt bold rounded
        static let titleBold: SwiftUI.Font         = .system(.title, design: .rounded, weight: .bold)

        // MARK: Large Title (~34pt) — hero / display text

        /// ~34pt regular rounded
        static let largeTitle: SwiftUI.Font        = .system(.largeTitle, design: .rounded)
        /// ~34pt bold rounded
        static let largeTitleBold: SwiftUI.Font    = .system(.largeTitle, design: .rounded, weight: .bold)

        // MARK: Special purpose

        /// Timestamp monospaced caption (alias for captionMonospaced)
        static let timestamp: SwiftUI.Font         = .system(.caption, design: .monospaced, weight: .regular)
    }

    // MARK: - Animation Presets

    enum Animation {
        /// Smooth spring — default interactions, 0.3s response
        static let smooth: SwiftUI.Animation  = .spring(response: 0.3, dampingFraction: 0.7)
        /// Quick ease — fast micro-interactions, 0.15s
        static let quick: SwiftUI.Animation   = .easeInOut(duration: 0.15)
        /// Gentle spring — emphasis transitions, 0.5s response
        static let gentle: SwiftUI.Animation  = .spring(response: 0.5, dampingFraction: 0.8)
        /// Hover ease — card hover states, 0.18s
        static let hover: SwiftUI.Animation   = .easeInOut(duration: 0.18)
    }
}

// MARK: - View Modifiers

// MARK: Modern Card

struct ModernCardModifier: ViewModifier {
    var isHovered: Bool = false

    @ViewBuilder
    static func fallbackBackground(isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(
                color: .black.opacity(isHovered ? 0.12 : 0.06),
                radius: isHovered ? 16 : 8,
                y: isHovered ? 6 : 3
            )
    }

    func body(content: Content) -> some View {
        content
            .background {
                #if compiler(>=6.2)
                if #available(macOS 26.0, iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                        .fill(.clear)
                        .glassEffect(in: .rect(cornerRadius: TS.Radius.md))
                } else {
                    ModernCardModifier.fallbackBackground(isHovered: isHovered)
                }
                #else
                ModernCardModifier.fallbackBackground(isHovered: isHovered)
                #endif
            }
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                    .stroke(
                        isHovered
                            ? Color.brandPrimary.opacity(0.25)
                            : Color.borderPrimary.opacity(0.6),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(TS.Animation.hover, value: isHovered)
    }
}

extension View {
    /// Applies a modern card style with optional hover interaction.
    func modernCard(isHovered: Bool = false) -> some View {
        modifier(ModernCardModifier(isHovered: isHovered))
    }
}

// MARK: - Button Styles

/// Primary button — gradient fill with brand shadow.
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TS.Font.bodySemibold)
            .foregroundStyle(.white)
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDestructive
                                ? [Color.statusError, Color.statusError.opacity(0.80)]
                                : [Color.brandPrimary, Color.brandPrimary.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: isDestructive
                            ? Color.statusError.opacity(0.30)
                            : Color.brandPrimary.opacity(0.30),
                        radius: 8,
                        y: 3
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(TS.Animation.quick, value: configuration.isPressed)
    }
}

/// Secondary button — outlined with semi-transparent tinted background.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TS.Font.bodyMedium)
            .foregroundStyle(Color.brandPrimary)
            .padding(.horizontal, TS.Spacing.lg)
            .padding(.vertical, TS.Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.brandPrimary.opacity(configuration.isPressed ? 0.12 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(0.35), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(TS.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Brand Components

/// Yinga four-color horizontal brand bar.
struct YingaBar: View {
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.898, green: 0.0,   blue: 0.455))   // magenta  #E50074
                    .frame(width: geo.size.width / 4)
                Rectangle()
                    .fill(Color(red: 0.0,   green: 0.482, blue: 0.769))   // blue     #007BC4
                    .frame(width: geo.size.width / 4)
                Rectangle()
                    .fill(Color(red: 0.0,   green: 0.624, blue: 0.235))   // green    #009F3C
                    .frame(width: geo.size.width / 4)
                Rectangle()
                    .fill(Color(red: 0.953, green: 0.573, blue: 0.0))     // orange   #F39200
                    .frame(width: geo.size.width / 4)
            }
        }
        .frame(height: height)
    }
}

/// Yinga full-color logo (spinner + wordmark) rendered as native SwiftUI paths.
/// Traced from the official SVG at yinga.nl.
struct YingaLogo: View {
    var body: some View {
        GeometryReader { geo in
            let svgWidth: CGFloat = 400.42
            let svgHeight: CGFloat = 171.77
            let scale = min(geo.size.width / svgWidth, geo.size.height / svgHeight)
            let xOffset = (geo.size.width - svgWidth * scale) / 2

            ZStack(alignment: .topLeading) {
                // Orange quarter — top-right
                YingaPath.orangeQuarter
                    .fill(Color(red: 0.953, green: 0.573, blue: 0.0))
                // Magenta quarter — top-left
                YingaPath.magentaQuarter
                    .fill(Color(red: 0.898, green: 0.0, blue: 0.455))
                // Green quarter — bottom-right
                YingaPath.greenQuarter
                    .fill(Color(red: 0.0, green: 0.635, blue: 0.310))
                // Blue quarter — bottom-left
                YingaPath.blueQuarter
                    .fill(Color(red: 0.0, green: 0.482, blue: 0.769))
                // Wordmark "yinga" in magenta
                YingaPath.wordmark
                    .fill(Color(red: 0.898, green: 0.0, blue: 0.455))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: xOffset)
        }
        .aspectRatio(400.42 / 171.77, contentMode: .fit)
    }
}

// SVG path data for the Yinga logo, extracted from the official SVG.
private enum YingaPath {
    // Spinner: orange (top-right)
    static var orangeQuarter: Path {
        Path { p in
            p.move(to: CGPoint(x: 370.22, y: 22.26))
            p.addCurve(to: CGPoint(x: 378.15, y: 30.19), control1: CGPoint(x: 373.84, y: 23.68), control2: CGPoint(x: 376.73, y: 26.57))
            p.addCurve(to: CGPoint(x: 380.27, y: 31.64), control1: CGPoint(x: 378.49, y: 31.06), control2: CGPoint(x: 379.33, y: 31.64))
            p.addLine(to: CGPoint(x: 398.12, y: 31.64))
            p.addCurve(to: CGPoint(x: 400.38, y: 28.97), control1: CGPoint(x: 399.54, y: 31.64), control2: CGPoint(x: 400.63, y: 30.25))
            p.addCurve(to: CGPoint(x: 371.45, y: 0.04), control1: CGPoint(x: 397.76, y: 14.28), control2: CGPoint(x: 386.14, y: 2.66))
            p.addCurve(to: CGPoint(x: 368.78, y: 2.30), control1: CGPoint(x: 370.06, y: -0.21), control2: CGPoint(x: 368.78, y: 0.88))
            p.addLine(to: CGPoint(x: 368.78, y: 20.15))
            p.addCurve(to: CGPoint(x: 370.22, y: 22.26), control1: CGPoint(x: 368.78, y: 21.09), control2: CGPoint(x: 369.36, y: 21.93))
            p.closeSubpath()
        }
    }

    // Spinner: magenta (top-left)
    static var magentaQuarter: Path {
        Path { p in
            p.move(to: CGPoint(x: 352.13, y: 30.19))
            p.addCurve(to: CGPoint(x: 360.06, y: 22.26), control1: CGPoint(x: 353.55, y: 26.57), control2: CGPoint(x: 356.44, y: 23.68))
            p.addCurve(to: CGPoint(x: 361.51, y: 20.14), control1: CGPoint(x: 360.93, y: 21.92), control2: CGPoint(x: 361.51, y: 21.08))
            p.addLine(to: CGPoint(x: 361.51, y: 2.30))
            p.addCurve(to: CGPoint(x: 358.84, y: 0.04), control1: CGPoint(x: 361.51, y: 0.88), control2: CGPoint(x: 360.23, y: -0.21))
            p.addCurve(to: CGPoint(x: 329.91, y: 28.97), control1: CGPoint(x: 344.15, y: 2.66), control2: CGPoint(x: 332.53, y: 14.28))
            p.addCurve(to: CGPoint(x: 332.17, y: 31.64), control1: CGPoint(x: 329.66, y: 30.36), control2: CGPoint(x: 330.76, y: 31.64))
            p.addLine(to: CGPoint(x: 350.02, y: 31.64))
            p.addCurve(to: CGPoint(x: 352.13, y: 30.19), control1: CGPoint(x: 350.96, y: 31.64), control2: CGPoint(x: 351.80, y: 31.06))
            p.closeSubpath()
        }
    }

    // Spinner: green (bottom-right)
    static var greenQuarter: Path {
        Path { p in
            p.move(to: CGPoint(x: 378.15, y: 40.36))
            p.addCurve(to: CGPoint(x: 370.22, y: 48.29), control1: CGPoint(x: 376.73, y: 43.98), control2: CGPoint(x: 373.84, y: 46.87))
            p.addCurve(to: CGPoint(x: 368.77, y: 50.41), control1: CGPoint(x: 369.35, y: 48.63), control2: CGPoint(x: 368.77, y: 49.47))
            p.addLine(to: CGPoint(x: 368.77, y: 68.26))
            p.addCurve(to: CGPoint(x: 371.44, y: 70.52), control1: CGPoint(x: 368.77, y: 69.68), control2: CGPoint(x: 370.05, y: 70.77))
            p.addCurve(to: CGPoint(x: 400.37, y: 41.59), control1: CGPoint(x: 386.13, y: 67.90), control2: CGPoint(x: 397.75, y: 56.28))
            p.addCurve(to: CGPoint(x: 398.11, y: 38.92), control1: CGPoint(x: 400.62, y: 40.20), control2: CGPoint(x: 399.52, y: 38.92))
            p.addLine(to: CGPoint(x: 380.26, y: 38.92))
            p.addCurve(to: CGPoint(x: 378.15, y: 40.36), control1: CGPoint(x: 379.32, y: 38.92), control2: CGPoint(x: 378.48, y: 39.50))
            p.closeSubpath()
        }
    }

    // Spinner: blue (bottom-left)
    static var blueQuarter: Path {
        Path { p in
            p.move(to: CGPoint(x: 360.06, y: 48.29))
            p.addCurve(to: CGPoint(x: 352.13, y: 40.36), control1: CGPoint(x: 356.44, y: 46.87), control2: CGPoint(x: 353.55, y: 43.98))
            p.addCurve(to: CGPoint(x: 350.01, y: 38.91), control1: CGPoint(x: 351.79, y: 39.49), control2: CGPoint(x: 350.95, y: 38.91))
            p.addLine(to: CGPoint(x: 332.16, y: 38.91))
            p.addCurve(to: CGPoint(x: 329.90, y: 41.58), control1: CGPoint(x: 330.74, y: 38.91), control2: CGPoint(x: 329.65, y: 40.19))
            p.addCurve(to: CGPoint(x: 358.83, y: 70.51), control1: CGPoint(x: 332.52, y: 56.27), control2: CGPoint(x: 344.14, y: 67.89))
            p.addCurve(to: CGPoint(x: 361.50, y: 68.25), control1: CGPoint(x: 360.22, y: 70.76), control2: CGPoint(x: 361.50, y: 69.67))
            p.addLine(to: CGPoint(x: 361.50, y: 50.40))
            p.addCurve(to: CGPoint(x: 360.06, y: 48.29), control1: CGPoint(x: 361.50, y: 49.46), control2: CGPoint(x: 360.92, y: 48.63))
            p.closeSubpath()
        }
    }

    // Wordmark "yinga" — all letter paths combined
    static var wordmark: Path {
        Path { p in
            // Letter "y" (with descender)
            p.move(to: CGPoint(x: 59.09, y: 137.38))
            p.addLine(to: CGPoint(x: 59.09, y: 71.88))
            p.addCurve(to: CGPoint(x: 52.46, y: 65.25), control1: CGPoint(x: 59.09, y: 68.22), control2: CGPoint(x: 56.12, y: 65.25))
            p.addCurve(to: CGPoint(x: 45.83, y: 71.88), control1: CGPoint(x: 48.80, y: 65.25), control2: CGPoint(x: 45.83, y: 68.22))
            p.addLine(to: CGPoint(x: 45.83, y: 112.84))
            p.addCurve(to: CGPoint(x: 29.54, y: 132.16), control1: CGPoint(x: 45.83, y: 125.78), control2: CGPoint(x: 40.40, y: 132.16))
            p.addCurve(to: CGPoint(x: 13.25, y: 112.84), control1: CGPoint(x: 18.68, y: 132.16), control2: CGPoint(x: 13.25, y: 125.78))
            p.addLine(to: CGPoint(x: 13.25, y: 71.88))
            p.addCurve(to: CGPoint(x: 6.62, y: 65.25), control1: CGPoint(x: 13.25, y: 68.22), control2: CGPoint(x: 10.28, y: 65.25))
            p.addCurve(to: CGPoint(x: 0, y: 71.88), control1: CGPoint(x: 2.96, y: 65.25), control2: CGPoint(x: 0, y: 68.22))
            p.addLine(to: CGPoint(x: 0, y: 114.12))
            p.addCurve(to: CGPoint(x: 26.99, y: 143.66), control1: CGPoint(x: 0, y: 133.44), control2: CGPoint(x: 9.42, y: 143.66))
            p.addCurve(to: CGPoint(x: 45.52, y: 135.84), control1: CGPoint(x: 35.14, y: 143.66), control2: CGPoint(x: 41.53, y: 141.10))
            p.addLine(to: CGPoint(x: 45.84, y: 135.84))
            p.addLine(to: CGPoint(x: 45.84, y: 137.41))
            p.addLine(to: CGPoint(x: 45.84, y: 146.21))
            p.addCurve(to: CGPoint(x: 33.06, y: 160.26), control1: CGPoint(x: 45.84, y: 155.47), control2: CGPoint(x: 41.37, y: 160.26))
            p.addCurve(to: CGPoint(x: 25.07, y: 158.35), control1: CGPoint(x: 30.02, y: 160.26), control2: CGPoint(x: 27.47, y: 159.62))
            p.addCurve(to: CGPoint(x: 23.56, y: 157.81), control1: CGPoint(x: 24.52, y: 158.05), control2: CGPoint(x: 24.07, y: 157.81))
            p.addCurve(to: CGPoint(x: 17.85, y: 159.50), control1: CGPoint(x: 21.50, y: 157.26), control2: CGPoint(x: 19.28, y: 157.81))
            p.addLine(to: CGPoint(x: 17.83, y: 159.52))
            p.addCurve(to: CGPoint(x: 19.32, y: 167.92), control1: CGPoint(x: 15.60, y: 162.17), control2: CGPoint(x: 16.41, y: 165.62))
            p.addCurve(to: CGPoint(x: 20.43, y: 168.73), control1: CGPoint(x: 19.32, y: 167.92), control2: CGPoint(x: 19.98, y: 168.46))
            p.addCurve(to: CGPoint(x: 34.49, y: 171.77), control1: CGPoint(x: 23.95, y: 170.65), control2: CGPoint(x: 28.58, y: 171.77))
            p.addCurve(to: CGPoint(x: 59.09, y: 146.53), control1: CGPoint(x: 50.78, y: 171.77), control2: CGPoint(x: 59.09, y: 163.14))
            p.addLine(to: CGPoint(x: 59.09, y: 137.41))
            p.addLine(to: CGPoint(x: 59.09, y: 137.38))
            p.closeSubpath()

            // Letter "i" dot
            p.move(to: CGPoint(x: 78.94, y: 43.66))
            p.addCurve(to: CGPoint(x: 88.70, y: 33.89), control1: CGPoint(x: 78.13, y: 37.42), control2: CGPoint(x: 82.67, y: 32.97))
            p.addCurve(to: CGPoint(x: 95.49, y: 40.68), control1: CGPoint(x: 92.17, y: 34.42), control2: CGPoint(x: 94.97, y: 37.21))
            p.addCurve(to: CGPoint(x: 85.72, y: 50.44), control1: CGPoint(x: 96.41, y: 46.72), control2: CGPoint(x: 91.96, y: 51.26))
            p.addCurve(to: CGPoint(x: 78.94, y: 43.66), control1: CGPoint(x: 82.21, y: 49.98), control2: CGPoint(x: 79.39, y: 47.17))
            p.closeSubpath()

            // Letter "i" stem
            p.move(to: CGPoint(x: 80.60, y: 137.66))
            p.addLine(to: CGPoint(x: 87.23, y: 137.66))
            p.addCurve(to: CGPoint(x: 93.86, y: 131.03), control1: CGPoint(x: 90.89, y: 137.66), control2: CGPoint(x: 93.86, y: 134.69))
            p.addLine(to: CGPoint(x: 93.86, y: 65.23))
            p.addCurve(to: CGPoint(x: 87.23, y: 58.60), control1: CGPoint(x: 93.86, y: 61.57), control2: CGPoint(x: 90.89, y: 58.60))
            p.addLine(to: CGPoint(x: 87.23, y: 58.60))
            p.addCurve(to: CGPoint(x: 80.60, y: 65.23), control1: CGPoint(x: 83.57, y: 58.60), control2: CGPoint(x: 80.60, y: 61.57))
            p.addLine(to: CGPoint(x: 80.60, y: 131.03))
            p.addCurve(to: CGPoint(x: 87.23, y: 137.66), control1: CGPoint(x: 80.60, y: 134.69), control2: CGPoint(x: 83.57, y: 137.66))
            p.closeSubpath()

            // Letter "n"
            p.move(to: CGPoint(x: 160.29, y: 94.30))
            p.addCurve(to: CGPoint(x: 144.00, y: 74.82), control1: CGPoint(x: 160.29, y: 80.89), control2: CGPoint(x: 155.18, y: 74.82))
            p.addCurve(to: CGPoint(x: 127.71, y: 94.30), control1: CGPoint(x: 132.82, y: 74.82), control2: CGPoint(x: 127.71, y: 80.89))
            p.addLine(to: CGPoint(x: 127.71, y: 137.66))
            p.addCurve(to: CGPoint(x: 121.08, y: 144.29), control1: CGPoint(x: 127.71, y: 141.32), control2: CGPoint(x: 124.74, y: 144.29))
            p.addLine(to: CGPoint(x: 121.08, y: 144.29))
            p.addCurve(to: CGPoint(x: 114.45, y: 137.66), control1: CGPoint(x: 117.42, y: 144.29), control2: CGPoint(x: 114.45, y: 141.32))
            p.addLine(to: CGPoint(x: 114.45, y: 92.96))
            p.addCurve(to: CGPoint(x: 144.13, y: 63.32), control1: CGPoint(x: 114.45, y: 73.70), control2: CGPoint(x: 127.75, y: 63.27))
            p.addCurve(to: CGPoint(x: 173.54, y: 92.87), control1: CGPoint(x: 163.21, y: 63.37), control2: CGPoint(x: 173.54, y: 73.75))
            p.addLine(to: CGPoint(x: 173.54, y: 137.67))
            p.addCurve(to: CGPoint(x: 166.91, y: 144.30), control1: CGPoint(x: 173.54, y: 141.33), control2: CGPoint(x: 170.57, y: 144.30))
            p.addLine(to: CGPoint(x: 166.91, y: 144.30))
            p.addCurve(to: CGPoint(x: 160.28, y: 137.67), control1: CGPoint(x: 163.25, y: 144.30), control2: CGPoint(x: 160.28, y: 141.33))
            p.addLine(to: CGPoint(x: 160.29, y: 94.30))
            p.closeSubpath()

            // Letter "g" (with descender)
            p.move(to: CGPoint(x: 251.48, y: 93.52))
            p.addLine(to: CGPoint(x: 251.48, y: 143.51))
            p.addCurve(to: CGPoint(x: 221.46, y: 171.78), control1: CGPoint(x: 251.48, y: 161.08), control2: CGPoint(x: 240.14, y: 171.78))
            p.addCurve(to: CGPoint(x: 195.59, y: 163.00), control1: CGPoint(x: 210.92, y: 171.78), control2: CGPoint(x: 202.14, y: 168.75))
            p.addCurve(to: CGPoint(x: 202.30, y: 153.90), control1: CGPoint(x: 189.45, y: 158.48), control2: CGPoint(x: 195.73, y: 149.27))
            p.addCurve(to: CGPoint(x: 220.67, y: 160.29), control1: CGPoint(x: 207.57, y: 158.21), control2: CGPoint(x: 213.48, y: 160.29))
            p.addCurve(to: CGPoint(x: 238.24, y: 142.56), control1: CGPoint(x: 232.17, y: 160.29), control2: CGPoint(x: 238.24, y: 153.55))
            p.addLine(to: CGPoint(x: 238.24, y: 135.69))
            p.addLine(to: CGPoint(x: 237.92, y: 135.69))
            p.addCurve(to: CGPoint(x: 219.24, y: 143.67), control1: CGPoint(x: 233.93, y: 140.96), control2: CGPoint(x: 227.54, y: 143.67))
            p.addCurve(to: CGPoint(x: 191.29, y: 113.49), control1: CGPoint(x: 201.03, y: 143.67), control2: CGPoint(x: 191.29, y: 134.03))
            p.addLine(to: CGPoint(x: 191.29, y: 93.53))
            p.addCurve(to: CGPoint(x: 221.98, y: 63.35), control1: CGPoint(x: 191.29, y: 73.66), control2: CGPoint(x: 202.07, y: 63.17))
            p.addCurve(to: CGPoint(x: 251.50, y: 93.53), control1: CGPoint(x: 238.39, y: 63.55), control2: CGPoint(x: 251.50, y: 77.12))
            p.closeSubpath()
            // "g" inner counter
            p.move(to: CGPoint(x: 238.22, y: 112.05))
            p.addLine(to: CGPoint(x: 238.22, y: 94.80))
            p.addCurve(to: CGPoint(x: 221.29, y: 74.84), control1: CGPoint(x: 238.22, y: 81.22), control2: CGPoint(x: 232.95, y: 74.84))
            p.addCurve(to: CGPoint(x: 204.52, y: 94.80), control1: CGPoint(x: 209.63, y: 74.84), control2: CGPoint(x: 204.52, y: 81.22))
            p.addLine(to: CGPoint(x: 204.52, y: 112.05))
            p.addCurve(to: CGPoint(x: 221.29, y: 132.17), control1: CGPoint(x: 204.52, y: 125.78), control2: CGPoint(x: 209.79, y: 132.17))
            p.addCurve(to: CGPoint(x: 238.22, y: 112.05), control1: CGPoint(x: 232.95, y: 132.17), control2: CGPoint(x: 238.22, y: 125.46))
            p.closeSubpath()

            // Letter "a"
            p.move(to: CGPoint(x: 326.38, y: 94.30))
            p.addLine(to: CGPoint(x: 326.38, y: 116.02))
            p.addCurve(to: CGPoint(x: 296.04, y: 146.20), control1: CGPoint(x: 326.38, y: 135.66), control2: CGPoint(x: 315.84, y: 146.20))
            p.addCurve(to: CGPoint(x: 267.45, y: 121.61), control1: CGPoint(x: 277.67, y: 146.20), control2: CGPoint(x: 267.45, y: 137.26))
            p.addCurve(to: CGPoint(x: 295.88, y: 97.49), control1: CGPoint(x: 267.45, y: 106.02), control2: CGPoint(x: 277.51, y: 97.49))
            p.addLine(to: CGPoint(x: 313.13, y: 97.49))
            p.addLine(to: CGPoint(x: 313.13, y: 95.57))
            p.addCurve(to: CGPoint(x: 294.92, y: 74.81), control1: CGPoint(x: 313.13, y: 81.04), control2: CGPoint(x: 307.22, y: 74.81))
            p.addCurve(to: CGPoint(x: 279.11, y: 80.88), control1: CGPoint(x: 289.01, y: 74.81), control2: CGPoint(x: 283.42, y: 77.21))
            p.addCurve(to: CGPoint(x: 271.92, y: 71.62), control1: CGPoint(x: 272.96, y: 85.65), control2: CGPoint(x: 265.77, y: 76.13))
            p.addCurve(to: CGPoint(x: 296.04, y: 63.31), control1: CGPoint(x: 278.79, y: 66.03), control2: CGPoint(x: 286.77, y: 63.31))
            p.addCurve(to: CGPoint(x: 326.38, y: 94.29), control1: CGPoint(x: 315.68, y: 63.31), control2: CGPoint(x: 326.38, y: 73.85))
            p.closeSubpath()
            // "a" inner counter
            p.move(to: CGPoint(x: 313.13, y: 114.74))
            p.addLine(to: CGPoint(x: 313.13, y: 108.51))
            p.addLine(to: CGPoint(x: 297.48, y: 108.51))
            p.addCurve(to: CGPoint(x: 280.71, y: 121.77), control1: CGPoint(x: 286.94, y: 108.51), control2: CGPoint(x: 280.71, y: 112.98))
            p.addCurve(to: CGPoint(x: 296.04, y: 134.71), control1: CGPoint(x: 280.71, y: 130.50), control2: CGPoint(x: 286.30, y: 134.71))
            p.addCurve(to: CGPoint(x: 313.13, y: 114.75), control1: CGPoint(x: 307.70, y: 134.71), control2: CGPoint(x: 313.13, y: 128.32))
            p.closeSubpath()
        }
    }
}

/// "Developed by [Yinga logo]" footer for consistent branding across the app.
/// On macOS shown in all views; on iOS only on LoginView.
struct YingaFooter: View {
    var body: some View {
        HStack(spacing: TS.Spacing.sm) {
            Text("Developed by")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)

            YingaLogo()
                .frame(height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, TS.Spacing.sm)
    }
}

/// Animated pulsing dot used as a recording indicator.
/// Honours Reduce Motion: when enabled the expanding ring is dropped and a
/// static solid dot remains as the recording indicator (WCAG 2.3.3).
struct PulsingRecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(Color.statusError.opacity(0.3))
                    .frame(width: size * 2.2, height: size * 2.2)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }
            Circle()
                .fill(Color.statusError)
                .frame(width: size, height: size)
        }
        .onAppear { if !reduceMotion { isPulsing = true } }
    }
}
