import XCTest
import SwiftData
import SwiftUI
@testable import ThoughtVault

// Flow assertions ported from windows/src/services/__tests__/llm.audit-integration.test.ts
// and notuleValidation.test.ts: one generation, a source check, one content audit, and a
// rejected draft that is handed back for review instead of being approved.

/// Scripted provider: `generateNotulen` returns a fixed draft, `complete` answers the audits.
private final class StubLLM: LLMService, @unchecked Sendable {
    struct Generation { let transcription, systemPrompt, notulePrompt: String; let constraints: [String] }

    private let lock = NSLock()
    private let draft: String
    private let audit: @Sendable (String) throws -> String
    private var _generations: [Generation] = []
    private var _audits: [String] = []
    private var _progressChunks = 0

    /// `audit` receives the user message of each `complete` call.
    init(draft: String, audit: @escaping @Sendable (String) throws -> String = StubLLM.approve()) {
        self.draft = draft
        self.audit = audit
    }

    var generations: [Generation] { lock.withLock { _generations } }
    var audits: [String] { lock.withLock { _audits } }
    var progressChunks: Int { lock.withLock { _progressChunks } }
    var isAvailable: Bool { true }

    func generateNotulen(transcription: String, systemPrompt: String, notulePrompt: String, outputTemplate: String?,
                         constraints: [String], onProgress: @Sendable (String) -> Void) async throws -> String {
        lock.withLock { _generations.append(Generation(transcription: transcription, systemPrompt: systemPrompt,
                                                         notulePrompt: notulePrompt, constraints: constraints)) }
        // Stream the draft like a real provider; the generator must not forward it anywhere.
        onProgress(draft)
        lock.withLock { _progressChunks += 1 }
        return draft
    }

    func complete(system: String, user: String) async throws -> String {
        lock.withLock { _audits.append(user) }
        return try audit(user)
    }

    /// Approves the source check and covers/supports every unit, optionally edited first.
    static func approve(_ change: (@Sendable (inout [String: Any]) -> Void)? = nil) -> @Sendable (String) throws -> String {
        { user in
            if user.hasPrefix("Broncontrole") { return #"{"uncertain":false}"# }
            let json = user[user.index(after: user.firstIndex(of: "\n")!)...]
            let input = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            let sourceIds = (input["source"] as! [[String: String]]).map { $0["id"]! }
            let noteIds = (input["notes"] as! [[String: String]]).map { $0["id"]! }
            var report: [String: Any] = [
                "uncertain": false,
                "source": sourceIds.map { ["id": $0, "status": "covered", "evidence": noteIds] },
                "notes": noteIds.map { ["id": $0, "status": "supported", "evidence": sourceIds] },
            ]
            change?(&report)
            return String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
        }
    }
}

/// The draft waits up to two seconds for the source check to start; with `draftError` it then fails while
/// the source check is still waiting to be cancelled.
private final class OverlapLLM: LLMService, @unchecked Sendable {
    private let lock = NSLock()
    private let draftError: Error?
    private var _sourceStarted = false, _startedDuringDraft = false, _sourceCancelled = false
    init(draftError: Error? = nil) { self.draftError = draftError }

    var startedDuringDraft: Bool { lock.withLock { _startedDuringDraft } }
    var sourceCancelled: Bool { lock.withLock { _sourceCancelled } }
    var isAvailable: Bool { true }

    func generateNotulen(transcription: String, systemPrompt: String, notulePrompt: String, outputTemplate: String?,
                         constraints: [String], onProgress: @Sendable (String) -> Void) async throws -> String {
        var waited = 0
        while !lock.withLock({ _sourceStarted }), waited < 200 { try await Task.sleep(nanoseconds: 10_000_000); waited += 1 }
        lock.withLock { _startedDuringDraft = _sourceStarted }
        if let draftError { throw draftError }
        return "<p>Sam neemt vrijdag contact op met de klant.</p>"
    }

    func complete(system: String, user: String) async throws -> String {
        guard user.hasPrefix("Broncontrole") else { return try StubLLM.approve()(user) }
        lock.withLock { _sourceStarted = true }
        guard draftError != nil else { return #"{"uncertain":false}"# }
        do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch {
            lock.withLock { _sourceCancelled = true }
            throw error
        }
        return #"{"uncertain":true}"#
    }
}

private let profile = Profile(id: "standaard", name: "Standaard", systemPrompt: "Je bent notulist.",
                              notulePrompt: "Maak notulen.", template: nil)

private func generate(_ service: StubLLM, _ transcription: String, quickNote: String? = nil,
                      participants: [Participant] = []) async throws -> String {
    try await NotuleGenerator(service: service).generate(
        transcription: transcription, profile: profile, participants: participants, quickNote: quickNote,
        createdAt: Date(timeIntervalSince1970: 0), corrections: [])
}

private func warnings(_ items: String..., in html: String) -> String {
    NotuleAudit.appendingWarnings(items, to: html)
}

final class NotuleGeneratorTests: XCTestCase {

    // "audits correct conditional and negative paraphrases ... without literal-only rejection"
    func testApprovedNotuleIsReturned() async throws {
        let raw = "Fatima stuurt de offerte vrijdag. Als de test slaagt, geeft Bram maandag akkoord. Er is nog niet over uitvoering besloten."
        let html = "<p>De offerte wordt vrijdag door Fatima verstuurd. Bram geeft maandag uitsluitend bij een geslaagde test akkoord. Over uitvoering bestaat nog geen besluit.</p>"
        let service = StubLLM(draft: html)
        let result = try await generate(service, raw)
        XCTAssertEqual(result, html)
        XCTAssertEqual(service.generations.count, 1)
        XCTAssertEqual(service.audits.count, 2)
        XCTAssertTrue(service.audits[0].hasPrefix("Broncontrole"))
        XCTAssertTrue(service.audits[1].contains("Fatima stuurt de offerte vrijdag."))
        XCTAssertTrue(service.audits[1].contains("Over uitvoering bestaat nog geen besluit."))
    }

    // DEC-063: an audit finding no longer blocks; the notule is returned with the finding in plain words.
    func testFindingIsShownInTheNotule() async throws {
        for owner in ["Emma", "Youssef", "Robin"] {
            let html = "<p>Sam neemt dinsdag telefonisch contact op.</p>"
            let service = StubLLM(draft: html, audit: StubLLM.approve { report in
                var source = report["source"] as! [[String: Any]]
                source[1]["status"] = "missing"; source[1]["evidence"] = [String]()
                report["source"] = source
            })
            let result = try await generate(service, "Sam belt dinsdag. \(owner) controleert woensdag de offerte.")
            XCTAssertEqual(result, warnings("Dit is gezegd, maar staat misschien niet in de notule: “\(owner) controleert woensdag de offerte.”", in: html))
            XCTAssertEqual(service.audits.count, 2)
        }
    }

    // The quick-note section stays; both failed checks end up in one section.
    func testFailedChecksKeepTheNotesSection() async throws {
        let html = "<p>Sam neemt dinsdag telefonisch contact op met de leverancier.</p>"
        let service = StubLLM(draft: html, audit: { _ in throw URLError(.timedOut) })
        let result = try await generate(service, "Sam belt dinsdag de leverancier.", quickNote: "Offerte nalopen")
        XCTAssertEqual(result, warnings(NotuleAudit.uncheckedSourceWarning, NotuleAudit.uncheckedContentWarning,
                                        in: html + "<h2>Notities</h2><p>Offerte nalopen</p>"))
    }

    // A technical audit failure shows the general line, never an internal code like "T2".
    func testAuditServiceFailureShowsGeneralWarning() async throws {
        let html = "<p>Sam neemt vrijdag contact op.</p>"
        let service = StubLLM(draft: html, audit: { user in
            if user.hasPrefix("Broncontrole") { return #"{"uncertain":false}"# }
            throw LLMError.serverError(500)
        })
        let result = try await generate(service, "Sam belt vrijdag.")
        XCTAssertEqual(result, warnings(NotuleAudit.uncheckedContentWarning, in: html))
        XCTAssertEqual(service.generations.count, 1)
        XCTAssertEqual(service.audits.count, 2)
    }

    // The T9 case: "covered" without any notule sentence pointing at it.
    func testMissingEvidenceShowsGeneralWarningWithoutCode() async throws {
        let html = "<p>Sam neemt vrijdag contact op.</p>"
        let service = StubLLM(draft: html, audit: StubLLM.approve { report in
            report["source"] = (report["source"] as! [[String: Any]]).map { var item = $0; item["status"] = "covered"; return item }
            report["notes"] = (report["notes"] as! [[String: Any]]).map { var note = $0; note["evidence"] = ["T1"]; return note }
        })
        let result = try await generate(service, "Sam belt vrijdag. Iris mailt maandag.")
        XCTAssertEqual(result, warnings(NotuleAudit.uncheckedContentWarning, in: html))
        XCTAssertFalse(result.contains("T2"))
    }

    // An unsure source check never blocks: the notule carries the warning.
    func testUnclearSourceAddsWarningToApprovedNotule() async throws {
        let html = "<p>Sam neemt vrijdag contact op.</p>"
        let service = StubLLM(draft: html, audit: { user in
            user.hasPrefix("Broncontrole") ? #"{"uncertain":true}"# : try StubLLM.approve()(user)
        })
        let result = try await generate(service, "Sam belt vrijdag. Het zit op derf.")
        XCTAssertEqual(result, html + "<h2>Even nalopen</h2><ul><li>\(NotuleAudit.unclearSourceWarning)</li></ul>")
        XCTAssertEqual(service.audits.count, 2)
    }

    // An unsure notule audit adds the general line next to the source warning.
    func testUnclearSourceAndUnsureAuditBothWarn() async throws {
        let html = "<p>Een stellig verhaal over een pilot.</p>"
        let service = StubLLM(draft: html, audit: { user in
            if user.hasPrefix("Broncontrole") { return #"{"uncertain":true}"# }
            return try StubLLM.approve { $0["uncertain"] = true }(user)
        })
        let result = try await generate(service, "En mensen processen stok maken voorbij pilot zeker leeg.")
        XCTAssertEqual(result, warnings(NotuleAudit.unclearSourceWarning, NotuleAudit.uncheckedContentWarning, in: html))
    }

    // An unsupported notule sentence is quoted; one generation, two audit calls, no retry.
    func testUnsupportedSentenceIsQuoted() async throws {
        let html = "<p>Sam neemt dinsdag telefonisch contact op. Iris mailt vrijdag de offerte.</p>"
        let service = StubLLM(draft: html, audit: StubLLM.approve { report in
            var notes = report["notes"] as! [[String: Any]]
            notes[1]["status"] = "unsupported"; notes[1]["evidence"] = [String]()
            report["notes"] = notes
        })
        let result = try await generate(service, "Sam belt dinsdag.")
        XCTAssertEqual(result, warnings("Dit staat in de notule, maar is misschien niet zo gezegd: “Iris mailt vrijdag de offerte.”", in: html))
        XCTAssertEqual(service.progressChunks, 1, "the stub streamed its draft")
        XCTAssertEqual(service.generations.count, 1)
        XCTAssertEqual(service.audits.count, 2)
    }

    // "never labels a protected source condition non-factual to approve its omission": still flagged.
    func testProtectedConstraintCannotBeWavedThrough() async throws {
        let html = "<p>Sam neemt vrijdag contact op.</p>"
        let service = StubLLM(draft: html, audit: StubLLM.approve { report in
            var source = report["source"] as! [[String: Any]]
            source[0]["status"] = "non_factual"; source[0]["evidence"] = [String]()
            report["source"] = source
            report["notes"] = (report["notes"] as! [[String: Any]]).map { var note = $0; note["evidence"] = ["T2"]; return note }
        })
        let result = try await generate(service, "Er is geen besluit genomen. Sam belt vrijdag.")
        XCTAssertEqual(result, warnings(NotuleAudit.uncheckedContentWarning, in: html))
    }

    func testSystemPromptAndConstraintsReachTheModel() async throws {
        let raw = "Sam belt vrijdag. Er gaan geen klantgegevens naar leveranciers. We besluiten dit niet vandaag."
        let service = StubLLM(draft: "<p>Sam belt vrijdag; er gaan geen klantgegevens naar leveranciers en er is vandaag niet besloten.</p>")
        _ = try await generate(service, raw, quickNote: "Bel Sam", participants: [Participant(name: "Fatima")])
        let call = try XCTUnwrap(service.generations.first)
        XCTAssertEqual(call.systemPrompt, notuleSystemPrompt("Je bent notulist."))
        XCTAssertEqual(call.constraints, ["Er gaan geen klantgegevens naar leveranciers.", "We besluiten dit niet vandaag."])
        XCTAssertTrue(call.notulePrompt.contains("Bel Sam"))
        XCTAssertTrue(call.notulePrompt.contains("- Fatima"))
        let content = buildNotuleUserContent(notulePrompt: call.notulePrompt, transcription: call.transcription,
                                             outputTemplate: nil, constraints: call.constraints)
        XCTAssertTrue(content.hasSuffix("\n2. We besluiten dit niet vandaag."))
    }

    func testEmptyDraftIsRejectedBeforeTheAudit() async {
        let service = StubLLM(draft: "  \n ")
        do {
            _ = try await generate(service, "Sam belt vrijdag.")
            XCTFail("Expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("De notule-generator gaf een leeg concept. De transcriptie is bewaard."))
        }
        // Only the source check, which runs alongside the draft, may have been sent; never the content audit.
        XCTAssertTrue(service.audits.allSatisfy { $0.hasPrefix("Broncontrole") }, "\(service.audits)")
    }

    /// A long quick note used to make an empty notule look usable once its section was added.
    func testUsabilityCheckRunsBeforeNotesSectionIsAdded() async {
        let service = StubLLM(draft: "<p>Ok.</p>")
        do {
            _ = try await generate(service, "Sam belt vrijdag.", quickNote: String(repeating: "Offerte nalopen met Sam. ", count: 4))
            XCTFail("Expected an unusable notule")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw."))
        }
        // Only the source check, which runs alongside the draft, may have been sent; never the content audit.
        XCTAssertTrue(service.audits.allSatisfy { $0.hasPrefix("Broncontrole") }, "\(service.audits)")
    }

    func testBracketTextIsNoLongerRejected() {
        XCTAssertTrue(NotuleGenerator.hasUsableNotule("<p>De planning is besproken [onverstaanbaar] en daarna goedgekeurd.</p>"))
    }

    // notuleValidation.test.ts "rejects empty HTML, a copied template, and a missing-transcript response"
    func testUnusableNotules() {
        XCTAssertFalse(NotuleGenerator.hasUsableNotule("<style>h1{color:red}</style><div>...</div>"))
        XCTAssertFalse(NotuleGenerator.hasUsableNotule("<h1>[Beschrijvende titel]</h1><p>[Samenvatting]</p>"))
        XCTAssertFalse(NotuleGenerator.hasUsableNotule("<p>Er is geen transcriptie aangeleverd. Lever die eerst aan.</p>"))
        XCTAssertTrue(NotuleGenerator.hasUsableNotule("<h2>Kernuitkomst</h2><p>De planning voor volgende week is besproken.</p>"))
    }

    func testSourceCheckRunsWhileTheDraftIsWritten() async throws {
        let service = OverlapLLM()
        let html = try await NotuleGenerator(service: service).generate(
            transcription: "Sam belt vrijdag de klant.", profile: profile, participants: [], quickNote: nil,
            createdAt: Date(timeIntervalSince1970: 0), corrections: [])
        XCTAssertEqual(html, "<p>Sam neemt vrijdag contact op met de klant.</p>")
        XCTAssertTrue(service.startedDuringDraft)
    }

    func testFailedDraftWinsAndCancelsTheSourceCheck() async {
        let service = OverlapLLM(draftError: LLMError.generationFailed("concept mislukt"))
        let start = Date()
        do {
            _ = try await NotuleGenerator(service: service).generate(
                transcription: "Sam belt vrijdag de klant.", profile: profile, participants: [], quickNote: nil,
                createdAt: Date(timeIntervalSince1970: 0), corrections: [])
            XCTFail("Expected the draft error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Generatie mislukt: concept mislukt")
        }
        XCTAssertTrue(service.sourceCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4, "the source request must be cancelled, not awaited")
    }

    func testCancellationIsNotAReviewError() async {
        let service = StubLLM(draft: "<p>Sam neemt vrijdag contact op.</p>", audit: { _ in throw CancellationError() })
        do {
            _ = try await generate(service, "Sam belt vrijdag.")
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }

    func testCancelledTaskIsNotAReviewError() async {
        let service = StubLLM(draft: "<p>Sam neemt vrijdag contact op.</p>", audit: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw URLError(.cancelled)
        })
        do {
            _ = try await generate(service, "Sam belt vrijdag.")
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }
}

// MARK: - Rejected drafts in the local store

@MainActor
final class RejectedDraftStoreTests: XCTestCase {
    private func makeStore(notuleHtml: String = "") throws -> LocalTranscriptStore {
        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LocalTranscriptStore(container: container)
        try store.save(TranscriptRecord(id: "t1", taskId: "t1", title: "Overleg", rawTranscription: "Sam belt vrijdag.", notuleHtml: notuleHtml))
        return store
    }

    func testRejectedDraftIsStoredSeparately() throws {
        let store = try makeStore()
        try store.saveRejectedDraft(taskId: "t1", html: "<p>Concept</p>", reason: "Reden")
        let record = try XCTUnwrap(store.record(forTaskId: "t1"))
        XCTAssertEqual(record.notuleHtml, "")
        XCTAssertEqual(record.notuleDraftHtml, "<p>Concept</p>")
        XCTAssertEqual(record.notuleReviewReason, "Reden")
    }

    func testFinalizeClearsDraft() throws {
        let store = try makeStore()
        try store.saveRejectedDraft(taskId: "t1", html: "<p>Concept</p>", reason: "Reden")
        try store.finalizeNotule(taskId: "t1", html: "<p>Goedgekeurd</p>", title: "Overleg")
        let record = try XCTUnwrap(store.record(forTaskId: "t1"))
        XCTAssertEqual(record.notuleHtml, "<p>Goedgekeurd</p>")
        XCTAssertNil(record.notuleDraftHtml)
        XCTAssertNil(record.notuleReviewReason)
    }

    func testRejectedRegenerationKeepsApprovedNotule() throws {
        let store = try makeStore(notuleHtml: "<p>Eerder goedgekeurd</p>")
        try store.saveRejectedDraft(taskId: "t1", html: "<p>Nieuw concept</p>", reason: "Reden")
        let record = try XCTUnwrap(store.record(forTaskId: "t1"))
        XCTAssertEqual(record.notuleHtml, "<p>Eerder goedgekeurd</p>")
        XCTAssertEqual(record.notuleDraftHtml, "<p>Nieuw concept</p>")
    }

    func testRejectedDraftForUnknownRecordThrows() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.saveRejectedDraft(taskId: "onbekend", html: "<p>x</p>", reason: "r"))
    }
}

final class NotuleFallbackTests: XCTestCase {
    private struct Down: Error {}

    func testFallbackDeliversWhenPrimaryFails() async throws {
        let html = try await NotuleGenerator.withFallback({ "<p>terugval</p>" }) { throw Down() }
        XCTAssertEqual(html, "<p>terugval</p>")
    }

    func testWithoutFallbackOriginalErrorSurfaces() async {
        do {
            _ = try await NotuleGenerator.withFallback(nil) { throw Down() }
            XCTFail("expected the primary error")
        } catch {
            XCTAssertTrue(error is Down)
        }
    }

    func testRejectedDraftAndCancellationSkipFallback() async {
        for thrown: Error in [NotuleReviewError(reason: "r", draftHtml: "<p>x</p>"), CancellationError()] {
            do {
                _ = try await NotuleGenerator.withFallback({ XCTFail("fallback ran"); return "" }) { throw thrown }
                XCTFail("expected an error")
            } catch {
                XCTAssertEqual(String(describing: type(of: error)), String(describing: type(of: thrown)))
            }
        }
    }
}

final class NotuleFallbackProviderTests: XCTestCase {
    private let key = NotuleGenerator.fallbackProviderKey
    private var originalValue: Any?

    override func setUp() {
        super.setUp()
        originalValue = UserDefaults.standard.object(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.set(originalValue, forKey: key)
        super.tearDown()
    }

    func testFallbackGuards() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNil(NotuleGenerator.fallbackProvider(for: .ollama), "unset means no fallback")
        UserDefaults.standard.set(NotulenProvider.ollama.rawValue, forKey: key)
        XCTAssertNil(NotuleGenerator.fallbackProvider(for: .ollama), "same as primary")
        UserDefaults.standard.set(NotulenProvider.cloud.rawValue, forKey: key)
        XCTAssertNil(NotuleGenerator.fallbackProvider(for: .ollama), "cloud is never a local fallback")
        UserDefaults.standard.set(NotulenProvider.anthropic.rawValue, forKey: key)
        XCTAssertEqual(NotuleGenerator.fallbackProvider(for: .ollama), .anthropic)
    }

    func testOfferResultDecodesServerShape() throws {
        let json = #"{"offer_id":5,"number":"20261110-1","url":"/offers/5/build","klant":{"id":3,"naam":"X","nieuw":true},"regels":3,"te_controleren":2,"bestaand":false,"model":"hoofd","terugval_gebruikt":true}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let r = try decoder.decode(ProspectFlowService.OfferResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.offerId, 5)
        XCTAssertEqual(r.teControleren, 2)
        XCTAssertTrue(r.terugvalGebruikt)
        XCTAssertEqual(r.klant.naam, "X")
    }

}

final class ProspectFlowReferenceTests: XCTestCase {
    func testOfferBodyNamesTheColleague() {
        let suite = "ProspectFlowMaker-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(ProspectFlowService.makerEmail(defaults: defaults))
        defaults.set("  collega@example.com ", forKey: SupportIdentity.emailKey)
        XCTAssertEqual(ProspectFlowService.makerEmail(defaults: defaults), "collega@example.com")
    }

    func testOfferReferencesStayWithinConfiguredInstance() {
        let suiteName = "ProspectFlowTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let taskId = "instance-test-" + UUID().uuidString
        let first = "https://first.example.test"
        let second = "https://second.example.test"
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(first, forKey: ProspectFlowService.baseURLKey)
        let pending = ProspectFlowService.OfferRef(pendingRequestId: "pending-first", pendingCustomer: "id:12")
        ProspectFlowService.setOfferRef(pending, for: taskId, defaults: defaults)
        defaults.set(second, forKey: ProspectFlowService.baseURLKey)
        XCTAssertNil(ProspectFlowService.offerRef(for: taskId, defaults: defaults))
        ProspectFlowService.setOfferRef(.init(id: 42, number: "second", url: "/offers/42/build"), for: taskId, defaults: defaults)
        defaults.set(first + "/", forKey: ProspectFlowService.baseURLKey)
        XCTAssertEqual(ProspectFlowService.offerRef(for: taskId, defaults: defaults), pending)
        defaults.set(second, forKey: ProspectFlowService.baseURLKey)
        ProspectFlowService.setOfferRef(.init(id: 43), for: taskId, baseURL: first, defaults: defaults)
        XCTAssertEqual(ProspectFlowService.offerRef(for: taskId, defaults: defaults)?.id, 42)
        XCTAssertEqual(ProspectFlowService.offerRef(for: taskId, baseURL: first, defaults: defaults)?.id, 43)
    }

    func testLegacyReferencesOnlyBelongToYinga() throws {
        let suiteName = "ProspectFlowLegacyTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = ProspectFlowService.OfferRef(id: 3, url: "/offers/3/build")
        defaults.set(try JSONEncoder().encode(reference), forKey: "prospectFlowOffer-test")
        defaults.set("https://other.example.test", forKey: ProspectFlowService.baseURLKey)
        XCTAssertNil(ProspectFlowService.offerRef(for: "test", defaults: defaults))
        defaults.set(ProspectFlowService.defaultBaseURL, forKey: ProspectFlowService.baseURLKey)
        XCTAssertEqual(ProspectFlowService.offerRef(for: "test", defaults: defaults), reference)
        ProspectFlowService.setOfferRef(nil, for: "test", defaults: defaults)
        XCTAssertNil(ProspectFlowService.offerRef(for: "test", defaults: defaults))
    }
    func testPendingCustomerChoiceKeepsOriginalNewCustomerAfterReopening() {
        let ref = ProspectFlowService.OfferRef(pendingRequestId: "lost-reply", pendingCustomer: "new:nieuw bv", pendingNewCustomerName: "Nieuw BV")
        guard case .new(let name) = ref.pendingChoice else { return XCTFail("Pending choice lost") }
        XCTAssertEqual(name, "Nieuw BV")
        XCTAssertEqual(ProspectFlowService.Customer.new(name).key, ref.pendingCustomer)
        let legacy = ProspectFlowService.OfferRef(pendingRequestId: "legacy", pendingCustomer: "new:nieuw bv")
        XCTAssertEqual(legacy.pendingChoice?.key, "new:nieuw bv")
        let existing = ProspectFlowService.OfferRef(pendingRequestId: "existing", pendingCustomer: "id:12")
        XCTAssertEqual(existing.pendingChoice?.key, "id:12")
        XCTAssertNotEqual(existing.pendingChoice?.key, ref.pendingChoice?.key)
        XCTAssertNil(ProspectFlowService.OfferRef(pendingCustomer: "new:nieuw bv").pendingChoice)
        for key in ["new:", "new:  ", "id:0", "id:-1", "id:bad", "other"] {
            XCTAssertNil(ProspectFlowService.OfferRef(pendingRequestId: "invalid", pendingCustomer: key).pendingChoice)
        }
    }

    @MainActor
    func testOfferOpeningReportsRefusalAndInvalidURL() async {
        for url in [URL(string: "https://pf.example.test/offers/1/build"), nil] {
            let error: String? = await withCheckedContinuation { continuation in
                openProspectFlowOffer(url, using: OpenURLAction { _ in .discarded },
                                      onFailure: { continuation.resume(returning: $0) },
                                      onSuccess: { continuation.resume(returning: nil) })
            }
            XCTAssertNotNil(error)
        }
    }

    @MainActor
    func testOfferOpeningCompletesOnlyWhenBrowserAccepts() async {
        let opened: Bool = await withCheckedContinuation { continuation in
            openProspectFlowOffer(URL(string: "https://pf.example.test/offers/1/build"),
                                  using: OpenURLAction { _ in .handled },
                                  onFailure: { _ in continuation.resume(returning: false) },
                                  onSuccess: { continuation.resume(returning: true) })
        }
        XCTAssertTrue(opened)
    }

    func testOfferLinksCannotLeaveTheirInstance() {
        let service = ProspectFlowService(baseURL: "https://pf.example.test", apiKey: "fixture")
        XCTAssertEqual(service.openURL("/offers/1/build")?.absoluteString, "https://pf.example.test/offers/1/build")
        for path in ["@other.example.test/path", "//other.example.test/path", "https://other.example.test/path", "javascript:alert(1)"] {
            XCTAssertNil(service.openURL(path), path)
        }
    }

}
