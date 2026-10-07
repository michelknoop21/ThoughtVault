// AccountView+iOS.swift
// ThoughtVault
//
// iOS Account, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-account-northstar.jpg): profile card and
// grouped rows for profile, security, privacy and logout. Rows open the
// existing account sections. The NorthStar's subscription, preferences and
// active-sessions rows have no backing data in the app and are left out;
// account deletion stays the existing request via support.

#if os(iOS)
import SwiftUI

extension AccountView {

    var iosBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    IOSNightIllustration()
                        .frame(width: 210, height: 105)
                        .offset(x: IOSMetric.gutter, y: -10)
                    IOSScreenTitle(title: "Account",
                                   subtitle: "Beheer je account, beveiliging en gegevens bij ThoughtVault.")
                        .padding(.trailing, 110)
                }
                profileCard
                    .padding(.top, 18)

                section("Profiel") {
                    row(icon: "person", title: "Persoonlijke gegevens", subtitle: "Naam en e-mailadres") {
                        sub("Persoonlijke gegevens") { profileSection }
                    }
                }

                section("Beveiliging") {
                    row(icon: "lock", title: "Wachtwoord wijzigen", subtitle: "Kies een nieuw, sterk wachtwoord") {
                        sub("Wachtwoord") { passwordSection }
                    }
                    IOSDivider()
                    NavigationLink {
                        sub("Tweestapsverificatie") { twoFASection }
                    } label: {
                        IOSRow(icon: "shield", tint: .blue, title: "Tweestapsverificatie",
                               subtitle: twoFASubtitle) {
                            HStack(spacing: 10) {
                                if twoFAStatus?.enabled == true {
                                    Text("Actief").font(.system(size: 13)).foregroundStyle(IOSColor.ready)
                                }
                                IOSChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                section("Privacy & data") {
                    Button { Task { await exportUserData() } } label: {
                        IOSRow(icon: "square.and.arrow.down", title: "Gegevens exporteren",
                               subtitle: exportSuccessMessage ?? "Download een kopie van je data") {
                            if isExportingData { ProgressView().tint(IOSColor.lavender) } else { IOSChevron() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExportingData)
                    IOSDivider()
                    Link(destination: URL(string: "mailto:support@prezent.nl?subject=GDPR%20Account%20Verwijdering%20ThoughtVault")!) {
                        IOSRow(icon: "trash", tint: .red, title: "Account verwijderen",
                               subtitle: "Aanvraag via support, binnen 30 dagen verwerkt") {
                            Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(IOSColor.text2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.danger)
                        .padding(.top, 10)
                }

                section("Overig") {
                    Button { showLogoutConfirm = true } label: {
                        IOSRow(icon: "rectangle.portrait.and.arrow.right", tint: .red, title: "Uitloggen",
                               subtitle: "Log uit op dit apparaat") { IOSChevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .iosScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var twoFASubtitle: String {
        guard let status = twoFAStatus else { return "Extra beveiliging voor je account" }
        guard status.enabled else { return "Uit" }
        if let left = status.backupCodesRemaining { return "\(left) backupcodes over" }
        return "Extra beveiliging voor je account"
    }

    // MARK: Profile card

    private var profileCard: some View {
        let user = authVM.currentUser
        return HStack(spacing: 18) {
            ZStack {
                Circle().strokeBorder(IOSColor.borderViolet, lineWidth: 1).frame(width: 84, height: 84)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.74, green: 0.46, blue: 1.0), Color(red: 0.46, green: 0.24, blue: 0.90)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
                    .frame(width: 70, height: 70)
                Group {
                    if let initials = user?.initials, !initials.isEmpty {
                        Text(initials.uppercased()).font(.system(size: 26, weight: .bold))
                    } else {
                        Image(systemName: "person").font(.system(size: 26))
                    }
                }
                .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name.flatMap { $0.isEmpty ? nil : $0 } ?? (user == nil ? "Niet ingelogd" : "Account"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(IOSColor.text)
                    .lineLimit(1)
                if let email = user?.email {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundStyle(IOSColor.link)
                        .lineLimit(1)
                }
                if user?.role?.lowercased() == "admin" {
                    Text("Admin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IOSColor.lavender)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(IOSColor.tile))
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .iosCard(raised: true)
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let rows = content()
        return VStack(alignment: .leading, spacing: 10) {
            IOSSectionHeader(title)
            IOSGroup { rows }
        }
        .padding(.top, 22)
    }

    private func row<Destination: View>(icon: String, title: String, subtitle: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            IOSRow(icon: icon, title: title, subtitle: subtitle) { IOSChevron() }
        }
        .buttonStyle(.plain)
    }

    private func sub<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        List { content() }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(IOSBackground())
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
