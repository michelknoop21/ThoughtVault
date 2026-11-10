import SwiftUI

enum SupportLinks {
    static let privacy = URL(string: "https://thoughtvault.yinga.ai/privacy.html")!
}

struct SupportIdentityView: View {
    @AppStorage(SupportIdentity.nameKey) private var supportName = ""
    @AppStorage(SupportIdentity.emailKey) private var supportEmail = ""
    @State private var name = ""
    @State private var email = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TS.Spacing.lg) {
                Text("Voor wie zijn de antwoorden?")
                    .font(TS.Font.titleBold)
                    .foregroundStyle(Color.labelPrimary)
                Text("Antwoorden op je meldingen verschijnen in de app en komen per e-mail.")
                    .font(TS.Font.body)
                Text("Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                Link(String(localized: "support.privacy.link"), destination: SupportLinks.privacy)
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.brandPrimary)
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    Text("Naam").font(TS.Font.calloutSemibold)
                    TextField("Naam", text: $name)
                        .textContentType(.name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                    Text("E-mailadres").font(TS.Font.calloutSemibold)
                    TextField("E-mailadres", text: $email)
                        .textContentType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    if !email.isEmpty && !SupportIdentity.isValidEmail(email) {
                        Text("Dit e-mailadres klopt niet.")
                            .font(TS.Font.caption)
                            .foregroundStyle(.red)
                    }
                }
                if name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 200 || email.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 320 {
                    Text(String(localized: "support.identity.limit"))
                        .font(TS.Font.caption).foregroundStyle(Color.statusError)
                }
                Button("Doorgaan") {
                    guard SupportIdentity.isComplete(name: name, email: email) else { return }
                    supportName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    supportEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    AppLog.clickPath.info("Identiteit ingevuld")
                    if !AppEnvironment.isDebugSnapshot { Task { await SupportRelay.shared.flush() } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!SupportIdentity.isComplete(name: name, email: email))
            }
            .padding(TS.Spacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            name = supportName.isEmpty ? (LocalTranscriptStore.shared.fetchSelfProfile()?.name ?? "") : supportName
            email = supportEmail
        }
    }
}
