// TranscriptDecoderTests.swift
// ThoughtVaultTests
// nl.prezent.ThoughtVault

import Testing
import Foundation
@testable import ThoughtVault

@Suite("Transcript Decoder Tests")
struct TranscriptDecoderTests {

    // MARK: - Transcript Decoding

    @Test("Decode transcript with string ID")
    func decodeTranscriptWithStringId() throws {
        let json = """
        {
            "id": "abc-123",
            "title": "Testgesprek",
            "date": "2026-03-01T10:00:00.000Z",
            "raw_transcription": "Dit is een testtranscriptie.",
            "notule_html": "<p>Samenvatting</p>",
            "tags": ["vergadering", "test"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let transcript = try decoder.decode(Transcript.self, from: json)

        #expect(transcript.id == "abc-123")
        #expect(transcript.title == "Testgesprek")
        #expect(transcript.rawTranscription == "Dit is een testtranscriptie.")
        #expect(transcript.notuleHtml == "<p>Samenvatting</p>")
        #expect(transcript.tags == ["vergadering", "test"])
    }

    @Test("Decode transcript with integer ID — converts to string")
    func decodeTranscriptWithIntegerId() throws {
        let json = """
        {
            "id": 42,
            "title": "Vergadering 42",
            "date": "2026-02-15T08:30:00Z",
            "tags": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let transcript = try decoder.decode(Transcript.self, from: json)

        #expect(transcript.id == "42")
        #expect(transcript.title == "Vergadering 42")
        #expect(transcript.tags.isEmpty)
    }

    @Test("Decode transcript with fractional-seconds ISO8601 date")
    func decodeTranscriptWithFractionalDate() throws {
        let json = """
        {
            "id": "xyz",
            "title": "Datum test",
            "date": "2026-01-20T14:45:30.123Z",
            "tags": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let transcript = try decoder.decode(Transcript.self, from: json)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: transcript.date)
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 20)
        #expect(components.hour == 14)
    }

    @Test("Decode transcript with missing optional fields")
    func decodeTranscriptWithMissingOptionals() throws {
        let json = """
        {
            "id": "minimal",
            "title": "Minimaal",
            "date": "2026-03-01T00:00:00Z",
            "tags": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let transcript = try decoder.decode(Transcript.self, from: json)

        #expect(transcript.rawTranscription == nil)
        #expect(transcript.notuleHtml == nil)
    }

    @Test("Encode and re-decode transcript roundtrip")
    func encodeDecodeRoundtrip() throws {
        let original = Transcript(
            id: "rt-001",
            title: "Roundtrip test",
            date: Date(timeIntervalSince1970: 1772000000),
            rawTranscription: "Transcriptie tekst",
            notuleHtml: "<h1>Notulen</h1>",
            tags: ["tag1", "tag2"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Transcript.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.rawTranscription == original.rawTranscription)
        #expect(decoded.notuleHtml == original.notuleHtml)
        #expect(decoded.tags == original.tags)
        // Date precision limited to seconds
        #expect(abs(decoded.date.timeIntervalSince(original.date)) < 1.0)
    }

    // MARK: - TranscriptTask Decoding

    @Test("Decode TranscriptTask from API response")
    func decodeTranscriptTaskFromAPI() throws {
        let json = """
        {
            "id": "local-uuid-1",
            "task_id": "server-task-42",
            "filename": "recording_1772000000.wav",
            "status": "completed",
            "raw_transcription": "Hallo wereld",
            "notule_html": "<p>Notulen</p>",
            "error_message": null,
            "local_audio_path": null,
            "progress": 1.0,
            "tags": ["test"],
            "profile_id": "zakelijk"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let task = try decoder.decode(TranscriptTask.self, from: json)

        #expect(task.id == "local-uuid-1")
        #expect(task.taskId == "server-task-42")
        #expect(task.filename == "recording_1772000000.wav")
        #expect(task.status == .completed)
        #expect(task.rawTranscription == "Hallo wereld")
        #expect(task.notuleHtml == "<p>Notulen</p>")
        #expect(task.errorMessage == nil)
        #expect(task.progress == 1.0)
        #expect(task.tags == ["test"])
        #expect(task.profileId == "zakelijk")
    }

    @Test("Decode TranscriptTask with default values")
    func decodeTranscriptTaskWithDefaults() throws {
        let task = TranscriptTask()

        #expect(!task.id.isEmpty)  // UUID auto-generated
        #expect(task.taskId == "")
        #expect(task.filename == "")
        #expect(task.status == .pending)
        #expect(task.progress == 0.0)
        #expect(task.tags.isEmpty)
        #expect(task.profileId == nil)
    }

    // MARK: - TaskStatus

    @Test("TaskStatus isActive is false only for terminal states")
    func taskStatusIsActive() {
        #expect(TaskStatus.pending.isActive == true)
        #expect(TaskStatus.uploading.isActive == true)
        #expect(TaskStatus.converting.isActive == true)
        #expect(TaskStatus.transcribing.isActive == true)
        #expect(TaskStatus.transcribed.isActive == true)
        #expect(TaskStatus.queued.isActive == true)
        #expect(TaskStatus.processingWebhook.isActive == true)
        #expect(TaskStatus.generatingLocal.isActive == true)
        #expect(TaskStatus.completed.isActive == false)
        #expect(TaskStatus.error.isActive == false)
    }

    @Test("TaskStatus progress values are ordered")
    func taskStatusProgressOrdering() {
        let orderedStatuses: [TaskStatus] = [
            .pending, .uploading, .converting, .transcribing,
            .transcribed, .queued, .processingWebhook, .generatingLocal, .completed
        ]
        for i in 0..<(orderedStatuses.count - 1) {
            #expect(orderedStatuses[i].progress <= orderedStatuses[i + 1].progress)
        }
        #expect(TaskStatus.completed.progress == 1.0)
        #expect(TaskStatus.error.progress == 0.0)
    }

    // MARK: - Profile Decoding

    @Test("Decode Profile from snake_case API response")
    func decodeProfileFromAPI() throws {
        let json = """
        {
            "id": "zakelijk",
            "name": "Zakelijk",
            "system_prompt": "Je bent een professionele notulist.",
            "notule_prompt": "Maak professionele notulen.",
            "template": null,
            "is_default": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let profile = try decoder.decode(Profile.self, from: json)

        #expect(profile.id == "zakelijk")
        #expect(profile.name == "Zakelijk")
        #expect(profile.systemPrompt == "Je bent een professionele notulist.")
        #expect(profile.notulePrompt == "Maak professionele notulen.")
        #expect(profile.template == nil)
        #expect(profile.isDefault == true)
    }

    @Test("Default profiles exist and are valid")
    func defaultProfilesAreValid() {
        let defaults = Profile.defaults
        #expect(defaults.count == 3)

        let ids = defaults.map(\.id)
        #expect(ids.contains("zakelijk"))
        #expect(ids.contains("informeel"))
        #expect(ids.contains("technisch"))

        for profile in defaults {
            #expect(!profile.name.isEmpty)
            #expect(!profile.systemPrompt.isEmpty)
            #expect(!profile.notulePrompt.isEmpty)
            #expect(profile.isDefault == true)
        }
    }

    // MARK: - TranscriptsResponse Decoding

    @Test("Decode TranscriptsResponse with items key mapping")
    func decodeTranscriptsResponse() throws {
        let json = """
        {
            "transcripts": [
                {
                    "id": "1",
                    "title": "Test",
                    "date": "2026-03-01T10:00:00Z",
                    "tags": []
                }
            ],
            "total": 1,
            "page": 1,
            "limit": 20
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(TranscriptsResponse.self, from: json)

        #expect(response.items.count == 1)
        #expect(response.total == 1)
        #expect(response.page == 1)
        #expect(response.limit == 20)
        #expect(response.items[0].title == "Test")
    }
}
