#if DEBUG
import Foundation
#if os(macOS)
import AppKit
#endif

/// Screenshot support for debug builds. `-TVDebugSeed YES` fills an empty store with sample
/// people, a minute and 40 glossary terms; `-TVDebugWindow 1920x1080` sizes the main window.
/// Seeding only runs in a separate container (bundle id ending in `.screens`) or in the
/// simulator, so it can never touch real data.
@MainActor
enum DebugScreenshotSeed {
    static var isEnabled: Bool {
        guard !AppEnvironment.isRunningTests, UserDefaults.standard.string(forKey: "TVDebugSeed") == "YES" else { return false }
        #if targetEnvironment(simulator)
        let isolated = true
        #else
        let isolated = Bundle.main.bundleIdentifier?.hasSuffix(".screens") == true
        #endif
        return isolated
    }

    static func run() {
        guard isEnabled, LocalTranscriptStore.shared.allTranscripts().isEmpty else { return }
        seedPeople()
        seedGlossary()
        try? LocalTranscriptStore.shared.save(TranscriptRecord(
            title: "Schadebezoek Keizersgracht", rawTranscription: "Jan de Vries neemt het rapport op zich.",
            notuleHtml: "<h1>Schadebezoek Keizersgracht</h1><h2>Besluiten</h2><ul><li>Jan de Vries stelt het rapport op voor vrijdag.</li><li>Contra-expertise wordt ingepland door Jan Smit.</li></ul>",
            profileId: "meeting", profileName: "Meeting"))
    }

    static func seedSupport(_ support: SupportViewModel) {
        guard IOSDebug.supportSeed || IOSDebug.supportSettingsSnapshot || IOSDebug.supportBadgeSnapshot, support.tickets.isEmpty else { return }
        let date = Date(timeIntervalSince1970: 1_794_312_000)
        support.tickets = [
            SupportTicket(id: "support-demo-1", ref: "TV-001", status: "WAITING_FOR_USER", category: "BUG",
                          description: "Opnemen stopt onverwacht", unread: true, createdAt: date, updatedAt: nil,
                          lastMessage: .init(senderRole: "ADMIN", createdAt: date, excerpt: "Welke microfoon gebruik je?")),
            SupportTicket(id: "support-demo-2", ref: "TV-002", status: "RESOLVED", category: "QUESTION",
                          description: "Waar vind ik mijn notules?", unread: false, createdAt: date, updatedAt: date,
                          lastMessage: nil)
        ]
        support.unreadCount = 1
        support.thread = supportMessages(for: support.tickets[0])
    }

    static func supportMessages(for ticket: SupportTicket) -> [SupportMessage] {
        [SupportMessage(id: ticket.id + "-user", body: ticket.description, senderRole: "USER", createdAt: ticket.createdAt),
         SupportMessage(id: ticket.id + "-admin", body: ticket.lastMessage?.excerpt ?? "Je vindt je notules bij Transcripties.",
                        senderRole: "ADMIN", createdAt: ticket.createdAt.addingTimeInterval(60))]
    }

    private static func seedPeople() {
        let service = PersonDirectoryService.shared
        let jan = PersonProfile(name: "Jan de Vries", role: "Schade-expert", organization: "Achmea", aliases: ["Jan V."],
                                meetingTypes: ["Schadebezoek"], expertiseTags: ["Waterschade"], isInternal: false)
        try? service.add(jan)
        try? service.add(PersonProfile(name: "Jan Smit", role: "Projectleider", organization: "Gemeente Utrecht", isInternal: false))
        try? service.add(PersonProfile(name: "Pieter Bos", role: "Teamleider", organization: "ThoughtVault", isInternal: true))
        try? service.update(jan, source: "handmatig") { $0.responsibilities = ["Rapport opstellen"] }
        try? service.update(jan, source: "gesprek:demo") { $0.responsibilities.append("Contra-expertise plannen"); $0.expertiseTags.append("Funderingsherstel") }
    }

    private static func seedGlossary() {
        let terms = ["Achmea", "Ansible", "Azure", "Bitbucket", "Confluence", "Docker", "Equinoxe", "FastAPI", "Grafana", "Helm",
                     "Jira", "Kubernetes", "LogiVert", "Lutetia", "Mistral", "n8n", "Obsidian", "Ollama", "Peppol", "PostgreSQL",
                     "Prezent", "Prometheus", "Redis", "SharePoint", "Symfony", "Tauri", "Terraform", "ThoughtVault", "Twig", "Whisper",
                     "SRC", "RSC", "Contra-expertise", "Funderingsherstel", "Keizersgracht", "Schadebezoek", "Uitkeringsvoorstel",
                     "Verzekeringsnemer", "Waterschade", "Zakelijke polis"]
        var entries = terms.enumerated().map { index, term in
            PersonalCorrection(canonical: term, variants: index % 3 == 0 ? ["\(term.lowercased())e"] : [],
                               scope: index % 7 == 0 ? "meeting" : nil, enabled: index != 5,
                               note: index % 2 == 0 ? "Voorbeeldterm \(index + 1) voor de schermafbeelding" : nil)
        }
        entries[30].note = "Schaderegelingscentrum van de verzekeraar"
        try? PersonalCorrections.save(entries)
        _ = try? PersonalCorrections.saveRecording(PersonalCorrection(id: entries[30].id, canonical: "SRC", variants: ["S R C"], note: "Schaderegelingscentrum"), source: "handmatig")
    }

    /// `-TVDebugSnapshot <name>` makes the app render its own visible windows to
    /// `<container tmp>/<name>-<n>.png` and quit, so no Screen Recording grant is needed.
    /// Web views (the notule body) render blank this way.
    static func snapshotAndQuit() async {
        #if os(macOS)
        guard let name = UserDefaults.standard.string(forKey: "TVDebugSnapshot") else { return }
        try? await Task.sleep(for: .seconds(7))
        for (index, window) in NSApp.windows.filter({ $0.isVisible && $0.frame.height > 200 }).enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(index).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        NSApp.terminate(nil)
        #endif
    }

    static func sizeWindow() {
        #if os(macOS)
        let parts = (UserDefaults.standard.string(forKey: "TVDebugWindow") ?? "").split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        for window in NSApp.windows where window.isVisible && window.canBecomeMain {
            window.setFrame(NSRect(x: 0, y: 0, width: parts[0], height: parts[1]), display: true)
        }
        #endif
    }
}
#endif
