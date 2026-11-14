import XCTest
@testable import ThoughtVault

final class NotulenDefaultMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "NotulenDefaultMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testFreshInstallGetsOpenRouter() {
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: false)
        XCTAssertEqual(NotulenProvider.installDefault(defaults: defaults), .openRouter)
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), .openRouter)
    }

    func testExistingInstallWithoutStoredValueKeepsPlatformDefault() {
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: true)
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), NotulenProvider.platformDefault)

        let onboarded = UserDefaults(suiteName: suite + "-onboarded")!
        defer { onboarded.removePersistentDomain(forName: suite + "-onboarded") }
        onboarded.set(false, forKey: "hasCompletedOnboarding")
        NotulenProvider.decideLegacyDefault(defaults: onboarded, storeExists: false)
        XCTAssertEqual(NotulenProvider.configured(defaults: onboarded), NotulenProvider.platformDefault)
    }

    func testStoredValueAlwaysWins() {
        defaults.set(NotulenProvider.anthropic.rawValue, forKey: "notulenProvider")
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: false)
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), .anthropic)
        defaults.set(true, forKey: NotulenProvider.legacyDefaultKey)
        XCTAssertEqual(NotulenProvider.configured(defaults: defaults), .anthropic)
    }

    func testDecisionRunsOnce() {
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: false)
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: true)
        XCTAssertEqual(NotulenProvider.installDefault(defaults: defaults), .openRouter)
    }

    func testSyncedProviderKeyIsNeverWritten() {
        NotulenProvider.decideLegacyDefault(defaults: defaults, storeExists: false)
        XCTAssertNil(defaults.object(forKey: "notulenProvider"))
        let existing = UserDefaults(suiteName: suite + "-existing")!
        defer { existing.removePersistentDomain(forName: suite + "-existing") }
        NotulenProvider.decideLegacyDefault(defaults: existing, storeExists: true)
        XCTAssertNil(existing.object(forKey: "notulenProvider"))
    }
}
