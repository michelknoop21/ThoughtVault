import Foundation

/// JSON-RPC side of the local MCP server: protocol messages, tool catalogue and argument
/// validation. Tool work itself happens in `call`. Behaviour is pinned by
/// data/mcp/protocol-fixtures.json, which the Windows router runs too.
struct McpRouter: Sendable {
    /// Arguments and result travel as JSON objects in `Data`, so they can cross to the main actor.
    typealias Call = @Sendable (_ name: String, _ arguments: Data) async throws -> Data

    static let supportedVersions = ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26"]
    static let fallbackVersion = "2025-11-25"
    private static let versionKey = "io.modelcontextprotocol/protocolVersion"

    let catalogue: McpCatalogue
    let version: String

    /// Handles one line from a client. Returns the response line, or nil for notifications.
    func handle(_ line: String, allowWrite: Bool, call: Call) async -> String? {
        guard let data = line.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let message = parsed as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid Request"]])
        }
        // No id: a notification. An explicit null id is still a request and gets an answer.
        guard let id = message["id"] else { return nil }
        guard let method = message["method"] as? String else {
            // A response to a server request (we send none) needs no answer.
            if message["result"] != nil || message["error"] != nil { return nil }
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "Invalid Request"]])
        }
        let params = message["params"] as? [String: Any] ?? [:]
        let response: [String: Any]
        if let requested = (params["_meta"] as? [String: Any])?[Self.versionKey] as? String,
           !Self.supportedVersions.contains(requested) {
            response = ["error": ["code": -32022, "message": "Unsupported protocol version",
                                  "data": ["supported": Self.supportedVersions, "requested": requested]]]
        } else {
            response = await dispatch(method, params: params, allowWrite: allowWrite, call: call)
        }
        return Self.encode(response.merging(["jsonrpc": "2.0", "id": id]) { _, new in new })
    }

    private func dispatch(_ method: String, params: [String: Any], allowWrite: Bool, call: Call) async -> [String: Any] {
        let serverInfo = ["name": "ThoughtVault", "version": version]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return ["result": ["resultType": "complete",
                               "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.fallbackVersion,
                               "capabilities": ["tools": ["listChanged": false]],
                               "serverInfo": serverInfo, "instructions": catalogue.instructions]]
        case "server/discover":
            return ["result": ["resultType": "complete", "supportedVersions": Self.supportedVersions,
                               "capabilities": ["tools": [String: Any]()],
                               "_meta": ["io.modelcontextprotocol/serverInfo": serverInfo],
                               "instructions": catalogue.instructions, "ttlMs": 0, "cacheScope": "private"]]
        case "ping":
            return ["result": ["resultType": "complete"]]
        case "tools/list":
            return ["result": ["resultType": "complete", "tools": catalogue.listed(allowWrite: allowWrite),
                               "ttlMs": 0, "cacheScope": "private"]]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard let tool = catalogue.tool(name), allowWrite || tool.readOnly else {
                return ["error": ["code": -32602, "message": "Unknown tool: \(name)"]]
            }
            let raw = params["arguments"] ?? [String: Any]()
            if let problem = McpSchema.problem(raw, schema: tool.inputSchema) {
                return ["result": Self.toolError("Ongeldige invoer: \(problem)")]
            }
            var arguments = raw as? [String: Any] ?? [:]
            for (key, property) in tool.inputSchema["properties"] as? [String: [String: Any]] ?? [:] where arguments[key] == nil {
                if let value = property["default"] { arguments[key] = value }
            }
            do {
                let data = try await call(name, JSONSerialization.data(withJSONObject: arguments))
                let value = try JSONSerialization.jsonObject(with: data)
                return ["result": ["resultType": "complete",
                                   "content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
                                   "structuredContent": value]]
            } catch {
                return ["result": Self.toolError(error.localizedDescription)]
            }
        default:
            return ["error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    private static func toolError(_ text: String) -> [String: Any] {
        ["resultType": "complete", "content": [["type": "text", "text": text]], "isError": true]
    }

    static func encode(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// data/mcp/tools.json: the tool contract shared with the Windows app.
struct McpCatalogue: @unchecked Sendable {
    struct Tool { let name: String; let readOnly: Bool; let inputSchema: [String: Any]; let listed: [String: Any] }
    // "destructive" marks tools that overwrite existing content, so clients ask before calling them.
    let instructions: String
    let tools: [Tool]

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["tools"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        instructions = root["instructions"] as? String ?? ""
        tools = entries.map { entry in
            let readOnly = entry["scope"] as? String == "read"
            var listed = entry
            listed.removeValue(forKey: "scope")
            listed.removeValue(forKey: "destructive")
            listed["annotations"] = ["readOnlyHint": readOnly, "destructiveHint": entry["destructive"] as? Bool ?? false,
                                     "openWorldHint": false]
            return Tool(name: entry["name"] as? String ?? "", readOnly: readOnly,
                        inputSchema: entry["inputSchema"] as? [String: Any] ?? [:], listed: listed)
        }
    }

    static func bundled() throws -> McpCatalogue {
        guard let url = Bundle.main.url(forResource: "tools", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try McpCatalogue(data: Data(contentsOf: url))
    }

    func tool(_ name: String) -> Tool? { tools.first { $0.name == name } }
    func listed(allowWrite: Bool) -> [[String: Any]] { tools.filter { allowWrite || $0.readOnly }.map(\.listed) }
}

/// The subset of JSON Schema that tools.json uses.
enum McpSchema {
    static func problem(_ value: Any, schema: [String: Any], path: String = "") -> String? {
        let label = path.isEmpty ? "invoer" : path
        if let types = (schema["type"] as? [String]) ?? (schema["type"] as? String).map({ [$0] }),
           !types.contains(where: { matches(value, type: $0) }) {
            return "\(label) moet van type \(types.joined(separator: " of ")) zijn"
        }
        if let allowed = schema["enum"] as? [String], !allowed.contains(value as? String ?? "") {
            return "\(label) moet een van \(allowed.joined(separator: ", ")) zijn"
        }
        if let text = value as? String {
            if let min = schema["minLength"] as? Int, text.utf16.count < min { return "\(label) is te kort" }
            if let max = schema["maxLength"] as? Int, text.utf16.count > max { return "\(label) is te lang (maximaal \(max) tekens)" }
        }
        if let number = value as? NSNumber, !isBoolean(value) {
            if let min = schema["minimum"] as? Double, number.doubleValue < min { return "\(label) moet minstens \(Int(min)) zijn" }
            if let max = schema["maximum"] as? Double, number.doubleValue > max { return "\(label) mag hoogstens \(Int(max)) zijn" }
        }
        if let items = value as? [Any] {
            if let min = schema["minItems"] as? Int, items.count < min { return "\(label) heeft minstens \(min) waarde(n) nodig" }
            if let itemSchema = schema["items"] as? [String: Any] {
                for (index, item) in items.enumerated() {
                    if let problem = problem(item, schema: itemSchema, path: "\(label)[\(index)]") { return problem }
                }
            }
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil { return "\(key) ontbreekt" }
            for (key, item) in object {
                guard let itemSchema = properties[key] else {
                    if schema["additionalProperties"] as? Bool == false { return "\(key) is geen bekend veld" }
                    continue
                }
                if let problem = problem(item, schema: itemSchema, path: key) { return problem }
            }
        }
        return nil
    }

    /// JSONSerialization gives NSNumber for both; `is Bool` is also true for the number 1.
    private static func isBoolean(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        let isBool = isBoolean(value)
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return isBool
        case "integer": return !isBool && (value as? NSNumber).map { $0.doubleValue.rounded() == $0.doubleValue } ?? false
        case "number": return !isBool && value is NSNumber
        case "null": return value is NSNull
        default: return true
        }
    }
}
