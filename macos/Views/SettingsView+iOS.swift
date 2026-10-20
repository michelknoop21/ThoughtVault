// SettingsView+iOS.swift
// ThoughtVault
//
// iOS Instellingen, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-instellingen-northstar.jpg): grouped
// cards of icon rows under spaced section labels. Every row opens an existing
// settings section, so all current settings stay reachable; Mensen and Admin
// moved here from the tab bar (product decision 2026-09-29). NorthStar rows
// without an existing setting (audio quality, notule language, notifications,
// e-mail summaries, theme) are left out.

#if os(iOS)
import SwiftUI

extension SettingsView {

    var iosSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                IOSBrandBar()
                    .padding(.top, -10)
                IOSScreenTitle(title: "Instellingen", subtitle: "Maak ThoughtVault helemaal van jou.")
                    .padding(.top, -4)

                group("Opname") {
                    if OnDeviceTranscriber.shared.isAvailable() {
                        IOSRow(icon: "mic", title: "Transcriptie op apparaat", subtitle: "Sneller, geen audiodata naar server") {
                            Toggle("Transcriptie op apparaat", isOn: $preferOnDeviceTranscription)
                                .labelsHidden()
                                .tint(IOSColor.violet)
                                .scaleEffect(0.9, anchor: .trailing)
                        }
                        IOSDivider()
                    }
                    link(icon: "slider.horizontal.3", title: "Opnameprofielen", subtitle: "Kies het standaardprofiel en beheer je profielen.") {
                        ProfilesView()
                    }
                }

                group("Notulen generatie") {
                    link(icon: "sparkles", title: "Verwerking",
                         subtitle: isLocalProcessing ? "Lokaal op dit apparaat" : "Cloud (server)") {
                        subpage("Verwerking") {
                            verwerkingsmodusSection
                            if isLocalProcessing {
                                transcriptieSection
                                lokaleNotulenSection
                            } else {
                                cloudNotulenSection
                            }
                        }
                    }
                    IOSDivider()
                    link(icon: "person.text.rectangle", title: "Over jou", subtitle: "Context voor betere notulen.") {
                        subpage("Over jou") { ProfileSettingsView() }
                    }
                }

                group("Agenda") {
                    link(icon: "calendar", title: "Agenda koppelen", subtitle: calendarSubtitle) {
                        subpage("Agenda") { agendaSection }
                    }
                }

                group("Integraties") {
                    link(icon: "tray.and.arrow.down", title: "Obsidian", subtitle: "Notulen automatisch naar je vault.") {
                        subpage("Obsidian") { obsidianSection }
                    }
                }

                group("Organisatie") {
                    link(icon: "person.2", title: "Mensen", subtitle: "Deelnemers en hun gegevens.") {
                        PeopleDirectoryView()
                    }
                    if authVM.currentUser?.role?.lowercased() == "admin" {
                        IOSDivider()
                        link(icon: "person.badge.key", title: "Admin", subtitle: "Gebruikers en instellingen beheren.") {
                            AdminView()
                        }
                    }
                }

                group("Account") {
                    link(icon: "person", title: "Account", subtitle: accountSubtitle) {
                        subpage("Account") { accountSection }
                    }
                    IOSDivider()
                    link(icon: "lock.shield", title: "Rechten", subtitle: "Microfoon en spraakherkenning.") {
                        subpage("Rechten") { permissiesSection }
                    }
                    IOSDivider()
                    link(icon: "info.circle", title: "Over ThoughtVault", subtitle: "Verbinding, updates en feedback.") {
                        subpage("Over ThoughtVault") {
                            verbindingSection
                            updatesSection
                            onboardingSection
                            feedbackSection
                            overSection
                        }
                    }
                }
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .iosScreen()
        .toolbar(.hidden, for: .navigationBar)
        // Screenshot hooks (debug builds only, see IOSDebug).
        .navigationDestination(isPresented: .constant(IOSDebug.open == "profiles")) { ProfilesView() }
        .navigationDestination(isPresented: .constant(IOSDebug.open == "account")) { AccountView() }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let rows = content()
        return VStack(alignment: .leading, spacing: 8) {
            IOSKicker(text: title)
                .padding(.leading, 2)
            IOSGroup { rows }
        }
        .padding(.top, 16)
    }

    private func link<Destination: View>(icon: String, title: String, subtitle: String?,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            IOSRow(icon: icon, title: title, subtitle: subtitle) { IOSChevron() }
        }
        .buttonStyle(.plain)
    }

    /// An existing settings section on the night background.
    private func subpage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(IOSBackground())
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var calendarSubtitle: String {
        if calendarService.isMicrosoftConnected { return "Microsoft 365 gekoppeld" }
        if calendarService.hasCalendarAccess { return "Apple Agenda gekoppeld" }
        return "Automatisch context uit je afspraken."
    }

    private var accountSubtitle: String {
        guard let user = authVM.currentUser else { return "Niet ingelogd" }
        return user.name.flatMap { $0.isEmpty ? nil : $0 } ?? user.email
    }
}
#endif
