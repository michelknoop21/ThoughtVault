import XCTest
@testable import ThoughtVault

/// Answers every request with an empty JSON body and `status`.
private final class ModelListStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var seen: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.seen.append(request)
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

    /// Volgende commits the key in the field, also while its delayed save is still pending.
    func testVolgendeTakesTheTypedKeyOverTheStoredOne() {
        XCTAssertEqual(OnboardingNotulen.keyForNext(typed: " sk-nieuw ", stored: "sk-oud"), "sk-nieuw")
        XCTAssertEqual(OnboardingNotulen.keyForNext(typed: "", stored: "sk-oud"), "sk-oud")
        XCTAssertNil(OnboardingNotulen.keyForNext(typed: "", stored: nil))
    }

    /// Volgende decides on a fresh test of exactly the committed key, so nothing remembered
    /// (or lost on a restart) and no late result for another key counts.
    func testKeyTestSendsExactlyTheCommittedKey() async {
        ModelListStub.seen = []
        ModelListStub.status = 401
        let refused = await OnboardingNotulen.keyTest(.openRouter, key: "sk-a", session: modelListSession)
        XCTAssertEqual(refused, .rejected)
        XCTAssertEqual(ModelListStub.seen.last?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-a")
        ModelListStub.status = 500
        let anthropic = await OnboardingNotulen.keyTest(.anthropic, key: "sk-b", session: modelListSession)
        XCTAssertEqual(anthropic, .inconclusive)
        XCTAssertEqual(ModelListStub.seen.last?.value(forHTTPHeaderField: "x-api-key"), "sk-b")
        ModelListStub.status = 200
        let openAI = await OnboardingNotulen.keyTest(.openAI, key: "sk-c", session: modelListSession)
        XCTAssertEqual(openAI, .passed)
    }

    /// Only a full pass of the protected endpoint counts; a model list alone does not.
    func testCloudConnectionOnlyReadyPasses() {
        XCTAssertEqual(KeyTestOutcome(connection: .ready), .passed)
        XCTAssertEqual(KeyTestOutcome(connection: .keyRejected), .rejected)
        XCTAssertEqual(KeyTestOutcome(connection: .unreachable), .inconclusive)
        XCTAssertEqual(KeyTestOutcome(connection: .keyMissing), .inconclusive)
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
}
