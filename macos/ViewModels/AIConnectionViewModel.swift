import Foundation
import Security
import CryptoKit
import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MinutesStyle: Codable, Hashable, Sendable {
    var font: String = "Arial"
    var size: Double = 11
    var text_color: String = "#222222"
    var accent_color: String = "#3454d1"
    var line_height: Double = 1.5
    var margin_mm: Double = 20
    var paper: String = "A4"
    var orientation: String = "portrait"

    func validate() throws {
        guard ["Arial", "Georgia", "Verdana", "Times New Roman"].contains(font),
              ["A4", "Letter"].contains(paper), ["portrait", "landscape"].contains(orientation),
              size.isFinite, (8...32).contains(size), line_height.isFinite, (1...2.5).contains(line_height),
              margin_mm.isFinite, (5...40).contains(margin_mm),
              text_color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              accent_color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
        else { throw AIConnectionError.message("Ongeldige vormgeving.") }
    }

    func css(selector: String = "body") throws -> String {
        try validate()
        return "@page{size:\(paper) \(orientation);margin:\(margin_mm)mm}"
            + "\(selector){font-family:'\(font)';font-size:\(size)pt;color:\(text_color);line-height:\(line_height);margin:0;background:#fff;\(selector == "body" ? "" : "padding:\(margin_mm)mm;")}"
            + "\(selector) h1,\(selector) h2,\(selector) h3{font-family:inherit;color:\(accent_color)!important;line-height:inherit;border:0;padding:0;margin:1em 0 .5em}"
            + "\(selector) h1{font-size:1.8em}\(selector) h2{font-size:1.4em}\(selector) h3{font-size:1.15em}"
            + "\(selector) p,\(selector) li,\(selector) th,\(selector) td{font-family:inherit;font-size:inherit;line-height:inherit;color:inherit!important}"
            + "\(selector) p{margin:.5em 0}\(selector) strong,\(selector) em{color:inherit!important}"
            + "table{border-collapse:collapse;width:100%;font-size:inherit}th,td{border:1px solid #ddd;padding:6px;text-align:left;text-transform:none;letter-spacing:normal}"
            + "\(selector) th{background:#f5f5f5!important}\(selector) td{background:#fff!important}"
    }

    func apply(to html: String) throws -> String {
        // MCP accepts formatted text, never executable markup or remote resources.
        let body = html.replacingOccurrences(of: #"<(script|style|iframe|object)\b[^>]*>[\s\S]*?</\1\s*>"#, with: "", options: [.caseInsensitive, .regularExpression])
        let allowed: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "strong", "em", "b", "i", "u", "ul", "ol", "li", "table", "thead", "tbody", "tfoot", "tr", "td", "th", "br", "hr", "blockquote", "code", "pre", "div", "span"]
        let tags = try NSRegularExpression(pattern: "<[^>]*>")
        let name = try NSRegularExpression(pattern: #"^<\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)\b"#)
        var clean = body
        for match in tags.matches(in: body, range: NSRange(body.startIndex..., in: body)).reversed() {
            guard let range = Range(match.range, in: clean) else { continue }
            let tag = String(clean[range])
            var replacement = ""
            if let parsed = name.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
               let nameRange = Range(parsed.range(at: 2), in: tag), let closingRange = Range(parsed.range(at: 1), in: tag) {
                let tagName = tag[nameRange].lowercased()
                if allowed.contains(tagName) { replacement = "<\(tag[closingRange])\(tagName)>" }
            }
            clean.replaceSubrange(range, with: replacement)
        }
        return "<style>\(try css())\(try css(selector: "#content"))</style>" + clean
    }
}

enum AIConnectionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

extension Notification.Name {
    static let aiOpenView = Notification.Name("aiOpenView")
    static let aiTranscriptChanged = Notification.Name("aiTranscriptChanged")
}

@MainActor @Observable
final class AIConnectionViewModel {
    static let shared = AIConnectionViewModel()
    private static let key = "localMcpConnection"
    struct Connection: Codable {
        var device_id: String
        var credential: String
        var user_id: String
        var scopes: [String]
    }
    private(set) var connection: Connection?
    var status: String = "Lokale MCP uitgeschakeld"
    var busy = false
    private weak var recordingVM: RecordingViewModel?
    #if os(macOS)
    @ObservationIgnored private var localServer: LocalMCPServer?
    #endif

    func start(recordingVM: RecordingViewModel) {
        self.recordingVM = recordingVM
        guard connection == nil else { return }
        if let raw = KeychainService.shared.load(for: Self.key), let data = raw.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Connection.self, from: data) {
            connection = saved
            startLocalServer()
        }
    }

    private func store(_ value: Connection) throws {
        let raw = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        KeychainService.shared.save(raw, for: Self.key)
        guard KeychainService.shared.load(for: Self.key) == raw else {
            throw AIConnectionError.message("MCP-sleutel opslaan in de sleutelhanger mislukt.")
        }
        connection = value
    }

    private func startLocalServer() {
        #if os(macOS)
        localServer?.stop()
        guard let current = connection, !current.scopes.isEmpty else { return }
        do {
            let server = try LocalMCPServer(token: current.credential, scopes: current.scopes, handler: { [weak self] tool, arguments in
                guard let self, self.connection != nil else { throw AIConnectionError.message("Lokale MCP uitgeschakeld.") }
                return try await self.execute(["id": UUID().uuidString, "device_id": "local", "scope": Self.requiredScope(tool),
                    "expires_at": Date().timeIntervalSince1970 + 25, "tool": tool, "arguments": arguments])
            }, onStatus: { [weak self] status in self?.status = status })
            localServer = server
            server.start()
        } catch { status = "Lokale MCP kon niet starten: \(error.localizedDescription)" }
        #else
        status = "Lokale MCP is beschikbaar in de desktopapp."
        #endif
    }

    func pair(scopes: [String]) async {
        busy = true
        defer { busy = false }
        do {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AIConnectionError.message("Veilige MCP-sleutel maken mislukt.")
            }
            try store(Connection(device_id: "local", credential: bytes.map { String(format: "%02x", $0) }.joined(), user_id: "local", scopes: scopes))
            startLocalServer()
        } catch { status = error.localizedDescription }
    }

    func updatePermissions(_ scopes: [String]) async {
        guard var current = connection else { return }
        #if os(macOS)
        localServer?.stop()
        #endif
        connection?.scopes = []
        current.scopes = scopes
        do { try store(current); startLocalServer() }
        catch { status = error.localizedDescription }
    }

    func disconnect() async {
        var revoked = connection
        revoked?.scopes = []
        connection = nil
        #if os(macOS)
        localServer?.stop(); localServer = nil
        #endif
        do {
            if let revoked { try store(revoked) }
            connection = nil
            KeychainService.shared.delete(for: Self.key)
            status = "Lokale MCP uitgeschakeld"
        } catch { connection = nil; status = "MCP is gestopt, maar uitschakelen opslaan mislukt. Controleer de sleutelhanger vóór herstart." }
    }

    func copyConfiguration() {
        #if os(macOS)
        guard let current = connection,
              let data = try? JSONSerialization.data(withJSONObject: ["url": "http://127.0.0.1:11218/mcp", "headers": ["Authorization": "Bearer \(current.credential)"]], options: .prettyPrinted),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static func requiredScope(_ tool: String) -> String {
        if ["start_recording", "pause_recording", "resume_recording", "stop_recording"].contains(tool) { return "record" }
        if ["save_minutes", "update_transcript", "save_profile", "open_view"].contains(tool) { return "write" }
        return "read"
    }

    private func allowed(_ command: [String: Any]) -> Bool {
        guard let current = connection, let tool = command["tool"] as? String,
              let expires = command["expires_at"] as? Double,
              command["device_id"] as? String == current.device_id,
              command["scope"] as? String == Self.requiredScope(tool),
              current.scopes.contains(Self.requiredScope(tool)), expires > Date().timeIntervalSince1970 else { return false }
        return true
    }

    static func revision(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func snapshot(_ record: TranscriptRecord) -> [String: Any] {
        ["id": record.id, "title": record.title, "tags": record.tags,
         "text": record.rawTranscription, "minutes": record.notuleHtml,
         "style": record.minutesStyleJSON ?? ""]
    }

    private func execute(_ command: [String: Any]) async throws -> [String: Any] {
        guard allowed(command), let tool = command["tool"] as? String,
              let args = command["arguments"] as? [String: Any], let vm = recordingVM else {
            throw AIConnectionError.message("Opdracht niet toegestaan.")
        }
        let store = LocalTranscriptStore.shared
        if tool == "get_app_state" {
            return ["recording_phase": String(describing: vm.recordingState), "tasks": vm.activeTasks.map { ["id": $0.taskId, "status": $0.status.rawValue] }]
        }
        if tool == "list_transcripts" {
            let query = args["query"] as? String ?? ""
            let offset = args["offset"] as? Int ?? 0, limit = args["limit"] as? Int ?? 20
            guard offset >= 0, (1...100).contains(limit) else { throw AIConnectionError.message("Ongeldige paginering.") }
            let records = store.allRecords().filter { query.isEmpty || ($0.title + " " + $0.tags.joined(separator: " ")).localizedCaseInsensitiveContains(query) }
            return ["total": records.count, "items": try records.dropFirst(offset).prefix(limit).map { record in
                ["id": record.taskId, "title": record.title, "tags": record.tags, "created_at": ISO8601DateFormatter().string(from: record.createdAt), "revision": try Self.revision(Self.snapshot(record))] as [String: Any]
            }]
        }
        let profiles = LocalProfileStore.choices()
        if tool == "list_profiles" { return ["profiles": profiles.map { ["id": $0.id, "name": $0.name, "is_default": $0.isDefault == true] as [String: Any] }] }
        if tool == "get_profile" || tool == "save_profile" {
            guard var profile = profiles.first(where: { $0.id == args["profile_id"] as? String }) else { throw AIConnectionError.message("Profiel niet gevonden.") }
            let snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
            let revision = try Self.revision(snapshot)
            if tool == "get_profile" { return snapshot.merging(["revision": revision]) { _, new in new } }
            guard args["revision"] as? String == revision else { throw AIConnectionError.message("Profiel is gewijzigd. Lees het opnieuw.") }
            guard let name = args["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
                  let system = args["system_prompt"] as? String, let prompt = args["notule_prompt"] as? String,
                  let template = args["output_template"] as? String, [system, prompt, template].allSatisfy({ $0.count <= 100_000 })
            else { throw AIConnectionError.message("Ongeldig profiel.") }
            if profile.isDefault == true { profile.id = UUID().uuidString; profile.isDefault = false }
            profile.name = name
            profile.systemPrompt = system
            profile.notulePrompt = prompt
            profile.template = template
            if let raw = args["style"] as? [String: Any] {
                profile.minutesStyle = try JSONDecoder().decode(MinutesStyle.self, from: JSONSerialization.data(withJSONObject: raw))
                try profile.minutesStyle?.validate()
            }
            try LocalProfileStore.save(profile)
            await vm.reloadProfiles()
            let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
            return ["profile_id": profile.id, "revision": try Self.revision(saved)]
        }
        if tool == "open_view" {
            guard let view = args["view"] as? String, ["recording", "transcripts", "transcript", "profiles", "settings"].contains(view) else { throw AIConnectionError.message("Onbekend scherm.") }
            if view == "transcript", store.record(forTaskId: args["transcript_id"] as? String ?? "") == nil { throw LocalStoreError.recordNotFound }
            NotificationCenter.default.post(name: .aiOpenView, object: nil, userInfo: args)
            #if os(macOS)
            NSApplication.shared.windows.first(where: { $0.canBecomeMain })?.deminiaturize(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            #endif
            return ["ok": true]
        }
        if ["start_recording", "pause_recording", "resume_recording", "stop_recording"].contains(tool) {
            switch tool {
            case "start_recording":
                guard vm.recordingState == .idle, let profile = profiles.first(where: { $0.id == args["profile_id"] as? String }),
                      let rawMode = args["mode"] as? String,
                      let mode = RecordingMode(rawValue: rawMode == "system" ? "systemAudio" : rawMode) else { throw AIConnectionError.message("Controleer opnamefase, profiel en audiomodus.") }
                if mode != .systemAudio, AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { throw AIConnectionError.message("Geef eerst microfoontoegang in Systeeminstellingen.") }
                vm.selectedProfile = profile; vm.selectedMode = mode
                await vm.startRecording()
                if case let .error(message) = vm.recordingState { throw AIConnectionError.message(message) }
            case "pause_recording":
                guard vm.recordingState == .recording else { throw AIConnectionError.message("Geen actieve opname.") }; vm.pauseRecording()
            case "resume_recording":
                guard vm.recordingState == .paused else { throw AIConnectionError.message("Geen gepauzeerde opname.") }; vm.resumeRecording()
            default:
                guard vm.recordingState.isRecording else { throw AIConnectionError.message("Geen actieve opname.") }
                // stopAndUpload flips to stopping before its first suspension.
                await vm.stopAndUpload()
            }
            if case let .error(message) = vm.recordingState { throw AIConnectionError.message(message) }
            return ["recording_phase": String(describing: vm.recordingState)]
        }
        guard let record = store.record(forTaskId: args["transcript_id"] as? String ?? "") else { throw LocalStoreError.recordNotFound }
        if tool == "get_transcript" {
            let offset = args["offset"] as? Int ?? 0, limit = args["limit"] as? Int ?? 16000
            guard offset >= 0, (1...32000).contains(limit) else { throw AIConnectionError.message("Ongeldig transcriptdeel.") }
            let text = record.rawTranscription
            return ["id": record.taskId, "title": record.title, "tags": record.tags,
                    "text": String(text.dropFirst(offset).prefix(limit)), "total_length": text.count,
                    "next_offset": offset + limit < text.count ? offset + limit : NSNull(),
                    "minutes": record.notuleHtml, "revision": try Self.revision(Self.snapshot(record))]
        }
        if tool == "save_minutes" || tool == "update_transcript" {
            if tool == "save_minutes" {
                guard let html = args["html"] as? String, html.count <= 1_000_000 else { throw AIConnectionError.message("Ongeldige notule.") }
            } else if args["title"] as? String == nil || args["tags"] as? [String] == nil { throw AIConnectionError.message("Ongeldige titel of tags.") }
            var style: MinutesStyle?
            if let raw = args["style"] as? [String: Any] {
                style = try JSONDecoder().decode(MinutesStyle.self, from: JSONSerialization.data(withJSONObject: raw))
                try style?.validate()
            }
            try store.applyAIEdit(taskId: record.taskId, revision: args["revision"] as? String ?? "",
                                  html: tool == "save_minutes" ? args["html"] as? String : nil,
                                  title: tool == "update_transcript" ? args["title"] as? String : nil,
                                  tags: tool == "update_transcript" ? args["tags"] as? [String] : nil, style: style)
            NotificationCenter.default.post(name: .aiTranscriptChanged, object: nil)
            return ["id": record.taskId, "revision": try Self.revision(Self.snapshot(record))]
        }
        if tool == "export_minutes" {
            let html = record.notuleHtml
            switch args["format"] as? String {
            case "pdf", "html":
                let style = record.minutesStyleJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                return ["html": html, "title": record.title, "style": style ?? NSNull()]
            case "markdown": return ["content": htmlToMarkdown(html), "mime_type": "text/markdown"]
            case "txt": return ["content": htmlToMarkdown(html), "mime_type": "text/plain"]
            default: throw AIConnectionError.message("Onbekend exportformaat.")
            }
        }
        throw AIConnectionError.message("Onbekende opdracht.")
    }
}

#if os(macOS)
@preconcurrency import Network

/// Loopback-only JSON MCP. Token and payloads never leave the local machine.
@MainActor
final class LocalMCPServer {
    private let listener: NWListener
    private let token: String
    private let scopes: [String]
    private let handler: @MainActor (String, [String: Any]) async throws -> [String: Any]
    private let onStatus: @MainActor (String) -> Void
    private var connections: [UUID: NWConnection] = [:]
    private var running = false
    private static let tools: [[String: Any]] = (try! JSONSerialization.jsonObject(with: Data(catalog.utf8))) as! [[String: Any]]

    init(token: String, scopes: [String], handler: @escaping @MainActor (String, [String: Any]) async throws -> [String: Any], onStatus: @escaping @MainActor (String) -> Void) throws {
        guard token.count == 64, scopes.allSatisfy({ ["read", "write", "record"].contains($0) }) else { throw AIConnectionError.message("Ongeldige MCP-instelling.") }
        self.token = token; self.scopes = scopes; self.handler = handler; self.onStatus = onStatus
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 11218)
        listener = try NWListener(using: parameters)
    }
    func start() {
        running = true
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.onStatus("Lokale MCP actief op http://127.0.0.1:11218/mcp")
                case .failed: self?.onStatus("Lokale MCP kon niet starten. Controleer of de poort vrij is."); self?.stop()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
    }
    func stop() {
        running = false; listener.cancel()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }
    private func accept(_ connection: NWConnection) {
        guard running, connections.count < 8 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(35))
            self?.connections.removeValue(forKey: id)?.cancel()
        }
        receive(connection, id: id, bytes: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var bytes = bytes; if let data { bytes.append(data) }
                guard error == nil, bytes.count <= 2_020_000 else { self.finish(connection, id: id, status: 400, object: ["error": "Ongeldige aanvraag."]); return }
                guard let range = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                    if complete || bytes.count > 16_384 { self.finish(connection, id: id, status: 400, object: ["error": "Ongeldige header."]) }
                    else { self.receive(connection, id: id, bytes: bytes) }; return
                }
                guard let header = String(data: bytes[..<range.upperBound], encoding: .utf8) else { self.finish(connection, id: id, status: 400, object: [:]); return }
                let lines = header.components(separatedBy: "\r\n")
                var headers: [String: String] = [:]
                for line in lines.dropFirst() where !line.isEmpty {
                    guard let colon = line.firstIndex(of: ":") else { self.finish(connection, id: id, status: 400, object: [:]); return }
                    let key = line[..<colon].lowercased()
                    guard headers[key] == nil else { self.finish(connection, id: id, status: 400, object: [:]); return }
                    headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard self.running, headers["authorization"] == "Bearer \(self.token)",
                      ["127.0.0.1:11218", "localhost:11218"].contains(headers["host"] ?? ""), headers["origin"] == nil, headers["transfer-encoding"] == nil else {
                    self.finish(connection, id: id, status: 403, object: ["error": "Geen lokale MCP-toegang."]); return
                }
                guard lines.first == "POST /mcp HTTP/1.1" else { self.finish(connection, id: id, status: 405, object: [:]); return }
                guard headers["mcp-protocol-version"] == nil || headers["mcp-protocol-version"] == "2025-06-18" else { self.finish(connection, id: id, status: 400, object: [:]); return }
                guard let length = Int(headers["content-length"] ?? ""), (0...2_000_000).contains(length) else { self.finish(connection, id: id, status: 400, object: [:]); return }
                let needed = range.upperBound + length
                if bytes.count < needed {
                    if complete { self.finish(connection, id: id, status: 400, object: [:]) }
                    else { self.receive(connection, id: id, bytes: bytes) }; return
                }
                guard let request = try? JSONSerialization.jsonObject(with: bytes[range.upperBound..<needed]) as? [String: Any] else { self.finish(connection, id: id, status: 400, object: [:]); return }
                let result = await self.process(request)
                self.finish(connection, id: id, status: result.0, object: result.1)
            }
        }
    }
    private func process(_ request: [String: Any]) async -> (Int, [String: Any]?) {
        guard request["jsonrpc"] as? String == "2.0", request["method"] is String else { return (400, ["error": "Ongeldige aanvraag."]) }
        guard let id = request["id"] else { return (202, nil) }
        let result: [String: Any]
        switch request["method"] as? String {
        case "initialize": result = ["protocolVersion": "2025-06-18", "capabilities": ["tools": ["listChanged": false]], "serverInfo": ["name": "ThoughtVault Mac", "version": "1.0"], "instructions": "Local app only. Read revisions before writes. Never retry uncertain recording results."]
        case "ping": result = [:]
        case "tools/list": result = ["tools": Self.tools.filter { scopes.contains($0["scope"] as? String ?? "") }.map { tool in var tool = tool; tool.removeValue(forKey: "scope"); return tool }]
        case "tools/call":
            let params = request["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            do {
                guard params["arguments"] == nil || params["arguments"] is [String: Any] else { throw AIConnectionError.message("Ongeldige toolargumenten.") }
                guard running, Self.tools.contains(where: { $0["name"] as? String == name }), scopes.contains(AIConnectionViewModel.requiredScope(name)) else { throw AIConnectionError.message("Tool niet toegestaan.") }
                let value = name == "list_devices" ? ["devices": [["id": "local", "platform": "macOS", "online": true]]] : try await handler(name, params["arguments"] as? [String: Any] ?? [:])
                result = ["content": [["type": "text", "text": String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)]], "structuredContent": value, "isError": false]
            } catch { result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true] }
        default: return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Onbekende methode"]])
        }
        return (200, ["jsonrpc": "2.0", "id": id, "result": result])
    }
    private func finish(_ connection: NWConnection, id: UUID, status: Int, object: [String: Any]?) {
        guard connections.removeValue(forKey: id) != nil else { return }
        let body = object.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var response = Data("HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static let catalog = #"""
[{"name": "list_devices", "description": "Read the availability of this local app.", "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}, {"name": "get_app_state", "description": "Read recording phase and background processing tasks.", "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}, {"name": "list_transcripts", "description": "Search local transcripts. Returns metadata, no transcript text.", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}, "offset": {"type": "integer"}, "limit": {"type": "integer"}}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}, {"name": "get_transcript", "description": "Read a text chunk plus a content revision for subsequent writes.", "inputSchema": {"type": "object", "properties": {"transcript_id": {"type": "string"}, "offset": {"type": "integer"}, "limit": {"type": "integer"}}, "required": ["transcript_id"], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}, {"name": "save_minutes", "description": "Attach generated minutes to the original transcript; reject stale revisions.", "inputSchema": {"type": "object", "properties": {"transcript_id": {"type": "string"}, "revision": {"type": "string"}, "html": {"type": "string"}, "style": {"type": "object"}}, "required": ["transcript_id", "revision", "html"], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "write"}, {"name": "update_transcript", "description": "Update title and tags only if the read revision is still current.", "inputSchema": {"type": "object", "properties": {"transcript_id": {"type": "string"}, "revision": {"type": "string"}, "title": {"type": "string"}, "tags": {"type": "array", "items": {"type": "string"}}}, "required": ["transcript_id", "revision", "title", "tags"], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "write"}, {"name": "list_profiles", "description": "List the device's current recording profiles.", "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}, {"name": "get_profile", "description": "Read profile prompts, output template and revision.", "inputSchema": {"type": "object", "properties": {"profile_id": {"type": "string"}}, "required": ["profile_id"], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}, {"name": "save_profile", "description": "Save a profile; built-in profiles are copied to a custom profile.", "inputSchema": {"type": "object", "properties": {"profile_id": {"type": "string"}, "revision": {"type": "string"}, "name": {"type": "string"}, "system_prompt": {"type": "string"}, "notule_prompt": {"type": "string"}, "output_template": {"type": "string"}, "style": {"type": "object"}}, "required": ["profile_id", "revision", "name", "system_prompt", "notule_prompt", "output_template"], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "write"}, {"name": "open_view", "description": "Open a screen in this local app.", "inputSchema": {"type": "object", "properties": {"view": {"type": "string", "enum": ["recording", "transcripts", "transcript", "profiles", "settings"]}, "transcript_id": {"type": "string"}}, "required": ["view"], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "write"}, {"name": "start_recording", "description": "Start recording using the selected profile/audio mode and visible indicator.", "inputSchema": {"type": "object", "properties": {"profile_id": {"type": "string"}, "mode": {"type": "string", "enum": ["microphone", "system", "combined"]}}, "required": ["profile_id", "mode"], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "record"}, {"name": "pause_recording", "description": "Pause an active recording.", "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "record"}, {"name": "resume_recording", "description": "Resume a paused recording.", "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "record"}, {"name": "stop_recording", "description": "Stop once and start the app's existing processing flow.", "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}, "annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}, "scope": "record"}, {"name": "export_minutes", "description": "Export HTML, Markdown or text. PDF returns print-ready HTML and document styling for the client to render.", "inputSchema": {"type": "object", "properties": {"transcript_id": {"type": "string"}, "format": {"type": "string", "enum": ["html", "markdown", "txt", "pdf"]}}, "required": ["transcript_id", "format"], "additionalProperties": false}, "annotations": {"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false}, "scope": "read"}]
"""#
}
#endif
