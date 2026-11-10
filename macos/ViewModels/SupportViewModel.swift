import CryptoKit
import Foundation
import Observation

enum SupportPane: Hashable { case report, tickets }

@MainActor @Observable
final class SupportViewModel {
    var unreadCount = 0
    var tickets: [SupportTicket] = []
    var thread: [SupportMessage] = []
    var pane: SupportPane = .report
    @ObservationIgnored private let relay: SupportRelay
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = AppLog(category: "Support")

    init(relay: SupportRelay = .shared, defaults: UserDefaults = .standard) {
        self.relay = relay
        self.defaults = defaults
    }

    var isAutoReportEnabled: Bool {
        defaults.object(forKey: SupportIdentity.autoReportKey) == nil
            || defaults.bool(forKey: SupportIdentity.autoReportKey)
    }

    func report(stage: SupportStage, shown: String, error: String) async {
        // Error strings can contain provider response text; never copy them into the log.
        logger.warning("Failure during \(stage.rawValue)")
        guard isAutoReportEnabled, Self.shouldReport(shown) else { return }
        let report = SupportReport.make(kind: "auto", category: .bug, stage: stage.rawValue,
                                        shown: shown, error: error,
                                        fingerprint: Self.fingerprint(stage: stage, error: error),
                                        clickPath: AppLog.clickPath(in: await AppLog.tail()))
        do {
            try await relay.enqueue(report)
            Task { await relay.flush() }
        } catch { logger.warning("Automatic support report could not be queued") }
    }

    func reportCrash(runningStage: SupportStage?) async {
        let message = runningStage.map { "gestopt tijdens \($0.rawValue)" } ?? "onverwacht gestopt"
        await report(stage: runningStage ?? .crash, shown: message, error: message)
    }

    func submit(category: SupportCategory, description: String) async -> SendOutcome {
        let report = SupportReport.make(kind: "manual", category: category, stage: "",
                                        shown: description, error: "", fingerprint: nil,
                                        clickPath: AppLog.clickPath(in: await AppLog.tail()))
        return await relay.send(report)
    }

    func refreshUnread() async {
        do { unreadCount = try await relay.unreadCount() }
        catch { logger.warning("Support unread count could not be loaded") }
    }

    func loadTickets() async {
        do { tickets = try await relay.tickets() }
        catch { logger.warning("Support tickets could not be loaded") }
    }

    func openThread(_ ticket: SupportTicket) async {
        do {
            thread = try await relay.messages(ticketId: ticket.id)
            await refreshUnread()
        } catch { logger.warning("Support messages could not be loaded") }
    }

    func reply(_ body: String, to ticket: SupportTicket) async throws {
        try await relay.sendMessage(ticketId: ticket.id, body: body)
        await openThread(ticket)
    }

    func startPolling() async {
        while !Task.isCancelled {
            await refreshUnread()
            do { try await Task.sleep(for: .seconds(15 * 60)) }
            catch { return }
        }
    }

    nonisolated static func fingerprint(stage: SupportStage, error: String) -> String {
        let normalized = (stage.rawValue + "|" + error).filter { $0 < "0" || $0 > "9" }
        return SHA256.hash(data: Data(normalized.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func shouldReport(_ message: String) -> Bool {
        // Add each new user instruction sentence here.
        let instructions: Set<String> = [
            "Microfoontoestemming geweigerd. Geef toegang via Instellingen.",
            "Opname is leeg of te kort om te verwerken.",
            "Opname is te kort (minimaal 3 seconden). Probeer opnieuw.",
            "Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.",
            "Geannuleerd door gebruiker."
        ]
        return !instructions.contains(message)
    }

    nonisolated static func stage(afterFailureOf status: TaskStatus) -> SupportStage {
        status == .generatingLocal ? .notule : .transcriberen
    }
}
