// OnboardingView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Multi-step first-run onboarding flow. Guides new users through
// welcome, permissions setup, and configuration before granting app access.

import SwiftUI
import Speech
import AVFoundation

// MARK: - OnboardingView

struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State private var currentStep: OnboardingStep = .welcome
    @State private var micPermission: PermissionState = .unknown
    @State private var speechPermission: PermissionState = .unknown
    @State private var calendarPermission: PermissionState = .unknown
    @State private var isAnimatingIn: Bool = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome     = 0
        case microphoon  = 1
        case spraak      = 2
        case agenda      = 3
        case klaar       = 4

        var title: String {
            switch self {
            case .welcome:    return "Welkom bij TranscriptStudio"
            case .microphoon: return "Microfoontoestemming"
            case .spraak:     return "Spraakherkenning"
            case .agenda:     return "Agenda"
            case .klaar:      return "Alles klaar!"
            }
        }

        var icon: String {
            switch self {
            case .welcome:    return "waveform.badge.mic"
            case .microphoon: return "mic.fill"
            case .spraak:     return "waveform"
            case .agenda:     return "calendar"
            case .klaar:      return "checkmark.seal.fill"
            }
        }

        var gradientColors: [Color] {
            switch self {
            case .welcome:    return [Color.gradientPurple, Color.gradientBlue]
            case .microphoon: return [Color.gradientBlue, Color.brandSecondary.opacity(0.5)]
            case .spraak:     return [Color.gradientGreen, Color.brandAccent.opacity(0.4)]
            case .agenda:     return [Color.gradientOrange, Color.brandOrange.opacity(0.4)]
            case .klaar:      return [Color.brandPrimary.opacity(0.3), Color.gradientPurple]
            }
        }
    }

    enum PermissionState {
        case unknown, granted, denied
        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .granted: return "checkmark.circle.fill"
            case .denied:  return "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .unknown: return Color.labelTertiary
            case .granted: return Color.statusSuccess
            case .denied:  return Color.statusError
            }
        }
    }

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: currentStep.gradientColors + [Color.white.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(TS.Animation.gentle, value: currentStep)

            VStack(spacing: 0) {
                // Step indicator
                stepIndicator

                // Content area
                TabView(selection: $currentStep) {
                    ForEach(OnboardingStep.allCases, id: \.self) { step in
                        stepContent(step)
                            .tag(step)
                    }
                }
#if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
#else
                .tabViewStyle(.automatic)
#endif

                // Navigation buttons
                navigationFooter
            }
        }
        .onAppear {
            withAnimation(TS.Animation.gentle) {
                isAnimatingIn = true
            }
            Task { await checkExistingPermissions() }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: TS.Spacing.sm) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == currentStep ? Color.brandPrimary : Color.brandPrimary.opacity(0.20))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
                    .animation(TS.Animation.smooth, value: currentStep)
            }
        }
        .padding(.top, TS.Spacing.xl)
        .padding(.bottom, TS.Spacing.md)
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:    welcomeStep
        case .microphoon: microphoonStep
        case .spraak:     spraakStep
        case .agenda:     agendaStep
        case .klaar:      klaarStep
        }
    }

    // MARK: Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            // Brand bar
            YingaBar(height: 4)
                .frame(width: 80)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            // Hero icon
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.10))
                    .frame(width: 120, height: 120)
                Image(systemName: OnboardingStep.welcome.icon)
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.brandPrimary)
            }

            VStack(spacing: TS.Spacing.sm) {
                Text("Welkom bij")
                    .font(TS.Font.title2)
                    .foregroundStyle(Color.labelSecondary)
                Text("TranscriptStudio")
                    .font(TS.Font.largeTitleBold)
                    .foregroundStyle(Color.brandPrimary)
            }

            Text("Neem vergaderingen op, transcribeer ze automatisch en genereer professionele notulen — in seconden.")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TS.Spacing.xl)

            Spacer()
            Spacer()
        }
    }

    // MARK: Microfoon Step

    private var microphoonStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            permissionIcon(systemName: "mic.fill", permission: micPermission)

            VStack(spacing: TS.Spacing.sm) {
                Text("Microfoon")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("TranscriptStudio heeft toegang tot je microfoon nodig om vergaderingen op te nemen.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TS.Spacing.xl)
            }

            permissionStatusRow(permission: micPermission, label: "Microfoon toegang")

            if micPermission == .unknown {
                Button("Toegang verlenen") {
                    Task { await requestMicPermission() }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if micPermission == .denied {
                VStack(spacing: TS.Spacing.sm) {
                    Text("Toegang geweigerd — open Systeeminstellingen om dit te wijzigen.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.statusError)
                        .multilineTextAlignment(.center)
                    Button("Systeeminstellingen openen") {
                        openSystemSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: Spraak Step

    private var spraakStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            permissionIcon(systemName: "waveform", permission: speechPermission)

            VStack(spacing: TS.Spacing.sm) {
                Text("Spraakherkenning")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("Voor on-device transcriptie verwerkt TranscriptStudio je spraak lokaal op dit apparaat. Je audio blijft privé.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TS.Spacing.xl)
            }

            permissionStatusRow(permission: speechPermission, label: "Spraakherkenning toegang")

            if speechPermission == .unknown {
                Button("Toegang verlenen") {
                    Task { await requestSpeechPermission() }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if speechPermission == .denied {
                VStack(spacing: TS.Spacing.sm) {
                    Text("Toegang geweigerd — je kunt nog steeds de cloud-transcriptie gebruiken.")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                    Button("Systeeminstellingen openen") {
                        openSystemSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: Agenda Step

    private var agendaStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            permissionIcon(systemName: "calendar", permission: calendarPermission)

            VStack(spacing: TS.Spacing.sm) {
                Text("Agenda")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("TranscriptStudio detecteert aankomende Teams-, Zoom- en Meet-vergaderingen en biedt een snelkoppeling om een opname te starten.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TS.Spacing.xl)
            }

            permissionStatusRow(permission: calendarPermission, label: "Agenda toegang")

            VStack(spacing: TS.Spacing.sm) {
                if calendarPermission == .unknown {
                    Button("Agenda koppelen") {
                        Task { await requestCalendarPermission() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Button("Overslaan") {
                    advanceStep()
                }
                .buttonStyle(.plain)
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: Klaar Step

    private var klaarStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.statusSuccess.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.statusSuccess)
            }

            VStack(spacing: TS.Spacing.sm) {
                Text("Alles klaar!")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("TranscriptStudio is geconfigureerd en klaar voor gebruik. Begin met je eerste opname.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TS.Spacing.xl)
            }

            // Permission summary
            VStack(spacing: TS.Spacing.sm) {
                summaryRow(icon: "mic.fill", label: "Microfoon", permission: micPermission)
                summaryRow(icon: "waveform", label: "Spraakherkenning", permission: speechPermission)
                summaryRow(icon: "calendar", label: "Agenda", permission: calendarPermission)
            }
            .padding(TS.Spacing.md)
            .background(Color.surfacePrimary.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))

            Spacer()
            Spacer()
        }
    }

    // MARK: - Reusable Components

    private func permissionIcon(systemName: String, permission: PermissionState) -> some View {
        ZStack {
            Circle()
                .fill(permission == .granted ? Color.statusSuccess.opacity(0.12) : Color.brandPrimary.opacity(0.10))
                .frame(width: 120, height: 120)
            Image(systemName: systemName)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(permission == .granted ? Color.statusSuccess : Color.brandPrimary)
        }
    }

    private func permissionStatusRow(permission: PermissionState, label: String) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: permission.icon)
                .foregroundStyle(permission.color)
            Text(label)
                .font(TS.Font.bodyMedium)
                .foregroundStyle(Color.labelPrimary)
            Spacer()
            Text(permission == .granted ? "Verleend" : permission == .denied ? "Geweigerd" : "Niet gevraagd")
                .font(TS.Font.footnote)
                .foregroundStyle(permission.color)
        }
        .padding(TS.Spacing.sm)
        .background(Color.surfacePrimary.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
        .padding(.horizontal, TS.Spacing.xl)
    }

    private func summaryRow(icon: String, label: String, permission: PermissionState) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 20)
            Text(label)
                .font(TS.Font.bodyMedium)
                .foregroundStyle(Color.labelPrimary)
            Spacer()
            Image(systemName: permission.icon)
                .foregroundStyle(permission.color)
        }
    }

    // MARK: - Navigation Footer

    private var navigationFooter: some View {
        HStack {
            if currentStep.rawValue > 0 {
                Button {
                    withAnimation(TS.Animation.smooth) {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                    }
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Image(systemName: "chevron.left")
                        Text("Terug")
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
            }

            Spacer()

            if currentStep == .klaar {
                Button("Starten") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    advanceStep()
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Text(currentStep == .welcome ? "Beginnen" : "Volgende")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, TS.Spacing.xl)
        .padding(.vertical, TS.Spacing.lg)
        .background(Color.white.opacity(0.3))
    }

    // MARK: - Permission Requests

    private func checkExistingPermissions() async {
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micPermission = audioStatus == .authorized ? .granted : audioStatus == .denied ? .denied : .unknown

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechPermission = speechStatus == .authorized ? .granted : speechStatus == .denied ? .denied : .unknown

        let calStatus = await checkCalendarStatus()
        calendarPermission = calStatus
    }

    private func checkCalendarStatus() async -> PermissionState {
        #if os(macOS)
        return .unknown // Check via EKEventStore on macOS
        #else
        return .unknown
        #endif
    }

    private func requestMicPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            micPermission = granted ? .granted : .denied
        }
    }

    private func requestSpeechPermission() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechPermission = status == .authorized ? .granted : .denied
                }
                continuation.resume()
            }
        }
    }

    private func requestCalendarPermission() async {
        await CalendarService.shared.requestAccess()
        await MainActor.run {
            calendarPermission = CalendarService.shared.hasCalendarAccess ? .granted : .denied
            if calendarPermission == .granted {
                advanceStep()
            }
        }
    }

    private func openSystemSettings() {
        #if os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        #else
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        #endif
    }

    private func advanceStep() {
        withAnimation(TS.Animation.smooth) {
            if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .frame(width: 500, height: 700)
}
