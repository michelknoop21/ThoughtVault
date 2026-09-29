// HomeView+Card.swift
// ThoughtVault
//
// The "Nieuwe opname" card of the macOS Home NorthStar: record button (starts
// a recording), settings shortcut, idle bars and the microphone permission
// panel backed by PermissionManager.

#if os(macOS)
import SwiftUI

extension HomeView {

    // MARK: Recording card

    private var micGranted: Bool { PermissionManager.shared.microphoneGranted }

    func recordingCard(_ layout: HomeLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nieuwe opname")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(HomeColor.kicker)
                        .frame(height: 13)
                    Text("Begin een nieuwe opname")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 9)
                    Text("Spreek je gedachten, vergadering of idee. ThoughtVault maakt er automatisch notities, samenvattingen en taken van.")
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    recordControls
                        .padding(.top, 18)
                }
                .padding(.leading, 38)
                .padding(.top, 35)
                if layout.cardPanelBeside {
                    micPanel
                        .frame(width: 238, height: 249, alignment: .top)
                        .padding(.top, 31)
                        .padding(.trailing, 20)
                }
            }
            .padding(.trailing, layout.cardPanelBeside ? 0 : 24)
            if !layout.cardPanelBeside {
                micPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 301, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [HomeColor.cardTop, HomeColor.card], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HomeColor.cardBorder, lineWidth: 1))
    }

    private var recordControls: some View {
        HStack(spacing: 0) {
            Button { onOpenSettings?() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(HomeColor.text)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.11, green: 0.13, blue: 0.23)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.controlBorder, lineWidth: 1))
            }
            .buttonStyle(StudioPressStyle())
            .help("Instellingen")
            .accessibilityLabel("Instellingen")

            Button { onStartRecording?(.microphone) } label: {
                HomeMicButton()
            }
            .buttonStyle(StudioPressStyle())
            .padding(.leading, 19)
            .help("Opname starten")
            .accessibilityLabel("Opname starten")

            // Bars share the button's centre line; the status sits 59 pt below it.
            HomeIdleBars()
                .frame(height: 76)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(micGranted ? HomeColor.ready : HomeColor.warning)
                            .frame(width: 7, height: 7)
                        Text(micGranted ? "Klaar om op te nemen" : "Microfoontoegang nodig")
                            .font(.system(size: 12.5))
                            .foregroundStyle(HomeColor.text2)
                            .fixedSize()
                    }
                    .padding(.leading, 3)
                    .offset(y: 18)
                }
                .padding(.leading, 20)
                .frame(minWidth: 140, maxWidth: .infinity)

            Text("0:00")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(HomeColor.text2)
                .padding(.leading, 27)
                .accessibilityHidden(true)
        }
        .frame(height: 132, alignment: .center)
    }

    // MARK: Microphone panel

    @ViewBuilder
    private var micPanel: some View {
        let permissions = PermissionManager.shared
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: micGranted ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(micGranted ? Color(red: 0.14, green: 0.43, blue: 0.27) : Color(red: 0.55, green: 0.37, blue: 0.10)))
                    .overlay(Circle().strokeBorder((micGranted ? HomeColor.ready : HomeColor.warning).opacity(0.55), lineWidth: 1))
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(micGranted ? "Microfoon gereed" : "Geen microfoontoegang")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(micGranted ? Color(red: 0.42, green: 0.84, blue: 0.58) : HomeColor.warning)
                    Text(micGranted ? "ThoughtVault heeft toegang tot je microfoon." : "Geef ThoughtVault toegang om op te nemen.")
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 18)

            Button {
                if micGranted || permissions.microphoneDenied {
                    permissions.openSystemSettings()
                } else {
                    Task { await permissions.requestMicrophone() }
                }
            } label: {
                HStack {
                    Text(micGranted || permissions.microphoneDenied ? "Toegang beheren" : "Toegang geven")
                        .font(.system(size: 13.5))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(HomeColor.text)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HomeColor.control))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HomeColor.controlBorder, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 15)

            Rectangle().fill(HomeColor.panelBorder).frame(height: 1)
                .padding(.top, 23)

            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(red: 0.96, green: 0.72, blue: 0.24))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tip")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeColor.text)
                    Text("Spreek natuurlijk. Je kunt op elk moment pauzeren.")
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 15)
            .padding(.bottom, 14)
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HomeColor.panelBorder, lineWidth: 1))
    }
}
#endif
