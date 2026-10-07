// OnboardingView+iOS.swift
// ThoughtVault
//
// iOS onboarding, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-onboarding-northstar.jpg): brand header
// with "n van 4" progress, a hero, the permission card and "Daarna komt nog".
// iOS has four counted steps: welcome, microphone + speech recognition
// (one step, as in the NorthStar), calendar and "Over jou"; the finish screen
// follows. The NorthStar's screen-recording step is macOS-only. The existing
// permission, calendar and profile logic is reused unchanged.

#if os(iOS)
import SwiftUI

extension OnboardingView {

    /// Counted steps on iOS; `.spraak` is part of the microphone step.
    private var iosSteps: [OnboardingStep] { [.welcome, .microphoon, .agenda, .profiel] }

    private var iosIndex: Int? { iosSteps.firstIndex(of: currentStep == .spraak ? .microphoon : currentStep) }

    var iosBody: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 6)
            Group {
                switch currentStep {
                case .welcome: welcomeHero
                case .microphoon, .spraak: permissionStep
                case .agenda: reused(agendaStep)
                case .profiel: reused(profielStep)
                default: reused(klaarStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(currentStep == .spraak ? .microphoon : currentStep)
            .transition(.opacity)
            .animation(TS.Animation.smooth, value: currentStep)
            footer
        }
        .background(IOSBackground(glow: 1.3))
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.84, green: 0.45, blue: 1), Color(red: 0.52, green: 0.28, blue: 0.96)],
                                                startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
            Text("ThoughtVault")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IOSColor.text)
            Spacer()
            if let index = iosIndex {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(index + 1) van \(iosSteps.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.text2)
                    HStack(spacing: 5) {
                        ForEach(0..<iosSteps.count, id: \.self) { k in
                            Capsule()
                                .fill(k <= index ? IOSColor.violet : IOSColor.control)
                                .frame(width: 22, height: 5)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stap \(index + 1) van \(iosSteps.count)")
            }
        }
        .frame(height: 44)
    }

    // MARK: Welcome

    private var welcomeHero: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                VStack(spacing: 4) {
                    Text("Welkom bij")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(IOSColor.text)
                    Text("ThoughtVault")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(IOSColor.nameGradient)
                }
                Text("Neem vergaderingen op, transcribeer ze automatisch en genereer in seconden professionele notulen.")
                    .font(.system(size: 16))
                    .foregroundStyle(IOSColor.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    /// Orb over mountains with a glowing path.
    private var hero: some View {
        ZStack {
            IOSLiveWave(isActive: false, levels: { [] })
                .frame(height: 140)
                .opacity(0.6)
            IOSMicOrb(size: 150)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        // Background, so the wide landscape never widens the layout.
        .background {
            IOSNightIllustration(showsMoon: false)
                .frame(width: 600, height: 200)
                .offset(x: -60, y: 40)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                .opacity(0.9)
        }
        .clipped()
    }

    // MARK: Microphone + speech

    private var permissionsGranted: Bool { micPermission == .granted && speechPermission == .granted }
    private var permissionsDenied: Bool { micPermission == .denied || speechPermission == .denied }

    private var permissionStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                (Text("Maak van gesprekken\n").foregroundStyle(IOSColor.text)
                 + Text("direct notities").foregroundStyle(IOSColor.nameGradient))
                    .font(.system(size: 27, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                Text("ThoughtVault luistert, begrijpt en maakt automatisch heldere notities. Zo kun jij je volle aandacht bij het gesprek houden.")
                    .font(.system(size: 14))
                    .foregroundStyle(IOSColor.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                permissionCard
                    .padding(.top, 22)
                    .padding(.horizontal, IOSMetric.gutter)
                upcoming
                    .padding(.top, 22)
                    .padding(.horizontal, IOSMetric.gutter)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var permissionCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                IOSMicOrb(size: 76)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IOSColor.cardRaised))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Microfoon en spraakherkenning")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("We hebben toegang tot je microfoon nodig om gesprekken op te nemen en realtime te transcriberen.")
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if permissionsGranted {
                Label("Toegang gegeven", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IOSColor.ready)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(IOSColor.tileGreen))
            } else if permissionsDenied {
                VStack(spacing: 8) {
                    Text("Toegang geweigerd. Open Instellingen om dit te wijzigen.")
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.danger)
                        .multilineTextAlignment(.center)
                    primaryButton("Instellingen openen") { openSystemSettings() }
                }
            } else {
                primaryButton("Sta toegang toe") {
                    Task {
                        if micPermission == .unknown { await requestMicPermission() }
                        if speechPermission == .unknown { await requestSpeechPermission() }
                    }
                }
            }
            if ProcessingMode.isLocalMode {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock")
                        .font(.system(size: 20))
                        .foregroundStyle(IOSColor.text2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alles blijft lokaal op dit apparaat")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(IOSColor.text)
                        Text("Je audio wordt niet ge\u{00FC}pload naar de cloud.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(IOSColor.text2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .iosCard(raised: true)
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daarna komt nog")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IOSColor.text)
            upcomingRow(.agenda, icon: "calendar", title: "Agenda koppelen", subtitle: "Automatisch context uit je afspraken.")
            upcomingRow(.profiel, icon: "person.text.rectangle", title: "Over jou", subtitle: "Context voor betere notulen.")
        }
    }

    private func upcomingRow(_ step: OnboardingStep, icon: String, title: String, subtitle: String) -> some View {
        Button { withAnimation(TS.Animation.smooth) { currentStep = step } } label: {
            HStack(spacing: 16) {
                IOSIconTile(systemName: icon, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(IOSColor.text)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(IOSColor.text2)
                }
                Spacer(minLength: 6)
                if let index = iosSteps.firstIndex(of: step) {
                    Text("\(index + 1) van \(iosSteps.count)").font(.system(size: 13)).foregroundStyle(IOSColor.text2)
                }
                IOSChevron()
            }
            .padding(14)
            .iosCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Reused steps

    /// Existing step content on the night background.
    private func reused<V: View>(_ content: V) -> some View {
        content
            .foregroundStyle(IOSColor.text)
            .tint(IOSColor.violet)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            switch currentStep {
            case .welcome:
                primaryButton("Beginnen") { advanceStep() }
            case .microphoon, .spraak:
                if permissionsGranted {
                    primaryButton("Volgende") { withAnimation(TS.Animation.smooth) { currentStep = .agenda } }
                } else {
                    Button { withAnimation(TS.Animation.smooth) { currentStep = .agenda } } label: {
                        HStack(spacing: 6) {
                            Text("Nu overslaan")
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(IOSColor.lavender)
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            case .klaar:
                primaryButton("Maak je eerste opname") {
                    pendingFirstRecording = true
                    hasCompletedOnboarding = true
                }
            default:
                HStack(spacing: 14) {
                    Button { goBackStep() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Terug")
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(IOSColor.text2)
                    }
                    .buttonStyle(.plain)
                    primaryButton("Volgende") {
                        if currentStep == .profiel { saveProfileIfFilled() }
                        advanceStep()
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(IOSColor.accentGradient))
            .shadow(color: IOSColor.violet.opacity(0.45), radius: 12)
        }
        .buttonStyle(.plain)
    }
}
#endif
