// Models.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Core data models for the ThoughtVault app.

import Foundation
import OSLog
import SwiftUI

// MARK: - DateParsing

/// Parse date strings from the backend which may come in various ISO8601 formats.
/// Python's datetime.isoformat() on naive datetimes produces "yyyy-MM-ddTHH:mm:ss.ffffff"
/// without timezone suffix, which ISO8601DateFormatter cannot parse.
enum DateParsing {
    nonisolated(unsafe) private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    nonisolated(unsafe) private static let noTzFrac: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    nonisolated(unsafe) private static let noTz: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    nonisolated(unsafe) private static let spaceSeparated: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ string: String) -> Date? {
        isoFrac.date(from: string)
            ?? iso.date(from: string)
            ?? noTzFrac.date(from: string)
            ?? noTz.date(from: string)
            ?? spaceSeparated.date(from: string)
    }
}

// MARK: - TaskStatus

enum TaskStatus: String, Codable, Sendable {
    case pending
    case uploading
    case downloading
    case converting
    case transcribing
    case transcribed
    case queued
    case processingWebhook = "processing_webhook"
    case generatingLocal = "generating_local"
    case completed
    case error

    /// True for all active/in-progress states, false only for terminal states.
    var isActive: Bool {
        switch self {
        case .completed, .error: return false
        default: return true
        }
    }

    /// Normalized progress value from 0.0 to 1.0.
    var progress: Double {
        switch self {
        case .pending:           return 0.0
        case .uploading:         return 0.15
        case .downloading:       return 0.10
        case .converting:        return 0.25
        case .transcribing:      return 0.45
        case .transcribed:       return 0.60
        case .queued:            return 0.65
        case .processingWebhook: return 0.85
        case .generatingLocal:   return 0.90
        case .completed:         return 1.0
        case .error:             return 0.0
        }
    }

    /// Dutch display name for use in the UI.
    var displayName: String {
        switch self {
        case .pending:           return "Wachten"
        case .uploading:         return "Uploaden"
        case .downloading:       return "Downloaden..."
        case .converting:        return "Converteren"
        case .transcribing:      return "Transcriberen"
        case .transcribed:       return "Getranscribeerd"
        case .queued:            return "In wachtrij"
        case .processingWebhook: return "Verwerken"
        case .generatingLocal:   return "Lokaal genereren"
        case .completed:         return "Voltooid"
        case .error:             return "Fout"
        }
    }
}

// MARK: - ProcessingMode

/// Where transcription + notule generation happens. `local` runs fully on-device
/// (no backend server required); `cloud` uses the FastAPI backend + n8n.
enum ProcessingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case local
    case cloud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Lokaal (geen server)"
        case .cloud: return "Cloud (server)"
        }
    }

    /// App-wide source of truth for local mode, readable from any layer
    /// (views, view models, APIService) via the shared `processingMode` default.
    static var isLocalMode: Bool {
        (ProcessingMode(rawValue: UserDefaults.standard.string(forKey: "processingMode") ?? local.rawValue) ?? .local) == .local
    }
}

// MARK: - NotulenProvider

enum NotulenProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case cloud          // N8N + Claude (server-side)
    case ollama         // Local Ollama instance
    case lmStudio       // Local LM Studio instance
    case appleIntelligence  // Apple Intelligence (macOS 26+ / iOS 26+)

    var id: String { rawValue }

    /// Dutch display name.
    var displayName: String {
        switch self {
        case .cloud:             return "Cloud (N8N + Claude)"
        case .ollama:            return "Ollama (lokaal)"
        case .lmStudio:          return "LM Studio (lokaal)"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    /// Default local-mode provider for the current platform.
    /// macOS can run Ollama locally, so it stays the default there. iOS/iPadOS cannot run
    /// Ollama on-device, so it prefers on-device Apple Intelligence when available and
    /// otherwise falls back to Ollama (which must then point at a remote server URL).
    static var platformDefault: NotulenProvider {
        #if os(iOS)
        #if canImport(FoundationModels)
        if #available(iOS 26, *), AppleFoundationModelService.unavailabilityReason == nil {
            return .appleIntelligence
        }
        #endif
        return .ollama
        #else
        return .ollama
        #endif
    }
}

// MARK: - RecordingMode

enum RecordingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case microphone
    case systemAudio
    case combined

    var id: String { rawValue }

    /// Only microphone recording is available on iOS; system audio requires macOS.
    var availableOnIOS: Bool {
        switch self {
        case .microphone: return true
        case .systemAudio, .combined: return false
        }
    }

    /// Dutch display name.
    var displayName: String {
        switch self {
        case .microphone:  return "Microfoon"
        case .systemAudio: return "Systeemgeluid"
        case .combined:    return "Gecombineerd"
        }
    }

    /// SF Symbol name for the mode.
    var iconName: String {
        switch self {
        case .microphone:  return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .combined:    return "waveform"
        }
    }
}

// MARK: - RecordingState

enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
    case uploading
    case error(String)

    /// True only for actively recording or paused states.
    var isRecording: Bool {
        switch self {
        case .recording, .paused: return true
        default: return false
        }
    }
}

// MARK: - Profile

// ⚠️ COLLISION WARNING: Do NOT rename or reuse `Profile` for person-identity concepts.
// `PersonProfile` (@Model, PersonProfile.swift) is the new type for people/self-profile.
// `Profile` here is the notule-style template (zakelijk, informeel, etc.) — keep separate.
struct Profile: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var icon: String?
    var systemPrompt: String?
    var notulePrompt: String?
    var template: String?
    var isDefault: Bool?

    // MARK: Default profiles

    static let zakelijk = Profile(
        id: "zakelijk",
        name: "Zakelijk",
        description: "Zakelijke vergadernotulen",
        icon: "briefcase.fill",
        systemPrompt: "Je bent een professionele notulist die zakelijke vergaderingen nauwkeurig en beknopt samenvat.",
        notulePrompt: "Maak professionele notulen van deze vergadering. Includeer: aanwezigen (indien vermeld), agendapunten, besluiten, actiepunten met eigenaar en deadline, en een korte samenvatting.",
        template: nil,
        isDefault: true
    )

    static let informeel = Profile(
        id: "informeel",
        name: "Informeel",
        description: "Informele gesprekssamenvattingen",
        icon: "bubble.left.and.bubble.right.fill",
        systemPrompt: "Je bent een vriendelijke assistent die gesprekken in begrijpelijke taal samenvat.",
        notulePrompt: "Vat dit gesprek samen in een informele, leesbare stijl. Benoem de belangrijkste onderwerpen en afspraken die zijn gemaakt.",
        template: nil,
        isDefault: true
    )

    static let technisch = Profile(
        id: "technisch",
        name: "Technisch",
        description: "Technische vergadernotulen",
        icon: "wrench.and.screwdriver.fill",
        systemPrompt: "Je bent een technische notulist gespecialiseerd in software ontwikkeling en IT-projecten.",
        notulePrompt: "Maak technische notulen van dit overleg. Focus op: architectuurbesluiten, technische afspraken, bugs/issues besproken, sprint-items, en actiepunten voor het team.",
        template: nil,
        isDefault: true
    )

    static let handleiding = Profile(
        id: "handleiding",
        name: "Handleiding",
        description: "Eindgebruikershandleiding op basis van ingesproken schermopnames",
        icon: "book.fill",
        systemPrompt: "Je bent een technisch schrijver die ingesproken walkthroughs omzet naar stapsgewijze eindgebruikershandleidingen.",
        notulePrompt: "Analyseer deze ingesproken walkthrough en maak er een gestructureerde handleiding van. Benoem schermen, knoppen, menu's en velden. Structureer per functionaliteit met genummerde stappen.",
        template: nil,
        isDefault: true
    )

    static let blogSamenvatting = Profile(
        id: "blog_samenvatting",
        name: "Blog Samenvatting",
        description: "Blogklare samenvatting van een ingesproken verhaal",
        icon: "doc.richtext.fill",
        systemPrompt: "Je bent een contentschrijver die audio omzet naar een blogklare samenvatting.",
        notulePrompt: "Maak een blogklare samenvatting van deze opname met een pakkende titel, kernboodschap en heldere alinea's.",
        template: nil,
        isDefault: true
    )

    static let notitie = Profile(
        id: "notitie",
        name: "Notitie",
        description: "Korte gedachten en ideeën → Obsidian-notitie",
        icon: "note.text",
        systemPrompt: "Je bent een assistent die gesproken notities opschont tot leesbare tekst. Behoud de toon en inhoud, verwijder alleen vulwoorden en herhalingen. Maak géén samenvatting, structuur of notulen — gewoon schone, leesbare tekst.",
        notulePrompt: "Schonk deze gesproken tekst op tot een leesbare notitie. Behoud de originele betekenis, toon en alle details. Verwijder alleen vulwoorden (uh, eh, nou), herhalingen en aarzelingen. Maak géén samenvatting, géén structuur, géén notulen — gewoon schone tekst die direct in Obsidian kan worden opgeslagen.",
        template: nil,
        isDefault: true
    )

    /// Built-in profiles, enriched with the rich prompts + HTML templates from
    /// ProfileTemplates.json (falling back to the inline prompts when unavailable).
    static var defaults: [Profile] {
        let base: [Profile] = [.zakelijk, .informeel, .technisch, .handleiding, .blogSamenvatting, .notitie]
        return base.map { profile in
            guard let entry = ProfileTemplates.entry(for: profile.id) else { return profile }
            var enriched = profile
            enriched.systemPrompt = entry.systemPrompt ?? profile.systemPrompt
            enriched.notulePrompt = entry.notulePrompt ?? profile.notulePrompt
            enriched.template = entry.template ?? profile.template
            if enriched.description == nil { enriched.description = entry.description }
            return enriched
        }
    }
}

// MARK: - TranscriptTask

struct TranscriptTask: Identifiable, Codable, Sendable {
    /// Local client-side UUID (also used as `Identifiable` key).
    var id: String
    /// Server-assigned task identifier (used for SSE streams and status polling).
    var taskId: String
    var filename: String
    var status: TaskStatus
    var rawTranscription: String?
    var notuleHtml: String?
    var errorMessage: String?
    var localAudioPath: String?
    var progress: Double
    var tags: [String]
    var profileId: String?
    var createdAt: Date?
    var username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case filename
        case status
        case rawTranscription = "raw_transcription"
        case notuleHtml = "notule_html"
        case errorMessage = "error_message"
        case localAudioPath = "local_audio_path"
        case progress
        case tags
        case profileId = "profile_id"
        case createdAt = "created_at"
        case username
    }

    init(
        id: String = UUID().uuidString,
        taskId: String = "",
        filename: String = "",
        status: TaskStatus = .pending,
        rawTranscription: String? = nil,
        notuleHtml: String? = nil,
        errorMessage: String? = nil,
        localAudioPath: String? = nil,
        progress: Double = 0.0,
        tags: [String] = [],
        profileId: String? = nil,
        createdAt: Date? = nil,
        username: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.filename = filename
        self.status = status
        self.rawTranscription = rawTranscription
        self.notuleHtml = notuleHtml
        self.errorMessage = errorMessage
        self.localAudioPath = localAudioPath
        self.progress = progress
        self.tags = tags
        self.profileId = profileId
        self.createdAt = createdAt
        self.username = username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedTaskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
        self.id = decodedId.flatMap { $0.isEmpty ? nil : $0 } ?? (decodedTaskId.isEmpty ? UUID().uuidString : decodedTaskId)
        self.taskId = decodedTaskId
        self.filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""

        if let rawStatus = try container.decodeIfPresent(String.self, forKey: .status),
           let parsedStatus = TaskStatus(rawValue: rawStatus) {
            self.status = parsedStatus
        } else {
            self.status = .pending
        }

        self.rawTranscription = try container.decodeIfPresent(String.self, forKey: .rawTranscription)
        self.notuleHtml = try container.decodeIfPresent(String.self, forKey: .notuleHtml)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.localAudioPath = try container.decodeIfPresent(String.self, forKey: .localAudioPath)
        self.progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0.0
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.profileId = try container.decodeIfPresent(String.self, forKey: .profileId)
        self.createdAt = Self.decodeDateLossy(from: container, key: .createdAt)
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
    }

    private static func decodeDateLossy(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        if let rawString = try? container.decodeIfPresent(String.self, forKey: key),
           !rawString.isEmpty {
            if let parsed = DateParsing.parse(rawString) { return parsed }
        }
        if let unix = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: unix)
        }
        return nil
    }
}

// MARK: - Transcript

struct Transcript: Identifiable, Codable, Hashable, Sendable {
    var id: String
    /// Server-assigned task identifier used for all API calls (detail, update, delete).
    var taskId: String
    var title: String
    var date: Date
    var rawTranscription: String?
    var notuleHtml: String?
    var tags: [String]
    var createdAt: String?
    var duration: Double?
    var profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case title
        case date
        case rawTranscription = "raw_transcription"
        case notuleHtml = "notule_html"
        case tags
        case createdAt = "created_at"
        case duration
        case profileName = "profile_name"
        // Backend sometimes returns these alternative field names
        case transcription
        case result
        case filename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode task_id (used for all API calls)
        let decodedTaskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""

        // Flexible ID decoding: accept both String and Int from backend
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = UUID().uuidString
        }

        // Use task_id for API calls; fall back to id if task_id is absent
        taskId = decodedTaskId.isEmpty ? id : decodedTaskId

        // Flexible title: fall back to filename
        let decodedTitle = try? container.decodeIfPresent(String.self, forKey: .title)
        let decodedFilename = try? container.decodeIfPresent(String.self, forKey: .filename)
        title = decodedTitle ?? decodedFilename ?? "Naamloze opname"

        // Flexible date decoding: try `date` field, fall back to `created_at`
        let rawCreatedAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        let dateString = (try? container.decodeIfPresent(String.self, forKey: .date)) ?? rawCreatedAt

        if let ds = dateString {
            if let parsed = DateParsing.parse(ds) {
                date = parsed
            } else {
                os_log("Failed to parse Transcript date: %{public}@", type: .error, ds)
                date = Date()
            }
        } else {
            date = Date()
        }

        // Flexible field names: raw_transcription or transcription
        rawTranscription = (try? container.decodeIfPresent(String.self, forKey: .rawTranscription))
            ?? (try? container.decodeIfPresent(String.self, forKey: .transcription))

        // Flexible field names: notule_html or result
        notuleHtml = (try? container.decodeIfPresent(String.self, forKey: .notuleHtml))
            ?? (try? container.decodeIfPresent(String.self, forKey: .result))

        tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        createdAt = rawCreatedAt
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(title, forKey: .title)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: date), forKey: .date)
        try container.encodeIfPresent(rawTranscription, forKey: .rawTranscription)
        try container.encodeIfPresent(notuleHtml, forKey: .notuleHtml)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(profileName, forKey: .profileName)
    }

    init(
        id: String = UUID().uuidString,
        taskId: String = "",
        title: String,
        date: Date = Date(),
        rawTranscription: String? = nil,
        notuleHtml: String? = nil,
        tags: [String] = [],
        createdAt: String? = nil,
        duration: Double? = nil,
        profileName: String? = nil
    ) {
        self.id = id
        self.taskId = taskId.isEmpty ? id : taskId
        self.title = title
        self.date = date
        self.rawTranscription = rawTranscription
        self.notuleHtml = notuleHtml
        self.tags = tags
        self.createdAt = createdAt
        self.duration = duration
        self.profileName = profileName
    }
}

// MARK: - TranscriptsResponse

struct TranscriptsResponse: Codable, Sendable {
    var items: [Transcript]
}

// MARK: - Authentication models

struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct LoginResponse: Codable, Sendable {
    let token: String?
    let requiresTwoFactor: Bool?
    let tempToken: String?

    enum CodingKeys: String, CodingKey {
        case token
        case requiresTwoFactor = "requires_two_factor"
        case tempToken = "temp_token"
    }
}

struct TwoFactorRequest: Codable, Sendable {
    let tempToken: String
    let code: String

    enum CodingKeys: String, CodingKey {
        case tempToken = "temp_token"
        case code
    }
}

struct TwoFAStatus: Codable, Sendable {
    let enabled: Bool
    let backupCodesRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case enabled
        case backupCodesRemaining = "backup_codes_remaining"
    }
}

struct TwoFASetupResponse: Codable, Sendable {
    let qrCode: String
    let secret: String

    enum CodingKeys: String, CodingKey {
        case qrCode = "qr_code"
        case secret
    }
}

struct TwoFAVerifyResponse: Codable, Sendable {
    let backupCodes: [String]

    enum CodingKeys: String, CodingKey {
        case backupCodes = "backup_codes"
    }
}

// MARK: - QueuedItem

enum QueuedItem: Codable, Sendable {
    case audio(url: URL, retryCount: Int = 0, id: String = UUID().uuidString)
    case text(transcription: String, profileId: String, retryCount: Int = 0, id: String = UUID().uuidString)

    /// Shared retry limit — aligned with Windows MAX_RETRIES = 5.
    static let maxRetries = 5

    var retryCount: Int {
        switch self {
        case .audio(_, let count, _): return count
        case .text(_, _, let count, _): return count
        }
    }

    /// Stable identity that survives encode/decode round-trips and retries.
    var id: String {
        switch self {
        case .audio(_, _, let id): return id
        case .text(_, _, _, let id): return id
        }
    }

    // MARK: Codable

    private enum ItemType: String, Codable {
        case audio, text
    }

    private enum CodingKeys: String, CodingKey {
        case type, url, transcription, profileId, retryCount, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        let retryCount = (try? container.decodeIfPresent(Int.self, forKey: .retryCount)) ?? 0
        // Legacy items without an id gain a stable id from this load onwards
        let id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        switch type {
        case .audio:
            let url = try container.decode(URL.self, forKey: .url)
            self = .audio(url: url, retryCount: retryCount, id: id)
        case .text:
            let transcription = try container.decode(String.self, forKey: .transcription)
            let profileId = try container.decode(String.self, forKey: .profileId)
            self = .text(transcription: transcription, profileId: profileId, retryCount: retryCount, id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(id, forKey: .id)
        switch self {
        case .audio(let url, _, _):
            try container.encode(ItemType.audio, forKey: .type)
            try container.encode(url, forKey: .url)
        case .text(let transcription, let profileId, _, _):
            try container.encode(ItemType.text, forKey: .type)
            try container.encode(transcription, forKey: .transcription)
            try container.encode(profileId, forKey: .profileId)
        }
    }

    /// Returns a copy of this item with retryCount incremented by one.
    /// Preserves the item's id so it keeps the same identity after a retry.
    func incrementingRetryCount() -> QueuedItem {
        switch self {
        case .audio(let url, let count, let id):
            return .audio(url: url, retryCount: count + 1, id: id)
        case .text(let transcription, let profileId, let count, let id):
            return .text(transcription: transcription, profileId: profileId, retryCount: count + 1, id: id)
        }
    }
}

// MARK: - SSEEvent

struct SSEEvent: Sendable {
    let event: String
    let data: String
}

// MARK: - UploadFailureReason

enum UploadFailureReason: Sendable {
    case authExpired
    case serverError(Int)   // HTTP status code
    case fileTooLarge
    case validationError(String)
    case networkError
    case unknown

    /// Whether the user can meaningfully retry this failure.
    var isRetryable: Bool {
        switch self {
        case .fileTooLarge, .validationError: return false
        default: return true
        }
    }

    /// Dutch title for UI display.
    var title: String {
        switch self {
        case .authExpired:        return "Sessie verlopen"
        case .serverError:        return "Serverfout"
        case .fileTooLarge:       return "Bestand te groot"
        case .validationError:    return "Validatiefout"
        case .networkError:       return "Netwerkfout"
        case .unknown:            return "Onbekende fout"
        }
    }

    /// Dutch description for UI display.
    var description: String {
        switch self {
        case .authExpired:
            return "Je sessie is verlopen. Log opnieuw in om te uploaden."
        case .serverError(let code):
            return "De server heeft een fout gemeld (HTTP \(code)). Controleer je internetverbinding en probeer het over een paar minuten opnieuw."
        case .fileTooLarge:
            return "Het audiobestand is te groot (maximaal 500 MB). Maak kortere opnames."
        case .validationError(let message):
            return message
        case .networkError:
            return "Kan geen verbinding maken met de server. Controleer je internetverbinding. De opname is opgeslagen en wordt automatisch opnieuw geprobeerd."
        case .unknown:
            return "Er is een onverwachte fout opgetreden. Controleer je internetverbinding en probeer het opnieuw. Als het probleem aanhoudt, herstart de app."
        }
    }

    /// SF Symbol name for UI display.
    var iconName: String {
        switch self {
        case .authExpired:     return "lock.fill"
        case .serverError:     return "exclamationmark.triangle.fill"
        case .fileTooLarge:    return "doc.fill.badge.plus"
        case .validationError: return "xmark.circle.fill"
        case .networkError:    return "wifi.exclamationmark"
        case .unknown:         return "questionmark.circle.fill"
        }
    }
}

// MARK: - SavedRecording

struct SavedRecording: Identifiable, Sendable {
    let filename: String
    let date: Date
    let fileSize: Int64

    var id: String { filename }

    /// Human-readable file size string (KB or MB).
    var formattedSize: String {
        let mb = Double(fileSize) / 1_048_576
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = Double(fileSize) / 1_024
            return String(format: "%.0f KB", kb)
        }
    }

    /// Dutch-localized date and time string.
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
