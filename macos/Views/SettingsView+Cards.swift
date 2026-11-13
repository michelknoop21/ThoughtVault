// SettingsView+Cards.swift
// ThoughtVault
//
// macOS Instellingen tabs Algemeen, Notulen, Agenda, Obsidian, Account and
// Geavanceerd as cards with an icon and a heading, in the style of the
// Verwerking page. Every row is the existing settings row (the iOS sections
// show the same rows); only the presentation differs. Two columns when the
// content area is wide enough, one column below that.

#if os(macOS)
import SwiftUI

extension SettingsView {

    // MARK: Page

    /// Two columns from a 980 pt content width, else one; capped so lines stay
    /// readable on a wide screen.
    private func cardsPage<Left: View, Right: View>(
        _ layout: SettingsLayout,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        pageScroll(layout) {
            if layout.w - layout.leading - layout.trailing >= 980 {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) { left() }.frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: 18) { right() }.frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: 1240, alignment: .leading)
            } else {
                VStack(spacing: 18) {
                    left()
                    right()
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    /// One column on a readable width, for tabs with a single card.
    private func cardsColumn<Content: View>(_ layout: SettingsLayout, @ViewBuilder content: () -> Content) -> some View {
        pageScroll(layout) {
            VStack(spacing: 18) { content() }.frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func pageScroll<Content: View>(_ layout: SettingsLayout, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.vertical) {
            content()
                .padding(.leading, layout.leading)
                .padding(.trailing, layout.trailing)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Algemeen

    func algemeenCards(_ layout: SettingsLayout) -> some View {
        cardsPage(layout) {
            #if !APP_STORE
            SettingsCard(icon: "arrow.triangle.2.circlepath", title: "Updates") { updatesRows }
            #endif
            // No server to connect to in local mode.
            if !isLocalProcessing {
                SettingsCard(icon: "network", title: "Verbinding",
                             subtitle: "Status van de verbinding met de ThoughtVault-server.") { verbindingRows }
            }
        } right: {
            SettingsCard(icon: "info.circle", title: "Over") { overRows }
        }
    }

    // MARK: Notulen

    func notulenCards(_ layout: SettingsLayout) -> some View {
        cardsPage(layout) {
            SettingsCard(icon: "doc.text", title: "Profielen",
                         subtitle: "Het standaard profiel wordt automatisch geselecteerd bij een nieuwe opname.") { profielenRows }
            SettingsCard(icon: "arrow.counterclockwise", title: "Onboarding",
                         subtitle: "Doorloop de welkomststappen en toestemmingen opnieuw, bijvoorbeeld om je profiel of permissies opnieuw in te stellen.") { onboardingRows }
        } right: {
            SettingsCard(icon: "person.crop.circle", title: "Profiel", subtitle: "Over jou") {
                ProfileSettingsView(embedded: true)
            }
        }
    }

    // MARK: Agenda

    func agendaCards(_ layout: SettingsLayout) -> some View {
        cardsColumn(layout) {
            SettingsCard(icon: "calendar", title: "Agenda",
                         subtitle: "ThoughtVault detecteert Teams-, Zoom- en Meet-vergaderingen en biedt een snelkoppeling om opnames te starten.") { agendaRows }
        }
    }

    // MARK: Obsidian

    func obsidianCards(_ layout: SettingsLayout) -> some View {
        vaultFolderImporter(cardsPage(layout) {
            SettingsCard(icon: "tray.and.arrow.down", title: "Obsidian-koppeling", subtitle: LocalizedStringKey(obsidianFooterText)) { obsidianRows }
        } right: {
            SettingsCard(icon: "network", title: "Local REST API") { obsidianRestRows }
            SettingsCard(icon: "doc.text", title: "Prospect Flow",
                         subtitle: "Maakt vanuit een notule een conceptofferte in Prospect Flow. Er gaat nooit iets naar de klant.") {
                ProspectFlowSettingsSection(inCard: true)
            }
        })
    }

    // MARK: Account

    func accountCards(_ layout: SettingsLayout) -> some View {
        cardsPage(layout) {
            if isLocalProcessing {
                SettingsCard(icon: "person", title: "Lokale app",
                             subtitle: "Deze app werkt lokaal zonder ThoughtVault-login.") {
                    Text("Je profiel stel je in bij Notulen.")
                        .font(.system(size: 13.5)).foregroundStyle(HomeColor.text2)
                }
            } else {
                SettingsCard(icon: "person", title: "Account") { accountRows }
            }
            supportContactCard
        } right: {
            supportCard
        }
        .onAppear {
            supportNameDraft = IOSDebug.supportSettingsSnapshot ? "Anna Voorbeeld" : supportName
            supportEmailDraft = IOSDebug.supportSettingsSnapshot ? "anna@example.com" : supportEmail
        }
    }

    private var supportContactCard: some View {
        SettingsCard(icon: "envelope", title: "Contact voor meldingen",
                     subtitle: "Hierop krijg je antwoord op je meldingen.") {
            SettingFieldRow("Naam") {
                TextField("Naam", text: $supportNameDraft)
                    .textContentType(.name)
                    .studioField()
            }
            SettingFieldRow("E-mailadres") {
                TextField("E-mailadres", text: $supportEmailDraft)
                    .textContentType(.emailAddress)
                    .studioField()
            }
            if !supportEmailDraft.isEmpty && !SupportIdentity.isValidEmail(supportEmailDraft) {
                Text("Dit e-mailadres klopt niet.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusError)
            }
            if supportNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 200 || supportEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 320 {
                Text(String(localized: "support.identity.limit"))
                    .font(TS.Font.caption).foregroundStyle(Color.statusError)
            }
            Button("Opslaan", action: saveSupportIdentity)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSaveSupportIdentity)
        }
        .allowsHitTesting(!IOSDebug.supportSettingsSnapshot)
    }

    private var supportCard: some View {
        SettingsCard(icon: "lifepreserver", title: "Support",
                     subtitle: "Meld een probleem en lees het antwoord in de app.") {
            supportRowButton(icon: "square.and.pencil", title: "Melding maken") { openSupport(.report) }
            supportRowButton(icon: "bubble.left.and.bubble.right", title: "Mijn meldingen",
                             badge: supportVM.unreadCount) { openSupport(.tickets) }
            Divider().overlay(HomeColor.divider)
            Toggle(isOn: $supportAutoReport) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Foutrapporten automatisch versturen")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(HomeColor.text)
                    Text("Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee.")
                        .font(.system(size: 12.5)).foregroundStyle(HomeColor.text2)
                }
            }
            Divider().overlay(HomeColor.divider)
            supportRowButton(icon: "doc.text.magnifyingglass", title: "Toon logbestand") {
                NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL])
            }
            Link(String(localized: "support.privacy.link"), destination: SupportLinks.privacy)
                .font(.system(size: 13))
                .foregroundStyle(HomeColor.lavender)
        }
        .allowsHitTesting(!IOSDebug.supportSettingsSnapshot)
    }

    private func supportRowButton(icon: String, title: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(HomeColor.lavender).frame(width: 18)
                Text(title)
                Spacer(minLength: 8)
                if badge > 0 {
                    Text(badge, format: .number)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color.brandPrimary))
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(HomeColor.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(StudioQuietButtonStyle(height: 40))
    }

    // MARK: Geavanceerd

    func geavanceerdCards(_ layout: SettingsLayout) -> some View {
        cardsColumn(layout) {
            SettingsCard(icon: "lock.shield", title: "Permissies") { permissiesRows }
            BrandFooter()
        }
    }
}
#endif
