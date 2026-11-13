// ProspectFlowViews.swift
// ThoughtVault
//
// Menu items, confirmation sheet and settings section for the Prospect Flow
// draft-offer link. Shared by macOS and iOS.

import SwiftUI

@MainActor
func openProspectFlowOffer(
    _ url: URL?, using openURL: OpenURLAction,
    onFailure: @escaping (String) -> Void, onSuccess: @escaping () -> Void = {}
) {
    let failed = { onFailure(String(localized: "De offerte is bewaard, maar de link kon niet worden geopend. Probeer opnieuw.")) }
    guard let url else { failed(); return }
    openURL(url) { accepted in
        if accepted { onSuccess() } else { failed() }
    }
}

// MARK: - Menu items

struct ProspectFlowMenuItems: View {
    let transcript: Transcript
    let onOpenError: (String) -> Void
    let start: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        if ProspectFlowService.isConfigured, !(transcript.notuleHtml ?? "").isEmpty {
            Divider()
            if let ref = ProspectFlowService.offerRef(for: transcript.taskId),
               let number = ref.number, let path = ref.url {
                Button {
                    openProspectFlowOffer(ProspectFlowService().openURL(path), using: openURL, onFailure: onOpenError)
                } label: {
                    Label("Open offerte \(number)", systemImage: "doc.text.magnifyingglass")
                }
                Button(action: start) {
                    Label("Nieuwe conceptofferte maken", systemImage: "plus.square.on.square")
                }
            } else {
                Button(action: start) {
                    Label("Maak offerte in Prospect Flow", systemImage: "eurosign.square")
                }
            }
        }
    }
}

// MARK: - Sheet

struct ProspectFlowOfferSheet: View {
    let transcript: Transcript

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Phase { case loading, choose, working, done(ProspectFlowService.OfferResult), failed(String) }

    @State private var phase: Phase = .loading
    @State private var candidates: [ProspectFlowService.Candidate] = []
    @State private var selectedId: Int?          // nil = new customer
    @State private var newName = ""
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var openError: String?

    private let service = ProspectFlowService()

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.md) {
            Text("Conceptofferte in Prospect Flow")
                .font(TS.Font.title3)
            content
            if let openError {
                Text(openError).font(TS.Font.footnote).foregroundStyle(Color.statusError)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(TS.Spacing.lg)
        #if os(macOS)
        .frame(width: 460, height: 460)
        #endif
        .task { await loadCandidates() }
        .onDisappear { searchTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Klant zoeken\u{2026}").frame(maxWidth: .infinity)
        case .choose, .failed:
            customerPicker
            if case .failed(let message) = phase {
                Text(message)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.statusError)
            }
        case .working:
            VStack(spacing: TS.Spacing.sm) {
                ProgressView()
                Text("Regels afleiden, dit kan tot 2 minuten duren.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity)
        case .done(let result):
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Label(
                    result.bestaand ? "Offerte \(result.number) bestond al" : "Offerte \(result.number) aangemaakt",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(Color.statusSuccess)
                Text("Klant: \(result.klant.naam)\(result.klant.nieuw ? " (nieuw)" : "")")
                Text("\(result.regels) regels, waarvan \(result.teControleren) te controleren.")
                if result.terugvalGebruikt {
                    Text("Gemaakt met het terugvalmodel \(result.model ?? "").")
                        .foregroundStyle(Color.labelSecondary)
                }
                Text("Concept: er is niets naar de klant gestuurd.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
            .font(TS.Font.body)
        }
    }

    private var customerPicker: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Text("Klant").font(TS.Font.captionSemibold).foregroundStyle(Color.labelSecondary)
            TextField("Zoek een andere klant", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, q in scheduleSearch(q) }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(candidates) { c in
                        row(title: c.plaats.map { "\(c.naam), \($0)" } ?? c.naam, selected: selectedId == c.id) {
                            searchTask?.cancel()
                            selectedId = c.id
                        }
                    }
                    row(title: String(localized: "Nieuwe klant"), selected: selectedId == nil) {
                        searchTask?.cancel()
                        selectedId = nil
                    }
                }
            }
            .frame(maxHeight: 180)
            if selectedId == nil {
                TextField("Naam van de nieuwe klant", text: $newName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.brandPrimary : Color.labelTertiary)
                Text(title).foregroundStyle(Color.labelPrimary)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            switch phase {
            case .done(let result):
                Button("Sluiten") { dismiss() }
                Button("Open offerte") {
                    openProspectFlowOffer(service.openURL(result.url), using: openURL,
                                          onFailure: { openError = $0 }, onSuccess: { dismiss() })
                }
                .buttonStyle(.borderedProminent)
            case .working:
                EmptyView()
            default:
                Button("Annuleren") { dismiss() }
                Button("Maak conceptofferte") { Task { await create() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedId == nil && newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .tint(Color.brandPrimary)
    }

    // MARK: Actions

    private func loadCandidates() async {
        let text = transcript.title + "\n" + HTMLPlainText.from(transcript.notuleHtml ?? "")
        let pendingChoice = ProspectFlowService.offerRef(for: transcript.taskId, baseURL: service.baseURL)?.pendingChoice
        switch pendingChoice {
        case .new(let name): selectedId = nil; newName = name
        case .existing(let id): selectedId = id
        case nil: break
        }
        do {
            candidates = try await service.match(text: text)
            if let selectedId, !candidates.contains(where: { $0.id == selectedId }) {
                candidates.insert(.init(id: selectedId, naam: String(localized: "Eerder gekozen klant") + " (\(selectedId))", plaats: nil), at: 0)
            }
            if case nil = pendingChoice { selectedId = candidates.first?.id }
            phase = .choose
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let term = q.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let found = try? await service.search(term), !Task.isCancelled,
                  !found.isEmpty else { return }
            let selected = candidates.first(where: { $0.id == selectedId })
            candidates = found
            if let selected, !found.contains(where: { $0.id == selected.id }) {
                candidates.insert(selected, at: 0)
            }
        }
    }

    private func create() async {
        let taskId = transcript.taskId
        let customer: ProspectFlowService.Customer = selectedId.map { .existing($0) }
            ?? .new(newName.trimmingCharacters(in: .whitespaces))
        var ref = ProspectFlowService.offerRef(for: taskId, baseURL: service.baseURL) ?? .init()
        // Resolve an uncertain POST before allowing a different customer choice.
        if ref.pendingRequestId?.isEmpty == false, ref.pendingCustomer != customer.key {
            phase = .failed(String(localized: "Er is nog een onbevestigde offerteaanvraag. Heropen dit venster en rond die eerst af voordat je een andere klant kiest."))
            return
        }
        let requestId = ref.pendingCustomer == customer.key ? (ref.pendingRequestId ?? UUID().uuidString)
                                                            : UUID().uuidString
        ref.pendingRequestId = requestId
        ref.pendingCustomer = customer.key
        if case .new(let name) = customer { ref.pendingNewCustomerName = name }
        else { ref.pendingNewCustomerName = nil }
        ProspectFlowService.setOfferRef(ref, for: taskId, baseURL: service.baseURL)
        phase = .working
        do {
            let result = try await service.createOffer(requestId: requestId, transcript: transcript, customer: customer)
            ProspectFlowService.setOfferRef(.init(id: result.offerId, number: result.number, url: result.url), for: taskId, baseURL: service.baseURL)
            phase = .done(result)
        } catch {
            // The API checks this request ID before returning a missing-customer error.
            if case ProspectFlowService.PFError.server(let code, let detail) = error,
               code == 404, detail == "Klant niet gevonden" {
                ProspectFlowService.setOfferRef(.init(id: ref.id, number: ref.number, url: ref.url), for: taskId, baseURL: service.baseURL)
            }
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Settings

struct ProspectFlowSettingsSection: View {
    @AppStorage(ProspectFlowService.baseURLKey) private var baseURL = ProspectFlowService.defaultBaseURL
    @State private var apiKey = ""
    @State private var testing = false
    @State private var status: (ok: Bool, message: String)?
    /// In a settings card the card supplies the title and description.
    var inCard = false

    var body: some View {
        if inCard {
            rows.onAppear(perform: loadKey)
        } else {
            Section { rows } header: {
                Text("Prospect Flow")
            } footer: {
                Text("Maakt vanuit een notule een conceptofferte in Prospect Flow. Er gaat nooit iets naar de klant.")
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)
            }
            .onAppear(perform: loadKey)
        }
    }

    private func loadKey() { apiKey = KeychainService.shared.load(for: ProspectFlowService.apiKeyKeychainKey) ?? "" }

    @ViewBuilder private var rows: some View {
            SettingFieldRow("Adres") {
                TextField(ProspectFlowService.defaultBaseURL, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.body)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }
            SettingFieldRow("API-sleutel") {
                SecureField("Sleutel van de Prospect Flow-instance", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(TS.Font.bodyMonospaced)
                    .onChange(of: apiKey) { _, value in saveKey(value) }
            }
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Button {
                    Task { await test() }
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Text("Verbinding testen") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(testing || apiKey.isEmpty)
                if let status {
                    Text(status.message)
                        .font(TS.Font.footnote)
                        .foregroundStyle(status.ok ? Color.statusSuccess : Color.statusError)
                        .lineLimit(2)
                }
            }
    }

    private func saveKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.shared.delete(for: ProspectFlowService.apiKeyKeychainKey)
        } else {
            do {
                try KeychainService.shared.save(trimmed, for: ProspectFlowService.apiKeyKeychainKey)
            } catch {
                status = (false, error.localizedDescription)
            }
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            _ = try await ProspectFlowService(baseURL: baseURL, apiKey: apiKey).match(text: "")
            status = (true, String(localized: "Verbonden"))
        } catch {
            status = (false, error.localizedDescription)
        }
    }
}
