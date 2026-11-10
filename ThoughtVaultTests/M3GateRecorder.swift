import Foundation
import os

/// Intercepts the production chat-completion requests to ollama.com, sends each one once
/// through `transport` and keeps the exchange as gate evidence. No retries, hard request cap.
/// Only active between `start` and `stop`, so the rest of the suite never touches it.
final class M3GateRecorder: URLProtocol, @unchecked Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)

    struct Exchange: Sendable {
        let caseName: String
        let number: Int
        let url: String
        /// Request headers without credentials.
        let headers: [String: String]
        let body: Data
        var status: Int?
        var response = Data()
        var error: String?

        var label: String { "\(caseName)-\(number)" }
        var transportOK: Bool { error == nil && status == 200 }
    }

    private struct State {
        var transport: Transport?
        var cap = 0
        var caseName = ""
        var exchanges: [Exchange] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let forwardedKey = "M3GateForwarded"
    private var loading: Task<Void, Never>?

    static func start(cap: Int, transport: @escaping Transport) {
        state.withLock { $0 = State(transport: transport, cap: cap) }
        URLProtocol.registerClass(M3GateRecorder.self)
    }

    static func stop() {
        URLProtocol.unregisterClass(M3GateRecorder.self)
        state.withLock { $0.transport = nil }
    }

    /// Requests after this call are numbered `<name>-1`, `<name>-2`, ...
    static func begin(_ caseName: String) { state.withLock { $0.caseName = caseName } }

    static func exchanges(for caseName: String) -> [Exchange] {
        state.withLock { $0.exchanges.filter { $0.caseName == caseName } }
    }

    static var requestCount: Int { state.withLock { $0.exchanges.count } }

    /// Drops every header that can carry a credential.
    static func redacted(_ headers: [String: String]?) -> [String: String] {
        (headers ?? [:]).filter { !["authorization", "proxy-authorization", "cookie"].contains($0.key.lowercased()) }
    }

    /// Model text and model id from an OpenAI-style server-sent event stream.
    static func modelText(_ data: Data) -> (text: String, model: String?) {
        var text = ""
        var model: String?
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) where line.hasPrefix("data: ") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] else { continue }
            model = model ?? json["model"] as? String
            let delta = (json["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]
            text += delta?["content"] as? String ?? ""
        }
        return (text, model)
    }

    /// The real network call: a separate ephemeral session that this protocol never intercepts.
    static let live: Transport = { request in
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (http, data)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard property(forKey: forwardedKey, in: request) == nil, request.url?.host?.lowercased() == "ollama.com",
              request.url?.path == "/v1/chat/completions" else { return false }
        return state.withLock { $0.transport != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let body = Self.body(of: request)
        let (index, transport) = Self.state.withLock { state -> (Int?, Transport?) in
            let caseName = state.caseName
            var exchange = Exchange(caseName: caseName, number: state.exchanges.filter { $0.caseName == caseName }.count + 1,
                                    url: request.url?.absoluteString ?? "", headers: Self.redacted(request.allHTTPHeaderFields),
                                    body: body)
            guard state.exchanges.count < state.cap, let transport = state.transport else {
                exchange.error = "M3 request cap of \(state.cap) reached; request not sent"
                state.exchanges.append(exchange)
                return (nil, nil)
            }
            state.exchanges.append(exchange)
            return (state.exchanges.count - 1, transport)
        }
        guard let index, let transport else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        // URLProtocol and its client predate Sendable; URLSession accepts these callbacks from any thread.
        nonisolated(unsafe) let owner: URLProtocol = self
        nonisolated(unsafe) let client = self.client
        loading = Task {
            do {
                let (response, data) = try await transport(Self.forwardable(request, body: body))
                Self.state.withLock {
                    $0.exchanges[index].status = response.statusCode
                    $0.exchanges[index].response = data
                }
                client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(owner, didLoad: data)
                client?.urlProtocolDidFinishLoading(owner)
            } catch {
                Self.state.withLock { $0.exchanges[index].error = String(describing: error) }
                client?.urlProtocol(owner, didFailWithError: error)
            }
        }
    }

    override func stopLoading() { loading?.cancel() }

    /// URLSession hands a protocol its body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func forwardable(_ request: URLRequest, body: Data) -> URLRequest {
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        mutable.httpBodyStream = nil
        mutable.httpBody = body
        URLProtocol.setProperty(true, forKey: forwardedKey, in: mutable)
        return mutable as URLRequest
    }
}
