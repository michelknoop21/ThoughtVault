// OnboardingView+NotulenIOS.swift
// ThoughtVault
//
// iPhone layout of the wizard step "Wie schrijft je notulen?": provider rows in
// one card, then key and model of the chosen provider. The big Volgende button
// and Overslaan live in the iOS footer (OnboardingView+iOS). Logic is shared
// with macOS in OnboardingView+Notulen.

#if os(iOS)
import SwiftUI

extension OnboardingView {

    var notulenStep: some View {
        notulenSkipAlert(ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Wie schrijft je notulen?")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(IOSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Opnemen en omzetten naar tekst gebeurt op je iPhone. Kies wie de notule schrijft.")
                    .font(.system(size: 15))
                    .foregroundStyle(IOSColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                VStack(spacing: 8) {
                    NotulenChoiceTile(title: "OpenRouter", subtitle: "Eén sleutel voor veel modellen",
                                      recommended: true, selected: notulenChoice == .openRouter) { notulenChoice = .openRouter }
                    NotulenChoiceTile(title: "Op deze iPhone", subtitle: "Gratis, kortere notulen",
                                      selected: notulenChoice == .onDevice) { notulenChoice = .onDevice }
                    NotulenChoiceTile(title: "Andere aanbieder", subtitle: "Eigen adres en sleutel",
                                      selected: notulenChoice == .other) { notulenChoice = .other }
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    notulenConfig(device: "iPhone")
                }
                .padding(16)
                .iosCard(raised: true)
                .padding(.top, 18)
                .tint(IOSColor.violet)

                if notulenChoice != .onDevice {
                    Text("Kies een model")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .padding(.top, 22)
                    notulenModelHint.padding(.top, 4)
                }
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively))
    }

    /// Big Volgende with Overslaan under it, as in the iPhone frames.
    var notulenIOSFooter: some View {
        VStack(spacing: 4) {
            Button { notulenNext() } label: {
                HStack(spacing: 8) {
                    Text("Volgende")
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(IOSColor.accentGradient))
                .shadow(color: IOSColor.violet.opacity(0.45), radius: 12)
            }
            .buttonStyle(StudioScalePressStyle(scale: 0.97))
            Button("Overslaan") { notulenSkipAsk = true }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IOSColor.lavender)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
        }
    }
}
#endif
