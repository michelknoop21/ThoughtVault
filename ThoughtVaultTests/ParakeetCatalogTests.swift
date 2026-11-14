import XCTest
@testable import ThoughtVault

final class ParakeetCatalogTests: XCTestCase {

    func testCatalogHoldsOnlyMultilingualModelsUltraFirst() {
        XCTAssertEqual(ParakeetCatalog.all.map(\.id), ["ultra", "v3", "redux"])
        XCTAssertEqual(ParakeetCatalog.model("v3").label, "Parakeet TDT v3")
        XCTAssertEqual(ParakeetCatalog.model("unknown").id, ParakeetCatalog.fallbackID)
        XCTAssertEqual(ParakeetCatalog.model("ultra").sizeText, "632 MB")
    }

    func testFitsNeedsOSAndTwiceTheDownloadSize() {
        let redux = ParakeetCatalog.model("redux")
        XCTAssertTrue(ParakeetCatalog.fits(redux, system: 15, phone: false, freeMegabytes: 440))
        XCTAssertFalse(ParakeetCatalog.fits(redux, system: 15, phone: false, freeMegabytes: 439))
        XCTAssertFalse(ParakeetCatalog.fits(redux, system: 14, phone: false, freeMegabytes: 10_000))
        XCTAssertTrue(ParakeetCatalog.fits(redux, system: 18, phone: true, freeMegabytes: 10_000))
        XCTAssertFalse(ParakeetCatalog.fits(redux, system: 17, phone: true, freeMegabytes: 10_000))
    }

    func testRecommendedPrefersUltraThenV3ThenRedux() {
        func pick(_ memory: Int, _ system: Int, phone: Bool = false, free: Int = 10_000) -> String {
            ParakeetCatalog.recommended(memoryGB: memory, system: system, phone: phone, freeMegabytes: free).id
        }
        XCTAssertEqual(pick(16, 15), "ultra")
        XCTAssertEqual(pick(16, 15, free: 1_000), "v3")       // no room for Ultra
        XCTAssertEqual(pick(16, 15, free: 500), "redux")      // only Redux fits
        XCTAssertEqual(pick(8, 15), "v3")
        XCTAssertEqual(pick(4, 15), "redux")
        XCTAssertEqual(pick(4, 14), "v3")                     // Redux needs macOS 15
        XCTAssertEqual(pick(8, 18, phone: true), "ultra")
        XCTAssertEqual(pick(6, 18, phone: true), "redux")
        XCTAssertEqual(pick(6, 17, phone: true), "v3")        // Redux needs iOS 18
        XCTAssertEqual(pick(16, 15, free: 100), ParakeetCatalog.fallbackID)
    }

    func testSelectedIDFallsBackToRecommendedModel() {
        let defaults = UserDefaults(suiteName: "ParakeetCatalogTests-\(UUID().uuidString)")!
        let redux = ParakeetCatalog.model("redux")
        XCTAssertEqual(ParakeetCatalog.selectedID(defaults: defaults, recommended: redux), "redux")
        defaults.set("ultra", forKey: ParakeetCatalog.defaultsKey)
        XCTAssertEqual(ParakeetCatalog.selectedID(defaults: defaults, recommended: redux), "ultra")
        defaults.set("bark3", forKey: ParakeetCatalog.defaultsKey)
        XCTAssertEqual(ParakeetCatalog.selectedID(defaults: defaults, recommended: redux), "redux")
    }

    func testBlockerNamesOSThenMemoryThenStorage() {
        let ultra = ParakeetCatalog.model("ultra")
        XCTAssertNil(ParakeetCatalog.blocker(ultra, memoryGB: 16, system: 15, phone: false, freeMegabytes: 10_000))
        XCTAssertEqual(ParakeetCatalog.blocker(ultra, memoryGB: 16, system: 13, phone: false, freeMegabytes: 10_000), .system(14))
        XCTAssertEqual(ParakeetCatalog.blocker(ultra, memoryGB: 8, system: 15, phone: false, freeMegabytes: 10_000), .memory(16))
        XCTAssertEqual(ParakeetCatalog.blocker(ultra, memoryGB: 16, system: 15, phone: false, freeMegabytes: 100), .storage(1264))
        XCTAssertEqual(ParakeetCatalog.blocker(ParakeetCatalog.model("redux"), memoryGB: 4, system: 17, phone: true, freeMegabytes: 10_000), .system(18))
    }
}
