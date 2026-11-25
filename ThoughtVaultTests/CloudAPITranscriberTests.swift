import XCTest
@testable import ThoughtVault

/// Cloud STT request shape and response/error handling, without network:
/// a stub URLProtocol answers in place of the provider.
final class CloudAPITranscriberTests: XCTestCase {

    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lastRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func transcriber(base: String = "https://api.groq.com/openai") -> CloudAPITranscriber {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return CloudAPITranscriber(providerName: "Groq", baseURL: base, model: "whisper-large-v3",
                                   apiKey: "sk-test", session: URLSession(configuration: config))
    }

    func testMultipartBodyHasFieldsAndFile() {
        let body = CloudAPITranscriber.multipartBody(boundary: "B", fields: [("model", "whisper-1"), ("language", "nl")],
                                                     audio: Data("RIFF".utf8))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"))
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\nnl\r\n"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n--B--\r\n"))
    }

    func testEndpointNormalisesBase() {
        XCTAssertEqual(transcriber().endpoint?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(transcriber(base: "https://x.test/v1/").endpoint?.absoluteString, "https://x.test/v1/audio/transcriptions")
        XCTAssertEqual(transcriber(base: CloudSTTProvider.openrouter.baseURL).endpoint?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
    }

    func testUploadReturnsTextAndSendsAuth() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data(#"{"text":"Hallo Michel"}"#.utf8)
        let text = try await transcriber().upload(audio: Data("RIFF".utf8), prompt: "Namen en termen: Michel.").text
        XCTAssertEqual(text, "Hallo Michel")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    func testUnauthorizedGivesDutchKeyError() async {
        StubProtocol.status = 401
        StubProtocol.body = Data(#"{"error":{"message":"Invalid API Key"}}"#.utf8)
        do {
            _ = try await transcriber().upload(audio: Data(), prompt: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Cloud-transcriptie mislukt: API-sleutel ongeldig voor Groq.")
        }
    }

    func testRateLimitWrapsProviderMessage() async {
        StubProtocol.status = 429
        StubProtocol.body = Data(#"{"error":{"message":"Rate limit reached"}}"#.utf8)
        do {
            _ = try await transcriber().upload(audio: Data(), prompt: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Cloud-transcriptie mislukt: Groq gaf fout 429: Rate limit reached")
        }
    }

    func testWhisperModelsAskForSegmentsAndGpt4oModelsDoNot() {
        XCTAssertTrue(transcriber().wantsSegments)
        XCTAssertTrue(CloudAPITranscriber(providerName: "OpenRouter", baseURL: "", model: "openai/whisper-large-v3", apiKey: "k").wantsSegments)
        XCTAssertFalse(CloudAPITranscriber(providerName: "OpenAI", baseURL: "", model: "gpt-4o-transcribe", apiKey: "k").wantsSegments)
    }

    func testVerboseReplyGivesSegmentPieces() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data(#"{"text":"Ja. Doe ik.","language":"dutch","segments":[{"id":0,"seek":0,"start":0.0,"end":1.2,"text":" Ja.","tokens":[1]},{"id":1,"seek":0,"start":1.4,"end":2.6,"text":" Doe ik.","tokens":[2]}]}"#.utf8)
        let reply = try await transcriber().upload(audio: Data("RIFF".utf8), prompt: nil)
        XCTAssertEqual(reply.text, "Ja. Doe ik.")
        XCTAssertEqual(reply.pieces, [TimedPiece(start: 0, end: 1.2, text: " Ja."), TimedPiece(start: 1.4, end: 2.6, text: " Doe ik.")])
    }

    func testPlainReplyGivesNoPieces() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data(#"{"text":"Hallo"}"#.utf8)
        let reply = try await transcriber().upload(audio: Data("RIFF".utf8), prompt: nil)
        XCTAssertEqual(reply.pieces, [])
    }

    func testOpenRouterTranscriptionListReplacesThePresets() {
        let body = Data(#"{"data":[{"id":"mistralai/voxtral-small-transcribe-3-0","architecture":{"output_modalities":["transcription"]}},{"id":"openai/gpt-4o-transcribe","architecture":{"output_modalities":["transcription"]}},{"id":"openai/gpt-6.1-terra","architecture":{"output_modalities":["text"]}},{"id":"deepgram/nova-3"}]}"#.utf8)
        let listed = CloudSTTProvider.transcriptionModelIds(body)
        XCTAssertEqual(listed, ["mistralai/voxtral-small-transcribe-3-0", "openai/gpt-4o-transcribe", "deepgram/nova-3"])
        XCTAssertTrue(CloudSTTProvider.transcriptionModelIds(Data("geen json".utf8)).isEmpty)
        // Presets the key may use come first; a preset it may not use is left out.
        XCTAssertEqual(CloudSTTProvider.openrouter.choices(listed: listed),
                       ["openai/gpt-4o-transcribe", "deepgram/nova-3", "mistralai/voxtral-small-transcribe-3-0"])
        XCTAssertEqual(CloudSTTProvider.openrouter.choices(listed: []), CloudSTTProvider.openrouter.models)
        XCTAssertEqual(CloudSTTProvider.groq.choices(listed: listed), CloudSTTProvider.groq.models)
        // A routed id is kept until the key's list is known; a bare OpenAI id is not.
        XCTAssertTrue(CloudSTTProvider.openrouter.keeps("mistralai/voxtral-small-transcribe-3-0"))
        XCTAssertFalse(CloudSTTProvider.openrouter.keeps("gpt-4o-transcribe"))
        XCTAssertFalse(CloudSTTProvider.openai.keeps("openai/gpt-4o-transcribe"))
        XCTAssertTrue(CloudSTTProvider.custom.keeps("whatever"))
    }
}
