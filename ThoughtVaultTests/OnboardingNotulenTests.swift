import XCTest
@testable import ThoughtVault

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
}
