import Foundation
import CryptoKit
import SwiftData

/// Only portable content crosses devices; audio paths, credentials and the people directory stay local.
struct SyncedNotule: Codable, Equatable, Sendable {
    var id: String
    var taskId: String
    var title: String
    var filename: String
    var rawTranscription: String
    var notuleHtml: String
    var profileId: String
    var profileName: String?
    var tags: [String]
    var createdAt: Date
    var source: String
    var participantsJSON: String?
    var notuleDraftHtml: String?
    var notuleReviewReason: String?
    var durationSeconds: Double?
    var notuleUsageJSON: String?
    var mergeSourcesJSON: String?

    @MainActor init(_ record: TranscriptRecord) {
        id = record.id
        taskId = record.taskId
        title = record.title
        filename = record.filename
        rawTranscription = record.rawTranscription
        notuleHtml = record.notuleHtml
        profileId = record.profileId
        profileName = record.profileName
        tags = record.tags
        createdAt = record.createdAt
        source = record.source
        participantsJSON = record.participantsJSON
        notuleDraftHtml = record.notuleDraftHtml
        notuleReviewReason = record.notuleReviewReason
        durationSeconds = record.durationSeconds
        notuleUsageJSON = record.notuleUsageJSON
        mergeSourcesJSON = record.mergeSourcesJSON
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    func digest() throws -> String {
        SHA256.hash(data: try encoded()).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor func apply(to record: TranscriptRecord) {
        record.taskId = taskId
        record.title = title
        record.filename = filename
        record.rawTranscription = rawTranscription
        record.notuleHtml = notuleHtml
        record.profileId = profileId
        record.profileName = profileName
        record.tags = tags
        record.createdAt = createdAt
        record.source = source
        record.participantsJSON = participantsJSON
        record.notuleDraftHtml = notuleDraftHtml
        record.notuleReviewReason = notuleReviewReason
        record.durationSeconds = durationSeconds
        record.notuleUsageJSON = notuleUsageJSON
        record.mergeSourcesJSON = mergeSourcesJSON
    }

    func conflictCopy() throws -> Self {
        var copy = self
        copy.id = "conflict-" + (try digest())
        copy.taskId = copy.id
        copy.title += " (bewerkingsconflict)"
        return copy
    }
}

/// This journal is independent of the existing SwiftData schema. Missing/corrupt state is never
/// treated as an empty cloud: unreadable journals stop sync, keeping the local database untouched.
struct NotuleSyncState: Codable {
    struct Entry: Codable {
        var digest: String?
        var serverDigest: String?
        var uploadDigest: String?
        var systemFields: Data?
        var pending = false

        func keepsLocalChange(against incomingDigest: String) -> Bool {
            pending && digest != incomingDigest && (serverDigest == incomingDigest || uploadDigest == incomingDigest)
        }
    }
    var zoneWasRemoved: Bool?
    var accountID: String?
    var engineState: Data?
    var entries: [String: Entry] = [:]

    mutating func bindAccount(_ id: String) throws {
        guard accountID == nil || accountID == id else { throw NotuleSyncError.accountChanged }
        accountID = id
    }

    mutating func reconcile(_ records: [SyncedNotule]) throws {
        var present = Set<String>()
        for record in records {
            guard present.insert(record.id).inserted else { throw NotuleSyncError.invalidData }
            let digest = try record.digest()
            if entries[record.id]?.digest != digest {
                var entry = entries[record.id] ?? Entry()
                entry.digest = digest
                entry.pending = true
                entries[record.id] = entry
            }
        }
        for id in Array(entries.keys) where !present.contains(id) && entries[id]?.digest != nil {
            entries[id]?.digest = nil
            entries[id]?.pending = true
        }
    }

    mutating func acknowledged(id: String, digest: String?, fields: Data?) {
        guard var entry = entries[id] else { return }
        entry.systemFields = fields
        entry.serverDigest = digest
        if entry.uploadDigest == digest { entry.uploadDigest = nil }
        // An edit made while the upload was in flight must remain queued.
        entry.pending = entry.digest != digest
        entries[id] = entry
    }

    static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum NotuleSyncError: LocalizedError {
    case accountChanged, noAccount, invalidData, localRecovery, zoneRemoved
    var errorDescription: String? {
        switch self {
        case .accountChanged: return String(localized: "Meld je aan met het oorspronkelijke iCloud-account. Je notulen worden niet naar een ander account verstuurd.")
        case .noAccount: return String(localized: "Meld je aan bij iCloud om je notulen te synchroniseren.")
        case .invalidData: return String(localized: "De synchronisatiegegevens konden niet veilig worden gelezen. Je lokale notulen blijven bewaard.")
        case .localRecovery: return String(localized: "De lokale opslag moet eerst worden hersteld. iCloud-synchronisatie is gepauzeerd om je notulen te beschermen.")
        case .zoneRemoved: return String(localized: "De notulenopslag is uit iCloud verwijderd. Synchronisatie is gepauzeerd; je lokale notulen blijven bewaard.")
        }
    }
}
