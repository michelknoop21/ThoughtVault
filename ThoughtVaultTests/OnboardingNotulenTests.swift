import XCTest
@testable import ThoughtVault

/// Answers every request with an empty JSON body and `status`.
private final class ModelListStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let modelListSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ModelListStub.self]
    return URLSession(configuration: configuration)
}()

final class OnboardingNotulenTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "OnboardingNotulenTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testEachTileInstallsItsProvider() {
        XCTAssertEqual(OnboardingNotulen.provider(for: .openRouter, current: .openRouter, appleIntelligence: true), .openRouter)
        XCTAssertEqual(OnboardingNotulen.provider(for: .onDevice, current: .openRouter, appleIntelligence: true), .appleIntelligence)
        XCTAssertEqual(OnboardingNotulen.provider(for: .onDevice, current: .openRouter, appleIntelligence: false), .ollama)
        XCTAssertEqual(OnboardingNotulen.provider(for: .other, current: .openRouter, appleIntelligence: true), .openAICompatible)
        XCTAssertEqual(OnboardingNotulen.provider(for: .openRouter, current: .cloud, appleIntelligence: true), .openRouter)
    }

    func testRerunKeepsTheProviderOfTheSameTile() {
        XCTAssertEqual(OnboardingNotulen.choice(for: .anthropic), .other)
        XCTAssertEqual(OnboardingNotulen.provider(for: .other, current: .anthropic, appleIntelligence: true), .anthropic)
        XCTAssertEqual(OnboardingNotulen.choice(for: .lmStudio), .onDevice)
        XCTAssertEqual(OnboardingNotulen.provider(for: .onDevice, current: .lmStudio, appleIntelligence: true), .lmStudio)
        XCTAssertEqual(OnboardingNotulen.choice(for: .openRouter), .openRouter)
    }

    func testLocalProvidersNeedNoKey() {
        XCTAssertTrue(OnboardingNotulen.isReady(.appleIntelligence))
        XCTAssertTrue(OnboardingNotulen.isReady(.ollama))
    }

    func testApplyStoresTheProvider() {
        OnboardingNotulen.skip(defaults: defaults)
        OnboardingNotulen.apply(.appleIntelligence, defaults: defaults)
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), .appleIntelligence)
        XCTAssertFalse(defaults.bool(forKey: OnboardingNotulen.skippedKey))
    }

    func testSkipWritesNoProviderAndMarksTheStep() {
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: false)
        OnboardingNotulen.skip(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "notulenProvider"))
        XCTAssertTrue(defaults.bool(forKey: OnboardingNotulen.skippedKey))
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), .openRouter)
    }

    /// Existing installs never reach the step: their provider and legacy default stay as they were.
    func testExistingUserIsUnaffected() {
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(NotulenProvider.ollama.rawValue, forKey: "notulenProvider")
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: true)
        XCTAssertEqual(OnboardingNotulen.choice(for: .configured(defaults: defaults)), .onDevice)
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), .ollama)
        XCTAssertNil(defaults.object(forKey: OnboardingNotulen.skippedKey))
    }

    /// An iPhone has no Ollama or LM Studio of its own: the on-device tile without
    /// Apple Intelligence leads to the skip question instead of storing Ollama.
    func testOnDeviceWithoutLocalServerIsNotReady() {
        let provider = OnboardingNotulen.provider(for: .onDevice, current: .openRouter, appleIntelligence: false)
        XCTAssertFalse(OnboardingNotulen.isReady(provider, localServers: false))
        XCTAssertFalse(OnboardingNotulen.isReady(.lmStudio, localServers: false))
        XCTAssertTrue(OnboardingNotulen.isReady(.appleIntelligence, localServers: false))
        XCTAssertTrue(OnboardingNotulen.isReady(provider, localServers: true))
    }

    /// A refused key stays refused per provider, through tile switches, tests of other
    /// providers and inconclusive retries; only a passing test or another key lifts it.
    func testRejectionIsKeptPerProviderUntilPassOrOtherKey() {
        var rejections: [NotulenProvider: String] = [:]
        OnboardingNotulen.record(.rejected, key: "sk-fout", for: .openRouter, in: &rejections)
        XCTAssertTrue(OnboardingNotulen.isRejected(.openRouter, storedKey: "sk-fout", in: rejections))
        XCTAssertFalse(rejections.values.contains("sk-fout"), "only a fingerprint is kept")

        OnboardingNotulen.record(.passed, key: "sk-ander", for: .openAICompatible, in: &rejections)
        XCTAssertTrue(OnboardingNotulen.isRejected(.openRouter, storedKey: "sk-fout", in: rejections))

        OnboardingNotulen.record(.inconclusive, key: "sk-fout", for: .openRouter, in: &rejections)
        XCTAssertTrue(OnboardingNotulen.isRejected(.openRouter, storedKey: "sk-fout", in: rejections))

        XCTAssertFalse(OnboardingNotulen.isRejected(.openRouter, storedKey: "sk-nieuw", in: rejections))
        XCTAssertFalse(OnboardingNotulen.isRejected(.openRouter, storedKey: nil, in: rejections))

        OnboardingNotulen.record(.passed, key: "sk-fout", for: .openRouter, in: &rejections)
        XCTAssertFalse(OnboardingNotulen.isRejected(.openRouter, storedKey: "sk-fout", in: rejections))
    }

    func testKeyTestOutcomeFromStatus() {
        XCTAssertEqual(KeyTestOutcome(status: 200), .passed)
        XCTAssertEqual(KeyTestOutcome(status: 401), .rejected)
        XCTAssertEqual(KeyTestOutcome(status: 403), .rejected)
        XCTAssertEqual(KeyTestOutcome(status: 500), .inconclusive)
        XCTAssertEqual(KeyTestOutcome(status: nil), .inconclusive)
    }

    /// The OpenAI and Anthropic key tests read the models list; its 401 must reach the caller.
    func testModelListsReportTheStatus() async {
        ModelListStub.status = 401
        let anthropic = await AnthropicLLMService(model: "m", apiKey: "k", session: modelListSession).fetchModelList()
        XCTAssertEqual(anthropic.status, 401)
        XCTAssertTrue(anthropic.models.isEmpty)
        let openAI = await OpenAICompatibleLLMService(baseURL: OpenAICompatibleLLMService.openAIBaseURL, model: "m",
                                                      apiKey: "k", session: modelListSession).fetchModelList()
        XCTAssertEqual(openAI.status, 401)
    }

    /// A key the provider just refused blocks Volgende, even though it is stored.
    func testRejectedKeyIsNotReady() {
        XCTAssertFalse(OnboardingNotulen.isReady(.openRouter, keyRejected: true))
        XCTAssertFalse(OnboardingNotulen.isReady(.openAICompatible, keyRejected: true))
    }

}
