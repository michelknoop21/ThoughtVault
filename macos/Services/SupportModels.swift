import Darwin
import Foundation

enum SupportStage: String, Codable, Sendable { case opnemen, transcriberen, notule, crash }
enum SupportCategory: String, Codable, Sendable, CaseIterable {
    case bug = "BUG", featureRequest = "FEATURE_REQUEST", question = "QUESTION"
}

struct SupportReport: Codable, Sendable, Equatable {
    var kind: String
    var category: SupportCategory
    var stage: String
    var shownMessage: String
    var errorText: String
    var fingerprint: String?
    var clickPath: [String]
    var appVersion: String
    var os: String
    var device: String
    var platform: String
    var occurredAt: Date
    var name = ""
    var email = ""
    var log: String?

    static func make(kind: String, category: SupportCategory, stage: String, shown: String,
                     error: String, fingerprint: String?, clickPath: [String]) -> SupportReport {
        func capped(_ text: String, _ limit: Int) -> String {
            String((kind == "auto" ? LogRedact.scrub(text) : text).prefix(limit))
        }
        return SupportReport(kind: kind, category: category, stage: stage,
                             shownMessage: capped(shown, 5_000), errorText: capped(error, 2_000),
                             fingerprint: kind == "auto" ? fingerprint : nil,
                             clickPath: clickPath.suffix(30).map { capped($0, 80) },
                             appVersion: DeviceInfo.appVersion, os: DeviceInfo.os,
                             device: DeviceInfo.device, platform: DeviceInfo.platform, occurredAt: Date())
    }
}

struct ReportResult: Decodable, Sendable, Equatable {
    let ticketId: String
    let ref: String
    let repeated: Bool
    let count: Int
    let logAttached: Bool?
}
enum SendOutcome: Equatable, Sendable { case sent(ReportResult?), queued, failed }

struct SupportTicket: Decodable, Identifiable, Sendable, Equatable {
    struct LastMessage: Decodable, Sendable, Equatable {
        let senderRole: String
        let createdAt: Date
        let excerpt: String
    }
    let id: String
    let ref: String
    let status: String
    let category: String
    let description: String
    let unread: Bool
    let createdAt: Date
    let updatedAt: Date?
    let lastMessage: LastMessage?
}
struct SupportMessage: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let body: String
    let senderRole: String
    let createdAt: Date
}

enum SupportIdentity {
    static let installationKey = "supportInstallationId", secretKey = "supportSecret"
    static let nameKey = "supportName", emailKey = "supportEmail", autoReportKey = "supportAutoReport"

    static func isValidEmail(_ value: String) -> Bool {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.contains(where: { $0.isWhitespace }) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func isComplete(name: String, email: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidEmail(email)
    }
}

enum DeviceInfo {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
    static var os: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(platform) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    static var platform: String {
        #if os(iOS)
        "iOS"
        #else
        "macOS"
        #endif
    }
    static var device: String {
        #if os(iOS)
        var system = utsname()
        guard uname(&system) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #else
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: model)
        #endif
    }
}

enum SupportJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid support date"))
        }
        return decoder
    }
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
