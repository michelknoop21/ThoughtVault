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

    func testLearnedNotReplacedButInContextBlock() throws {
        var entry = PersonalCorrection(canonical: "Yinga", variants: ["Jengo"])
        entry.learned = ["Django"]
        XCTAssertEqual(PersonalCorrections.text("Jengo en Django", entries: [entry], profileId: nil), "Yinga en Django")
        let block = PersonalCorrections.contextBlock(entries: [entry], people: [], transcript: "Django", profileId: nil, maxCharacters: 6000)
        XCTAssertTrue(block.hasSuffix("- Yinga (ook gehoord als: Jengo, Django)"))
        // Round trip keeps the field; a learned spelling that became a variant is dropped on upsert.
        try PersonalCorrections.save([entry], to: tmp)
        XCTAssertEqual(try PersonalCorrections.load(from: tmp), [entry])
        var fixed = entry; fixed.id = "other"; fixed.variants = ["Django"]; fixed.learned = nil
        let merged = PersonalCorrections.upsert([entry], entry: fixed)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].variants, ["Jengo", "Django"])
        XCTAssertNil(merged[0].learned)
        // Old files without the field still decode, and it is not written when absent.
        try PersonalCorrections.save([PersonalCorrection(canonical: "Prezent", variants: [])], to: tmp)
        XCTAssertFalse(try String(contentsOf: tmp, encoding: .utf8).contains("learned"))
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
        let block = PersonalCorrections.contextBlock(entries: [], people: [person("Jan de Vries", role: "schade-expert", org: "Achmea", tasks: ["rapport opstellen"])], transcript: "", profileId: nil, maxCharacters: 6000, includeRoles: true)
        XCTAssertTrue(block.contains("Jan de Vries (schade-expert, Achmea), taken: rapport opstellen"))
    }

    /// The minutes prompt leaves role and organization out: models copied them into the notule
    /// although the transcript never said them, and the audit then rejects the notule.
    func testMinutesContextOmitsRoleAndOrganization() {
        let jan = person("Jan de Vries", role: "schade-expert", org: "Achmea", tasks: ["rapport opstellen"], aliases: ["Jan V."])
        let block = PersonalCorrections.contextBlock(entries: [], people: [jan], transcript: "", profileId: nil, maxCharacters: 6000)
        XCTAssertTrue(block.contains("- Jan de Vries (ook gehoord als: Jan V.), taken: rapport opstellen"), block)
        XCTAssertFalse(block.contains("Achmea"))
        XCTAssertFalse(block.contains("schade-expert"))
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

    func testApplyCorrectsNotuleAndTranscript() {
        let entry = PersonalCorrection(canonical: "Maikel", variants: ["Michael"], scope: nil)
        let result = PersonalCorrections.apply(entry, notule: "<p>Michael belt.</p>", transcript: "Michael zegt: michael belt.")
        XCTAssertEqual(result.notule, "<p>Maikel belt.</p>")
        XCTAssertEqual(result.transcript, "Maikel zegt: Maikel belt.")
        XCTAssertNil(PersonalCorrections.apply(entry, notule: "", transcript: nil).transcript)
    }

    func testPersonCorrectionSkipsPartOfNameAndName() throws {
        let entry = try XCTUnwrap(PersonalCorrections.personCorrection(name: "Sanne Bakker", heardAs: ["Sanne", " ", "sanne bakker", "Sanne Backer", "sanne backer", "Bakker"], scope: "p1"))
        XCTAssertEqual(entry.variants, ["Sanne Backer"])
        XCTAssertEqual(entry.scope, "p1")
        let result = PersonalCorrections.apply(entry, notule: "<p>Sanne Backer en Sanne</p>", transcript: "Sanne zei tegen Sanne Backer")
        XCTAssertEqual(result.notule, "<p>Sanne Bakker en Sanne</p>")
        XCTAssertEqual(result.transcript, "Sanne zei tegen Sanne Bakker")
        XCTAssertNil(PersonalCorrections.personCorrection(name: "Sanne Bakker", heardAs: ["Sanne", "SANNE BAKKER", ""], scope: nil))
    }

    func testNewestEntryWinsWhenTwoEntriesContradict() {
        let old = PersonalCorrection(id: "old", canonical: "A‑E", variants: ["AI"], scope: nil)
        let new = PersonalCorrection(id: "new", canonical: "AI", variants: ["A‑E"], scope: nil)
        XCTAssertEqual(PersonalCorrections.text("AI-tools en A-E slop", entries: [old, new], profileId: nil), "AI-tools en AI slop")
        XCTAssertEqual(PersonalCorrections.active([old, new], profileId: nil).map(\.id), ["new"])
        XCTAssertFalse(PersonalCorrections.contextBlock(entries: [old, new], people: [], transcript: "", profileId: nil, maxCharacters: 6000).contains("- A‑E"))
        // Saved the other way round, the other entry wins.
        XCTAssertEqual(PersonalCorrections.text("AI-tools", entries: [new, old], profileId: nil), "A‑E-tools")
        // A chain is no contradiction: the older entry keeps working and nothing cascades.
        let chain = PersonalCorrection(id: "chain", canonical: "Other", variants: ["AI"], scope: nil)
        XCTAssertEqual(PersonalCorrections.text("A-E", entries: [new, chain], profileId: nil), "AI")
    }

    func testVariantsInsideAddressesBecomeLowercaseTerm() {
        let yinga = PersonalCorrection(canonical: "Yinga", variants: ["Jinga"], scope: nil)
        XCTAssertEqual(PersonalCorrections.text("Mail analytics@jinga.nl of kijk op https://www.Jinga.nl/jinga.", entries: [yinga], profileId: nil),
                       "Mail analytics@yinga.nl of kijk op https://www.yinga.nl/yinga.")
        let mail = PersonalCorrection(canonical: "info@yinga.nl", variants: ["info@jingle.nl"], scope: nil)
        XCTAssertEqual(PersonalCorrections.text("Stuur naar info@jingle.nl", entries: [mail], profileId: nil), "Stuur naar info@yinga.nl")
        // A term with a space cannot be part of an address; code spans stay as they are.
        let spaced = PersonalCorrection(canonical: "Prospect Flow", variants: ["prospectflow"], scope: nil)
        XCTAssertEqual(PersonalCorrections.text("sales@prospectflow.nl `prospectflow`", entries: [spaced], profileId: nil), "sales@prospectflow.nl `prospectflow`")
        XCTAssertEqual(PersonalCorrections.html("<p>a@jinga.nl &amp; <a href=\"mailto:a@jinga.nl\">a@jinga.nl</a></p>", entries: [yinga], profileId: nil),
                       "<p>a@yinga.nl &amp; <a href=\"mailto:a@jinga.nl\">a@jinga.nl</a></p>")
    }

    func testLearnedSpellingHoldingTheTermIsNoMisspelling() {
        XCTAssertFalse(PersonalCorrections.isMisspelling("de Prospectflow", of: "Prospectflow"))
        XCTAssertFalse(PersonalCorrections.isMisspelling("zo'n Prospectflow", of: "Prospectflow"))
        XCTAssertTrue(PersonalCorrections.isMisspelling("prospectsflow", of: "Prospectflow"))
        XCTAssertFalse(PersonalCorrections.isMisspelling("API", of: "AI"))
        XCTAssertTrue(PersonalCorrections.isMisspelling("ei", of: "AI"))
        XCTAssertTrue(PersonalCorrections.isMisspelling("A–E", of: "AI"))
        XCTAssertFalse(PersonalCorrections.isMisspelling("de antwoorden", of: "AI Antwoorden"))
        XCTAssertTrue(PersonalCorrections.isMisspelling("ei antwoorden", of: "AI Antwoorden"))
        XCTAssertTrue(PersonalCorrections.isMisspelling("Sanne Backer", of: "Sanne Bakker"))
        var entry = PersonalCorrection(canonical: "Prospectflow", variants: ["Prospect Flow"], scope: nil)
        entry.learned = ["de Prospectflow", "prospectsflow"]
        XCTAssertEqual(entry.heardAs, ["Prospect Flow", "prospectsflow"])
    }
}
