// TranscriptRecord.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// SwiftData model for transcripts/notulen that are processed and stored locally,
// so the history works fully offline without the backend server.

import Foundation
import SwiftData

// MARK: - TranscriptRecord

@Model
final class TranscriptRecord {

    /// Stable local identifier (also used as the task id for locally processed items).
    @Attribute(.unique) var id: String
    var taskId: String
    var title: String
    var filename: String
    var rawTranscription: String
    var notuleHtml: String
    var profileId: String
    var profileName: String?
    var tags: [String]
    var createdAt: Date
    var localAudioPath: String?
    /// "local" for on-device processed records, "cloud" for server-synced records.
    var source: String
    /// JSON-encoded [Participant] captured at record time, so local notule
    /// regeneration (other profile) can re-inject the deelnemerslijst. Optional →
    /// lightweight-migration safe for existing stores.
    var participantsJSON: String?
    var minutesStyleJSON: String?

    init(
        id: String = UUID().uuidString,
        taskId: String = "",
        title: String,
        filename: String = "",
        rawTranscription: String = "",
        notuleHtml: String = "",
        profileId: String = "",
        profileName: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        localAudioPath: String? = nil,
        source: String = "local",
        participantsJSON: String? = nil
    ) {
        self.id = id
        self.taskId = taskId.isEmpty ? id : taskId
        self.title = title
        self.filename = filename
        self.rawTranscription = rawTranscription
        self.notuleHtml = notuleHtml
        self.profileId = profileId
        self.profileName = profileName
        self.tags = tags
        self.createdAt = createdAt
        self.localAudioPath = localAudioPath
        self.source = source
        self.participantsJSON = participantsJSON
    }

    /// Typed accessor over participantsJSON.
    var participants: [Participant] {
        get {
            guard let data = participantsJSON?.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([Participant].self, from: data)) ?? []
        }
        set {
            participantsJSON = newValue.isEmpty
                ? nil
                : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    /// Maps this record to the `Transcript` value type used throughout the UI.
    var asTranscript: Transcript {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Transcript(
            id: id,
            taskId: taskId,
            title: title,
            date: createdAt,
            rawTranscription: rawTranscription.isEmpty ? nil : rawTranscription,
            notuleHtml: notuleHtml.isEmpty ? nil : notuleHtml,
            tags: tags,
            createdAt: formatter.string(from: createdAt),
            duration: nil,
            profileName: profileName
        )
    }
}
