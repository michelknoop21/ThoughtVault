import XCTest
import SwiftData
@testable import ThoughtVault

// Mirrors windows/src/services/__tests__/notuleDetailLevel.test.ts.

final class NotuleDetailLevelTests: XCTestCase {

    // MARK: Target length

    func testTargetLengthClampsAndRounds() {
        XCTAssertNil(NotuleDetailLevel.volledig.targetLength(transcriptCharacters: 40_000))
        // Below, inside and above the clamps.
        XCTAssertEqual(NotuleDetailLevel.kort.targetLength(transcriptCharacters: 10_000), 1500)
        XCTAssertEqual(NotuleDetailLevel.kort.targetLength(transcriptCharacters: 40_000), 2400)
        XCTAssertEqual(NotuleDetailLevel.kort.targetLength(transcriptCharacters: 100_000), 4000)
        XCTAssertEqual(NotuleDetailLevel.normaal.targetLength(transcriptCharacters: 10_000), 2500)
        XCTAssertEqual(NotuleDetailLevel.normaal.targetLength(transcriptCharacters: 40_000), 6000)
        XCTAssertEqual(NotuleDetailLevel.normaal.targetLength(transcriptCharacters: 100_000), 8000)
        // Rounded to a multiple of 100: 2449.98 down, 2450.04 up.
        XCTAssertEqual(NotuleDetailLevel.kort.targetLength(transcriptCharacters: 40_833), 2400)
        XCTAssertEqual(NotuleDetailLevel.kort.targetLength(transcriptCharacters: 40_834), 2500)
        XCTAssertEqual(NotuleDetailLevel.normaal.targetLength(transcriptCharacters: 33_333), 5000)
        XCTAssertEqual(NotuleDetailLevel.maximumLength(target: 2400), 3100)
        XCTAssertEqual(NotuleDetailLevel.maximumLength(target: 1500), 2000)
        XCTAssertEqual(NotuleDetailLevel.maximumLength(target: 8000), 10_400)
    }

    func testDutchNumber() {
        XCTAssertEqual(NotuleDetailLevel.dutchNumber(999), "999")
        XCTAssertEqual(NotuleDetailLevel.dutchNumber(2400), "2.400")
        XCTAssertEqual(NotuleDetailLevel.dutchNumber(10_400), "10.400")
        XCTAssertEqual(NotuleDetailLevel.dutchNumber(1_000_050), "1.000.050")
    }

    func testDraftBlocksVerbatim() {
        XCTAssertEqual(NotuleDetailLevel.volledig.draftBlock(transcriptCharacters: 40_000), "")
        XCTAssertEqual(NotuleDetailLevel.kort.draftBlock(transcriptCharacters: 40_000),
                       "\n\nDetailniveau Kort: schrijf een beknopte notule van ongeveer 2.400 tekens, hooguit 3.100. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Laat bijzaken, achtergrond, voorbeelden, anekdotes, herhalingen en zijpaden weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau en de secties van het profiel; laat secties weg die alleen bijzaken zouden bevatten.")
        XCTAssertEqual(NotuleDetailLevel.normaal.draftBlock(transcriptCharacters: 40_000),
                       "\n\nDetailniveau Normaal: schrijf een notule van ongeveer 6.000 tekens, hooguit 7.800. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Geef per hoofdonderwerp in één of twee zinnen de context. Laat zijpaden, anekdotes, herhalingen en details zonder gevolg voor een besluit of actie weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau van het profiel.")
    }

    func testDraftBlockIsAppendedAfterTheConstraints() {
        let block = NotuleDetailLevel.kort.draftBlock(transcriptCharacters: 2000)
        let plain = buildNotuleUserContent(notulePrompt: "P", transcription: "t", outputTemplate: nil, constraints: ["Geen klantgegevens extern."])
        XCTAssertEqual(buildNotuleUserContent(notulePrompt: "P", transcription: "t", outputTemplate: nil,
                                              constraints: ["Geen klantgegevens extern."], detailBlock: block), plain + block)
    }

    // MARK: Essential constraints

    func testEssentialConstraintsKeepOnlyAnchoredSentences() {
        let text = "Er gaan geen klantgegevens naar leveranciers. Het budget wordt niet hoger dan 12.450 euro. Dit mag niet zonder Bram. De oude afspraak vervalt. We doen niets met de folder."
        XCTAssertEqual(NotuleAudit.constraintSentences(text).count, 5)
        XCTAssertEqual(NotuleAudit.essentialConstraints(text),
                       ["Het budget wordt niet hoger dan 12.450 euro.", "Dit mag niet zonder Bram.", "De oude afspraak vervalt."])
    }

    // MARK: Audit with minor

    private let source = "Sam belt vrijdag de klant. We hadden het nog even over het weer."
    private let html = "<p>Sam belt vrijdag de klant.</p>"

    /// Covers T1 with N1 and gives `minorId` status minor; `noteEvidence` is what N1 cites.
    private func request(minor minorId: String, noteEvidence: [String] = ["T1"], systems: SystemLog? = nil) -> AuditRequest {
        { system, user in
            await systems?.add(system)
            let input = try JSONSerialization.jsonObject(with: Data(user[user.index(after: user.firstIndex(of: "\n")!)...].utf8)) as! [String: Any]
            let sourceIds = (input["source"] as! [[String: String]]).map { $0["id"]! }
            let report: [String: Any] = [
                "uncertain": false,
                "source": sourceIds.map { ["id": $0, "status": $0 == minorId ? "minor" : "covered"] },
                "notes": [["id": "N1", "status": "supported", "evidence": noteEvidence]],
            ]
            return String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
        }
    }

    actor SystemLog {
        var systems: [String] = []
        func add(_ system: String) { systems.append(system) }
    }

    private func audit(_ source: String, quickNote: String = "", required: [String] = [], level: NotuleDetailLevel,
                       request: @escaping AuditRequest) async throws {
        try await NotuleAudit.auditNotule(source: source, html: html, quickNote: quickNote, request: request,
                                          requiredSentences: required, detailLevel: level)
    }

    private func assertRejected(_ expected: String, _ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("Expected a rejection", line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, expected, line: line)
        }
    }

    func testMinorAcceptedAtKortForAPlainSentence() async throws {
        let log = SystemLog()
        try await audit(source, level: .kort, request: request(minor: "T2", systems: log))
        try await audit(source, level: .normaal, request: request(minor: "T2"))
        let systems = await log.systems
        XCTAssertEqual(systems.count, 1)
        XCTAssertTrue(systems[0].hasSuffix("\n" + NotuleDetailLevel.auditSuffixText))
    }

    func testMinorRejectedAtVolledigLikeAnUnknownStatus() async {
        let log = SystemLog()
        await assertRejected("Ongeldig controlebewijs") { try await self.audit(self.source, level: .volledig, request: self.request(minor: "T2", systems: log)) }
        let systems = await log.systems
        XCTAssertFalse(systems[0].contains(NotuleDetailLevel.auditSuffixText))
    }

    func testMinorRejectedOnAQuickNote() async {
        await assertRejected("De notule mist broninformatie: Bel ook over de planning.") {
            try await self.audit("Sam belt vrijdag de klant.", quickNote: "Bel ook over de planning.", level: .kort, request: self.request(minor: "Q1"))
        }
    }

    func testMinorRejectedOnARequiredSentence() async {
        await assertRejected("De notule mist broninformatie: We hadden het nog even over het weer.") {
            try await self.audit(self.source, required: ["We hadden het nog even over het weer."], level: .kort, request: self.request(minor: "T2"))
        }
    }

    func testMinorRejectedOnAnAmount() async {
        for sentence in ["De lunch kostte 12 euro.", "De korting was 5 %.", "Het kost € 40 per maand.", "Dat is 3 procent meer."] {
            await assertRejected("De notule mist broninformatie: \(sentence)") {
                try await self.audit("Sam belt vrijdag de klant. \(sentence)", level: .kort, request: self.request(minor: "T2"))
            }
        }
    }

    func testMinorWithEvidenceIsInvalid() async {
        // A supported notule sentence citing T2 gives the minor verdict derived evidence.
        await assertRejected("Ongeldig controlebewijs") {
            try await self.audit(self.source, level: .kort, request: self.request(minor: "T2", noteEvidence: ["T1", "T2"]))
        }
    }

    // MARK: Effective level

    func testEffectiveLevelPrefersUserChoiceThenProfileDefault() throws {
        let suite = "NotuleDetailLevelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let executive = Profile(id: "executive", name: "Executive", detailLevel: "kort")
        let custom = Profile(id: "eigen", name: "Eigen")

        XCTAssertEqual(NotuleDetailLevel.effective(for: executive, defaults: defaults), .kort)
        XCTAssertEqual(NotuleDetailLevel.effective(for: custom, defaults: defaults), .volledig)
        NotuleDetailLevel.setChoice(.normaal, for: "executive", defaults: defaults)
        NotuleDetailLevel.setChoice(.kort, for: "eigen", defaults: defaults)
        XCTAssertEqual(NotuleDetailLevel.effective(for: executive, defaults: defaults), .normaal)
        XCTAssertEqual(NotuleDetailLevel.effective(for: custom, defaults: defaults), .kort)
        NotuleDetailLevel.setChoice(nil, for: "executive", defaults: defaults)
        XCTAssertEqual(NotuleDetailLevel.effective(for: executive, defaults: defaults), .kort)
        // An unknown stored value falls back instead of failing.
        defaults.set(["eigen": "lang"], forKey: NotuleDetailLevel.choicesKey)
        XCTAssertEqual(NotuleDetailLevel.effective(for: custom, defaults: defaults), .volledig)
    }

    func testChooseStoresTheOverrideAndTheProfileDefaultRemovesIt() throws {
        let suite = "NotuleDetailLevelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let executive = Profile(id: "executive", name: "Executive", detailLevel: "kort")

        NotuleDetailLevel.choose(.volledig, for: executive, defaults: defaults)
        XCTAssertEqual(defaults.dictionary(forKey: NotuleDetailLevel.choicesKey) as? [String: String], ["executive": "volledig"])
        XCTAssertEqual(NotuleDetailLevel.effective(for: executive, defaults: defaults), .volledig)
        NotuleDetailLevel.choose(.kort, for: executive, defaults: defaults)
        XCTAssertEqual(defaults.dictionary(forKey: NotuleDetailLevel.choicesKey) as? [String: String], [:])
        XCTAssertEqual(NotuleDetailLevel.effective(for: executive, defaults: defaults), .kort)
    }

    func testBundledProfilesCarryTheirDefault() {
        let levels = Dictionary(uniqueKeysWithValues: Profile.defaults.map { ($0.id, $0.detailLevel) })
        XCTAssertEqual(levels["standaard"], "normaal")
        XCTAssertEqual(levels["projectoverleg"], "volledig")
        XCTAssertEqual(levels["klantgesprek"], "normaal")
        XCTAssertEqual(levels["brainstorm"], "normaal")
        XCTAssertEqual(levels["executive"], "kort")
        XCTAssertEqual(levels["een_op_een"], "kort")
        XCTAssertEqual(levels["promptnotitie"], .some(nil))
    }
}

// MARK: - Storage

@MainActor
final class NotuleDetailLevelStoreTests: XCTestCase {
    func testFinalizeStoresTheLevelAndRegenerateStartsFromIt() throws {
        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LocalTranscriptStore(container: container)
        try store.save(TranscriptRecord(id: "t1", taskId: "t1", title: "Overleg", rawTranscription: "Sam belt vrijdag.", profileId: "standaard"))
        let record = try XCTUnwrap(store.record(forTaskId: "t1"))
        XCTAssertNil(record.detailLevel)
        XCTAssertNil(RecordingViewModel.storedDetailLevel(record, profileId: "standaard"))

        try store.finalizeNotule(taskId: "t1", html: "<p>Sam belt vrijdag.</p>", title: "Overleg", detailLevel: .kort)
        XCTAssertEqual(record.detailLevel, "kort")
        XCTAssertEqual(RecordingViewModel.storedDetailLevel(record, profileId: "standaard"), .kort)
        XCTAssertNil(RecordingViewModel.storedDetailLevel(record, profileId: "executive"), "another profile uses its own level")

        // Without a level the stored one stays; older records fall back to the level in the usage JSON.
        try store.finalizeNotule(taskId: "t1", html: "<p>Sam belt vrijdag.</p>", title: "Overleg")
        XCTAssertEqual(record.detailLevel, "kort")
        record.detailLevel = nil
        record.notuleUsageJSON = #"{"provider":"","model":"","transcriptCharacters":1,"notuleCharacters":1,"notuleWords":1,"notuleSentences":1,"requests":1,"requestsWithUnknownUsage":0,"inputTokens":0,"outputTokens":0,"reasoningTokens":0,"durationMs":1,"steps":{},"contentCheckSkipped":false,"detailLevel":"normaal"}"#
        XCTAssertEqual(RecordingViewModel.storedDetailLevel(record, profileId: "standaard"), .normaal)
    }

    func testRegenerateSheetPreselection() throws {
        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LocalTranscriptStore(container: container)
        try store.save(TranscriptRecord(id: "t1", taskId: "t1", title: "Overleg", rawTranscription: "Sam belt vrijdag.", profileId: "standaard"))
        try store.finalizeNotule(taskId: "t1", html: "<p>Sam belt vrijdag.</p>", title: "Overleg", detailLevel: .kort)
        let record = try XCTUnwrap(store.record(forTaskId: "t1"))
        let suite = "NotuleDetailLevelStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let standaard = Profile(id: "standaard", name: "Standaard", detailLevel: "volledig")
        let klant = Profile(id: "klantgesprek", name: "Klantgesprek", detailLevel: "normaal")

        XCTAssertEqual(RecordingViewModel.regenerateDetailLevel(record, profile: standaard, defaults: defaults), .kort, "same profile: the stored level")
        XCTAssertEqual(RecordingViewModel.regenerateDetailLevel(record, profile: klant, defaults: defaults), .normaal, "other profile: its default")
        NotuleDetailLevel.setChoice(.kort, for: "klantgesprek", defaults: defaults)
        XCTAssertEqual(RecordingViewModel.regenerateDetailLevel(record, profile: klant, defaults: defaults), .kort, "other profile: the user's choice")
        XCTAssertEqual(RecordingViewModel.regenerateDetailLevel(nil, profile: standaard, defaults: defaults), .volledig)
        record.detailLevel = nil
        XCTAssertEqual(RecordingViewModel.regenerateDetailLevel(record, profile: standaard, defaults: defaults), .volledig, "older record: the profile's level")
    }

    /// The pre-draft-fields store opens through the app's own container path after `detailLevel` was added.
    func testOldStoreOpensWithDetailLevelField() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PreDraftFields", withExtension: "store"))
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Local.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        let suite = "NotuleDetailLevelStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let container = LocalTranscriptStore.makeContainer(at: url, defaults: defaults)
        XCTAssertEqual(container.configurations.first?.url, url, "must be the on-disk store, not the in-memory fallback")
        let record = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<TranscriptRecord>()).first)
        XCTAssertEqual(record.id, "fixture-1")
        XCTAssertNil(record.detailLevel)

        record.detailLevel = "kort"
        try container.mainContext.save()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files.contains { $0.contains("incompatible") }, "store was moved aside: \(files)")
    }
}
