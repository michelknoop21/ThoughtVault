import XCTest
@testable import ThoughtVault

/// Acceptance tests for the shared audio envelope, driven by the same fixture
/// as the Rust suite (tests/fixtures/envelope-fixture.json). Assertions are
/// spec thresholds, not golden floats — no cross-language float matching.
final class AudioEnvelopeProcessorTests: XCTestCase {

    private struct Step: Decodable {
        let dtMs: Double
        let db: Float
        let repeatCount: Int
        enum CodingKeys: String, CodingKey { case dtMs, db, repeatCount = "repeat" }
    }

    // Decoded on access — cheap and avoids Swift 6 static-mutable concurrency.
    private static var scenarios: [String: [Step]] {
        // Fixture lives at the repo root; locate it relative to this source file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ThoughtVaultTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("tests/fixtures/envelope-fixture.json")
        struct Fixture: Decodable { let scenarios: [String: [Step]] }
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(Fixture.self, from: data).scenarios
    }

    /// Runs a scenario through the processor, returning all outputs.
    private func run(_ name: String, processor: inout AudioEnvelopeProcessor) -> [Float] {
        guard let steps = Self.scenarios[name] else {
            XCTFail("Missing fixture scenario \(name)"); return []
        }
        var out: [Float] = []
        for step in steps {
            for _ in 0..<step.repeatCount {
                out.append(processor.process(db: step.db, dt: step.dtMs / 1000))
            }
        }
        return out
    }

    // 1. 2 s of silence → output 0
    func testSilenceIsZero() {
        var p = AudioEnvelopeProcessor()
        let out = run("silence", processor: &p)
        XCTAssertEqual(out.last, 0)
        XCTAssertTrue(out.suffix(30).allSatisfy { $0 == 0 })
    }

    // 2. Input at the noise floor → ≤ 0.03
    func testNoiseFloorSuppressed() {
        var p = AudioEnvelopeProcessor()
        let out = run("noiseFloor", processor: &p)
        XCTAssertLessThanOrEqual(out.last ?? 1, 0.03)
    }

    // 3. Speech −35..−18 dBFS → dynamic, roughly 0.30–0.90 with real spread
    func testSpeechIsDynamic() {
        var pSoft = AudioEnvelopeProcessor()
        let soft = run("speechSoft", processor: &pSoft).last ?? 0
        var pLoud = AudioEnvelopeProcessor()
        let loud = run("speechLoud", processor: &pLoud).last ?? 0
        XCTAssertGreaterThanOrEqual(soft, 0.30)
        XCTAssertLessThanOrEqual(loud, 0.90)
        XCTAssertGreaterThanOrEqual(loud - soft, 0.15, "soft vs loud speech must be visually distinct")
    }

    // 4. −8 dBFS → > 0.90, ≤ 1.0
    func testLoudNearMax() {
        var p = AudioEnvelopeProcessor()
        let out = run("loud", processor: &p).last ?? 0
        XCTAssertGreaterThan(out, 0.90)
        XCTAssertLessThanOrEqual(out, 1.0)
    }

    // 5. Silence → speech: ≥ 80% of steady value within ~70 ms
    func testAttack() {
        var p = AudioEnvelopeProcessor()
        _ = run("attackSilence", processor: &p)
        let early = run("attackSpeechEarly", processor: &p).last ?? 0
        let steady = run("attackSpeechSteady", processor: &p).last ?? 0
        XCTAssertGreaterThanOrEqual(early, 0.8 * steady)
    }

    // 6. Speech → silence: < 10% of steady value within ~550 ms
    func testRelease() {
        var p = AudioEnvelopeProcessor()
        _ = run("attackSilence", processor: &p)
        let steady = run("attackSpeechSteady", processor: &p).last ?? 0
        let released = run("releaseSilence", processor: &p).last ?? 1
        XCTAssertLessThan(released, 0.1 * steady)
    }

    // 7. 10 ms vs 33 ms update cadence → ~equal envelope after equal wall time
    func testFrameRateIndependence() {
        var pFine = AudioEnvelopeProcessor()
        let fine = run("dtFine", processor: &pFine).last ?? 0
        var pCoarse = AudioEnvelopeProcessor()
        let coarse = run("dtCoarse", processor: &pCoarse).last ?? 0
        XCTAssertEqual(fine, coarse, accuracy: 0.05)
    }

    // 8. Extreme inputs → never NaN/Inf, always 0..1
    func testExtremesStayFinite() {
        var p = AudioEnvelopeProcessor()
        let out = run("extremes", processor: &p)
        for v in out {
            XCTAssertTrue(v.isFinite)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
        // Also survive literal NaN/Inf inputs
        XCTAssertTrue(p.process(db: .nan, dt: 0.033).isFinite)
        XCTAssertTrue(p.process(db: .infinity, dt: 0.033).isFinite)
    }
}
