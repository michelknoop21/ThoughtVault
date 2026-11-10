import SwiftUI

extension SettingsView {
    var feedbackSection: some View {
        Section {
            #if os(macOS)
            Button { openSupport(.report) } label: {
                Label("Melding maken", systemImage: "square.and.pencil")
            }
            Button { openSupport(.tickets) } label: { supportTicketsLabel }
            #else
            NavigationLink { SupportSettingsReportView() } label: {
                Label("Melding maken", systemImage: "square.and.pencil")
            }
            NavigationLink { SupportSettingsTicketsView() } label: { supportTicketsLabel }
            #endif
            Toggle("Foutrapporten automatisch versturen", isOn: $supportAutoReport)
                .tint(Color.brandPrimary)
            Link(String(localized: "support.privacy.link"), destination: SupportLinks.privacy)
                .font(TS.Font.caption)
                .foregroundStyle(Color.brandPrimary)
            Text("Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee.")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
            TextField("Naam", text: $supportNameDraft)
                .textContentType(.name)
            TextField("E-mailadres", text: $supportEmailDraft)
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if !supportEmailDraft.isEmpty && !SupportIdentity.isValidEmail(supportEmailDraft) {
                Text("Dit e-mailadres klopt niet.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusError)
            }
            Button("Opslaan") {
                guard !IOSDebug.supportSettingsSnapshot,
                      SupportIdentity.isComplete(name: supportNameDraft, email: supportEmailDraft) else { return }
                supportName = supportNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                supportEmail = supportEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .disabled(!SupportIdentity.isComplete(name: supportNameDraft, email: supportEmailDraft)
                      || (supportNameDraft == supportName && supportEmailDraft == supportEmail))
        } header: {
            Text("Support")
        }
        .onAppear {
            supportNameDraft = IOSDebug.supportSettingsSnapshot ? "Anna Voorbeeld" : supportName
            supportEmailDraft = IOSDebug.supportSettingsSnapshot ? "anna@example.com" : supportEmail
        }
        .allowsHitTesting(!IOSDebug.supportSettingsSnapshot)
    }

    private var supportTicketsLabel: some View {
        HStack {
            Label("Mijn meldingen", systemImage: "bubble.left.and.bubble.right")
            Spacer()
            if supportVM.unreadCount > 0 {
                Text(supportVM.unreadCount, format: .number)
                    .font(TS.Font.caption)
                    .padding(.horizontal, TS.Spacing.sm)
                    .background(Color.brandPrimary, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    #if os(macOS)
    private func openSupport(_ pane: SupportPane) {
        guard !IOSDebug.supportSettingsSnapshot else { return }
        supportVM.pane = pane
        openSupportWindow(id: "support")
    }
    #endif

    // MARK: - Updates

    var updatesSection: some View {
        Section {
            Toggle(isOn: $checkForUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Controleer op updates")
                        .font(TS.Font.body)
                    Text("Toon een melding op de homepage als er een nieuwe versie beschikbaar is")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .tint(Color.brandPrimary)
        } header: {
            Text("Updates")
        }
    }

}

#if os(iOS)
private struct SupportSettingsReportView: View {
    @State private var category: SupportCategory = .bug
    @State private var description = ""
    @State private var outcome: SendOutcome?
    @State private var sending = false

    var body: some View {
        SupportReportForm(category: $category, description: $description, outcome: $outcome, sending: $sending)
            .padding(TS.Spacing.md)
            .navigationTitle("Melding maken")
            .navigationBarBackButtonHidden(sending)
    }
}

private struct SupportSettingsTicketsView: View {
    @State private var selectedTicket: SupportTicket?
    @State private var replies: [String: String] = [:]
    @State private var replying = false

    var body: some View {
        SupportTicketList { selectedTicket = $0 }
            .padding(TS.Spacing.md)
            .navigationTitle("Mijn meldingen")
            .navigationDestination(isPresented: Binding(
                get: { selectedTicket != nil },
                set: { if !$0 { selectedTicket = nil } })) {
                if let ticket = selectedTicket {
                    SupportThreadView(ticket: ticket, draft: Binding(
                        get: { replies[ticket.id, default: ""] },
                        set: { replies[ticket.id] = $0 }), sending: $replying)
                        .padding(TS.Spacing.md)
                        .navigationTitle(ticket.ref)
                        .navigationBarBackButtonHidden(replying)
                }
            }
    }
}
#endif
