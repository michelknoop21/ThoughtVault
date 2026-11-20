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
        let text = try await transcriber().upload(audio: Data("RIFF".utf8), prompt: "Namen en termen: Michel.")
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
}
