// ProfilePicker.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Horizontal pill-style profile selector. Each profile is shown as
// a compact chip; the selected profile is highlighted in brand color.

import SwiftUI

// MARK: - ProfilePicker

struct ProfilePicker: View {

    let profiles: [Profile]

    @Binding var selectedProfile: Profile?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.sm) {
                ForEach(profiles) { profile in
                    ProfileChip(
                        profile: profile,
                        isSelected: selectedProfile?.id == profile.id,
                        onTap: {
                            withAnimation(TS.Animation.smooth) {
                                selectedProfile = profile
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, TS.Spacing.xs)
            .padding(.vertical, TS.Spacing.xs)
        }
    }
}

// MARK: - ProfileChip

private struct ProfileChip: View {

    let profile: Profile
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TS.Spacing.xs) {
                // Dot indicator
                Circle()
                    .fill(isSelected ? Color.white : Color.brandSecondary.opacity(0.5))
                    .frame(width: 6, height: 6)

                Text(profile.name)
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(isSelected ? Color.white : Color.labelPrimary)
                    .lineLimit(1)

                // Default indicator
                if profile.isDefault == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.brandSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm - 2)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.brandSecondary, Color.brandSecondary.opacity(0.80)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: Color.brandSecondary.opacity(0.30),
                            radius: 6,
                            y: 2
                        )
                } else {
                    Capsule()
                        .fill(isHovered
                            ? Color.brandSecondary.opacity(0.10)
                            : Color.surfaceSecondary)
                        .overlay {
                            Capsule()
                                .stroke(
                                    isHovered ? Color.brandSecondary.opacity(0.30) : Color.borderPrimary,
                                    lineWidth: 1
                                )
                        }
                }
            }
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .animation(TS.Animation.hover, value: isHovered)
            .animation(TS.Animation.smooth, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selected: Profile? = Profile.zakelijk

    VStack(spacing: TS.Spacing.lg) {
        Text("Selecteer een profiel")
            .font(TS.Font.headlineBold)

        ProfilePicker(
            profiles: Profile.defaults,
            selectedProfile: $selected
        )

        if let selected {
            Text("Geselecteerd: \(selected.name)")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
        }
    }
    .padding(TS.Spacing.lg)
    .frame(width: 400)
}
