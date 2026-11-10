import XCTest
@testable import ThoughtVault

final class NotulePromptTests: XCTestCase {
    private let rules = NotuleAudit.factualityRules

    func testSystemPromptStartsWithSourceFidelity() {
        XCTAssertEqual(
            notuleSystemPrompt("P"),
            "P\n\nBrongetrouwheid gaat vóór beknoptheid en de template. " + rules + " Vermeld ieder expliciet vervallen tijdstip en iedere expliciete afwezigheid, ook als dat geen actie is. Als ergens geen besluit over uitvoering is genomen, behoud dat letterlijk als onbeslist; vraag niet hoe het uitgevoerd moet worden."
        )
    }

    func testUserContentEndsWithFactualityRules() {
        let content = buildNotuleUserContent(notulePrompt: "Maak notulen", transcription: "tekst", outputTemplate: nil)
        XCTAssertTrue(content.hasSuffix("Verzin geen feiten, besluiten, eigenaren of termijnen. " + rules + " Schrijf eenvoudige HTML zonder CSS, style-blok of code fences."))
        let placeholder = buildNotuleUserContent(notulePrompt: "{{TRANSCRIPTION}}", transcription: "tekst", outputTemplate: nil)
        XCTAssertTrue(placeholder.contains(rules))
    }

    func testConstraintBlockAppendedOnlyWhenPresent() {
        let without = buildNotuleUserContent(notulePrompt: "P", transcription: "t", outputTemplate: nil)
        XCTAssertFalse(without.contains("Verplicht te behouden bronzinnen"))
        let with = buildNotuleUserContent(notulePrompt: "P", transcription: "t", outputTemplate: nil, constraints: ["Budget is 12.450 euro.", "Geen klantgegevens extern."])
        XCTAssertTrue(with.hasSuffix("\n\nVerplicht te behouden bronzinnen (behoud de volledige betekenis, bedragen en voorwaarden bij het passende onderwerp, besluit of open punt; correcte parafrases mogen, tegenspraken nergens):\n1. Budget is 12.450 euro.\n2. Geen klantgegevens extern."))
    }

    func testUserContentKeepsFullTranscriptAndTemplate() {
        let raw = "Het budget is 12.450 euro inclusief btw, niet 15.000 euro."
        let content = buildNotuleUserContent(notulePrompt: "P", transcription: raw, outputTemplate: "<h2>Besluiten</h2>")
        XCTAssertTrue(content.contains(raw))
        XCTAssertTrue(content.contains("<h2>Besluiten</h2>"))
    }

    func testChunkSummaryMustShrink() async {
        let service = OpenAICompatibleLLMService(baseURL: "http://localhost:1", model: "m", maxChunkCharacters: 100)
        service.completionOverride = { _, user in String(user.dropFirst("Vat dit deel compact samen:\n\n".count)) }
        do {
            _ = try await service.summarizeInChunks(String(repeating: "a", count: 250))
            XCTFail("expected failure")
        } catch {
            guard case LLMError.generationFailed(let message) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(message, "De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw.")
        }
    }

    func testChunkPromptCarriesFactualityRules() async throws {
        let service = OpenAICompatibleLLMService(baseURL: "http://localhost:1", model: "m", maxChunkCharacters: 100)
        let seen = Recorder()
        service.completionOverride = { system, user in
            await seen.add(system, user)
            return "kort"
        }
        _ = try await service.summarizeInChunks(String(repeating: "a", count: 250))
        let systems = await seen.systems
        XCTAssertEqual(systems.first, "Je vat transcripties samen. Bewaar namen, feiten, besluiten, actiepunten, eigenaren en termijnen. Verzin niets. " + rules)
        let users = await seen.users
        XCTAssertTrue(users.first?.hasPrefix("Vat dit deel compact samen:\n\n") == true)
    }

    func testChunkingRepeatsUntilUnderLimit() async throws {
        let service = OpenAICompatibleLLMService(baseURL: "http://localhost:1", model: "m", maxChunkCharacters: 100)
        let seen = Recorder()
        service.completionOverride = { _, user in
            await seen.add("", user)
            let body = String(user.dropFirst("Vat dit deel compact samen:\n\n".count))
            return String(body.prefix(body.count / 2))
        }
        let result = try await service.summarizeInChunks(String(repeating: "a", count: 1000))
        XCTAssertLessThanOrEqual(result.count, 100)
        let calls = await seen.users.count
        XCTAssertGreaterThan(calls, 10)  // more than one pass over 100-char chunks
    }
}

private actor Recorder {
    var systems: [String] = []
    var users: [String] = []
    func add(_ s: String, _ u: String) { systems.append(s); users.append(u) }
}
