// SupportViews+Mac.swift
// ThoughtVault
//
// macOS layout of the Support window, in the style of the rest of the app:
// a pill switch between Melding maken and Mijn meldingen, the report form as
// one card on a readable width, and the tickets as a list beside the
// conversation. Below 760 pt the tickets fall back to one pane (list, then
// conversation with a way back). State and actions stay in SupportViews.swift.

#if os(macOS)
import SwiftUI

// MARK: - Window

extension SupportCenterView {

    var macBody: some View {
        // Read state here, not only inside the GeometryReader closure, so a change
        // made before the first layout (the debug hook) still re-renders the panes.
        let selected = selectedTicket
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                if support.pane == .report {
                    ScrollView(.vertical) {
                        SupportReportForm(category: $category, description: $description,
                                          outcome: $outcome, sending: $sending)
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 28)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else if geo.size.width >= 760 {
                    ticketsSplit(width: geo.size.width, selected: selected)
                } else {
                    ticketsSinglePane(selected: selected)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .foregroundStyle(HomeColor.text)
        .background(
            LinearGradient(colors: [HomeColor.backgroundTop, HomeColor.backgroundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .frame(minWidth: 520, idealWidth: 980, minHeight: 480, idealHeight: 680)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Support")
                .font(.system(size: 24, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 2) {
                paneButton(.report, title: "Melding maken")
                paneButton(.tickets, title: "Mijn meldingen", badge: support.unreadCount)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(HomeColor.side))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(HomeColor.sideBorder, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Support"))
            .disabled(replying)
            Spacer(minLength: 12)
            Button("Sluiten") { dismiss() }
                .buttonStyle(StudioQuietButtonStyle(height: 34))
        }
    }

    private func paneButton(_ pane: SupportPane, title: LocalizedStringKey, badge: Int = 0) -> some View {
        StudioSegmentButton(title: title, badge: badge, selected: support.pane == pane, thumb: paneThumb) {
            withAnimation(TS.Animation.quick) { support.pane = pane }
        }
    }

    private func ticketsSplit(width: CGFloat, selected: SupportTicket?) -> some View {
        HStack(alignment: .top, spacing: 20) {
            SupportTicketList(selectedID: selected?.id) { selectedTicket = $0 }
                .frame(width: min(380, max(290, width * 0.3)))
                .disabled(replying)
            Group {
                if let ticket = selected {
                    SupportThreadView(ticket: ticket, draft: replyDraft(for: ticket), sending: $replying)
                } else {
                    Text("Kies links een melding om het gesprek te lezen.")
                        .font(.system(size: 14))
                        .foregroundStyle(HomeColor.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .supportCard()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private func ticketsSinglePane(selected: SupportTicket?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let ticket = selected {
                Button { selectedTicket = nil } label: {
                    Label("Terug naar Mijn meldingen", systemImage: "chevron.left")
                }
                .buttonStyle(StudioQuietButtonStyle(height: 32))
                .disabled(replying)
                SupportThreadView(ticket: ticket, draft: replyDraft(for: ticket), sending: $replying)
            } else {
                SupportTicketList { selectedTicket = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

private extension View {
    func supportCard() -> some View {
        background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HomeColor.card.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HomeColor.cardBorder, lineWidth: 1))
    }

    /// Dark editor chrome with an indigo ring while focused.
    func supportEditor(focused: Bool) -> some View {
        font(.system(size: 14.5))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeColor.field.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Color.brandSecondary : HomeColor.fieldBorder, lineWidth: focused ? 1.5 : 1))
            .animation(TS.Animation.quick, value: focused)
    }

    /// Placeholder over an empty TextEditor (TextEditor has none of its own).
    func editorPlaceholder(_ text: LocalizedStringKey, shown: Bool) -> some View {
        overlay(alignment: .topLeading) {
            if shown {
                Text(text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(HomeColor.text3)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Melding maken

extension SupportReportForm {

    var macBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Waar gaat je melding over?")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 12) {
                    categoryTile(.bug, icon: "ladybug", title: "Fout", subtitle: "Iets werkt niet zoals het hoort")
                    categoryTile(.featureRequest, icon: "lightbulb", title: "Idee", subtitle: "Een wens of verbetering")
                    categoryTile(.question, icon: "questionmark.bubble", title: "Vraag", subtitle: "Je wilt weten hoe iets werkt")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Categorie"))
                .disabled(sending)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Omschrijving").font(.system(size: 15, weight: .semibold))
                TextEditor(text: $description)
                    .focused($editorFocused)
                    .supportEditor(focused: editorFocused)
                    .editorPlaceholder("Wat deed je, wat verwachtte je en wat gebeurde er?", shown: description.isEmpty)
                    .frame(minHeight: 190)
                    .accessibilityLabel(Text("Omschrijving"))
                    .disabled(sending)
                    .onChange(of: description) { _, value in limitLength(value) }
                Text("\(description.count)/5000")
                    .font(.system(size: 12.5))
                    .foregroundStyle(HomeColor.text3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Met je melding gaan je naam, e-mailadres, de app-versie, je apparaat, je klikpad en een afgeschermd logbestand mee. Je opnames, transcripties en notulen gaan nooit mee.")
                    .fixedSize(horizontal: false, vertical: true)
                Link(String(localized: "support.privacy.link"), destination: SupportLinks.privacy)
                    .foregroundStyle(HomeColor.lavender)
            }
            .font(.system(size: 13.5))
            .foregroundStyle(HomeColor.text2)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HomeColor.violet.opacity(0.10)))
            HStack(alignment: .center, spacing: 12) {
                if sending { ProgressView().controlSize(.small).accessibilityLabel(Text("Versturen")) }
                outcomeText
                    .font(.system(size: 13.5))
                    .foregroundStyle(HomeColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Versturen", action: send)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmed.isEmpty || sending || IOSDebug.supportSeed)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 26)
        .supportCard()
    }

    private func categoryTile(_ value: SupportCategory, icon: String, title: String, subtitle: String) -> some View {
        StudioChoiceTile(selected: category == value, icon: icon, title: title, subtitle: subtitle, vertical: true) {
            category = value
        }
    }
}

// MARK: - Mijn meldingen

extension SupportTicketList {

    var macBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button { Task { await support.loadTickets() } } label: {
                    Label("Vernieuwen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(StudioQuietButtonStyle(height: 30))
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if support.tickets.isEmpty {
                        Text("Nog geen meldingen. Via Melding maken stuur je een fout, idee of vraag.")
                            .font(.system(size: 14))
                            .foregroundStyle(HomeColor.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(support.tickets) { ticket in
                        SupportTicketRow(ticket: ticket, selected: ticket.id == selectedID) { select(ticket) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct SupportTicketRow: View {
    let ticket: SupportTicket
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ticket.ref)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? HomeColor.lavender : HomeColor.text2)
                    if ticket.unread {
                        Circle().fill(Color.brandPrimary).frame(width: 8, height: 8)
                            .accessibilityLabel(Text("Ongelezen"))
                    }
                    Spacer(minLength: 8)
                    StudioChip(text: SupportTicketList.statusLabel(ticket.status), color: Self.statusColor(ticket.status))
                }
                Text(ticket.description.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomeColor.text)
                    .lineLimit(2)
                if let last = ticket.lastMessage, last.senderRole == "ADMIN" {
                    Text("Support: \(last.excerpt)")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeColor.text2)
                        .lineLimit(1)
                }
                Text(ticket.updatedAt ?? ticket.createdAt, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(HomeColor.text3)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? HomeColor.violet.opacity(0.14) : HomeColor.card.opacity(hovered ? 1 : 0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? HomeColor.violet.opacity(0.8) : (hovered ? HomeColor.fieldBorder : HomeColor.cardBorder),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(StudioScalePressStyle(scale: 0.985))
        .onHover { hovered = $0 }
        .animation(TS.Animation.quick, value: hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "WAITING_FOR_USER": HomeColor.warning
        case "RESOLVED": HomeColor.ready
        case "CLOSED": HomeColor.text3
        default: HomeColor.lavender
        }
    }
}

// MARK: - Gesprek

extension SupportThreadView {

    var macBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.description.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ticket.ref)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                Text("\(ticket.ref) · \(categoryLabel) · \(ticket.createdAt.formatted(.dateTime.day().month(.wide).year()))")
                    .font(.system(size: 13))
                    .foregroundStyle(HomeColor.text2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(HomeColor.divider)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if loading { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                    ForEach(messages) { bubble($0) }
                }
                .padding(22)
            }
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            Divider().overlay(HomeColor.divider)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 12) {
                    TextEditor(text: $draft)
                        .focused($editorFocused)
                        .supportEditor(focused: editorFocused)
                        .editorPlaceholder("Schrijf een antwoord", shown: draft.isEmpty)
                        .frame(minHeight: 70, maxHeight: 120)
                        .accessibilityLabel(Text("Antwoord"))
                        .disabled(sending)
                    Button("Stuur", action: send)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSend)
                }
                if trimmed.unicodeScalars.count > 5_000 {
                    Text(String(localized: "support.reply.limit"))
                        .font(TS.Font.caption).foregroundStyle(Color.statusError)
                }
                if failed {
                    Text("Versturen lukte niet. Probeer het zo nog eens.")
                        .font(.system(size: 13)).foregroundStyle(Color.statusError)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .supportCard()
    }

    private var categoryLabel: String {
        switch ticket.category {
        case SupportCategory.bug.rawValue: String(localized: "Fout")
        case SupportCategory.featureRequest.rawValue: String(localized: "Idee")
        case SupportCategory.question.rawValue: String(localized: "Vraag")
        default: ticket.category
        }
    }

    private func bubble(_ message: SupportMessage) -> some View {
        let mine = message.senderRole != "ADMIN"
        return HStack(alignment: .top, spacing: 10) {
            if mine {
                Spacer(minLength: 60)
            } else {
                Text("TV")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeColor.lavender)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(HomeColor.violet.opacity(0.22)))
                    .accessibilityHidden(true)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(.system(size: 14.5))
                    .foregroundStyle(mine ? Color.white : HomeColor.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4,
                                               bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous)
                            .fill(mine
                                  ? AnyShapeStyle(LinearGradient(colors: [Color.brandPrimary, HomeColor.violet],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color.white.opacity(0.07)))
                    )
                (Text(mine ? "Jij" : "Support") + Text(" · ")
                    + Text(message.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 12))
                    .foregroundStyle(HomeColor.text3)
            }
            .frame(maxWidth: 520, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
