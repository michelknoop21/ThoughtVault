// Theme.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Centralized design token system. All spacing, radii, typography,
// and animations live here under the TS namespace.

import SwiftUI

// MARK: - TS Namespace

/// Top-level namespace for all ThoughtVault design tokens.
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

    func body(content: Content) -> some View {
        // Mockup panel: dark indigo glass, violet hairline, hover lifts the glow.
        content
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                    .fill(Color.cardDark.opacity(0.62))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
                    .shadow(
                        color: isHovered ? Color.brandPrimaryDark.opacity(0.35) : Color.black.opacity(0.30),
                        radius: isHovered ? 20 : 14,
                        y: 6
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? AnyShapeStyle(Color.brandPrimary.opacity(0.40))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color.brandLavender.opacity(0.16), Color.brandPrimary.opacity(0.08)],
                                startPoint: .top, endPoint: .bottom)),
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
    @Environment(\.isEnabled) private var isEnabled
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
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.45)
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
/// ThoughtVault brand bar: the logo's lavender → violet → indigo gradient.
struct BrandBar: View {
    var height: CGFloat = 3

    var body: some View {
        LinearGradient(
            colors: [Color.brandLavender, Color.brandPrimary, Color.brandSecondary],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
    }
}

/// "Developed by Yinga" footer for consistent branding across the app.
/// On macOS shown in all views; on iOS only on LoginView.
struct BrandFooter: View {
    var body: some View {
        HStack(spacing: TS.Spacing.xs) {
            Text("Developed by")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)

            Image("YingaLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 18)
                .accessibilityLabel("Yinga")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, TS.Spacing.sm)
    }
}

// MARK: - Vault Panel (mockup card style)

/// Glass panel from the approved mockup: dark indigo fill, violet hairline,
/// subtle inner top-highlight. Replaces ad-hoc `.ultraThinMaterial` cards.
struct VaultPanelModifier: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.cardDark.opacity(0.62))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.brandLavender.opacity(0.16), Color.brandPrimary.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.30), radius: 14, y: 6)
    }
}

extension View {
    /// Mockup-style dark glass panel.
    func vaultPanel(radius: CGFloat = 14) -> some View {
        modifier(VaultPanelModifier(radius: radius))
    }
}

/// Section heading with the vertical lavender→indigo accent bar from the mockup.
struct VaultSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color.brandLavender, Color.brandSecondary],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 15)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.labelPrimary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(TS.Font.captionSemibold)
                        .foregroundStyle(Color.brandLink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Small status chip (mockup: "Afgerond" / "Notule wordt geschreven…").
struct VaultChip: View {
    enum Tone { case ok, busy, neutral, warning }
    let text: String
    var tone: Tone = .neutral

    private var color: Color {
        switch tone {
        case .ok:      return Color.statusSuccess
        case .busy:    return Color.brandLink
        case .warning: return Color.statusWarning
        case .neutral: return Color.labelSecondary
        }
    }

    var body: some View {
        Text(text)
            .font(TS.Font.microBold)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(color.opacity(0.13)))
            .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
            .lineLimit(1)
    }
}

/// Violet gradient icon tile (mockup: document icon in recent-list rows).
struct VaultIconTile: View {
    let systemName: String
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [Color.brandPrimary.opacity(0.22), Color.brandSecondary.opacity(0.12)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.brandPrimary.opacity(0.22), lineWidth: 1)
            }
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(Color.brandLavender)
            }
            .frame(width: size, height: size)
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

// MARK: - Shared state components

/// Consistent empty state built on Apple's `ContentUnavailableView`, styled with
/// the brand accent. Replaces the ad-hoc empty states scattered across views.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .foregroundStyle(Color.labelPrimary)
        } description: {
            if let message {
                Text(message)
                    .foregroundStyle(Color.labelSecondary)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.map { "\(title). \($0)" } ?? title)
    }
}

/// Redacted placeholder shimmer for loading states. Apply to a laid-out
/// placeholder view: `PlaceholderRow().loadingSkeleton(isLoading)`.
private struct LoadingSkeletonModifier: ViewModifier {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    func body(content: Content) -> some View {
        content
            .redacted(reason: isLoading ? .placeholder : [])
            .opacity(isLoading && !reduceMotion ? (shimmer ? 0.55 : 1.0) : 1.0)
            .animation(
                isLoading && !reduceMotion
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: shimmer
            )
            .onAppear { if isLoading && !reduceMotion { shimmer = true } }
            .accessibilityHidden(isLoading)
    }
}

extension View {
    /// Redacted shimmer while `isLoading`; restores normally when false.
    func loadingSkeleton(_ isLoading: Bool) -> some View {
        modifier(LoadingSkeletonModifier(isLoading: isLoading))
    }
}
