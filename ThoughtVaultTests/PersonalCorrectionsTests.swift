import XCTest
@testable import ThoughtVault

final class PersonalCorrectionsTests: XCTestCase {
    private var tmp: URL!
    private var savedVocabulary: String?

    override func setUpWithError() throws {
        savedVocabulary = UserDefaults.standard.string(forKey: PersonalVocabulary.defaultsKey)
        UserDefaults.standard.removeObject(forKey: PersonalVocabulary.defaultsKey)
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pc-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        if let savedVocabulary { UserDefaults.standard.set(savedVocabulary, forKey: PersonalVocabulary.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: PersonalVocabulary.defaultsKey) }
    }

    private func person(_ name: String, role: String = "", org: String = "", tasks: [String] = [], aliases: [String] = []) -> PersonContext {
        PersonContext(name: name, role: role, organization: org, responsibilities: tasks, aliases: aliases)
    }

    func testLoadsVersion1DocumentWithoutNotes() throws {
        let json = #"{"version":1,"entries":[{"id":"a","canonical":"Yinga","variants":["Jengo"],"scope":null,"enabled":true}]}"#
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        let entries = try PersonalCorrections.load(from: tmp)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].note)
        try PersonalCorrections.save(entries, to: tmp)
        let written = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(written.contains("\"version\":2"))
        let doc = try JSONDecoder().decode(CorrectionDocument.self, from: Data(contentsOf: tmp))
        XCTAssertEqual(doc.dismissed, [])
    }

    func testEntryWithoutVariantsIsValid() throws {
        let entry = PersonalCorrection(canonical: "Prezent", variants: [])
        try PersonalCorrections.save([entry], to: tmp)
        XCTAssertEqual(try PersonalCorrections.load(from: tmp), [entry])
    }

    func testNoteLongerThan200IsRejected() throws {
        var entry = PersonalCorrection(canonical: "Yinga", variants: [])
        entry.note = String(repeating: "a", count: 200)
        XCTAssertNoThrow(try PersonalCorrections.validate(CorrectionDocument(entries: [entry])))
        entry.note = String(repeating: "a", count: 201)
        XCTAssertThrowsError(try PersonalCorrections.validate(CorrectionDocument(entries: [entry])))
    }

    func testContextBlockPrioritisesTermsFoundInTranscript() {
        let note = String(repeating: "x", count: 70)  // long enough that only one line fits in 120
        let a = PersonalCorrection(canonical: "Prezent", variants: ["Presant"], note: note)
        let b = PersonalCorrection(canonical: "Yinga", variants: ["Jengo"], note: note)
        let block = PersonalCorrections.contextBlock(entries: [a, b], people: [], transcript: "we spraken met jengo", profileId: nil, maxCharacters: 120)
        XCTAssertTrue(block.contains("Yinga"))
        XCTAssertFalse(block.contains("Prezent"))
    }

    func testContextBlockListsPeopleWithResponsibilities() {
        let block = PersonalCorrections.contextBlock(entries: [], people: [person("Jan de Vries", role: "schade-expert", org: "Achmea", tasks: ["rapport opstellen"])], transcript: "", profileId: nil, maxCharacters: 6000)
        XCTAssertTrue(block.contains("Jan de Vries (schade-expert, Achmea), taken: rapport opstellen"))
    }

    func testMigrateLegacyTermsCreatesEntriesOnce() throws {
        UserDefaults.standard.set("Yinga, Prezent", forKey: PersonalVocabulary.defaultsKey)
        try PersonalVocabulary.migrateLegacyTerms(at: tmp)
        try PersonalVocabulary.migrateLegacyTerms(at: tmp)
        let entries = try PersonalCorrections.load(from: tmp)
        XCTAssertEqual(entries.map(\.canonical), ["Yinga", "Prezent"])
        XCTAssertTrue(entries.allSatisfy { $0.variants.isEmpty })
        XCTAssertNil(UserDefaults.standard.string(forKey: PersonalVocabulary.defaultsKey))
    }

    func testContextBlockAddsExtraTermsLastAndDeduped() {
        let entry = PersonalCorrection(canonical: "Yinga", variants: ["Jengo"])
        let block = PersonalCorrections.contextBlock(entries: [entry], people: [person("Jan de Vries")], transcript: "", profileId: nil, maxCharacters: 6000,
                                                     extraTerms: ["Zeta", "yinga", "JENGO", "jan de vries"])
        let lines = block.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(lines.last, "- Zeta")
        XCTAssertEqual(lines.count, 3)
    }

    func testMigrateDropsKeyAndSkipsInvalidTerms() throws {
        UserDefaults.standard.set("Yinga, Kapot<term>", forKey: PersonalVocabulary.defaultsKey)
        try PersonalVocabulary.migrateLegacyTerms(at: tmp)
        XCTAssertEqual(try PersonalCorrections.load(from: tmp).map(\.canonical), ["Yinga"])
        XCTAssertNil(UserDefaults.standard.string(forKey: PersonalVocabulary.defaultsKey))
    }

    func testBudgetSmallerThanFirstLineStillFillsWithShorterLine() {
        let long = PersonalCorrection(canonical: "Lang", variants: [], note: String(repeating: "x", count: 100))
        let short = PersonalCorrection(canonical: "Kort", variants: [])
        // Newest is first ("Kort"), so put the long one newest to force the skip.
        let block = PersonalCorrections.contextBlock(entries: [short, long], people: [], transcript: "", profileId: nil, maxCharacters: 20)
        XCTAssertTrue(block.contains("- Kort"))
        XCTAssertFalse(block.contains("Lang"))
    }

    func testEmptyInputsReturnEmptyString() {
        XCTAssertEqual(PersonalCorrections.contextBlock(entries: [], people: [], transcript: "", profileId: nil, maxCharacters: 6000), "")
    }

    func testTranscriptMatchUsesWordBoundaries() {
        let ai = PersonalCorrection(canonical: "AI", variants: [])
        let other = PersonalCorrection(canonical: "Zeta", variants: [])
        // Entries are newest-last; "Zeta" is newest so it leads unless "AI" wrongly matches "maintain".
        let block = PersonalCorrections.contextBlock(entries: [ai, other], people: [], transcript: "we maintain it", profileId: nil, maxCharacters: 6000)
        XCTAssertTrue(block.range(of: "- Zeta")!.lowerBound < block.range(of: "- AI")!.lowerBound)
    }

    func testUnknownGlossaryVersionYieldsEmptyListForMinutes() throws {
        try #"{"version":99,"entries":[]}"#.write(to: tmp, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try PersonalCorrections.load(from: tmp))
        let entries = PersonalCorrections.loadOrEmpty(at: tmp)
        XCTAssertEqual(entries, [])
        XCTAssertTrue(PersonalCorrections.contextBlock(entries: entries, people: [person("Jan de Vries")], transcript: "", profileId: nil, maxCharacters: 6000).contains("Jan de Vries"))
    }

    func testTestHostNeverResolvesToRealAppSupport() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
        XCTAssertFalse(PersonalCorrections.url.path.hasPrefix(URL.applicationSupportDirectory.path))
    }
}
