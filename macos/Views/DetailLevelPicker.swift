// DetailLevelPicker.swift
// ThoughtVault
//
// Segmented Kort / Normaal / Volledig picker with one explanation line per level (DEC-073).
// Used in the profile settings and in the regenerate sheet.

import SwiftUI

struct DetailLevelPicker: View {
    @Binding var level: NotuleDetailLevel

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Picker("Detailniveau", selection: $level) {
                ForEach(NotuleDetailLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ForEach(NotuleDetailLevel.allCases, id: \.self) { item in
                Text(item.explanation)
                    .font(TS.Font.caption)
                    .foregroundStyle(item == level ? Color.labelPrimary : Color.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The picker bound to the user's choice for `profile`, stored through `NotuleDetailLevel.choose`.
struct ProfileDetailLevelPicker: View {
    let profile: Profile
    @State private var level: NotuleDetailLevel

    init(profile: Profile) {
        self.profile = profile
        _level = State(initialValue: NotuleDetailLevel.effective(for: profile))
    }

    var body: some View {
        DetailLevelPicker(level: $level)
            .onChange(of: level) { _, new in NotuleDetailLevel.choose(new, for: profile) }
    }
}

extension NotuleDetailLevel {
    var title: LocalizedStringKey {
        switch self {
        case .kort: "Kort"
        case .normaal: "Normaal"
        case .volledig: "Volledig"
        }
    }

    /// One line per level, taken from the prompt rules above (kortBlock, normaalBlock, targetLength).
    var explanation: LocalizedStringKey {
        switch self {
        case .kort: "Kort: besluiten, acties en bedragen; ongeveer 6% van het gesprek, 1.500 tot 4.000 tekens"
        case .normaal: "Normaal: ook één of twee zinnen context per onderwerp; ongeveer 15%, 2.500 tot 8.000 tekens"
        case .volledig: "Volledig: elke bronzin uit het gesprek komt terug, ook bijzaken"
        }
    }
}
