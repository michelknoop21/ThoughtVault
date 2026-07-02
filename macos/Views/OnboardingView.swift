// OnboardingView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Multi-step first-run onboarding flow. Guides new users through
// welcome, permissions setup, and configuration before granting app access.

import SwiftUI
import Speech
import AVFoundation
import EventKit
#if os(macOS)
import ScreenCaptureKit
#endif

// MARK: - OnboardingView

struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    /// Set when the user finishes onboarding via the first-recording CTA; ContentView
    /// reads this once to open the recording screen so the first action is one tap away.
    @AppStorage("pendingFirstRecording") private var pendingFirstRecording: Bool = false
    @Environment(CalendarService.self) private var calendarService

    @State private var currentStep: OnboardingStep = .welcome
    @State private var micPermission: PermissionState = .unknown
    @State private var speechPermission: PermissionState = .unknown
    @State private var calendarPermission: PermissionState = .unknown
    @State private var screenRecordingPermission: PermissionState = .unknown
    @State private var isAnimatingIn: Bool = false

    // Self-profile step fields
    @State private var profielNaam: String = ""
    @State private var profielRol: String = ""
    @State private var profielOrganisatie: String = ""
    @State private var profielAliassen: String = ""
    @State private var profielMeetingTypes: String = ""
    @State private var profielExpertise: String = ""

    enum OnboardingStep: Int, CaseIterable {
        case welcome        = 0
        case microphoon     = 1
        case spraak         = 2
        case agenda         = 3
        case schermopname   = 4
        case profiel        = 5
        case klaar          = 6

        var title: String {
            switch self {
            case .welcome:       return "Welkom bij TranscriptStudio"
            case .microphoon:    return "Microfoontoestemming"
            case .spraak:        return "Spraakherkenning"
            case .agenda:        return "Agenda"
            case .schermopname:  return "Schermopname"
            case .profiel:       return "Vertel iets over jezelf"
            case .klaar:         return "Alles klaar!"
            }
        }

        var icon: String {
            switch self {
            case .welcome:       return "waveform.badge.mic"
            case .microphoon:    return "mic.fill"
            case .spraak:        return "waveform"
            case .agenda:        return "calendar"
            case .schermopname:  return "rectangle.dashed.badge.record"
            case .profiel:       return "person.crop.circle"
            case .klaar:         return "checkmark.seal.fill"
            }
        }

        /// Whether this step is available on the current platform.
        var isAvailableOnCurrentPlatform: Bool {
            switch self {
            case .schermopname:
                #if os(macOS)
                return true
                #else
                return false
                #endif
            case .profiel:
                return true
            default:
                return true
            }
        }
    }

    /// Steps visible on the current platform (excludes macOS-only steps on iOS).
    private var visibleSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0.isAvailableOnCurrentPlatform }
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
            // One calm, static brand-tinted canvas. The per-step icon carries the
            // identity; a different animated gradient per step read as consumer-cute.
            LinearGradient(
                colors: [Color.surfaceSecondary, Color.brandPrimary.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Full-width brand bar directly under title bar
                YingaBar()

                // Step indicator
                stepIndicator

                // Content area
#if os(macOS)
                // A linear wizard: render only the current step. A TabView here
                // rendered a native tab bar and let users swipe/jump past mandatory
                // permission steps out of order, fighting the Back/Next footer.
                stepContent(currentStep)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentStep)
                    .transition(.opacity)
                    .animation(TS.Animation.smooth, value: currentStep)
#else
                TabView(selection: $currentStep) {
                    ForEach(visibleSteps, id: \.self) { step in
                        stepContent(step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
#endif

                // Navigation buttons
                navigationFooter
            }
#if os(macOS)
            .toolbar(.hidden)
#endif
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
            ForEach(visibleSteps, id: \.self) { step in
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
        case .welcome:       welcomeStep
        case .microphoon:    microphoonStep
        case .spraak:        spraakStep
        case .agenda:        agendaStep
        case .schermopname:  schermopnameStep
        case .profiel:       profielStep
        case .klaar:         klaarStep
        }
    }

    // MARK: Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

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

    @State private var connectingMicrosoft = false

    private var agendaStep: some View {
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            permissionIcon(systemName: "calendar", permission: calendarPermission)

            VStack(spacing: TS.Spacing.sm) {
                Text("Agenda")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("Hoe wil je je agenda koppelen?")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TS.Spacing.xl)
            }

            VStack(spacing: TS.Spacing.sm) {
                // Apple Calendar option
                Button {
                    calendarService.activeProvider = .apple
                    Task { await requestCalendarPermission() }
                } label: {
                    HStack(spacing: TS.Spacing.md) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Agenda")
                                .font(TS.Font.bodyMedium)
                            Text("Gebruikt je macOS kalenders (Outlook, Google, iCloud)")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        Spacer()
                        if calendarPermission == .granted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusSuccess)
                        }
                    }
                    .padding(TS.Spacing.md)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
                }
                .buttonStyle(.plain)

                // Microsoft 365 option (only if configured)
                if calendarService.isMicrosoftConfigured {
                    Button {
                        calendarService.activeProvider = .microsoft
                        connectingMicrosoft = true
                        Task {
                            do {
                                try await MicrosoftGraphService.shared.initiateAuth()
                                await calendarService.updateMicrosoftConnection()
                                advanceStep()
                            } catch {
                                // User cancelled or error — stay on step
                            }
                            connectingMicrosoft = false
                        }
                    } label: {
                        HStack(spacing: TS.Spacing.md) {
                            Image(systemName: "cloud")
                                .font(.title3)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Microsoft 365")
                                    .font(TS.Font.bodyMedium)
                                Text("Koppel rechtstreeks met je Microsoft werkaccount")
                                    .font(TS.Font.caption)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                            Spacer()
                            if connectingMicrosoft {
                                ProgressView()
                                    .controlSize(.small)
                            } else if calendarService.isMicrosoftConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.statusSuccess)
                            }
                        }
                        .padding(TS.Spacing.md)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(connectingMicrosoft)
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

    // MARK: Schermopname Step (macOS only)

    private var schermopnameStep: some View {
        #if os(macOS)
        VStack(spacing: TS.Spacing.xl) {
            Spacer()

            permissionIcon(systemName: "rectangle.dashed.badge.record", permission: screenRecordingPermission)

            VStack(spacing: TS.Spacing.sm) {
                Text("Schermopname")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("TranscriptStudio heeft schermopname-toestemming nodig om systeemaudio van videovergaderingen op te nemen.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TS.Spacing.xl)
            }

            permissionStatusRow(permission: screenRecordingPermission, label: "Schermopname toegang")

            if screenRecordingPermission == .unknown {
                Button("Toestemming verlenen") {
                    Task { await requestScreenRecordingPermission() }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if screenRecordingPermission == .denied {
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
        #else
        EmptyView()
        #endif
    }

    // MARK: Profiel Step

    private var profielStep: some View {
        ScrollView {
            VStack(spacing: TS.Spacing.xl) {
                Spacer()
                    .frame(height: TS.Spacing.lg)

                // Hero icon
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.10))
                        .frame(width: 120, height: 120)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(Color.brandPrimary)
                }

                VStack(spacing: TS.Spacing.sm) {
                    Text("Vertel iets over jezelf")
                        .font(TS.Font.title2Bold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("TranscriptStudio gebruikt jouw profiel om actiepunten straks aan de juiste persoon te koppelen. Je kunt dit altijd later aanpassen.")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TS.Spacing.xl)
                }

                // Form fields
                VStack(spacing: TS.Spacing.md) {
                    TextField("Naam", text: $profielNaam)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .padding(TS.Spacing.sm)
                        .background(Color.surfacePrimary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))

                    TextField("Rol / Functie", text: $profielRol)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .padding(TS.Spacing.sm)
                        .background(Color.surfacePrimary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))

                    TextField("Organisatie", text: $profielOrganisatie)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .padding(TS.Spacing.sm)
                        .background(Color.surfacePrimary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))

                    TextField("Hoe noemen collega's jou?", text: $profielAliassen)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .padding(TS.Spacing.sm)
                        .background(Color.surfacePrimary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))

                    TextField("Typische vergadertypen", text: $profielMeetingTypes)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .padding(TS.Spacing.sm)
                        .background(Color.surfacePrimary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))

                    TextField("Expertise / onderwerpen", text: $profielExpertise)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .padding(TS.Spacing.sm)
                        .background(Color.surfacePrimary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                }
                .padding(.horizontal, TS.Spacing.xl)

                // Skip button (D-07: no record written when skipped)
                Button("Overslaan") {
                    advanceStep()
                }
                .buttonStyle(.plain)
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)

                Spacer()
                    .frame(height: TS.Spacing.lg)
            }
        }
        .simultaneousGesture(DragGesture().onChanged { _ in }) // prevent TabView from swallowing scroll
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
                Text("Je bent klaar!")
                    .font(TS.Font.title2Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text("Je bent klaar om je eerste gesprek vast te leggen. Start een korte testopname of neem direct je volgende meeting op.")
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
                #if os(macOS)
                summaryRow(icon: "rectangle.dashed.badge.record", label: "Schermopname", permission: screenRecordingPermission)
                #endif
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
            if currentStep != visibleSteps.first {
                Button {
                    goBackStep()
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
                Button("Maak je eerste opname") {
                    pendingFirstRecording = true
                    hasCompletedOnboarding = true
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    if currentStep == .profiel {
                        // Save profile if any field is non-empty (D-07)
                        let anyFilled = !profielNaam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !profielRol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !profielOrganisatie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !profielAliassen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !profielMeetingTypes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !profielExpertise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if anyFilled {
                            let splitAndTrim: (String) -> [String] = { input in
                                input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            }
                            try? LocalTranscriptStore.shared.upsertSelfProfile(
                                name: profielNaam.trimmingCharacters(in: .whitespacesAndNewlines),
                                role: profielRol.trimmingCharacters(in: .whitespacesAndNewlines),
                                organization: profielOrganisatie.trimmingCharacters(in: .whitespacesAndNewlines),
                                aliases: splitAndTrim(profielAliassen),
                                meetingTypes: splitAndTrim(profielMeetingTypes),
                                expertiseTags: splitAndTrim(profielExpertise)
                            )
                        }
                    }
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
        .overlay(alignment: .bottom) {
            #if os(macOS)
            YingaFooter()
                .padding(.bottom, TS.Spacing.xs)
            #endif
        }
    }

    // MARK: - Permission Requests

    private func checkExistingPermissions() async {
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micPermission = audioStatus == .authorized ? .granted : audioStatus == .denied ? .denied : .unknown

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechPermission = speechStatus == .authorized ? .granted : speechStatus == .denied ? .denied : .unknown

        let calStatus = await checkCalendarStatus()
        calendarPermission = calStatus

        #if os(macOS)
        await checkScreenRecordingPermission()
        #endif
    }

    private func checkCalendarStatus() async -> PermissionState {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, iOS 17, *) {
            switch status {
            case .fullAccess: return .granted
            case .denied, .restricted: return .denied
            default: return .unknown
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            default: return .unknown
            }
        }
    }

    private func requestMicPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            micPermission = granted ? .granted : .denied
        }
    }

    private func requestSpeechPermission() async {
        let status = await withCheckedContinuation { continuation in
            // TCC invokes this on a background queue; @Sendable prevents
            // MainActor inference which would trap under Swift 6 (SIGTRAP).
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        speechPermission = status == .authorized ? .granted : .denied
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

    #if os(macOS)
    private func checkScreenRecordingPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            await MainActor.run {
                screenRecordingPermission = .granted
            }
        } catch {
            // If the call fails, permission has not been granted.
            // We cannot distinguish "not yet asked" from "denied" via ScreenCaptureKit,
            // so we keep .unknown until the user explicitly requests.
            await MainActor.run {
                if screenRecordingPermission != .unknown {
                    screenRecordingPermission = .denied
                }
            }
        }
    }

    private func requestScreenRecordingPermission() async {
        // CGRequestScreenCaptureAccess opens System Settings for the user to grant permission.
        CGRequestScreenCaptureAccess()
        // Re-check after a brief delay to allow the user to grant permission.
        try? await Task.sleep(for: .seconds(1))
        await checkScreenRecordingPermission()
    }
    #endif

    private func openSystemSettings() {
        #if os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        #else
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        #endif
    }

    private func advanceStep() {
        withAnimation(TS.Animation.smooth) {
            let steps = visibleSteps
            if let currentIndex = steps.firstIndex(of: currentStep),
               currentIndex + 1 < steps.count {
                currentStep = steps[currentIndex + 1]
            }
        }
    }

    private func goBackStep() {
        withAnimation(TS.Animation.smooth) {
            let steps = visibleSteps
            if let currentIndex = steps.firstIndex(of: currentStep),
               currentIndex > 0 {
                currentStep = steps[currentIndex - 1]
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .frame(width: 500, height: 700)
}
