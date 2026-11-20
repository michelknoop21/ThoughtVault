// ProfileCard.swift
// ThoughtVault
//
// One profile in the macOS Profielen list. A profile with a detail level shows the level picker.

import SwiftUI

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: Profile
    let isDefault: Bool
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var isHovered = false

    private var iconName: String {
        profile.icon ?? profileIcon(for: profile.id)
    }

    private var accentColor: Color {
        profileAccent(for: profile.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            header
            if profile.detailLevel != nil {
                ProfileDetailLevelPicker(profile: profile)
                    .padding(.leading, 44 + TS.Spacing.md)
            }
        }
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfacePrimary)
                .shadow(
                    color: .black.opacity(isHovered ? 0.08 : 0.04),
                    radius: isHovered ? 8 : 4,
                    y: isHovered ? 2 : 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(
                    isHovered ? accentColor.opacity(0.3) : Color.borderPrimary.opacity(0.5),
                    lineWidth: 1
                )
        }
        .onHover { hovering in
            withAnimation(TS.Animation.hover) { isHovered = hovering }
        }
    }

    private var header: some View {
        HStack(spacing: TS.Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accentColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TS.Spacing.sm) {
                    Text(profile.name)
                        .font(TS.Font.bodySemibold)
                        .foregroundStyle(Color.labelPrimary)

                    if isDefault {
                        Text("Standaard")
                            .font(TS.Font.microSemibold)
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, TS.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                Text(profile.description ?? profile.systemPrompt ?? "")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Actions
            if !isDefault {
                HStack(spacing: TS.Spacing.xs) {
                    actionButton(icon: "pencil", color: .labelSecondary) {
                        onEdit?()
                    }
                    actionButton(icon: "trash", color: .statusError.opacity(0.7)) {
                        onDelete?()
                    }
                }
                .opacity(isHovered ? 1 : 0.5)
            }
        }
    }

    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Color.surfaceSecondary.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func profileIcon(for id: String) -> String {
        switch id {
        case "zakelijk":  return "briefcase.fill"
        case "informeel": return "bubble.left.and.bubble.right.fill"
        case "technisch": return "wrench.and.screwdriver.fill"
        default:          return "doc.text.fill"
        }
    }

    private func profileAccent(for id: String) -> Color {
        switch id {
        case "zakelijk":  return .brandPrimary
        case "informeel": return .brandAccent
        case "technisch": return .brandSecondary
        default:          return .brandOrange
        }
    }
}
