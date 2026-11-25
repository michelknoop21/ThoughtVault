import { beforeEach, describe, expect, it, vi } from "vitest";
import fixture from "../../../../tests/fixtures/notule-detail/draft-volledig.json";
import { LLMService } from "../llm";
import { auditNotule, constraintSentences, essentialConstraints } from "../notuleAudit";
import { AUDIT_SUFFIX_TEXT, draftBlock, dutchNumber, effectiveDetailLevel, maximumLength, storedDetailLevel, targetLength } from "../notuleDetailLevel";
import { enrichProfile } from "../profileTemplates";
import { UsageMeter } from "../usageMeter";
import { useSettingsStore } from "../../stores/settingsStore";
import { sourceFixture, auditFixture } from "./notuleAuditFixtures";
import { DEFAULT_PROFILES, DEFAULT_SETTINGS } from "../../types";

// Mirrors ThoughtVaultTests/NotuleDetailLevelTests.swift and NotuleGeneratorDetailLevelTests.
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => args[0] === "log_write" ? Promise.resolve() : invoke(...args) }));
vi.mock("../tauriCommands", () => ({ loadCredential: async () => "fixture-key" }));
vi.mock("../../stores/personalCorrectionsStore", () => ({ usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) }, loadCorrectionsOrEmpty: async () => [] }));

describe("target length", () => {
  it("clamps, rounds to hundreds and formats Dutch style", () => {
    expect(targetLength("volledig", 40_000)).toBeNull();
    expect([10_000, 40_000, 100_000].map(t => targetLength("kort", t))).toEqual([1500, 2400, 4000]);
    expect([10_000, 40_000, 100_000].map(t => targetLength("normaal", t))).toEqual([2500, 6000, 8000]);
    expect([40_833, 40_834].map(t => targetLength("kort", t))).toEqual([2400, 2500]);
    expect(targetLength("normaal", 33_333)).toBe(5000);
    expect([2400, 1500, 8000].map(maximumLength)).toEqual([3100, 2000, 10_400]);
    expect([999, 2400, 10_400, 1_000_050].map(dutchNumber)).toEqual(["999", "2.400", "10.400", "1.000.050"]);
  });

  it("appends the kort and normaal blocks verbatim and nothing at volledig", () => {
    expect(draftBlock("volledig", 40_000)).toBe("");
    expect(draftBlock("kort", 40_000)).toBe("\n\nDetailniveau Kort: schrijf een beknopte notule van ongeveer 2.400 tekens, hooguit 3.100. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Laat bijzaken, achtergrond, voorbeelden, anekdotes, herhalingen en zijpaden weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau en de secties van het profiel; laat secties weg die alleen bijzaken zouden bevatten.");
    expect(draftBlock("normaal", 40_000)).toBe("\n\nDetailniveau Normaal: schrijf een notule van ongeveer 6.000 tekens, hooguit 7.800. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Geef per hoofdonderwerp in één of twee zinnen de context. Laat zijpaden, anekdotes, herhalingen en details zonder gevolg voor een besluit of actie weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau van het profiel.");
  });
});

it("keeps only anchored constraints as essential", () => {
  const text = "Er gaan geen klantgegevens naar leveranciers. Het budget wordt niet hoger dan 12.450 euro. Dit mag niet zonder Bram. De oude afspraak vervalt. We doen niets met de folder.";
  expect(constraintSentences(text)).toHaveLength(5);
  expect(essentialConstraints(text)).toEqual(["Het budget wordt niet hoger dan 12.450 euro.", "Dit mag niet zonder Bram.", "De oude afspraak vervalt."]);
});

describe("effective level", () => {
  it("prefers the user's choice, then the profile default, then volledig", () => {
    const executive = enrichProfile({ id: "executive", name: "Executive" });
    const custom = { id: "eigen", name: "Eigen" };
    expect(effectiveDetailLevel(executive)).toBe("kort");
    expect(effectiveDetailLevel(custom)).toBe("volledig");
    expect(effectiveDetailLevel(executive, { executive: "normaal" })).toBe("normaal");
    expect(effectiveDetailLevel(custom, { eigen: "kort" })).toBe("kort");
    expect(effectiveDetailLevel(custom, { eigen: "lang" })).toBe("volledig");
    expect(DEFAULT_SETTINGS.profile_detail_levels).toEqual({});
  });

  it("gives the bundled profiles their default", () => {
    expect(Object.fromEntries(DEFAULT_PROFILES.map(p => [p.id, p.detail_level]))).toEqual({
      standaard: "normaal", executive: "kort", projectoverleg: "volledig", klantgesprek: "normaal",
      een_op_een: "kort", brainstorm: "normaal", promptnotitie: undefined,
    });
  });

  it("starts a regeneration from the stored level of the same profile", () => {
    expect(storedDetailLevel({ profile_id: "standaard", detail_level: "kort" }, "standaard")).toBe("kort");
    expect(storedDetailLevel({ profile_id: "standaard", detail_level: "kort" }, "executive")).toBeUndefined();
    expect(storedDetailLevel({ profile_id: "standaard", notule_usage: { detail_level: "normaal" } as never }, "standaard")).toBe("normaal");
    expect(storedDetailLevel({ profile_id: "standaard" }, "standaard")).toBeUndefined();
  });
});

describe("audit with minor", () => {
  const source = "Sam belt vrijdag de klant. We hadden het nog even over het weer.";
  const html = "<p>Sam belt vrijdag de klant.</p>";
  // Covers T1 with N1 and marks `minorId` minor; `noteEvidence` is what N1 cites.
  const request = (minorId: string, noteEvidence = ["T1"]) => vi.fn(async (_system: string, user: string) => {
    const input = JSON.parse(user.split("\n").slice(1).join("\n")) as { source: { id: string }[] };
    return JSON.stringify({
      uncertain: false,
      source: input.source.map(s => ({ id: s.id, status: s.id === minorId ? "minor" : "covered" })),
      notes: [{ id: "N1", status: "supported", evidence: noteEvidence }],
    });
  });

  it("accepts minor at kort and normaal for a plain transcription sentence", async () => {
    const kort = request("T2");
    await expect(auditNotule(source, html, "", kort, [], false, undefined, undefined, "kort")).resolves.toBeUndefined();
    expect(kort.mock.calls[0][0].endsWith("\n" + AUDIT_SUFFIX_TEXT)).toBe(true);
    await expect(auditNotule(source, html, "", request("T2"), [], false, undefined, undefined, "normaal")).resolves.toBeUndefined();
  });

  it("rejects minor at volledig like an unknown status", async () => {
    const volledig = request("T2");
    await expect(auditNotule(source, html, "", volledig)).rejects.toThrow("Ongeldig controlebewijs");
    expect(volledig.mock.calls[0][0]).not.toContain(AUDIT_SUFFIX_TEXT);
  });

  it("rejects minor on a quick note, a required sentence and an amount", async () => {
    await expect(auditNotule("Sam belt vrijdag de klant.", html, "Bel ook over de planning.", request("Q1"), [], false, undefined, undefined, "kort"))
      .rejects.toThrow("De notule mist broninformatie: Bel ook over de planning.");
    await expect(auditNotule(source, html, "", request("T2"), ["We hadden het nog even over het weer."], false, undefined, undefined, "kort"))
      .rejects.toThrow("De notule mist broninformatie: We hadden het nog even over het weer.");
    for (const sentence of ["De lunch kostte 12 euro.", "De korting was 5 %.", "Het kost € 40 per maand.", "Dat is 3 procent meer."]) {
      await expect(auditNotule(`Sam belt vrijdag de klant. ${sentence}`, html, "", request("T2"), [], false, undefined, undefined, "kort"))
        .rejects.toThrow(`De notule mist broninformatie: ${sentence}`);
    }
  });

  it("rejects minor with evidence", async () => {
    await expect(auditNotule(source, html, "", request("T2", ["T1", "T2"]), [], false, undefined, undefined, "kort"))
      .rejects.toThrow("Ongeldig controlebewijs");
  });
});

describe("generateNotulen", () => {
  // `fixture`: the volledig draft of this code (draft-volledig.json), re-recorded for DEC-082.
  const html = "<p>Sam belt vrijdag de klant over de planning en het budget wordt 12.450 euro.</p>";
  const drafts: { system: string; user: string }[] = [];

  beforeEach(() => {
    vi.resetAllMocks();
    drafts.length = 0;
    useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama", ollama_url: "http://localhost:11434", ollama_model: "fixture" });
    invoke.mockImplementation(async (_command, args) => {
      const messages = JSON.parse(args.request.body).messages;
      const user = messages.at(-1).content;
      const content = user.startsWith("Broncontrole") ? sourceFixture(user) : user.startsWith("Inhoudsaudit") ? auditFixture(user)
        : (drafts.push({ system: messages[0].content, user }), html);
      return { status: 200, body: JSON.stringify({ choices: [{ message: { content } }] }) };
    });
  });

  it("sends the recorded draft at the default and at volledig", async () => {
    const meter = new UsageMeter();
    await LLMService.generateNotulen(fixture.transcription, fixture.profile, undefined, [], "", undefined, meter);
    await LLMService.generateNotulen(fixture.transcription, fixture.profile, undefined, [], "", undefined, undefined, false, undefined, "volledig");
    expect(drafts).toEqual([{ system: fixture.system, user: fixture.user }, { system: fixture.system, user: fixture.user }]);
    expect(meter.usageFor(fixture.transcription, html).detail_level).toBe("volledig");
  });

  it("appends the kort block after the essential constraints and records the level", async () => {
    const meter = new UsageMeter();
    await LLMService.generateNotulen(fixture.transcription, fixture.profile, undefined, [], "", undefined, meter, false, undefined, "kort");
    const block = draftBlock("kort", fixture.transcription.length);
    expect(block).toContain("ongeveer 1.500 tekens, hooguit 2.000.");
    const base = fixture.user.slice(0, fixture.user.indexOf("\n\nUitspraken uit de transcriptie"));
    expect(drafts[0].user).toBe(base + "\n\nUitspraken uit de transcriptie met een getal, besluit of voorwaarde. Neem de betekenis van elke uitspraak op bij het passende onderwerp, in je eigen woorden, met de genoemde bedragen en voorwaarden. Citeer ze niet en spreek ze nergens tegen. Is een uitspraak onverstaanbaar, neem haar dan niet over:\n1. De vorige afspraak vervalt." + block);
    expect(meter.usageFor(fixture.transcription, html).detail_level).toBe("kort");
  });
});
