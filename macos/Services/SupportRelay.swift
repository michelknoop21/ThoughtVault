import Foundation
import Security

enum SupportRelayError: Error, Equatable { case http(Int), automaticReportingDisabled }

actor SupportRelay {
    static let baseURL = URL(string: "https://thoughtvault.yinga.ai/support")!
    static let shared = SupportRelay()

    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let outbox: URL
    private let logTail: @Sendable (Int) async -> String
    private let logger = AppLog(category: "Support")
    private var registered = false
    private var registration: Task<Void, Error>?
    private var isFlushing = false
    // shortcut: completed receipts live only in memory after storage failure, add relay idempotency for crash-safe exactly-once delivery.
    private var completed: [URL: SendOutcome] = [:]
    private var retryAfter = Date.distantPast

    init(baseURL: URL = SupportRelay.baseURL,
         session: URLSession = URLSession(configuration: .ephemeral),
         defaults: UserDefaults = .standard,
         keychain: KeychainService = .shared,
         outbox: URL = AppLog.directory.appending(path: "outbox"),
         logTail: @escaping @Sendable (Int) async -> String = { await AppLog.tail(maxBytes: $0) }) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
        self.keychain = keychain
        self.outbox = outbox
        self.logTail = logTail
    }

    func enqueue(_ report: SupportReport) throws { _ = try store(report) }

    private var isAutoReportEnabled: Bool {
        defaults.object(forKey: SupportIdentity.autoReportKey) == nil
            || defaults.bool(forKey: SupportIdentity.autoReportKey)
    }

    private func store(_ report: SupportReport) throws -> URL {
        guard report.kind != "auto" || isAutoReportEnabled else {
            throw SupportRelayError.automaticReportingDisabled
        }
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        var stored = report
        stored.normalizeAutomatic()
        stored.name = ""
        stored.email = ""
        stored.log = nil
        let previous = Int64(files().last?.lastPathComponent.split(separator: "-").first ?? "0") ?? 0
        let sequence = max(Int64(Date().timeIntervalSince1970 * 1_000), previous + 1)
        let filename = "\(sequence)-\(UUID().uuidString).json"
        let url = outbox.appending(path: filename)
        try SupportJSON.encoder.encode(stored).write(to: url, options: .atomic)
        for old in files().dropLast(50) {
            do { try FileManager.default.removeItem(at: old); completed.removeValue(forKey: old) }
            catch { logger.warning("Support outbox retention cleanup failed") }
        }
        return url
    }

    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func pendingReports() -> [SupportReport] {
        files().filter { completed[$0] == nil }
            .compactMap { try? SupportJSON.decoder.decode(SupportReport.self, from: Data(contentsOf: $0)) }
    }

    func flush() async { _ = await drain(target: nil) }

    func send(_ report: SupportReport) async -> SendOutcome {
        do {
            let url = try store(report)
            return await drain(target: url) ?? pendingOutcome(url)
        } catch {
            logger.warning("Support report could not be queued")
            return .failed
        }
    }

    private func pendingOutcome(_ url: URL) -> SendOutcome {
        completed[url] ?? (FileManager.default.fileExists(atPath: url.path) ? .queued : .failed)
    }

    private func cleanup(_ url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            completed.removeValue(forKey: url)
        } catch {
            logger.warning("Completed support report cleanup failed; it will not be sent again this session")
        }
    }

    private func drain(target: URL?) async -> SendOutcome? {
        for url in Array(completed.keys) { cleanup(url) }
        if !isAutoReportEnabled {
            for url in files() where completed[url] == nil {
                if let report = try? SupportJSON.decoder.decode(SupportReport.self, from: Data(contentsOf: url)),
                   report.kind == "auto" {
                    completed[url] = .failed
                    cleanup(url)
                }
            }
        }
        let name = (defaults.string(forKey: SupportIdentity.nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (defaults.string(forKey: SupportIdentity.emailKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isFlushing, Date() >= retryAfter, SupportIdentity.isComplete(name: name, email: email) else { return nil }
        isFlushing = true
        defer { isFlushing = false }
        var targetOutcome: SendOutcome?
        for url in files() where completed[url] == nil {
            do {
                var report = try SupportJSON.decoder.decode(SupportReport.self, from: Data(contentsOf: url))
                report.normalizeAutomatic()
                report.name = name
                report.email = email
                report.log = await logTail(1_048_576)
                var response = try await authenticated(["reports"], body: SupportJSON.encoder.encode(report), automatic: report.kind == "auto", queuedReport: url)
                if response.1.statusCode == 413 {
                    report.log = await logTail(262_144)
                    response = try await authenticated(["reports"], body: SupportJSON.encoder.encode(report), automatic: report.kind == "auto", queuedReport: url)
                }
                let status = response.1.statusCode
                let outcome: SendOutcome
                if (200..<300).contains(status) {
                    let result = try? SupportJSON.decoder.decode(ReportResult.self, from: response.0)
                    outcome = .sent(result)
                    if result == nil { logger.warning("Support report accepted without a readable receipt") }
                } else if (400..<500).contains(status), status != 429, status != 401 {
                    outcome = .failed
                    logger.warning("Support report discarded (HTTP \(status))")
                } else { break }
                completed[url] = outcome
                if url == target { targetOutcome = outcome }
                cleanup(url)
            } catch SupportRelayError.automaticReportingDisabled {
                completed[url] = .failed
                if url == target { targetOutcome = .failed }
                cleanup(url)
            } catch {
                logger.warning("Support queue paused; report retained")
                break
            }
        }
        return targetOutcome
    }

    private func credentials() throws -> (String, String) {
        if let id = defaults.string(forKey: SupportIdentity.installationKey),
           let secret = keychain.load(for: SupportIdentity.secretKey) { return (id, secret) }
        return try newCredentials()
    }

    private func newCredentials() throws -> (String, String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainError.writeFailed(status) }
        let secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let id = UUID().uuidString.lowercased()
        try keychain.save(secret, for: SupportIdentity.secretKey)
        defaults.set(id, forKey: SupportIdentity.installationKey)
        return (id, secret)
    }

    private func ensureRegistered() async throws {
        if registered { return }
        if let registration { return try await registration.value }
        let task = Task { try await self.register() }
        registration = task
        defer { registration = nil }
        try await task.value
    }

    private func register() async throws {
        var pair = try credentials()
        for attempt in 0..<2 {
            let body = try SupportJSON.encoder.encode(["installationId": pair.0, "secret": pair.1])
            let (_, response) = try await request(["installations"], body: body)
            if response.statusCode == 200 || response.statusCode == 201 { registered = true; return }
            if response.statusCode == 409 && attempt == 0 { pair = try newCredentials(); continue }
            throw SupportRelayError.http(response.statusCode)
        }
    }

    private func authenticated(_ path: [String], body: Data? = nil, automatic: Bool = false, queuedReport: URL? = nil) async throws -> (Data, HTTPURLResponse) {
        try await ensureRegistered()
        var response = try await request(path, body: body, signed: true, automatic: automatic, queuedReport: queuedReport)
        if response.1.statusCode == 401 {
            registered = false
            try await ensureRegistered()
            response = try await request(path, body: body, signed: true, automatic: automatic, queuedReport: queuedReport)
        }
        return response
    }

    private func request(_ path: [String], body: Data?, signed: Bool = false, automatic: Bool = false, queuedReport: URL? = nil) async throws -> (Data, HTTPURLResponse) {
        guard Date() >= retryAfter else { throw SupportRelayError.http(429) }
        let url = path.reduce(baseURL) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if signed {
            let pair = try credentials()
            request.setValue(pair.0, forHTTPHeaderField: "X-TV-Installation")
            request.setValue(pair.1, forHTTPHeaderField: "X-TV-Secret")
        }
        // Recheck after every await (registration, log tail and retries), immediately before POST.
        guard !automatic || isAutoReportEnabled else { throw SupportRelayError.automaticReportingDisabled }
        if let queuedReport {
            guard completed[queuedReport] == nil, FileManager.default.fileExists(atPath: queuedReport.path) else {
                throw SupportRelayError.automaticReportingDisabled
            }
        }
        if queuedReport != nil {
            let name = (defaults.string(forKey: SupportIdentity.nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let email = (defaults.string(forKey: SupportIdentity.emailKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard SupportIdentity.isComplete(name: name, email: email) else { throw SupportRelayError.http(422) }
            var report = try SupportJSON.decoder.decode(SupportReport.self, from: request.httpBody ?? Data())
            report.name = name
            report.email = email
            request.httpBody = try SupportJSON.encoder.encode(report)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 429, let header = http.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
            retryAfter = Date().addingTimeInterval(seconds)
        }
        return (data, http)
    }

    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
    private struct UnreadCount: Decodable { let count: Int }

    private func decoded<Value: Decodable>(_ type: Value.Type, path: [String]) async throws -> Value {
        let (data, response) = try await authenticated(path)
        guard (200..<300).contains(response.statusCode) else { throw SupportRelayError.http(response.statusCode) }
        return try SupportJSON.decoder.decode(Envelope<Value>.self, from: data).data
    }

    func tickets() async throws -> [SupportTicket] { try await decoded([SupportTicket].self, path: ["tickets"]) }
    func unreadCount() async throws -> Int { try await decoded(UnreadCount.self, path: ["unread-count"]).count }

    private func messagePath(_ ticketId: String) throws -> [String] {
        guard ticketId.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil else {
            throw SupportRelayError.http(422)
        }
        return ["tickets", ticketId, "messages"]
    }

    func messages(ticketId: String) async throws -> [SupportMessage] {
        try await decoded([SupportMessage].self, path: messagePath(ticketId))
    }

    func sendMessage(ticketId: String, body: String) async throws {
        guard (1...5_000).contains(body.unicodeScalars.count) else { throw SupportRelayError.http(422) }
        let (_, response) = try await authenticated(messagePath(ticketId), body: SupportJSON.encoder.encode(["body": body]))
        guard (200..<300).contains(response.statusCode) else { throw SupportRelayError.http(response.statusCode) }
    }
}
