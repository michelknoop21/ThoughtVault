// CloudAPITranscriber.swift
// ThoughtVault
//
// Opt-in cloud speech-to-text with the user's own API key, against any
// OpenAI-compatible `POST {base}/v1/audio/transcriptions` endpoint (OpenAI,
// Groq, OpenRouter, or a custom base URL). Audio leaves the device only when the user
// selects this engine (DEC-074).

import Foundation

// MARK: - Provider presets

enum CloudSTTProvider: String, CaseIterable, Identifiable, Sendable {
    case openai, groq, openrouter, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .groq:   return "Groq"
        case .openrouter: return "OpenRouter"
        case .custom: return "Eigen adres"
        }
    }

    /// Empty for `.custom`: the user supplies the base URL.
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com"
        case .groq:   return "https://api.groq.com/openai"
        case .openrouter: return "https://openrouter.ai/api"
        case .custom: return ""
        }
    }

    /// Empty for `.custom`: the model is free text.
    var models: [String] {
        switch self {
        case .openai: return ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        case .groq:   return ["whisper-large-v3", "whisper-large-v3-turbo"]
        case .openrouter: return ["openai/gpt-4o-transcribe", "openai/whisper-large-v3"]
        case .custom: return []
        }
    }

    /// OpenAI shares the key used for notules.
    var keychainKey: String {
        switch self {
        case .openai: return "openAIApiKey"
        case .groq:   return "groqApiKey"
        case .openrouter: return "openRouterApiKey"
        case .custom: return "customSttApiKey"
        }
    }

    static let providerDefaultsKey = "cloudSTTProvider"
    static let modelDefaultsKey = "cloudSTTModel"
    static let baseURLDefaultsKey = "cloudSTTBaseURL"
}

// MARK: - Transcriber

struct CloudAPITranscriber: LocalTranscriber {

    let providerName: String
    let baseURL: String
    let model: String
    let apiKey: String
    var session: URLSession = .shared

    /// 10 minutes of 16 kHz mono 16-bit WAV is ~19 MB, under the 25 MB upload limit.
    static let chunkDuration: TimeInterval = 600

    static func fromDefaults() -> CloudAPITranscriber {
        let defaults = UserDefaults.standard
        let provider = CloudSTTProvider(rawValue: defaults.string(forKey: CloudSTTProvider.providerDefaultsKey) ?? "") ?? .openai
        let base = provider == .custom ? (defaults.string(forKey: CloudSTTProvider.baseURLDefaultsKey) ?? "") : provider.baseURL
        let model = defaults.string(forKey: CloudSTTProvider.modelDefaultsKey).flatMap { $0.isEmpty ? nil : $0 }
            ?? provider.models.first ?? ""
        return CloudAPITranscriber(providerName: provider.displayName, baseURL: base, model: model,
                                   apiKey: KeychainService.shared.load(for: provider.keychainKey) ?? "")
    }

    /// Accepts a base with or without a trailing `/v1`.
    var endpoint: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/v1") { base.removeLast(3) }
        return URL(string: base + "/v1/audio/transcriptions")
    }

    func transcribe(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> String {
        try await transcribeTimed(url: url, profileId: profileId, onProgress: onProgress).text
    }

    /// `verbose_json` carries segment times, but not every model accepts it: OpenAI's gpt-4o
    /// transcription models refuse it with a 400. Whisper models accept it at OpenAI, Groq and OpenRouter.
    // ponytail: model-name check; a per-model list once a custom endpoint needs otherwise.
    var wantsSegments: Bool { model.lowercased().contains("whisper") }

    func transcribeTimed(url: URL, profileId: String?, onProgress: @Sendable @escaping (Double) -> Void) async throws -> TimedTranscript {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LocalTranscriberError.cloudFailed("Geen API-sleutel ingesteld voor \(providerName).")
        }
        guard endpoint != nil, !model.isEmpty else {
            throw LocalTranscriberError.cloudFailed("Adres of model ontbreekt in de instellingen.")
        }
        onProgress(0.02)

        let chunks = try await AudioChunker.chunk(url: url, chunkDuration: Self.chunkDuration)
        defer { chunks.forEach { try? FileManager.default.removeItem(at: $0) } }
        onProgress(0.05)

        // No vocabulary prompt, as with local Whisper: names are corrected afterwards in LLMService.
        var parts: [TimedTranscript] = []
        for (index, chunkURL) in chunks.enumerated() {
            parts.append(try await upload(audio: try Data(contentsOf: chunkURL), prompt: nil))
            onProgress(0.05 + 0.95 * Double(index + 1) / Double(chunks.count))
        }

        let text = parts.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalTranscriberError.emptyResult }
        return TimedTranscript(text: text, pieces: TimedPiece.offset(parts.map(\.pieces), chunkDuration: Self.chunkDuration))
    }

    /// Uploads one WAV chunk and returns its `text`, with segment times when the model gives them.
    func upload(audio: Data, prompt: String?) async throws -> TimedTranscript {
        guard let endpoint else { throw LocalTranscriberError.cloudFailed("Ongeldig adres: \(baseURL)") }
        let boundary = "ThoughtVault-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields = [("model", model), ("language", "nl"), ("response_format", wantsSegments ? "verbose_json" : "json")]
        if let prompt { fields.append(("prompt", prompt)) }
        let body = Self.multipartBody(boundary: boundary, fields: fields, audio: audio)

        let (data, response) = try await session.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw LocalTranscriberError.cloudFailed(Self.errorMessage(status: status, body: data, provider: providerName))
        }
        struct Reply: Decodable { let text: String; let segments: [TimedPiece]? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw LocalTranscriberError.cloudFailed("Onverwacht antwoord van \(providerName).")
        }
        return TimedTranscript(text: reply.text, pieces: reply.segments ?? [])
    }

    static func multipartBody(boundary: String, fields: [(String, String)], audio: Data) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func errorMessage(status: Int, body: Data, provider: String) -> String {
        if status == 401 { return "API-sleutel ongeldig voor \(provider)." }
        struct Envelope: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: body))?.error.message
            ?? String(data: body.prefix(300), encoding: .utf8) ?? ""
        return "\(provider) gaf fout \(status): \(detail)"
    }
}
