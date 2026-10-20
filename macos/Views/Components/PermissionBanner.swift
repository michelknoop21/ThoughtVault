// PermissionBanner.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Inline banner shown when essential permissions are missing.
// Allows the user to grant permissions or open System Settings.

import SwiftUI

struct PermissionBanner: View {

    @Environment(PermissionManager.self) private var permissionManager

    @State private var isExpanded = false

    var body: some View {
        if permissionManager.hasMissingPermissions {
            VStack(spacing: 0) {
                // Collapsed header
                Button {
                    withAnimation(TS.Animation.smooth) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.brandOrange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ontbrekende rechten")
                                .font(TS.Font.footnoteSemibold)
                                .foregroundStyle(Color.labelPrimary)
                            Text("\(permissionManager.missingPermissionNames.joined(separator: ", "))")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.vertical, TS.Spacing.sm)
                }
                .buttonStyle(.plain)

                // Expanded detail
                if isExpanded {
                    VStack(spacing: TS.Spacing.sm) {
                        if !permissionManager.microphoneGranted {
                            permissionRow(
                                icon: "mic.fill",
                                title: "Microfoon",
                                description: "Vereist om vergaderingen op te nemen",
                                isDenied: permissionManager.microphoneDenied,
                                action: {
                                    Task { await permissionManager.requestMicrophone() }
                                }
                            )
                        }

                        #if os(macOS)
                        if permissionManager.systemAudioGranted == false {
                            permissionRow(
                                icon: "waveform",
                                title: "Systeemaudio",
                                description: "Voor het opnemen van geluid uit videocalls",
                                action: {
                                    permissionManager.openSystemAudioSettings()
                                }
                            )
                        }
                        #endif

                        if !permissionManager.speechRecognitionGranted {
                            permissionRow(
                                icon: "waveform",
                                title: "Spraakherkenning",
                                description: "Optioneel voor on-device transcriptie",
                                isDenied: permissionManager.speechRecognitionDenied,
                                action: {
                                    Task { await permissionManager.requestSpeechRecognition() }
                                }
                            )
                        }

                        Text("Na het verlenen van rechten kan een herstart van de app nodig zijn.")
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.labelTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TS.Spacing.xs)
                    }
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.bottom, TS.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                    .fill(Color.brandOrange.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                            .stroke(Color.brandOrange.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        isDenied: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.brandOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelPrimary)
                Text(description)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            Button(isDenied ? "Open Systeeminstellingen" : "Toestaan", action: action)
                .buttonStyle(SecondaryButtonStyle())
                .controlSize(.small)
        }
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.surfacePrimary)
        }
    }
}
