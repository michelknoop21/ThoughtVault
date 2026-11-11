// ProspectFlowService.swift
// ThoughtVault
//
// Turns a customer conversation into a draft offer in Prospect Flow. The server
// derives and prices the lines; this client only picks the customer and sends
// notule + transcript. Auth is the instance API key (X-API-Key), kept in the Keychain.

import Foundation

struct ProspectFlowService: Sendable {

    static let baseURLKey = "prospectFlowBaseURL"
    static let apiKeyKeychainKey = "prospectFlowApiKey"
    static let defaultBaseURL = "https://prospectflow.yinga.ai"

    let baseURL: String
    private let apiKey: String

    init(baseURL: String? = nil, apiKey: String? = nil) {
        var base = (baseURL ?? UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = base
        self.apiKey = apiKey ?? KeychainService.shared.load(for: Self.apiKeyKeychainKey) ?? ""
    }

    /// The menu item only shows once a key has been entered.
    static var isConfigured: Bool {
        !(KeychainService.shared.load(for: apiKeyKeychainKey) ?? "").isEmpty
    }

    // MARK: - Models

    struct Candidate: Decodable, Identifiable, Hashable, Sendable {
        let id: Int
        let naam: String
        let plaats: String?
    }

    struct OfferResult: Decodable, Sendable {
        struct Klant: Decodable, Sendable { let id: Int?; let naam: String; let nieuw: Bool }
        let offerId: Int
        let number: String
        let url: String
        let klant: Klant
        let regels: Int
        let teControleren: Int
        let bestaand: Bool
        let model: String?
        let terugvalGebruikt: Bool
    }

    /// Per-notule reference, so a second tap opens the same offer instead of creating a new one.
    struct OfferRef: Codable, Equatable, Sendable {
        var id: Int?
        var number: String?
        var url: String?
        /// Set before the POST and reused on retry: a timeout plus a second tap gives one offer.
        var pendingRequestId: String?
        /// Customer choice the pending id was made for; another choice gets a new id.
        var pendingCustomer: String?
        var pendingNewCustomerName: String?

        var pendingChoice: Customer? {
            guard pendingRequestId?.isEmpty == false, let pendingCustomer else { return nil }
            if pendingCustomer.hasPrefix("new:") {
                let normalized = String(pendingCustomer.dropFirst(4))
                guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let name = pendingNewCustomerName.flatMap { $0.lowercased() == normalized ? $0 : nil } ?? normalized
                return .new(name)
            }
            if pendingCustomer.hasPrefix("id:"), let id = Int(pendingCustomer.dropFirst(3)), id > 0 {
                return .existing(id)
            }
            return nil
        }
    }

    enum Customer: Sendable {
        case existing(Int)
        case new(String)

        var key: String {
            switch self {
            case .existing(let id): return "id:\(id)"
            case .new(let name): return "new:\(name.lowercased())"
            }
        }
    }

    enum PFError: LocalizedError {
        case missingConfig
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingConfig:
                return String(localized: "Vul eerst de Prospect Flow-URL en API-sleutel in.")
            case .server(let code, let detail):
                // The server's Dutch detail is the most precise text (a 503 or 403 has
                // several causes); the fixed texts only cover a missing detail.
                if !detail.isEmpty, code != 401, code != 429 { return detail }
                switch code {
                case 401: return String(localized: "Prospect Flow accepteert de API-sleutel niet.")
                case 403: return String(localized: "Deze functie staat uit in Prospect Flow.")
                case 413: return String(localized: "Het transcript is te lang voor Prospect Flow.")
                case 429: return String(localized: "Te veel verzoeken. Probeer het over een minuut opnieuw.")
                case 503: return String(localized: "Het AI-model van Prospect Flow is niet bereikbaar.")
                default: return String(localized: "Prospect Flow gaf status \(code).")
                }
            }
        }
    }

    // MARK: - Stored reference

    private static func refKey(_ taskId: String) -> String { "prospectFlowOffer-\(taskId)" }

    static func offerRef(for taskId: String) -> OfferRef? {
        guard let data = UserDefaults.standard.data(forKey: refKey(taskId)) else { return nil }
        return try? JSONDecoder().decode(OfferRef.self, from: data)
    }

    static func setOfferRef(_ ref: OfferRef?, for taskId: String) {
        if let ref, let data = try? JSONEncoder().encode(ref) {
            UserDefaults.standard.set(data, forKey: refKey(taskId))
        } else {
            UserDefaults.standard.removeObject(forKey: refKey(taskId))
        }
    }

    func openURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), let base = URL(string: baseURL), let host = base.host,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)),
              let url = URL(string: baseURL + path), url.scheme == base.scheme, url.host == host, url.port == base.port,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    // MARK: - Calls

    func match(text: String) async throws -> [Candidate] {
        struct Out: Decodable { let kandidaten: [Candidate] }
        let out: Out = try await send("/api/ai/offers/from-conversation/match", body: ["text": text])
        return out.kandidaten
    }

    func search(_ query: String) async throws -> [Candidate] {
        struct Row: Decodable { let id: Int; let companyName: String?; let contactName: String?; let city: String? }
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "search", value: query), URLQueryItem(name: "limit", value: "20")]
        let rows: [Row] = try await send("/api/customers?" + (comps.percentEncodedQuery ?? ""), body: nil)
        return rows.map {
            let company = ($0.companyName ?? "").trimmingCharacters(in: .whitespaces)
            return Candidate(id: $0.id, naam: company.isEmpty ? ($0.contactName ?? "") : company, plaats: $0.city)
        }
    }

    func createOffer(
        requestId: String, transcript: Transcript, customer: Customer
    ) async throws -> OfferResult {
        var body: [String: Any] = [
            "request_id": requestId,
            "transcript_id": transcript.taskId,
            "title": transcript.title,
            "recorded_at": ISO8601DateFormatter().string(from: transcript.date),
            "notule_html": transcript.notuleHtml ?? "",
            "transcript": transcript.rawTranscription ?? "",
        ]
        switch customer {
        case .existing(let id): body["customer_id"] = id
        case .new(let name): body["new_customer_name"] = name
        }
        let result: OfferResult = try await send("/api/ai/offers/from-conversation", body: body, timeout: 300)
        guard openURL(result.url) != nil else { throw PFError.server(502, String(localized: "Prospect Flow gaf een ongeldige offertelink.")) }
        return result
    }

    // MARK: - HTTP

    private func send<T: Decodable>(_ path: String, body: [String: Any]?, timeout: TimeInterval = 30) async throws -> T {
        guard !apiKey.isEmpty, let url = openURL(path)
        else { throw PFError.missingConfig }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req, delegate: ProspectFlowNoRedirect())
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw PFError.server(code, detail ?? "")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}


/// A redirect must never forward the instance key or conversation to another destination.
private final class ProspectFlowNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
