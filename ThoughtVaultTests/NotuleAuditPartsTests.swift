import XCTest
@testable import ThoughtVault

// Long meetings (DEC-065): coverage per part, then one check per notule sentence.
// Same scenarios as windows/src/services/__tests__/notuleAuditParts.test.ts.

private typealias LongReport = [String: Any]

/// Records every model call and the highest number of calls running at once.
private actor LongRecorder {
    var calls: [(system: String, user: String)] = []
    var running = 0
    var peak = 0
    /// User messages in the order their requests finished.
    var ended: [String] = []
    func begin(_ system: String, _ user: String) { calls.append((system, user)); running += 1; peak = max(peak, running) }
    func end(_ user: String) { running -= 1; ended.append(user) }
    /// Requests of one kind; coverage requests in part order, since parts start side by side.
    func requests(_ kind: String) -> [(system: String, user: String)] {
        let matching = calls.filter { longKind($0.user) == kind }
        return kind == "coverage" ? matching.sorted { partNumber($0.user)! < partNumber($1.user)! } : matching
    }
}

/// The part number of a step-1 request ("Inhoudsaudit deel 2 van 3"), nil for other requests.
private func partNumber(_ user: String) -> Int? {
    longKind(user) == "coverage" ? Int(user.split(separator: " ")[2]) : nil
}

/// Answers on the units it receives, like `model()` in notuleAuditParts.test.ts.
private struct LongModel: Sendable {
    /// N-IDs that preserve a source unit in step 1; none means non_factual.
    var cover: @Sendable (_ id: String) -> [String] = { _ in [] }
    var coverage: @Sendable (_ firstId: String, _ report: inout LongReport) -> Void = { _, _ in }
    var note: @Sendable (_ id: String, _ report: inout LongReport) -> Void = { _, _ in }
    var uncited: @Sendable (_ report: inout LongReport) -> Void = { _ in }
    /// Replaces the whole reply, or throws.
    var reply: @Sendable (_ user: String) throws -> String? = { _ in nil }
    /// Time each request takes, by user message.
    var delay: @Sendable (_ user: String) -> UInt64 = { _ in 0 }
}

/// The first notule ID of a step-2 request, nil for other requests.
private func noteId(_ user: String) -> String? { longKind(user) == "note" ? longIds(longInput(user)["notes"]).first : nil }

private func longKind(_ user: String) -> String {
    user.hasPrefix("Inhoudsaudit deel") ? "coverage" : user.hasPrefix("Notulezin controleren") ? "note" : "uncited"
}

private func longInput(_ user: String) -> [String: Any] {
    let json = user[user.index(after: user.firstIndex(of: "\n")!)...]
    return try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

private func longUnits(_ value: Any?) -> [[String: String]] { value as? [[String: String]] ?? [] }
private func longIds(_ value: Any?) -> [String] { longUnits(value).map { $0["id"]! } }

private func editSource(_ report: inout LongReport, _ edit: (inout [[String: Any]]) -> Void) {
    var source = report["source"] as! [[String: Any]]
    edit(&source)
    report["source"] = source
}

private func longRequest(_ recorder: LongRecorder, _ model: LongModel) -> AuditRequest {
    { system, user in
        await recorder.begin(system, user)
        let delay = model.delay(user)
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        await recorder.end(user)
        if let replaced = try model.reply(user) { return replaced }
        let data = longInput(user)
        var report: LongReport = ["uncertain": false]
        switch longKind(user) {
        case "coverage":
            let ids = longIds(data["source"])
            report["source"] = ids.map { id -> [String: Any] in
                let evidence = model.cover(id)
                return ["id": id, "status": evidence.isEmpty ? "non_factual" : "covered", "evidence": evidence]
            }
            model.coverage(ids[0], &report)
        case "note":
            let id = longIds(data["notes"])[0]
            report["notes"] = [["id": id, "status": "supported", "evidence": longIds(data["evidence"])] as [String: Any]]
            model.note(id, &report)
        default:
            report["notes"] = longIds(data["notes"]).map { id -> [String: Any] in ["id": id, "status": "non_factual", "evidence": [String]()] }
            model.uncited(&report)
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
    }
}

private func points(_ count: Int) -> String { (1...count).map { "Punt \($0) is besproken." }.joined(separator: " ") }
private let longSource = points(400) + " Sam belt vrijdag de klant."
private let sam = "<p>Sam belt vrijdag de klant.</p>"

/// One verdict for one notule sentence, as step 2 returns it.
private func verdict(_ id: String, _ status: String, _ evidence: [String] = []) -> [[String: Any]] {
    [["id": id, "status": status, "evidence": evidence]]
}

final class NotuleAuditPartsTests: XCTestCase {
    private func audit(_ source: String, _ html: String, quickNote: String = "", _ recorder: LongRecorder, _ model: LongModel) async throws {
        try await NotuleAudit.auditNotule(source: source, html: html, quickNote: quickNote, request: longRequest(recorder, model))
    }

    private func rejection(_ body: () async throws -> Void) async -> (any Error)? {
        do { try await body(); return nil } catch { return error }
    }

    private func assertRejects(_ expected: String, line: UInt = #line, _ body: () async throws -> Void) async {
        let error = await rejection(body)
        XCTAssertNotNil(error, "Expected a rejection", line: line)
        if let error {
            XCTAssertTrue(error.localizedDescription.contains(expected), "\"\(error.localizedDescription)\" does not contain \"\(expected)\"", line: line)
        }
    }

    func testShortPathKeepsTheSingleUnchangedRequest() async throws {
        let recorder = LongRecorder()
        let request: AuditRequest = { system, user in
            await recorder.begin(system, user)
            return #"{"uncertain":false,"source":[{"id":"T1","status":"covered"}],"notes":[{"id":"N1","status":"supported","evidence":["T1"]}]}"#
        }
        try await NotuleAudit.auditNotule(source: "Sam belt vrijdag.", html: "<p>Sam belt vrijdag de klant.</p>", quickNote: "", request: request)
        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(calls[0].system.contains("lange meeting"))
        XCTAssertTrue(calls[0].user.hasPrefix("Inhoudsaudit (geen generatie):\n"))
    }

    func testLongMeetingRunsCoveragePerPartThenOneCheckPerCitedSentence() async throws {
        let recorder = LongRecorder()
        try await audit(longSource, sam, quickNote: "Klant bellen.", recorder, LongModel(cover: { $0 == "T401" || $0 == "Q1" ? ["N1"] : [] }))
        let all = await recorder.calls
        XCTAssertEqual(all.count, 3)
        let coverage = await recorder.requests("coverage")
        XCTAssertEqual(coverage[0].system, NotuleAudit.coverageSystem)
        XCTAssertTrue(coverage[0].user.hasPrefix("Inhoudsaudit deel 1 van 2 (geen generatie):\n"))
        // 400 units minus the notule and the quick note leaves 398 transcription sentences per part.
        XCTAssertEqual(longIds(longInput(coverage[0].user)["source"]), (1...398).map { "T\($0)" } + ["Q1"])
        XCTAssertEqual(longIds(longInput(coverage[1].user)["source"]), ["T399", "T400", "T401", "Q1"])
        for call in coverage {
            XCTAssertEqual(longUnits(longInput(call.user)["notes"]), [["id": "N1", "text": "Sam belt vrijdag de klant."]])
        }
        let note = await recorder.requests("note")
        XCTAssertEqual(note[0].system, NotuleAudit.noteSystem)
        let data = longInput(note[0].user)
        XCTAssertEqual(longUnits(data["notes"]), [["id": "N1", "text": "Sam belt vrijdag de klant."]])
        XCTAssertEqual(longUnits(data["evidence"]), [["id": "T401", "text": "Sam belt vrijdag de klant."], ["id": "Q1", "text": "Klant bellen."]])
        XCTAssertEqual(longUnits(data["context"]), [["id": "T398", "text": "Punt 398 is besproken."], ["id": "T399", "text": "Punt 399 is besproken."],
                                                    ["id": "T400", "text": "Punt 400 is besproken."]])
    }

    func testStepOneRequestsStayWithinTheCharacterBudget() async throws {
        let recorder = LongRecorder()
        let source = ["a", "b", "c"].map { String(repeating: $0, count: 39_999) + "." }.joined(separator: " ")
        // Three parts fit; the step-2 request with the cited sentence and its neighbours does not, so it is never sent.
        await assertRejects("te groot") {
            try await audit(source, "<p>Kort verslag.</p>", recorder, LongModel(cover: { $0 == "T2" ? ["N1"] : [] }))
        }
        let all = await recorder.calls
        XCTAssertEqual(all.count, 3)
        for call in await recorder.requests("coverage") {
            let data = longInput(call.user)
            XCTAssertEqual(longUnits(data["source"]).count, 1)
            let length = (longUnits(data["source"]) + longUnits(data["notes"])).reduce(0) { $0 + $1["text"]!.utf16.count }
            XCTAssertLessThanOrEqual(length, 64_000)
        }
    }

    func testExactlyMaxAuditPartsPassesAndOneMoreIsRejectedWithoutRequest() async throws {
        let model = LongModel(cover: { $0 == "T1" ? ["N1"] : [] })
        let recorder = LongRecorder()
        try await audit(points(399 * NotuleAudit.maxAuditParts), "<p>Punt 1 is besproken.</p>", recorder, model)
        let coverage = await recorder.requests("coverage"), note = await recorder.requests("note")
        XCTAssertEqual(coverage.count, NotuleAudit.maxAuditParts)
        XCTAssertEqual(note.count, 1)
        let more = LongRecorder()
        await assertRejects("te groot") {
            try await audit(points(399 * NotuleAudit.maxAuditParts + 1), "<p>Punt 1 is besproken.</p>", more, model)
        }
        let count = await more.calls.count
        XCTAssertEqual(count, 0)
    }

    func testMoreThanMaxNoteChecksIsRejectedWithoutRequest() async {
        let recorder = LongRecorder()
        let html = "<p>" + (1...NotuleAudit.maxNoteChecks + 1).map { "Besluit \($0) is genomen." }.joined(separator: " ") + "</p>"
        await assertRejects("te groot") { try await audit(points(300), html, recorder, LongModel()) }
        let count = await recorder.calls.count
        XCTAssertEqual(count, 0)
    }

    func testInvalidStepOneRepliesAreRejectedBeforeMerging() async {
        let changes: [(String, @Sendable (inout LongReport) -> Void)] = [
            ("an unknown id", { editSource(&$0) { $0[0]["id"] = "T999" } }),
            ("a missing id", { editSource(&$0) { $0.removeLast() } }),
            ("a duplicate id", { editSource(&$0) { $0[1]["id"] = $0[0]["id"] } }),
            ("evidence outside the notule", { editSource(&$0) { $0[0] = ["id": "T1", "status": "covered", "evidence": ["N9"]] } }),
            ("covered without evidence", { editSource(&$0) { $0[0] = ["id": "T1", "status": "covered", "evidence": [String]()] } }),
            ("missing with evidence", { editSource(&$0) { $0[0] = ["id": "T1", "status": "missing", "evidence": ["N1"]] } }),
        ]
        for (name, change) in changes {
            let recorder = LongRecorder()
            let error = await rejection {
                try await audit(longSource, sam, recorder, LongModel(cover: { $0 == "T401" ? ["N1"] : [] }, coverage: { _, report in change(&report) }))
            }
            XCTAssertNotNil(error, name)
            // Both parts run side by side; step 2 never starts.
            let count = await recorder.calls.count
            XCTAssertEqual(count, 2, name)
        }
    }

    func testUncertainPartRejectsAndStopsAsking() async {
        let recorder = LongRecorder()
        await assertRejects("De inhoudscontrole is onzeker; beoordeel het concept") {
            try await audit(longSource, sam, recorder, LongModel(coverage: { _, report in report["uncertain"] = true }))
        }
        // Both parts run side by side; step 2 never starts.
        let count = await recorder.calls.count
        XCTAssertEqual(count, 2)
    }

    func testCoveragePartsRunSideBySide() async throws {
        let recorder = LongRecorder()
        let model = LongModel(cover: { $0 == "T401" ? ["N1"] : [] }, delay: { partNumber($0) == 1 ? 300_000_000 : 0 })
        try await audit(longSource, sam, recorder, model)
        let ended = await recorder.ended.compactMap(partNumber)
        XCTAssertEqual(ended, [2, 1], "part 2 must not wait for the slow part 1")
    }

    func testMergedCoverageDoesNotDependOnWhichPartFinishesFirst() async throws {
        // Part 1 says the quick note is kept by N1, part 2 says by N2: both notule sentences must cite it.
        let html = "<p>Sam belt vrijdag de klant. Punt 1 is besproken.</p>"
        let coverQuickNote: @Sendable (String, inout LongReport) -> Void = { first, report in
            editSource(&report) { source in
                let index = source.firstIndex { ($0["id"] as? String) == "Q1" }!
                source[index] = ["id": "Q1", "status": "covered", "evidence": [first == "T1" ? "N1" : "N2"]]
            }
        }
        var stepTwo: [[String]] = []
        for slowPart in [1, 2] {
            let recorder = LongRecorder()
            let model = LongModel(cover: { $0 == "T401" ? ["N1"] : $0 == "T1" ? ["N2"] : [] }, coverage: coverQuickNote,
                                  delay: { partNumber($0) == slowPart ? 200_000_000 : 0 })
            try await audit(longSource, html, quickNote: "Klant bellen.", recorder, model)
            let notes = await recorder.requests("note").map(\.user).sorted()
            XCTAssertEqual(notes.map { longIds(longInput($0)["evidence"]) }, [["T401", "Q1"], ["T1", "Q1"]])
            stepTwo.append(notes)
        }
        XCTAssertEqual(stepTwo[0], stepTwo[1])
    }

    func testFirstFailingPartIsReportedAndLaterPartsDoNotStart() async {
        // Six parts. Part 1 is slow and uncertain, part 2 fails at once, parts 3 and 4 finish after part 2.
        let recorder = LongRecorder()
        let model = LongModel(coverage: { first, report in if first == "T1" { report["uncertain"] = true } },
                              reply: { partNumber($0) == 2 ? #"{"source":["# : nil },
                              delay: { user in
                                  switch partNumber(user) {
                                  case 1?: 300_000_000
                                  case 2?: 0
                                  default: 100_000_000
                                  }
                              })
        await assertRejects("De inhoudscontrole is onzeker; beoordeel het concept") {
            try await audit(points(399 * 6), "<p>Punt 1 is besproken.</p>", recorder, model)
        }
        let started = await recorder.requests("coverage").compactMap { partNumber($0.user) }
        XCTAssertEqual(started, [1, 2, 3, 4])
    }

    func testUnreadableJSONInPartTwoRejectsAfterTwoRequests() async {
        let recorder = LongRecorder()
        let model = LongModel(cover: { $0 == "T401" ? ["N1"] : [] }, reply: { $0.hasPrefix("Inhoudsaudit deel 2") ? #"{"source":["# : nil })
        await assertRejects("De inhoudscontrole leverde geen bruikbaar controlebewijs; beoordeel het concept") {
            try await audit(longSource, sam, recorder, model)
        }
        let count = await recorder.calls.count
        XCTAssertEqual(count, 2)
    }

    func testQuickNoteMissingOrUncertainInOnePartRejects() async {
        for (status, message) in [("missing", "De notule mist broninformatie: Klant bellen."), ("uncertain", "De bron is onvoldoende duidelijk: Klant bellen.")] {
            let recorder = LongRecorder()
            let model = LongModel(cover: { $0 == "T401" || $0 == "Q1" ? ["N1"] : [] }, coverage: { first, report in
                guard first != "T1" else { return }
                editSource(&report) { source in
                    let index = source.firstIndex { ($0["id"] as? String) == "Q1" }!
                    source[index] = ["id": "Q1", "status": status, "evidence": [String]()]
                }
            })
            await assertRejects(message) { try await audit(longSource, sam, quickNote: "Klant bellen.", recorder, model) }
            for call in await recorder.requests("coverage") { XCTAssertTrue(longIds(longInput(call.user)["source"]).contains("Q1")) }
        }
    }

    func testStepTwoProblemsRejectWithTheirFinding() async {
        let cases = [
            ("contradiction", "De notule spreekt de bron tegen: Sam belt vrijdag de klant.", "Dit klopt misschien niet met wat er is gezegd: “Sam belt vrijdag de klant.”"),
            ("unsupported", "De notule bevat een onbevestigde bewering: Sam belt vrijdag de klant.", "Dit staat in de notule, maar is misschien niet zo gezegd: “Sam belt vrijdag de klant.”"),
            ("uncertain", "De bewering is onvoldoende duidelijk: Sam belt vrijdag de klant.", "Dit is misschien niet helemaal goed samengevat: “Sam belt vrijdag de klant.”"),
        ]
        for (status, message, finding) in cases {
            let model = LongModel(cover: { $0 == "T401" ? ["N1"] : [] }, note: { _, report in report["notes"] = verdict("N1", status) })
            let error = await rejection { try await audit(longSource, sam, LongRecorder(), model) }
            XCTAssertEqual((error as? NotuleAuditError)?.message, message)
            XCTAssertEqual((error as? NotuleAuditError)?.finding, finding)
        }
    }

    func testUncertainSentenceIsNotOverruledBySupportForAnother() async {
        let model = LongModel(cover: { $0 == "T401" ? ["N1", "N2"] : [] }, note: { id, report in
            if id == "N1" { report["notes"] = verdict("N1", "uncertain") }
        })
        await assertRejects("De bewering is onvoldoende duidelijk: Sam belt de klant.") {
            try await audit(longSource, "<p>Sam belt de klant. Sam belt vrijdag de klant.</p>", LongRecorder(), model)
        }
    }

    func testUncitedSentencesShareOneRequestWithoutEvidence() async throws {
        let recorder = LongRecorder()
        try await audit(longSource, "<h2>Verslag</h2><p>Sam belt vrijdag de klant.</p>", recorder, LongModel(cover: { $0 == "T401" ? ["N2"] : [] }))
        let uncited = await recorder.requests("uncited")
        XCTAssertEqual(uncited.count, 1)
        XCTAssertEqual(uncited[0].system, NotuleAudit.uncitedSystem)
        let data = longInput(uncited[0].user)
        XCTAssertEqual(Array(data.keys), ["notes"])
        XCTAssertEqual(longUnits(data["notes"]), [["id": "N1", "text": "Verslag"]])
        let invented = LongModel(cover: { $0 == "T401" ? ["N2"] : [] }, uncited: { report in report["notes"] = verdict("N1", "unsupported") })
        await assertRejects("De notule bevat een onbevestigde bewering: Joris betaalt de rekening.") {
            try await audit(longSource, "<p>Joris betaalt de rekening.</p><p>Sam belt vrijdag de klant.</p>", LongRecorder(), invented)
        }
    }

    func testSupportFromContextOnlyIsRejected() async {
        let model = LongModel(cover: { $0 == "T401" ? ["N1"] : [] }, note: { _, report in report["notes"] = verdict("N1", "supported", ["T400"]) })
        await assertRejects("Ongeldig controlebewijs") { try await audit(longSource, sam, LongRecorder(), model) }
    }

    func testQualificationAcrossPartBoundaryIsSentAsContext() async throws {
        let source = String(repeating: "Hallo allemaal. ", count: 398)
            + "De volgende opdracht is alleen een fictief voorbeeld. Sam deelt vrijdag het klantbestand."
        let html = "<p>Actie: Sam deelt vrijdag het klantbestand.</p>"
        let cover: @Sendable (String) -> [String] = { $0 == "T400" ? ["N1"] : [] }
        let recorder = LongRecorder()
        try await audit(source, html, recorder, LongModel(cover: cover))
        let coverage = await recorder.requests("coverage")
        XCTAssertEqual(longUnits(longInput(coverage[0].user)["source"]).last, ["id": "T399", "text": "De volgende opdracht is alleen een fictief voorbeeld."])
        XCTAssertEqual(longUnits(longInput(coverage[1].user)["source"]), [["id": "T400", "text": "Sam deelt vrijdag het klantbestand."]])
        let notes = await recorder.requests("note")
        let check = longInput(notes[0].user)
        XCTAssertEqual(longIds(check["evidence"]), ["T400"])
        XCTAssertTrue(longUnits(check["context"]).contains(["id": "T399", "text": "De volgende opdracht is alleen een fictief voorbeeld."]))
        for (status, reason) in [("contradiction", "De notule spreekt de bron tegen"), ("unsupported", "De notule bevat een onbevestigde bewering")] {
            let strict = LongModel(cover: cover, note: { _, report in report["notes"] = verdict("N1", status) })
            await assertRejects("\(reason): Actie: Sam deelt vrijdag het klantbestand.") { try await audit(source, html, LongRecorder(), strict) }
        }
    }

    func testInventedDeadlineIsRejected() async {
        let recorder = LongRecorder()
        let model = LongModel(cover: { $0 == "T401" ? ["N1"] : [] }, note: { _, report in report["notes"] = verdict("N1", "unsupported") })
        await assertRejects("De notule bevat een onbevestigde bewering: Sam deelt vrijdag het klantbestand.") {
            try await audit(points(400) + " Sam deelt het klantbestand.", "<p>Sam deelt vrijdag het klantbestand.</p>", recorder, model)
        }
        let note = await recorder.requests("note")
        XCTAssertEqual(longUnits(longInput(note[0].user)["evidence"]), [["id": "T401", "text": "Sam deelt het klantbestand."]])
    }

    // Ten notule sentences, each preserving its own source sentence T391 to T400.
    private let tenSource = points(401)
    private let tenHtml = "<p>" + (391...400).map { "Punt \($0) is besproken." }.joined(separator: " ") + "</p>"
    private let tenCover: @Sendable (String) -> [String] = { id in
        guard id.hasPrefix("T"), let number = Int(id.dropFirst()), (391...400).contains(number) else { return [] }
        return ["N\(number - 390)"]
    }

    func testFailedStepTwoRequestStartsNoNewRequests() async {
        struct Offline: Error {}
        let recorder = LongRecorder()
        // N1 fails before the others finish, so no completion can start a fifth check first.
        let model = LongModel(cover: tenCover, reply: { user in
            if noteId(user) == "N1" { throw Offline() }
            return nil
        }, delay: { user in noteId(user).map { $0 == "N1" ? 0 : 50_000_000 } ?? 0 })
        await assertRejects("De inhoudscontrole leverde geen bruikbaar controlebewijs; beoordeel het concept") {
            try await audit(tenSource, tenHtml, recorder, model)
        }
        // Two coverage parts, then only the first window.
        let count = await recorder.calls.count
        XCTAssertEqual(count, 2 + NotuleAudit.auditConcurrency)
    }

    func testSlowFirstCheckDoesNotHoldBackTheOthers() async throws {
        let slowFirst: @Sendable (String) -> UInt64 = { user in noteId(user) == "N1" ? 300_000_000 : 0 }
        let recorder = LongRecorder()
        try await audit(tenSource, tenHtml, recorder, LongModel(cover: tenCover, delay: slowFirst))
        let ended = await recorder.ended.compactMap(noteId), peak = await recorder.peak
        XCTAssertEqual(ended.count, 10)
        XCTAssertEqual(ended.last, "N1", "\(ended)")
        XCTAssertLessThanOrEqual(peak, NotuleAudit.auditConcurrency)

        // Outcomes are still read in order and a failure starts nothing new: the fast N2 fails first,
        // N3 and N4 finish after it without starting N5, and the slow N1 is the problem reported.
        let failing = LongModel(cover: tenCover, note: { id, report in
            if id == "N1" { report["notes"] = verdict("N1", "unsupported") }
            if id == "N2" { report["notes"] = verdict("N2", "contradiction") }
        }, delay: { user in
            switch noteId(user) {
            case "N1"?: 300_000_000
            case "N2"?, nil: 0
            default: 100_000_000
            }
        })
        let second = LongRecorder()
        await assertRejects("De notule bevat een onbevestigde bewering: Punt 391 is besproken.") {
            try await audit(tenSource, tenHtml, second, failing)
        }
        let notes = await second.requests("note").count
        XCTAssertEqual(notes, NotuleAudit.auditConcurrency)
    }

    func testCancellationIsPassedOn() async {
        let model = LongModel(cover: tenCover, reply: { user in
            if longKind(user) == "note" { throw CancellationError() }
            return nil
        })
        let error = await rejection { try await audit(tenSource, tenHtml, LongRecorder(), model) }
        XCTAssertTrue(error is CancellationError, "\(String(describing: error))")
    }

    func testAtMostFourRequestsRunAtOnce() async throws {
        let recorder = LongRecorder()
        try await audit(tenSource, tenHtml, recorder, LongModel(cover: tenCover, delay: { _ in 20_000_000 }))
        let note = await recorder.requests("note"), peak = await recorder.peak
        XCTAssertEqual(note.count, 10)
        XCTAssertLessThanOrEqual(peak, NotuleAudit.auditConcurrency)
        XCTAssertGreaterThan(peak, 1)
    }

    func testContradictionInLaterPartIsReportedAsContradiction() async {
        let model = LongModel(cover: { $0 == "T1" ? ["N1"] : $0 == "T401" ? ["N2"] : [] }, note: { id, report in
            if id == "N2" { report["notes"] = verdict("N2", "contradiction") }
        })
        await assertRejects("De notule spreekt de bron tegen: Sam belt maandag de klant.") {
            try await audit(longSource, "<p>Punt 1 is besproken. Sam belt maandag de klant.</p>", LongRecorder(), model)
        }
    }
}
