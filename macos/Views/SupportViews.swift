import SwiftUI

struct SupportCenterView: View {
    @Environment(SupportViewModel.self) private var support
    @Environment(\.dismiss) private var dismiss
    @State private var category: SupportCategory = .bug
    @State private var description = ""
    @State private var outcome: SendOutcome?
    @State private var sending = false
    @State private var selectedTicket: SupportTicket?
    @State private var replies: [String: String] = [:]
    @State private var replying = false

    var body: some View {
        @Bindable var support = support
        VStack(spacing: TS.Spacing.md) {
            HStack {
                Text("Support").font(TS.Font.titleBold)
                Spacer()
                Button("Sluiten") { dismiss() }
            }
            Picker("Support", selection: $support.pane) {
                Text("Melding maken").tag(SupportPane.report)
                Text("Mijn meldingen").tag(SupportPane.tickets)
            }
            .pickerStyle(.segmented)
            .disabled(replying)
            if support.pane == .report {
                SupportReportForm(category: $category, description: $description,
                                  outcome: $outcome, sending: $sending)
            } else if let ticket = selectedTicket {
                Button("Terug naar Mijn meldingen") { selectedTicket = nil }
                    .disabled(replying)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SupportThreadView(ticket: ticket, draft: Binding(
                    get: { replies[ticket.id, default: ""] },
                    set: { replies[ticket.id] = $0 }), sending: $replying)
            } else {
                SupportTicketList { selectedTicket = $0 }
            }
        }
        .padding(TS.Spacing.lg)
        .foregroundStyle(Color.labelPrimary)
        .background(.regularMaterial)
        .frame(idealWidth: 640, idealHeight: 620)
        .task {
            #if DEBUG
            if IOSDebug.supportSeed {
                DebugScreenshotSeed.seedSupport(support)
                if IOSDebug.open != "support-report" { support.pane = .tickets }
                if IOSDebug.open == "support-thread" { selectedTicket = support.tickets.first }
                DebugScreenshotSeed.sizeWindow()
                await DebugScreenshotSeed.snapshotAndQuit()
            }
            #endif
        }
    }
}

struct SupportReportForm: View {
    @Environment(SupportViewModel.self) private var support
    @Binding var category: SupportCategory
    @Binding var description: String
    @Binding var outcome: SendOutcome?
    @Binding var sending: Bool

    private var trimmed: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TS.Spacing.md) {
                Picker("Categorie", selection: $category) {
                    Text("Fout").tag(SupportCategory.bug)
                    Text("Idee").tag(SupportCategory.featureRequest)
                    Text("Vraag").tag(SupportCategory.question)
                }
                .pickerStyle(.segmented)
                .disabled(sending)
                Text("Omschrijving").font(TS.Font.calloutSemibold)
                TextEditor(text: $description)
                    .font(TS.Font.body)
                    .frame(minHeight: 160)
                    .accessibilityLabel(Text("Omschrijving"))
                    .disabled(sending)
                    .onChange(of: description) { _, value in
                        if value.count > 5_000 { description = String(value.prefix(5_000)) }
                    }
                Text("\(description.count)/5000").font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                Button("Versturen") {
                    guard !sending, !trimmed.isEmpty, !IOSDebug.supportSeed else { return }
                    sending = true
                    outcome = nil
                    let body = trimmed
                    let selectedCategory = category
                    Task {
                        let result = await support.submit(category: selectedCategory, description: body)
                        outcome = result
                        switch result {
                        case .sent, .queued: description = ""
                        case .failed: break
                        }
                        sending = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmed.isEmpty || sending || IOSDebug.supportSeed)
                if sending { ProgressView().accessibilityLabel(Text("Versturen")) }
                if let outcome {
                    switch outcome {
                    case .sent:
                        Text("Verstuurd. Het antwoord zie je in Mijn meldingen en in je e-mail.")
                    case .queued:
                        Text("Geen verbinding. De melding gaat vanzelf de deur uit zodra je weer online bent.")
                    case .failed:
                        Text("Versturen lukte niet. Probeer het zo nog eens.")
                    }
                }
            }
        }
        .onAppear { AppLog.clickPath.info("Melding maken geopend") }
    }
}

struct SupportTicketList: View {
    @Environment(SupportViewModel.self) private var support
    let select: (SupportTicket) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TS.Spacing.md) {
                Button("Vernieuwen") { Task { await support.loadTickets() } }
                if support.tickets.isEmpty {
                    Text("Nog geen meldingen. Via Melding maken stuur je een fout, idee of vraag.")
                        .foregroundStyle(Color.labelSecondary)
                }
                ForEach(support.tickets) { ticket in
                    Button { select(ticket) } label: {
                        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                            HStack {
                                Text(ticket.ref).font(TS.Font.calloutSemibold)
                                if ticket.unread {
                                    Circle().fill(Color.brandPrimary).frame(width: 8, height: 8)
                                        .accessibilityLabel(Text("Ongelezen"))
                                }
                                Spacer()
                                Text(ticket.updatedAt ?? ticket.createdAt, style: .relative)
                                    .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                            }
                            Text(ticket.description.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "")
                                .font(TS.Font.body).lineLimit(1)
                            Text(statusLabel(ticket.status)).font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .padding(TS.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: TS.Radius.sm))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            AppLog.clickPath.info("Mijn meldingen geopend")
            await support.loadTickets()
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "NEW": String(localized: "Nieuw")
        case "IN_PROGRESS": String(localized: "In behandeling")
        case "WAITING_FOR_USER": String(localized: "Wacht op jou")
        case "RESOLVED": String(localized: "Opgelost")
        case "CLOSED": String(localized: "Gesloten")
        default: status
        }
    }
}

struct SupportThreadView: View {
    @Environment(SupportViewModel.self) private var support
    let ticket: SupportTicket
    @Binding var draft: String
    @Binding var sending: Bool
    @State private var failed = false
    @State private var loading = true
    @State private var snapshot = SupportThreadSnapshot()

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text(ticket.ref).font(TS.Font.calloutSemibold)
            if loading { ProgressView() }
            ScrollView {
                VStack(spacing: TS.Spacing.md) {
                    ForEach((snapshot.ticketID == ticket.id ? snapshot.messages : []).sorted { $0.createdAt < $1.createdAt }) { message in
                        HStack {
                            if message.senderRole != "ADMIN" { Spacer(minLength: TS.Spacing.xl) }
                            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                                Text(message.body).font(TS.Font.body).textSelection(.enabled)
                                Text(message.createdAt, style: .date).font(TS.Font.caption)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                            .padding(TS.Spacing.md)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: TS.Radius.sm))
                            if message.senderRole == "ADMIN" { Spacer(minLength: TS.Spacing.xl) }
                        }
                    }
                }
            }
            Text("Antwoord").font(TS.Font.calloutSemibold)
            TextEditor(text: $draft).font(TS.Font.body).frame(minHeight: 70, maxHeight: 120)
                .accessibilityLabel(Text("Antwoord")).disabled(sending)
            Button("Stuur") {
                guard !sending, !trimmed.isEmpty, !IOSDebug.supportSeed else { return }
                sending = true
                failed = false
                let body = trimmed
                let request = snapshot.begin(ticketID: ticket.id)
                Task {
                    do {
                        let messages = try await support.reply(body, to: ticket)
                        snapshot.complete(messages, ticketID: ticket.id, request: request)
                        draft = ""
                    } catch { failed = true }
                    sending = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmed.isEmpty || sending || loading || snapshot.ticketID != ticket.id || IOSDebug.supportSeed)
            if failed { Text("Versturen lukte niet. Probeer het zo nog eens.") }
        }
        .task(id: ticket.id) {
            loading = true
            let request = snapshot.begin(ticketID: ticket.id)
            let messages = await support.messages(for: ticket)
            guard !Task.isCancelled else { return }
            snapshot.complete(messages, ticketID: ticket.id, request: request)
            loading = false
        }
    }
}

struct SupportThreadSnapshot {
    private(set) var ticketID: String?
    private(set) var messages: [SupportMessage] = []
    private var request: UUID?

    mutating func begin(ticketID: String) -> UUID {
        if self.ticketID != ticketID { messages = [] }
        self.ticketID = ticketID
        let request = UUID()
        self.request = request
        return request
    }

    mutating func complete(_ messages: [SupportMessage]?, ticketID: String, request: UUID) {
        guard self.ticketID == ticketID, self.request == request, let messages else { return }
        self.messages = messages
    }
}
