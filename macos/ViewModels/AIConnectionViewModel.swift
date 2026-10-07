import Foundation
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
        // The model owns all styling. Discard previous styles before applying it.
        let body = html.replacingOccurrences(of: "<style\\b[^>]*>[\\s\\S]*?</style>", with: "", options: [.caseInsensitive, .regularExpression])
        return "<style>\(try css())\(try css(selector: "#content"))</style>" + body
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
    static let base = "https://n8n.prezent.nl/tstudio/api"
    private static let key = "mcpDeviceConnection"
    struct Connection: Codable {
        var device_id: String
        var credential: String
        var user_id: String
        var scopes: [String]
    }
    private(set) var connection: Connection?
    var status: String = "Niet gekoppeld"
    var busy = false
    private var pollTask: Task<Void, Never>?
    private weak var recordingVM: RecordingViewModel?
    private let session = URLSession(configuration: .ephemeral)

    func start(recordingVM: RecordingViewModel) {
        self.recordingVM = recordingVM
        guard pollTask == nil else { return }
        if let raw = KeychainService.shared.load(for: Self.key), let data = raw.data(using: .utf8) {
            connection = try? JSONDecoder().decode(Connection.self, from: data)
        }
        if connection != nil { beginPolling() }
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, credential: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credential { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIConnectionError.message(result["detail"] as? String ?? "AI-koppeling niet bereikbaar. Probeer opnieuw.")
        }
        return result
    }

    private func store(_ value: Connection) throws {
        let raw = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        KeychainService.shared.save(raw, for: Self.key)
        guard KeychainService.shared.load(for: Self.key) == raw else {
            throw AIConnectionError.message("Koppelgegevens opslaan in de sleutelhanger mislukt.")
        }
        connection = value
    }

    func pair(scopes: [String]) async {
        busy = true
        defer { busy = false }
        do {
            #if os(macOS)
            let deviceName = Host.current().localizedName ?? "ThoughtVault Mac"
            let platform = "macOS"
            #else
            let deviceName = UIDevice.current.name
            let platform = "iOS"
            #endif
            let pending = try await request("/ai/devices/pair", method: "POST", body: [
                "name": deviceName, "platform": platform, "scopes": scopes,
            ])
            guard let uri = pending["verification_uri"] as? String, uri.hasPrefix(Self.base + "/ai/devices/verify?"),
                  let url = URL(string: uri), let ticket = pending["ticket"], let secret = pending["secret"] else {
                throw AIConnectionError.message("Ongeldige koppelaanvraag.")
            }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
            status = "Voltooi de koppeling in je browser"
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                try await Task.sleep(for: .seconds(2))
                let ready = try await request("/ai/devices/pair-status", method: "POST", body: ["ticket": ticket, "secret": secret])
                if ready["pending"] as? Bool == true { continue }
                let value = try JSONDecoder().decode(Connection.self, from: JSONSerialization.data(withJSONObject: ready))
                try store(value)
                beginPolling()
                return
            }
            throw AIConnectionError.message("Koppelaanvraag verlopen. Probeer opnieuw.")
        } catch { status = "Koppelen niet gelukt. Probeer opnieuw. \(error.localizedDescription)" }
    }

    func updatePermissions(_ scopes: [String]) async {
        guard var current = connection else { return }
        busy = true
        defer { busy = false }
        do {
            var reduced = current
            reduced.scopes = current.scopes.filter { scopes.contains($0) }
            // Persist reduced rights first, so a restart cannot restore revoked rights.
            try store(reduced)
            _ = try await request("/ai/devices/\(current.device_id)", method: "PUT", body: ["scopes": scopes], credential: current.credential)
            current.scopes = scopes
            try store(current)
        } catch { status = "Rechten wijzigen niet bevestigd. Probeer opnieuw. \(error.localizedDescription)" }
    }

    func disconnect() async {
        guard var current = connection else { return }
        busy = true
        defer { busy = false }
        do {
            current.scopes = []
            try store(current)
            _ = try await request("/ai/devices/\(current.device_id)", method: "DELETE", credential: current.credential)
            pollTask?.cancel(); pollTask = nil
            KeychainService.shared.delete(for: Self.key)
            connection = nil
            status = "Niet gekoppeld"
        } catch { status = "Ontkoppelen niet bevestigd. Probeer opnieuw. \(error.localizedDescription)" }
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

    private func beginPolling() {
        guard pollTask == nil else { return }
        status = "Verbinding maken…"
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let current = connection {
                do {
                    let reply = try await request("/ai/devices/\(current.device_id)/commands", credential: current.credential)
                    try Task.checkCancellation()
                    status = "Verbonden"
                    guard let command = reply["command"] as? [String: Any], allowed(command),
                          let id = command["id"] as? String else { continue }
                    var result: [String: Any]
                    if try !receipt(id) { result = ["error": "Resultaat onzeker; opdracht wordt niet herhaald."] }
                    else {
                        _ = try await request("/ai/devices/\(current.device_id)/commands/\(id)/validate", credential: current.credential)
                        guard allowed(command) else { continue }
                        do { result = try await execute(command) }
                        catch { result = ["error": error.localizedDescription] }
                    }
                    _ = try await request("/ai/devices/\(current.device_id)/commands/\(id)", method: "POST", body: ["result": result], credential: current.credential)
                } catch is CancellationError { return }
                catch {
                    status = "Verbinding onderbroken. Controleer je internetverbinding. \(error.localizedDescription)"
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func receipt(_ id: String) throws -> Bool {
        let folder = URL.applicationSupportDirectory.appending(path: "ThoughtVault")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "ai-command-receipts.json")
        var ids: [String] = []
        if FileManager.default.fileExists(atPath: url.path) {
            ids = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        }
        guard !ids.contains(id) else { return false }
        ids = Array(ids.suffix(999)) + [id]
        try JSONEncoder().encode(ids).write(to: url, options: .atomic)
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
