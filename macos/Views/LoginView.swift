// LoginView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Login screen with email/password, biometric login, and two-factor authentication.
// Forced light mode to maintain consistent brand presentation.

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - LoginView

struct LoginView: View {

    @Environment(AuthViewModel.self) var authVM

    @AppStorage("rememberUsername") private var rememberUsername: Bool = false
    @AppStorage("processingMode") private var processingMode: String = ProcessingMode.local.rawValue
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var twoFactorCode: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showForgotPassword: Bool = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.96, blue: 0.98),
                    Color(red: 0.92, green: 0.93, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Brand bar full width under window title bar
                BrandBar(height: 4)

                Spacer()

                // Branding
                brandingHeader

                Spacer()
                    .frame(maxHeight: TS.Spacing.xl)

                // Main card
                Group {
                    if authVM.requiresTwoFactor {
                        twoFactorCard
                    } else {
                        loginCard
                    }
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, TS.Spacing.xl)

                Spacer()

                // Footer
                yingaFooter
                    .padding(.bottom, TS.Spacing.sm)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(initialEmail: email)
        }
    }

    // MARK: - Branding Header

    private var brandingHeader: some View {
        VStack(spacing: TS.Spacing.md) {
            // App icon
            #if os(macOS)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            #else
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            #endif

            (Text("Thought").foregroundStyle(Color.labelPrimary)
                + Text("Vault").foregroundStyle(
                    LinearGradient(colors: [Color.brandLavender, Color.brandPrimary, Color.brandSecondary],
                                   startPoint: .leading, endPoint: .trailing)))
                .font(TS.Font.largeTitleBold)
        }
    }

    // MARK: - Brand Footer

    private var yingaFooter: some View {
        BrandFooter()
    }

    // MARK: - Login Card

    private var loginCard: some View {
        VStack(spacing: TS.Spacing.lg) {
            VStack(spacing: TS.Spacing.sm) {
                Text("Inloggen")
                    .font(TS.Font.title3Bold)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Voer je e-mailadres en wachtwoord in om door te gaan.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: TS.Spacing.md) {
                // Email field
                VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                    Text("E-mailadres")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelSecondary)

                    TextField("naam@bedrijf.nl", text: $email)
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .padding(TS.Spacing.sm + 2)
                        .background(Color.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                        .overlay {
                            RoundedRectangle(cornerRadius: TS.Radius.sm)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        }
                }

                // Password field
                VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                    Text("Wachtwoord")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelSecondary)

                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField("••••••••", text: $password)
                            } else {
                                SecureField("••••••••", text: $password)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(TS.Font.body)
                        .textContentType(.password)

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(Color.labelTertiary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Wachtwoord verbergen" : "Wachtwoord tonen")
                    }
                    .padding(TS.Spacing.sm + 2)
                    .background(Color.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    }

                    // Forgot password
                    Button("Wachtwoord vergeten?") {
                        showForgotPassword = true
                    }
                    .buttonStyle(.plain)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.brandSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // Remember username toggle
            Toggle("Onthoud gebruikersnaam", isOn: $rememberUsername)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
                .onChange(of: rememberUsername) { _, newValue in
                    if !newValue {
                        authVM.userEmail = ""
                    }
                }

            // Error message
            if let error = authVM.errorMessage {
                errorBanner(error)
            }

            // Login button
            Button {
                Task { await authVM.login(email: email, password: password) }
            } label: {
                Group {
                    if authVM.isLoading {
                        HStack(spacing: TS.Spacing.sm) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Inloggen...")
                        }
                    } else {
                        Text("Inloggen")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(authVM.isLoading || email.isEmpty || password.isEmpty)

            // Biometric login
            if BiometricService.shared.isEnabled {
                biometricLoginButton
            }

            // Use the app fully locally, without the server (no account needed).
            Button {
                processingMode = ProcessingMode.local.rawValue
            } label: {
                Text("Lokaal gebruiken (zonder server)")
                    .font(TS.Font.footnoteSemibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandPrimary)
            .padding(.top, TS.Spacing.xs)
        }
        .onSubmit {
            guard !authVM.isLoading && !email.isEmpty && !password.isEmpty else { return }
            Task { await authVM.login(email: email, password: password) }
        }
        .padding(TS.Spacing.lg)
        .modernCard()
        .onAppear {
            if rememberUsername, !authVM.userEmail.isEmpty {
                email = authVM.userEmail
            }
        }
    }

    // MARK: - Two-Factor Authentication Card

    private var twoFactorCard: some View {
        VStack(spacing: TS.Spacing.lg) {
            VStack(spacing: TS.Spacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.brandPrimary)

                Text("Twee-factor verificatie")
                    .font(TS.Font.title3Bold)
                    .foregroundStyle(Color.labelPrimary)

                Text("Voer de 6-cijferige code in uit je authenticator-app.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text("Verificatiecode")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)

                TextField("000000", text: $twoFactorCode)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .multilineTextAlignment(.center)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .padding(TS.Spacing.sm + 2)
                    .background(Color.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    }
                    .onChange(of: twoFactorCode) { _, new in
                        // Auto-submit when 6 digits entered
                        if new.count == 6 {
                            Task { await authVM.verifyTwoFactor(code: new) }
                        }
                    }
            }

            // Error message
            if let error = authVM.errorMessage {
                errorBanner(error)
            }

            Button {
                Task { await authVM.verifyTwoFactor(code: twoFactorCode) }
            } label: {
                Group {
                    if authVM.isLoading {
                        HStack(spacing: TS.Spacing.sm) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Verifiëren...")
                        }
                    } else {
                        Text("Verifiëren")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(authVM.isLoading || twoFactorCode.count < 6)

            Button("Terug naar inloggen") {
                authVM.requiresTwoFactor = false
                authVM.tempToken = nil
                authVM.errorMessage = nil
                twoFactorCode = ""
            }
            .buttonStyle(.plain)
            .font(TS.Font.footnote)
            .foregroundStyle(Color.labelSecondary)
        }
        .padding(TS.Spacing.lg)
        .modernCard()
    }

    // MARK: - Biometric Login Button

    private var biometricLoginButton: some View {
        Button {
            Task { await authVM.loginWithBiometrics() }
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                let type = BiometricService.shared.availableType
                Image(systemName: type == .faceID ? "faceid" : "touchid")
                    .font(.system(size: 18))
                Text(type == .faceID ? "Inloggen met Face ID" : "Inloggen met Touch ID")
                    .font(TS.Font.bodyMedium)
            }
            .foregroundStyle(Color.brandSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TS.Spacing.sm)
            .background(Color.brandSecondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.sm)
                    .stroke(Color.brandSecondary.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(authVM.isLoading)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusError)
            Text(message)
                .font(TS.Font.footnote)
                .foregroundStyle(Color.statusError)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TS.Spacing.sm)
        .background(Color.statusError.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.xs)
                .stroke(Color.statusError.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - Forgot Password

/// Self-contained 3-step password reset flow (request code → verify → set new
/// password), backed by the /auth/password-reset/* endpoints. Defined in this
/// file to avoid an Xcode project edit.
struct ForgotPasswordView: View {

    let initialEmail: String

    @Environment(\.dismiss) private var dismiss

    private enum Step { case request, verify, complete, done }

    @State private var step: Step = .request
    @State private var email: String = ""
    @State private var code: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var resetToken: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.lg) {
            header

            switch step {
            case .request:  requestStep
            case .verify:   verifyStep
            case .complete: completeStep
            case .done:     doneStep
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(TS.Spacing.xl)
        .frame(width: 420)
        .onAppear { email = initialEmail }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wachtwoord vergeten")
                    .font(TS.Font.title3Bold)
                    .foregroundStyle(Color.labelPrimary)
                Text(subtitle)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.labelTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sluiten")
        }
    }

    private var subtitle: LocalizedStringKey {
        switch step {
        case .request:  return "Voer je e-mailadres in. We sturen je een verificatiecode."
        case .verify:   return "Voer de 6-cijferige code in uit je e-mail."
        case .complete: return "Kies een nieuw wachtwoord."
        case .done:     return "Je wachtwoord is gewijzigd."
        }
    }

    // MARK: Steps

    private var requestStep: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            fieldLabel("E-mailadres")
            TextField("naam@bedrijf.nl", text: $email)
                .textFieldStyle(.plain)
                .font(TS.Font.body)
                .autocorrectionDisabled()
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .padding(TS.Spacing.sm + 2)
                .background(fieldBackground)

            primaryButton("Verstuur code", loadingTitle: "Versturen...") {
                await sendCode()
            }
            .disabled(email.isEmpty)
        }
    }

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Code verstuurd naar \(email) — als er een account bestaat.")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)

            fieldLabel("Verificatiecode")
            TextField("000000", text: $code)
                .textFieldStyle(.plain)
                .font(TS.Font.title3)
                .monospacedDigit()
                .padding(TS.Spacing.sm + 2)
                .background(fieldBackground)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }

            primaryButton("Verifieer code", loadingTitle: "Verifiëren...") {
                await verifyCode()
            }
            .disabled(code.count != 6)

            Button("Code opnieuw versturen") {
                Task { await sendCode() }
            }
            .buttonStyle(.plain)
            .font(TS.Font.footnote)
            .foregroundStyle(Color.brandSecondary)
        }
    }

    private var completeStep: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            fieldLabel("Nieuw wachtwoord")
            SecureField("Minimaal 8 tekens", text: $newPassword)
                .textFieldStyle(.plain)
                .font(TS.Font.body)
                .textContentType(.newPassword)
                .padding(TS.Spacing.sm + 2)
                .background(fieldBackground)

            fieldLabel("Bevestig nieuw wachtwoord")
            SecureField("Herhaal wachtwoord", text: $confirmPassword)
                .textFieldStyle(.plain)
                .font(TS.Font.body)
                .textContentType(.newPassword)
                .padding(TS.Spacing.sm + 2)
                .background(fieldBackground)

            primaryButton("Wachtwoord wijzigen", loadingTitle: "Opslaan...") {
                await completeReset()
            }
            .disabled(newPassword.count < 8 || newPassword != confirmPassword)
        }
    }

    private var doneStep: some View {
        VStack(spacing: TS.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusSuccess)
            Text("Je kunt nu inloggen met je nieuwe wachtwoord.")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text("Sluiten").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TS.Spacing.md)
    }

    // MARK: Building blocks

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(TS.Font.footnoteSemibold)
            .foregroundStyle(Color.labelSecondary)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: TS.Radius.sm)
            .fill(Color.surfacePrimary)
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.sm)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            }
    }

    private func primaryButton(_ title: LocalizedStringKey, loadingTitle: LocalizedStringKey, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                if isLoading {
                    HStack(spacing: TS.Spacing.sm) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(loadingTitle)
                    }
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }

    // MARK: Actions

    private func sendCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIService.shared.requestPasswordReset(username: email.trimmingCharacters(in: .whitespaces).lowercased())
            step = .verify
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            resetToken = try await APIService.shared.verifyPasswordResetCode(
                username: email.trimmingCharacters(in: .whitespaces).lowercased(),
                code: code
            )
            step = .complete
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeReset() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIService.shared.completePasswordReset(
                username: email.trimmingCharacters(in: .whitespaces).lowercased(),
                resetToken: resetToken,
                newPassword: newPassword
            )
            step = .done
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environment(AuthViewModel())
        .frame(width: 900, height: 600)
}
