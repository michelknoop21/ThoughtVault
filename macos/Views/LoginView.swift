// LoginView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
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
                // Yinga brand bar full width under window title bar
                YingaBar(height: 4)

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

            Text("Transcript Studio")
                .font(TS.Font.largeTitleBold)
                .foregroundStyle(Color.brandPrimary)
        }
    }

    // MARK: - Yinga Footer

    private var yingaFooter: some View {
        YingaFooter()
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
                }
            }

            // Remember username toggle
            Toggle("Onthoud gebruikersnaam", isOn: $rememberUsername)
                .toggleStyle(.checkbox)
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

// MARK: - Preview

#Preview {
    LoginView()
        .environment(AuthViewModel())
        .frame(width: 900, height: 600)
}
