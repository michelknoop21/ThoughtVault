// IOSTheme.swift
// ThoughtVault
//
// Shared building blocks of the approved iOS NorthStar set
// (docs/design/ios/*-northstar.jpg, 2026-09-29): palette, night background,
// cards, icon tiles, list rows, the brand bar and the mountain illustration.
// Geometry is measured at a 402 pt wide iPhone (NorthStar px / 1.93).

#if os(iOS)
import SwiftUI

/// Colours sampled from the iOS NorthStar set.
enum IOSColor {
    static let background = Color(red: 0.031, green: 0.055, blue: 0.110)
    static let card = Color(red: 0.051, green: 0.067, blue: 0.133)
    static let cardRaised = Color(red: 0.067, green: 0.078, blue: 0.170)
    static let border = Color(red: 0.13, green: 0.15, blue: 0.27)
    static let borderViolet = Color(red: 0.26, green: 0.20, blue: 0.52)
    static let divider = Color(red: 0.11, green: 0.13, blue: 0.23)
    static let control = Color(red: 0.090, green: 0.110, blue: 0.196)
    static let tile = Color(red: 0.141, green: 0.102, blue: 0.306)
    static let tileBlue = Color(red: 0.098, green: 0.165, blue: 0.333)
    static let tileRed = Color(red: 0.26, green: 0.10, blue: 0.16)
    static let tileGreen = Color(red: 0.07, green: 0.20, blue: 0.17)
    static let text = Color(red: 0.94, green: 0.94, blue: 0.98)
    static let text2 = Color(red: 0.70, green: 0.72, blue: 0.84)
    static let text3 = Color(red: 0.52, green: 0.55, blue: 0.68)
    static let kicker = Color(red: 0.62, green: 0.63, blue: 0.82)
    static let violet = Color(red: 0.55, green: 0.33, blue: 0.98)
    static let lavender = Color(red: 0.77, green: 0.50, blue: 0.95)
    static let link = Color(red: 0.66, green: 0.62, blue: 0.95)
    static let iconViolet = Color(red: 0.74, green: 0.50, blue: 1.0)
    static let iconBlue = Color(red: 0.40, green: 0.62, blue: 1.0)
    static let iconRed = Color(red: 0.96, green: 0.40, blue: 0.45)
    static let iconGreen = Color(red: 0.35, green: 0.85, blue: 0.62)
    static let ready = Color(red: 0.30, green: 0.85, blue: 0.47)
    static let warning = Color(red: 0.98, green: 0.72, blue: 0.30)
    static let danger = Color(red: 0.96, green: 0.42, blue: 0.42)
    /// Selected segment / primary button fill.
    static let accentGradient = LinearGradient(colors: [Color(red: 0.62, green: 0.34, blue: 1.0), Color(red: 0.45, green: 0.28, blue: 0.95)],
                                               startPoint: .leading, endPoint: .trailing)
    static let nameGradient = LinearGradient(colors: [Color(red: 0.80, green: 0.52, blue: 1.0), Color(red: 0.66, green: 0.40, blue: 0.97)],
                                             startPoint: .leading, endPoint: .trailing)
}

enum IOSMetric {
    static let gutter: CGFloat = 19
    static let radius: CGFloat = 14
}

// MARK: - Screenshot hooks

/// Debug-only launch arguments for simulator screenshots, where taps are not
/// available: `-TVDebugTab transcripts`, `-TVDebugOpen transcript`,
/// `-TVDebugBottom YES`. Release builds ignore them.
enum IOSDebug {
    static func string(_ key: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: key)
        #else
        return nil
        #endif
    }
    static var open: String? { string("TVDebugOpen") }
    static var scrollAnchor: UnitPoint { string("TVDebugBottom") == "YES" ? .bottom : .top }
}

// MARK: - Formatting

enum IOSFormat {
    private static let nl = Locale(identifier: "nl_NL")

    /// "Vandaag 14:00", "Gisteren 16:20", "12 aug 2026".
    static func day(_ date: Date, withTime: Bool = true) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(nl))
        let cal = Calendar.current
        if cal.isDateInToday(date) { return withTime ? "Vandaag \(time)" : "Vandaag" }
        if cal.isDateInYesterday(date) { return withTime ? "Gisteren \(time)" : "Gisteren" }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(nl)).replacingOccurrences(of: ".", with: "")
    }

    static func minutes(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "\(max(1, Int((seconds / 60).rounded()))) min"
    }

    /// "Vandaag 14:00 · 42 min"
    static func meta(_ date: Date, duration: Double?) -> String {
        [day(date), minutes(duration)].compactMap { $0 }.joined(separator: "  \u{00B7}  ")
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(nl))
    }
}

// MARK: - Background

/// Night-sky background: deep navy with a violet glow in the upper right.
struct IOSBackground: View {
    var glow: Double = 1
    var body: some View {
        ZStack {
            IOSColor.background
            RadialGradient(colors: [Color(red: 0.30, green: 0.16, blue: 0.62).opacity(0.45 * glow), .clear],
                           center: UnitPoint(x: 0.85, y: 0.02), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

struct IOSCardModifier: ViewModifier {
    var raised = false
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: IOSMetric.radius, style: .continuous)
                .fill(raised ? IOSColor.cardRaised : IOSColor.card))
            .overlay(RoundedRectangle(cornerRadius: IOSMetric.radius, style: .continuous)
                .strokeBorder(highlighted ? IOSColor.violet : (raised ? IOSColor.borderViolet.opacity(0.7) : IOSColor.border),
                              lineWidth: highlighted ? 1.5 : 1))
    }
}

extension View {
    func iosCard(raised: Bool = false, highlighted: Bool = false) -> some View {
        modifier(IOSCardModifier(raised: raised, highlighted: highlighted))
    }

    /// Standard screen chrome: night background, dark bars, no system title.
    func iosScreen() -> some View {
        defaultScrollAnchor(IOSDebug.scrollAnchor)
            .background(IOSBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
    }
}

/// Rounded square icon container used in every list.
struct IOSIconTile: View {
    enum Tint { case violet, blue, red, green }
    let systemName: String
    var tint: Tint = .violet
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .regular))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(background))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch tint {
        case .violet: return IOSColor.iconViolet
        case .blue: return IOSColor.iconBlue
        case .red: return IOSColor.iconRed
        case .green: return IOSColor.iconGreen
        }
    }

    private var background: Color {
        switch tint {
        case .violet: return IOSColor.tile
        case .blue: return IOSColor.tileBlue
        case .red: return IOSColor.tileRed
        case .green: return IOSColor.tileGreen
        }
    }
}

// MARK: - Text

struct IOSSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IOSColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension IOSSectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// "Alles bekijken >" style trailing link.
struct IOSLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(IOSColor.link)
        }
        .buttonStyle(.plain)
    }
}

/// Uppercase spaced kicker ("DINSDAG 29 SEPTEMBER", "OPNAME").
struct IOSKicker: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .kerning(1.8)
            .textCase(.uppercase)
            .foregroundStyle(IOSColor.kicker)
    }
}

/// Large screen title with optional subtitle ("Taken", "Instellingen").
struct IOSScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(IOSColor.text)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(IOSColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Brand bar

/// Logo, product name and the account button at the top of every tab root.
struct IOSBrandBar: View {
    var initials: String = ""
    var onAccount: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.84, green: 0.45, blue: 1), Color(red: 0.52, green: 0.28, blue: 0.96)],
                                                startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
            Text("ThoughtVault")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(IOSColor.text)
            Spacer(minLength: 0)
            if let onAccount {
                Button(action: onAccount) {
                    IOSAvatar(initials: initials, size: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account")
            }
        }
        .frame(height: 44)
    }
}

struct IOSAvatar: View {
    let initials: String
    var size: CGFloat = 36
    var body: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person").font(.system(size: size * 0.4))
            } else {
                Text(initials.uppercased()).font(.system(size: size * 0.4, weight: .medium))
            }
        }
        .foregroundStyle(IOSColor.text)
        .frame(width: size, height: size)
        .background(Circle().fill(Color(red: 0.13, green: 0.14, blue: 0.33)))
        .overlay(Circle().strokeBorder(Color(red: 0.30, green: 0.30, blue: 0.55).opacity(0.7), lineWidth: 1))
    }
}

extension TSUserInfo {
    /// Up to two initials from the name, else the first letter of the e-mail.
    var initials: String {
        let letters = (name ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(email.prefix(1)) : letters
    }
}

// MARK: - Rows

/// Settings-style row: icon tile, title, subtitle and a trailing accessory.
struct IOSRow<Accessory: View>: View {
    let icon: String
    var tint: IOSIconTile.Tint = .violet
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 16) {
            IOSIconTile(systemName: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IOSColor.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(IOSColor.text2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

struct IOSChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(IOSColor.text2)
            .accessibilityHidden(true)
    }
}

/// Card that stacks rows; put an `IOSDivider` between them.
struct IOSGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 2)
            .iosCard()
    }
}

/// Divider inset past the row's icon tile.
struct IOSDivider: View {
    var inset: CGFloat = 60
    var body: some View {
        Rectangle().fill(IOSColor.divider).frame(height: 1).padding(.leading, inset)
    }
}

// MARK: - Segmented control

/// Three-way switch with a violet gradient thumb (Taken, Notulen, Notule).
struct IOSSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String, icon: String?)]
    @Binding var selection: Value
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                if index > 0 && !selected && options[index - 1].value != selection {
                    Rectangle().fill(IOSColor.divider).frame(width: 1, height: height * 0.5)
                }
                Button { withAnimation(TS.Animation.quick) { selection = option.value } } label: {
                    HStack(spacing: 8) {
                        if let icon = option.icon { Image(systemName: icon).font(.system(size: 15)) }
                        Text(option.title).font(.system(size: 14.5, weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? .white : IOSColor.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: height - 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(IOSColor.accentGradient)
                                .shadow(color: IOSColor.violet.opacity(0.45), radius: 8)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IOSColor.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IOSColor.border, lineWidth: 1))
    }
}

// MARK: - Progress

struct IOSProgressRing: View {
    let progress: Double
    var size: CGFloat = 52
    var lineWidth: CGFloat = 5
    var showLabel = true

    var body: some View {
        ZStack {
            Circle().stroke(Color(red: 0.16, green: 0.15, blue: 0.33), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(LinearGradient(colors: [Color(red: 0.78, green: 0.45, blue: 1), Color(red: 0.45, green: 0.28, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(TS.Animation.smooth, value: progress)
            if showLabel {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: size * 0.26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(IOSColor.text)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Voortgang")
        .accessibilityValue("\(Int((progress * 100).rounded())) procent")
    }
}

// MARK: - Illustration

/// Mountains, moon and a glowing path winding up to the right. Decorative.
struct IOSNightIllustration: View {
    var showsMoon = true

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 220, sy = size.height / 110
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

            // Stars
            for (x, y) in [(40.0, 12.0), (96.0, 8.0), (150.0, 22.0), (62.0, 34.0), (190.0, 6.0), (120.0, 40.0)] {
                context.fill(Path(ellipseIn: CGRect(x: x * sx, y: y * sy, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.55)))
            }

            // Moon
            if showsMoon {
                var moon = context
            moon.addFilter(.shadow(color: Color(red: 0.70, green: 0.55, blue: 1.0).opacity(0.85), radius: 16))
            moon.fill(Path(ellipseIn: CGRect(x: 158 * sx, y: 22 * sy, width: 42 * sx, height: 42 * sx)),
                      with: .linearGradient(Gradient(colors: [Color(red: 0.95, green: 0.90, blue: 1.0), Color(red: 0.72, green: 0.60, blue: 0.98)]),
                                            startPoint: p(179, 22), endPoint: p(179, 64)))
            }

            // Back ridge
            var back = Path()
            back.move(to: p(0, 72))
            back.addCurve(to: p(70, 40), control1: p(25, 60), control2: p(50, 42))
            back.addCurve(to: p(130, 58), control1: p(92, 38), control2: p(110, 58))
            back.addCurve(to: p(200, 30), control1: p(160, 58), control2: p(180, 26))
            back.addCurve(to: p(220, 36), control1: p(208, 32), control2: p(214, 33))
            back.addLine(to: p(220, 110)); back.addLine(to: p(0, 110)); back.closeSubpath()
            context.fill(back, with: .linearGradient(Gradient(colors: [Color(red: 0.22, green: 0.17, blue: 0.45), Color(red: 0.07, green: 0.08, blue: 0.17).opacity(0.3)]),
                                                     startPoint: p(110, 30), endPoint: p(110, 110)))

            // Front ridge
            var front = Path()
            front.move(to: p(20, 110))
            front.addCurve(to: p(120, 70), control1: p(60, 96), control2: p(90, 72))
            front.addCurve(to: p(220, 62), control1: p(160, 68), control2: p(190, 58))
            front.addLine(to: p(220, 110)); front.closeSubpath()
            context.fill(front, with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.27), IOSColor.background.opacity(0.0)]),
                                                      startPoint: p(120, 66), endPoint: p(120, 110)))

            // Glowing path
            var path = Path()
            path.move(to: p(82, 108))
            path.addCurve(to: p(150, 84), control1: p(80, 96), control2: p(150, 98))
            path.addCurve(to: p(104, 72), control1: p(152, 76), control2: p(106, 80))
            path.addCurve(to: p(168, 64), control1: p(104, 66), control2: p(150, 68))
            var glow = context
            glow.addFilter(.shadow(color: Color(red: 0.85, green: 0.35, blue: 1.0).opacity(0.9), radius: 4))
            glow.stroke(path, with: .linearGradient(Gradient(colors: [Color(red: 0.80, green: 0.35, blue: 1.0), Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.25)]),
                                                    startPoint: p(82, 108), endPoint: p(168, 64)),
                        style: StrokeStyle(lineWidth: 1.6 * sx, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
#endif
