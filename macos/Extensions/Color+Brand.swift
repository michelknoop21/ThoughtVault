// Color+Brand.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Yinga brand color palette with adaptive light/dark mode support.

import SwiftUI

// MARK: - Adaptive Color Initializer

extension Color {
    /// Creates a color that automatically switches between a light and dark variant
    /// based on the current system appearance, using platform-specific APIs.
    init(light lightColor: Color, dark darkColor: Color) {
        #if os(macOS)
        self = Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(darkColor)
                : NSColor(lightColor)
        })
        #else
        self = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(darkColor)
                : UIColor(lightColor)
        })
        #endif
    }
}

// MARK: - Brand Colors

extension Color {

    // MARK: Yinga Brand (static)

    /// Yinga primary — magenta #E50074
    static let brandPrimary = Color(red: 0.898, green: 0.0, blue: 0.455)

    /// Yinga secondary — blue #007BC4
    static let brandSecondary = Color(red: 0.0, green: 0.482, blue: 0.769)

    /// Yinga accent — green #009F3C
    static let brandAccent = Color(red: 0.0, green: 0.624, blue: 0.235)

    /// Yinga orange #F39200
    static let brandOrange = Color(red: 0.953, green: 0.573, blue: 0.0)

    /// Darker magenta variant for hero gradients (HomeView hero card)
    static let brandPrimaryDark = Color(red: 0.72, green: 0.0, blue: 0.38)

    /// Neon blue used in waveform visualizations #00C2FF
    static let neonBlue = Color(red: 0.0, green: 0.761, blue: 1.0)

    // MARK: Dark backgrounds (static, optimized for Dynamic Island)

    /// Very dark background #0B0C15
    static let backgroundDark = Color(red: 0.043, green: 0.047, blue: 0.082)

    /// Dark card background #1A1C29
    static let cardDark = Color(red: 0.102, green: 0.110, blue: 0.161)

    // MARK: Adaptive Surface Colors

    /// Primary surface — white in light, very dark blue-gray in dark mode.
    static let surfacePrimary = Color(
        light: Color(red: 1.0,   green: 1.0,   blue: 1.0),
        dark:  Color(red: 0.10,  green: 0.11,  blue: 0.16)
    )

    /// Secondary surface — light gray in light, dark in dark mode.
    static let surfaceSecondary = Color(
        light: Color(red: 0.96,  green: 0.96,  blue: 0.97),
        dark:  Color(red: 0.13,  green: 0.14,  blue: 0.20)
    )

    /// Tertiary surface — slightly darker in light, deepest in dark mode.
    static let surfaceTertiary = Color(
        light: Color(red: 0.92,  green: 0.92,  blue: 0.94),
        dark:  Color(red: 0.16,  green: 0.17,  blue: 0.24)
    )

    // MARK: Adaptive Label Colors

    /// Primary label — near black in light, near white in dark mode.
    static let labelPrimary = Color(
        light: Color(red: 0.20,  green: 0.20,  blue: 0.23),
        dark:  Color(red: 0.95,  green: 0.95,  blue: 0.97)
    )

    /// Secondary label — medium gray in light, lighter gray in dark mode.
    static let labelSecondary = Color(
        light: Color(red: 0.42,  green: 0.42,  blue: 0.47),
        dark:  Color(red: 0.62,  green: 0.62,  blue: 0.68)
    )

    /// Tertiary label — lighter gray in light, subtle in dark mode.
    static let labelTertiary = Color(
        light: Color(red: 0.60,  green: 0.60,  blue: 0.65),
        dark:  Color(red: 0.42,  green: 0.42,  blue: 0.48)
    )

    // MARK: Adaptive Accent Backgrounds

    /// Subtle magenta tint background.
    static let accentBgPrimary = Color(
        light: Color(red: 1.0,  green: 0.90,  blue: 0.95),
        dark:  Color(red: 0.25, green: 0.05,  blue: 0.15)
    )

    /// Subtle blue tint background.
    static let accentBgSecondary = Color(
        light: Color(red: 0.88, green: 0.94,  blue: 1.0),
        dark:  Color(red: 0.05, green: 0.15,  blue: 0.28)
    )

    /// Subtle green tint background.
    static let accentBgAccent = Color(
        light: Color(red: 0.88, green: 0.97,  blue: 0.91),
        dark:  Color(red: 0.04, green: 0.20,  blue: 0.10)
    )

    /// Subtle orange tint background.
    static let accentBgOrange = Color(
        light: Color(red: 1.0,  green: 0.95,  blue: 0.88),
        dark:  Color(red: 0.25, green: 0.15,  blue: 0.02)
    )

    // MARK: Adaptive Borders

    /// Primary border — subtle gray dividers.
    static let borderPrimary = Color(
        light: Color(red: 0.88, green: 0.88, blue: 0.90),
        dark:  Color(red: 0.22, green: 0.23, blue: 0.30)
    )

    /// Secondary border — even subtler.
    static let borderSecondary = Color(
        light: Color(red: 0.93, green: 0.93, blue: 0.95),
        dark:  Color(red: 0.17, green: 0.18, blue: 0.25)
    )

    // MARK: Status Colors
    //
    // Two tiers per status:
    //  - the vivid color (`statusX`) for icons/indicators — graphical objects, 3:1 bar;
    //  - a darker `statusXText` for text on a light tint / dark surface — 4.5:1 bar.
    // Both are theme-adaptive so contrast holds in dark mode (see PRODUCT.md a11y bar).

    /// Error / danger — vivid, for icons & indicators (#EF4444 light).
    static let statusError = Color(
        light: Color(red: 0.937, green: 0.267, blue: 0.267),
        dark:  Color(red: 0.980, green: 0.450, blue: 0.450)
    )

    /// Warning — vivid amber, for icons & indicators (#F9A500 light).
    static let statusWarning = Color(
        light: Color(red: 0.976, green: 0.647, blue: 0.0),
        dark:  Color(red: 1.0,   green: 0.780, blue: 0.300)
    )

    /// Success — vivid green, for icons & indicators (#009F3C light).
    static let statusSuccess = Color(
        light: Color(red: 0.0,  green: 0.624, blue: 0.235),
        dark:  Color(red: 0.300, green: 0.820, blue: 0.500)
    )

    /// Error text — AA-passing on a light tint / dark surface.
    static let statusErrorText = Color(
        light: Color(red: 0.700, green: 0.120, blue: 0.120),
        dark:  Color(red: 0.980, green: 0.560, blue: 0.560)
    )

    /// Warning text — dark amber, AA-passing (amber must go deep to read).
    static let statusWarningText = Color(
        light: Color(red: 0.500, green: 0.330, blue: 0.0),
        dark:  Color(red: 1.0,   green: 0.820, blue: 0.420)
    )

    /// Success text — deep green, AA-passing.
    static let statusSuccessText = Color(
        light: Color(red: 0.0,  green: 0.420, blue: 0.180),
        dark:  Color(red: 0.450, green: 0.850, blue: 0.580)
    )

    /// Info / in-progress text — dark blue, AA-passing (active badge text).
    static let statusInfoText = Color(
        light: Color(red: 0.040, green: 0.360, blue: 0.540),
        dark:  Color(red: 0.520, green: 0.780, blue: 0.980)
    )

    // MARK: Platform Brand Colors (for calendar integrations)

    /// Microsoft Teams — purple
    static let platformTeams = Color(red: 0.290, green: 0.208, blue: 0.690)

    /// Zoom — blue
    static let platformZoom = Color(red: 0.176, green: 0.549, blue: 1.0)

    /// Google Meet — teal
    static let platformMeet = Color(red: 0.0, green: 0.620, blue: 0.451)

    // MARK: Onboarding Gradient Colors (light pastels)

    static let gradientPurple = Color(red: 0.85, green: 0.80, blue: 1.00)
    static let gradientBlue   = Color(red: 0.78, green: 0.90, blue: 1.00)
    static let gradientGreen  = Color(red: 0.80, green: 0.97, blue: 0.86)
    static let gradientOrange = Color(red: 1.00, green: 0.93, blue: 0.78)

    // MARK: Adaptive Code Viewer Backgrounds

    /// Subtle code block background.
    static let codeBackground = Color(
        light: Color(red: 0.95, green: 0.95, blue: 0.96),
        dark:  Color(red: 0.12, green: 0.13, blue: 0.18)
    )

    /// Deeper code block background for nested elements.
    static let codeBackgroundDeep = Color(
        light: Color(red: 0.90, green: 0.90, blue: 0.92),
        dark:  Color(red: 0.09, green: 0.10, blue: 0.15)
    )
}

// MARK: - ShapeStyle Convenience Extensions

extension ShapeStyle where Self == Color {
    static var brandPrimary: Color    { .brandPrimary }
    static var brandSecondary: Color  { .brandSecondary }
    static var brandAccent: Color     { .brandAccent }
    static var brandOrange: Color     { .brandOrange }
    static var neonBlue: Color        { .neonBlue }
    static var surfacePrimary: Color  { .surfacePrimary }
    static var labelPrimary: Color    { .labelPrimary }
    static var labelSecondary: Color  { .labelSecondary }
    static var statusError: Color     { .statusError }
    static var statusSuccess: Color   { .statusSuccess }
    static var statusWarning: Color   { .statusWarning }
}
