#if os(macOS)
import Foundation
import Network
import Security
import AppKit

/// Local MCP server inside the running app. Listens on a random loopback port and publishes
/// port and a per-start token in `mcp.json`; `ThoughtVault --mcp` (McpBridge) reads that file
/// and relays the client's stdio. First line of a connection is the token, then one JSON-RPC
/// message per line in both directions.
@MainActor @Observable
final class McpServer {
    static let shared = McpServer()
    nonisolated static let enabledKey = "mcpEnabled"
    nonisolated static let allowWriteKey = "mcpAllowWrite"
    nonisolated static var fileURL: URL { AppEnvironment.supportDirectory.appending(path: "ThoughtVault/mcp.json") }
    nonisolated static let maxLine = 8 * 1024 * 1024
    /// Before the token is checked a connection may not buffer more than this.
    nonisolated static let maxTokenLine = 256

    private(set) var status = ""
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var token = ""
    @ObservationIgnored private weak var recordingVM: RecordingViewModel?
    @ObservationIgnored private var router: McpRouter?
    @ObservationIgnored private var defaults = UserDefaults.standard
    @ObservationIgnored private var connections: [ObjectIdentifier: NWConnection] = [:]

    func attach(recordingVM: RecordingViewModel) {
        self.recordingVM = recordingVM
        apply()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            try? FileManager.default.removeItem(at: McpServer.fileURL)
        }
    }

    /// Starts or stops the listener to match the setting.
    func apply(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Self.enabledKey) { if listener == nil { start() } } else { stop() }
    }

    private func start() {
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            router = McpRouter(catalogue: try McpCatalogue.bundled(), version: version)
            let parameters = NWParameters.tcp
            parameters.acceptLocalOnly = true
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            let listener = try NWListener(using: parameters)
            token = Self.randomToken()
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            status = String(localized: "Koppeling kon niet starten: \(error.localizedDescription)")
        }
    }

    /// Switching off also ends sessions of clients that are already connected.
    func stop() {
        listener?.cancel()
        listener = nil
        router = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        try? FileManager.default.removeItem(at: Self.fileURL)
        status = ""
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            do {
                try Self.writeFile(port: port, token: token)
                status = String(localized: "Status: actief")
            } catch {
                stop()
                status = String(localized: "Koppeling kon niet starten: \(error.localizedDescription)")
            }
        case .failed(let error):
            stop()
            status = String(localized: "Koppeling gestopt: \(error.localizedDescription)")
        default: break
        }
    }

    nonisolated static func writeFile(port: UInt16, token: String, to url: URL = fileURL) throws {
        let data = try JSONSerialization.data(withJSONObject: ["port": Int(port), "token": token,
                                                               "pid": Int(ProcessInfo.processInfo.processIdentifier)])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    nonisolated static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fatalError("No secure random bytes available")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant time, so the token cannot be guessed byte by byte from timing.
    nonisolated static func tokenMatches(_ given: String, _ expected: String) -> Bool {
        let a = Array(given.utf8), b = Array(expected.utf8)
        guard a.count == b.count, !b.isEmpty else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let session = McpLineReader()
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { Task { @MainActor in self?.connections[key] = nil } }
        }
        connection.start(queue: .main)
        // A client that does not authenticate quickly is dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { if !session.authenticated { connection.cancel() } }
        }
        receive(connection, session)
    }

    private func receive(_ connection: NWConnection, _ session: McpLineReader) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return connection.cancel() }
                if let data, !data.isEmpty {
                    guard let lines = session.append(data, limit: Self.maxLine) else { return connection.cancel() }
                    // Until a full token line arrived, only a token's worth of bytes may wait.
                    if lines.isEmpty, !session.authenticated, session.bufferedBytes > Self.maxTokenLine { return connection.cancel() }
                    for line in lines { self.handle(line, session: session, connection: connection) }
                }
                if error != nil { return connection.cancel() }
                // The client stopped sending: close once the replies still in flight are out.
                if isComplete { session.closing = true; session.closeIfDone(connection) } else { self.receive(connection, session) }
            }
        }
    }

    private func handle(_ line: String, session: McpLineReader, connection: NWConnection) {
        guard session.authenticated else {
            if Self.tokenMatches(line, token) { session.authenticated = true } else { connection.cancel() }
            return
        }
        guard let router else { return connection.cancel() }
        let allowWrite = defaults.bool(forKey: Self.allowWriteKey)
        let recordingVM = recordingVM
        session.pending += 1
        Task { @MainActor in
            let reply = await router.handle(line, allowWrite: allowWrite) { name, arguments in
                try await McpServer.run(name, arguments, recordingVM: recordingVM)
            }
            if let reply { connection.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in }) }
            session.pending -= 1
            session.closeIfDone(connection)
        }
    }

    private static func run(_ name: String, _ arguments: Data, recordingVM: RecordingViewModel?) async throws -> Data {
        let args = try JSONSerialization.jsonObject(with: arguments) as? [String: Any] ?? [:]
        let value = try await McpTools(recordingVM: recordingVM).call(name, args)
        return try JSONSerialization.data(withJSONObject: value)
    }
}

/// One client connection: splits its byte stream into UTF-8 lines and tracks replies in flight.
@MainActor
final class McpLineReader {
    var authenticated = false
    var pending = 0
    var closing = false
    private var buffer = Data()
    /// Bytes already searched for a newline, so a long line is not rescanned per chunk.
    private var scanned = 0

    var bufferedBytes: Int { buffer.count }

    func closeIfDone(_ connection: NWConnection) {
        guard closing && pending == 0 else { return }
        // Sends are ordered: the FIN goes out after the last reply, then the connection is released.
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Complete lines so far, or nil when a line exceeds `limit`.
    func append(_ data: Data, limit: Int) -> [String]? {
        buffer.append(data)
        var lines: [String] = []
        var start = buffer.startIndex
        var searchFrom = buffer.startIndex + scanned
        while let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
            let text = String(decoding: buffer[start..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(text) }
            start = newline + 1
            searchFrom = start
        }
        buffer.removeSubrange(buffer.startIndex..<start)
        scanned = buffer.count
        return buffer.count > limit ? nil : lines
    }
}
#endif
