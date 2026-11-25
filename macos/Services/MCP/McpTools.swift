#if os(macOS)
import Foundation
import CryptoKit

enum McpToolError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

/// Tool handlers of the local MCP server. Each one goes through the same store and view model
/// functions the screens use, so sync, auto labels and task history behave as for a manual edit.
@MainActor
struct McpTools {
    let recordingVM: RecordingViewModel?
    var store: LocalTranscriptStore { .shared }
    var library: LibraryOrganization { .shared }

    func call(_ name: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "list_notes": return try listNotes(args)
        case "get_note": return try getNote(args)
        case "list_library": return ["entries": library.entries.filter { !$0.deleted }.map(Self.entry)]
        case "list_profiles": return ["profiles": profiles().map { profileSummary($0) }]
        case "get_profile": return try getProfile(args)
        case "list_people": return listPeople(args)
        case "list_recordings": return listRecordings()
        case "get_glossary": return try ["entries": PersonalCorrections.load().map(Self.glossaryEntry)]
        case "get_processing_status": return processingStatus()
        case "create_note": return try createNote(args)
        case "update_note": return try updateNote(args)
        case "save_library_entry": return try saveLibraryEntry(args)
        case "save_person": return try savePerson(args)
        case "add_glossary_term": return try addGlossaryTerm(args)
        case "regenerate_notule": return try regenerateNotule(args)
        case "transcribe_recording": return try transcribeRecording(args)
        default: throw McpToolError.message("Onbekende tool \(name).")
        }
    }

    // MARK: - Notes

    private func listNotes(_ args: [String: Any]) throws -> [String: Any] {
        let query = args["query"] as? String ?? ""
        let from = try (args["from"] as? String).map { try Self.date($0, endOfDay: false) }
        let to = try (args["to"] as? String).map { try Self.date($0, endOfDay: true) }
        let folder = args["folder_id"] as? String
        let profile = args["profile_id"] as? String
        let matching = store.allRecords().filter { record in
            (from.map { record.createdAt >= $0 } ?? true)
                && (to.map { record.createdAt <= $0 } ?? true)
                && (profile.map { record.profileId == $0 } ?? true)
                && (folder.map { library.matches($0, folderID: record.organization.folderID, tags: record.tags) } ?? true)
                && TranscriptSearch.matches(query, title: record.title, transcript: record.rawTranscription,
                                            notuleHtml: record.notuleHtml, tags: record.tags)
        }
        let offset = args["offset"] as? Int ?? 0
        let limit = args["limit"] as? Int ?? 25
        return ["total": matching.count, "offset": offset,
                "notes": matching.dropFirst(offset).prefix(limit).map(Self.summary)]
    }

    private func getNote(_ args: [String: Any]) throws -> [String: Any] {
        let record = try note(args["id"])
        var result = Self.summary(record)
        result["revision"] = Self.revision(record)
        result["participants"] = record.participants.map { ["name": $0.name, "role": $0.role, "organization": $0.organization] }
        result["notule"] = args["format"] as? String == "html" ? record.notuleHtml : htmlToMarkdown(record.notuleHtml)
        if args["include_transcript"] as? Bool ?? true {
            // UTF-16 code units, like Windows; a chunk never ends inside a surrogate pair.
            let units = Array(record.rawTranscription.utf16)
            let offset = min(args["transcript_offset"] as? Int ?? 0, units.count)
            var end = min(offset + (args["max_chars"] as? Int ?? 40_000), units.count)
            if end < units.count, end > offset, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            result["transcript"] = ["text": String(decoding: units[offset..<end], as: UTF16.self), "offset": offset,
                                    "total_chars": units.count, "next_offset": end < units.count ? end as Any : NSNull()]
        }
        return result
    }

    private func createNote(_ args: [String: Any]) throws -> [String: Any] {
        let folder = args["folder_id"] as? String
        if let folder { try requireFolder(folder) }
        let record = TranscriptRecord(title: args["title"] as? String ?? "",
                                      rawTranscription: args["transcript"] as? String ?? "",
                                      notuleHtml: (args["notule_markdown"] as? String).map(markdownToNotuleHTML) ?? "",
                                      tags: args["tags"] as? [String] ?? [])
        if let folder { var organization = record.organization; organization.folderID = folder; record.organization = organization }
        try store.save(record)
        return ["id": record.taskId, "revision": Self.revision(record)]
    }

    private func updateNote(_ args: [String: Any]) throws -> [String: Any] {
        let record = try note(args["id"])
        guard args["revision"] as? String == Self.revision(record) else {
            throw McpToolError.message("Notitie is intussen gewijzigd. Lees hem opnieuw met get_note.")
        }
        let id = record.taskId
        if let folder = args["folder_id"] as? String { try requireFolder(folder) }
        if let title = args["title"] as? String { try store.updateTitle(taskId: id, title: title) }
        if let tags = args["tags"] as? [String] { try store.updateTags(taskId: id, tags: tags) }
        if let folder = args["folder_id"] { try store.move(taskIDs: [id], to: folder as? String) }
        if let markdown = args["notule_markdown"] as? String { try store.updateNotule(taskId: id, html: markdownToNotuleHTML(markdown)) }
        return ["id": id, "revision": Self.revision(try note(id))]
    }

    private func requireFolder(_ id: String) throws {
        guard library.folders.contains(where: { $0.id == id }) else {
            throw McpToolError.message("Map niet gevonden. Gebruik een folder-id uit list_library.")
        }
    }

    private func note(_ id: Any?) throws -> TranscriptRecord {
        guard let id = id as? String, let record = store.record(forTaskId: id) else {
            throw McpToolError.message("Notitie niet gevonden. Gebruik een id uit list_notes.")
        }
        return record
    }

    // MARK: - Library, profiles, people, glossary

    private func saveLibraryEntry(_ args: [String: Any]) throws -> [String: Any] {
        let kind = args["kind"] as? String ?? "folder"
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = LibraryEntry(name: name, kind: kind)
        if let id = args["id"] as? String {
            guard let existing = library.entries.first(where: { $0.id == id && !$0.deleted && $0.kind == kind }) else {
                throw McpToolError.message("Map of label niet gevonden.")
            }
            entry = existing
            entry.name = name
        }
        if let description = args["description"] as? String { entry.description = description }
        try library.save(entry)
        // A new label gets its id from its name while saving; label names are unique.
        if kind == "label", args["id"] == nil {
            return ["id": library.labels.first { $0.name == name }?.id ?? entry.id]
        }
        return ["id": entry.id]
    }

    private func profiles() -> [Profile] {
        let loaded = recordingVM?.availableProfiles ?? []
        return loaded.isEmpty ? LocalProfileStore.choices() : loaded
    }

    private func profile(_ id: String) throws -> Profile {
        guard let profile = profiles().first(where: { $0.id == id }) else {
            throw McpToolError.message("Profiel niet gevonden. Gebruik een id uit list_profiles.")
        }
        return profile
    }

    private func profileSummary(_ profile: Profile) -> [String: Any] {
        ["id": profile.id, "name": profile.name, "description": profile.description ?? NSNull(),
         "detail_level": profile.detailLevel ?? NSNull(), "is_default": profile.isDefault ?? false,
         "builtin": Profile.defaults.contains { $0.id == profile.id }]
    }

    private func getProfile(_ args: [String: Any]) throws -> [String: Any] {
        let profile = try profile(args["id"] as? String ?? "")
        return profileSummary(profile).merging(["system_prompt": profile.systemPrompt ?? NSNull(),
                                                 "notule_prompt": profile.notulePrompt ?? NSNull(),
                                                 "output_template": profile.template ?? NSNull()]) { _, new in new }
    }

    private func listPeople(_ args: [String: Any]) -> [String: Any] {
        let query = (args["query"] as? String ?? "").lowercased()
        let people = PersonDirectoryService.shared.directoryPeople().filter { person in
            query.isEmpty || ([person.name, person.organization] + person.aliases + person.emails)
                .contains { $0.lowercased().contains(query) }
        }
        return ["people": people.map(Self.person)]
    }

    private func savePerson(_ args: [String: Any]) throws -> [String: Any] {
        let service = PersonDirectoryService.shared
        guard let id = args["id"] as? String else {
            let person = PersonProfile(name: args["name"] as? String ?? "", role: args["role"] as? String ?? "",
                                       organization: args["organization"] as? String ?? "",
                                       aliases: args["aliases"] as? [String] ?? [], emails: args["emails"] as? [String] ?? [])
            try service.add(person)
            return ["id": person.id]
        }
        guard let person = service.directoryPeople().first(where: { $0.id == id }) else {
            throw McpToolError.message("Persoon niet gevonden. Gebruik een id uit list_people.")
        }
        try service.update(person, source: "mcp") { person in
            if let value = args["name"] as? String { person.name = value }
            if let value = args["role"] as? String { person.role = value }
            if let value = args["organization"] as? String { person.organization = value }
            if let value = args["aliases"] as? [String] { person.aliases = value }
            if let value = args["emails"] as? [String] { person.emails = value }
        }
        return ["id": id]
    }

    private func addGlossaryTerm(_ args: [String: Any]) throws -> [String: Any] {
        var entries = try PersonalCorrections.load()
        let entry = PersonalCorrection(canonical: args["canonical"] as? String ?? "",
                                       variants: args["variants"] as? [String] ?? [], note: args["note"] as? String)
        entries.append(entry)
        try PersonalCorrections.save(entries)
        return ["id": entry.id]
    }

    // MARK: - Recordings and processing

    private func listRecordings() -> [String: Any] {
        let linked = Dictionary(store.allRecords().compactMap { record in
            record.localAudioPath.map { (URL(fileURLWithPath: $0).lastPathComponent, record) }
        }) { first, _ in first }
        let recordings = AudioRecorder.primaryRecordingURLs(from: AudioRecorder.savedRecordingURLs()).compactMap { url -> [String: Any]? in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
            let record = linked[url.lastPathComponent]
            return ["filename": url.lastPathComponent, "size_bytes": attributes[.size] as? Int64 ?? 0,
                    "created_at": Self.iso((attributes[.creationDate] as? Date) ?? Date()),
                    "duration_seconds": record?.durationSeconds ?? NSNull(), "note_id": record?.taskId ?? NSNull()]
        }
        return ["recordings": recordings]
    }

    private func processingStatus() -> [String: Any] {
        let active = (recordingVM?.activeTasks ?? []).map { task -> [String: Any] in
            ["id": task.id, "title": task.filename, "status": task.status.rawValue, "progress": task.progress,
             "error": task.errorMessage ?? NSNull()]
        }
        // Shape shared with Windows: active jobs, then the last 20 finished or failed ones.
        let recent = TaskHistoryStore.shared.entries.prefix(20).map { entry -> [String: Any] in
            ["id": entry.id, "title": entry.title, "status": entry.status.rawValue, "note_id": entry.transcriptId,
             "created_at": Self.iso(entry.createdAt), "finished_at": entry.finishedAt.map(Self.iso) ?? NSNull(),
             "error": entry.errorMessage ?? NSNull()]
        }
        return ["active": active, "recent": Array(recent)]
    }

    private func regenerateNotule(_ args: [String: Any]) throws -> [String: Any] {
        let record = try note(args["id"])
        let vm = try viewModel()
        let id = record.taskId
        let profileId = try profile(args["profile_id"] as? String ?? (record.profileId.isEmpty ? Profile.defaults[0].id : record.profileId)).id
        guard !vm.updateInstalling else { throw McpToolError.message("De app wordt bijgewerkt. Probeer het na de herstart opnieuw.") }
        if vm.activeTasks.contains(where: { $0.id == "local-regen-\(id)" && $0.status != .completed && $0.status != .error }) {
            throw McpToolError.message("De notule wordt al opnieuw gemaakt. Volg het met get_processing_status.")
        }
        // Failures land in the task list, which get_processing_status reports.
        Task { _ = try? await vm.regenerateNotuleLocally(taskId: id, profileId: profileId) }
        return ["started": true, "id": id, "profile_id": profileId]
    }

    private func transcribeRecording(_ args: [String: Any]) throws -> [String: Any] {
        let filename = args["filename"] as? String ?? ""
        let url = AudioRecorder.recordingsDirectoryURL().appendingPathComponent(filename)
        // Only plain names from list_recordings: no paths outside the recordings folder.
        guard filename == url.lastPathComponent, !filename.hasPrefix("."),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            throw McpToolError.message("Opname niet gevonden. Gebruik een filename uit list_recordings.")
        }
        let vm = try viewModel()
        guard ProcessingMode.isLocalMode else {
            throw McpToolError.message("Transcriberen via de AI-koppeling werkt alleen met lokale verwerking.")
        }
        // processLocally resets the recording screen, which would orphan a running recording.
        guard vm.recordingState != .recording, vm.recordingState != .paused else {
            throw McpToolError.message("Er loopt een opname. Probeer het na het stoppen opnieuw.")
        }
        guard !vm.updateInstalling else { throw McpToolError.message("De app wordt bijgewerkt. Probeer het na de herstart opnieuw.") }
        let recording = SavedRecording(filename: filename, date: attributes[.creationDate] as? Date ?? Date(),
                                       fileSize: attributes[.size] as? Int64 ?? 0)
        let profileId = try profile(args["profile_id"] as? String ?? vm.selectedProfile?.id ?? Profile.defaults[0].id).id
        Task { await vm.reprocessRecording(recording, profileId: profileId, useOnDevice: true) }
        return ["started": true, "filename": filename, "profile_id": profileId]
    }

    private func viewModel() throws -> RecordingViewModel {
        guard let recordingVM else { throw McpToolError.message("ThoughtVault is nog aan het opstarten. Probeer het zo opnieuw.") }
        return recordingVM
    }

    // MARK: - Mapping

    static func revision(_ record: TranscriptRecord) -> String {
        let parts: [Any] = [record.title, record.tags, record.organization.folderID ?? "", record.notuleHtml]
        let data = (try? JSONSerialization.data(withJSONObject: parts)) ?? Data()
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func summary(_ record: TranscriptRecord) -> [String: Any] {
        ["id": record.taskId, "title": record.title, "created_at": iso(record.createdAt),
         "duration_seconds": record.durationSeconds ?? NSNull(),
         "profile_id": record.profileId.isEmpty ? NSNull() : record.profileId as Any,
         "profile_name": record.profileName ?? NSNull(), "tags": record.tags,
         "folder_id": record.organization.folderID ?? NSNull(),
         "has_notule": !record.notuleHtml.isEmpty, "has_transcript": !record.rawTranscription.isEmpty]
    }

    static func entry(_ entry: LibraryEntry) -> [String: Any] {
        ["id": entry.id, "name": entry.name, "kind": entry.kind, "label_ids": entry.labelIDs,
         "description": entry.description, "automatic": entry.automatic]
    }

    static func person(_ person: PersonProfile) -> [String: Any] {
        ["id": person.id, "name": person.name, "role": person.role, "organization": person.organization,
         "aliases": person.aliases, "emails": person.emails, "responsibilities": person.responsibilities,
         "is_internal": person.isInternal ?? NSNull()]
    }

    static func glossaryEntry(_ entry: PersonalCorrection) -> [String: Any] {
        ["id": entry.id, "canonical": entry.canonical, "variants": entry.variants,
         "note": entry.note ?? NSNull(), "enabled": entry.enabled]
    }

    static func iso(_ date: Date) -> String { date.formatted(.iso8601) }

    /// A date-only value covers that whole local day.
    static func date(_ text: String, endOfDay: Bool) throws -> Date {
        if let full = try? Date(text, strategy: .iso8601) { return full }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: text) else { throw McpToolError.message("Ongeldige datum: \(text)") }
        return endOfDay ? Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? day : day
    }
}
#endif
