import { expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/core", async () => (await import("./fakeAppData")).tauriCore);
import { files } from "./fakeAppData";
import { correctText, correctHTML, upsertCorrection, validateCorrections, contextBlock, type PersonalCorrection, type PersonContext } from "../personalCorrections";
const rule: PersonalCorrection = { id:"yinga",canonical:"Yinga",variants:["Jengo","Django"],scope:null,enabled:true };
it("corrects exact Unicode words, loud/case variants and longest names without cascading", () => {
  expect(correctText("DJANGO, Jengo en Djangoes https://x.nl/Django Django@x.nl `Django`",[rule])).toBe("Yinga, Yinga en Djangoes https://x.nl/Django Django@x.nl `Django`");
  expect(correctText("Jan de Vries en Jan",[{...rule,canonical:"Ján de Vries",variants:["Jan de Vries","Jan"]}])).toBe("Ján de Vries en Ján de Vries");
  expect(correctText("Jengo",[rule,{...rule,id:"2",canonical:"Other",variants:["Yinga"]}])).toBe("Yinga");
});
it("keeps markup, attributes, links, code, CSS and comments intact", () => {
  const input = '<style>.Django{}</style><!-- Django --><p title="Django > x">Django</p><a href="/Django">Django</a><pre><code>Django</code></pre><script>Django</script><p>Jengo</p>';
  expect(correctHTML(input,[rule])).toBe(input.replace('>Django</p>','>Yinga</p>').replace('>Jengo</p>','>Yinga</p>'));
  expect(correctHTML('<p>Jengo</p>',[{...rule,canonical:"Yinga & Co"}])).toBe('<p>Yinga &amp; Co</p>');
});
it("uses only enabled rules in the matching profile", () => {
  const scoped = {...rule,scope:"meeting"};
  expect(correctText("Django",[scoped],"tech")).toBe("Django");
  expect(correctText("Django",[scoped],"meeting")).toBe("Yinga");
  expect(contextBlock([scoped],[],"Django","tech",6000)).toBe("");
  expect(correctText("Django",[{...rule,enabled:false}])).toBe("Django");
});
it("rejects conflicts, invalid documents and identical or empty variants", () => {
  expect(()=>validateCorrections({version:1,entries:[rule,{...rule,id:"2",scope:"meeting"}]})).toThrow("regel");
  expect(()=>validateCorrections({version:1,entries:[{...rule,variants:[" "]}]})).toThrow();
  expect(()=>validateCorrections({version:1,entries:[{...rule,variants:["Yinga"]}]})).toThrow();
  expect(()=>validateCorrections({version:1,entries:[{...rule,scope:"a"},{...rule,id:"2",scope:"b"}]})).not.toThrow();
});

it("merges new approved variants into an existing term without losing its identity", () => {
  const entries = upsertCorrection([rule], {...rule,id:"new",variants:["Jingo","django"]});
  expect(entries).toEqual([{...rule,variants:["Jengo","django","Jingo"]}]);
  expect(()=>validateCorrections({version:1,entries})).not.toThrow();
});

// Ported from the macOS PersonalCorrectionsTests.
const term = (canonical: string, variants: string[], note?: string): PersonalCorrection =>
  ({ id: crypto.randomUUID(), canonical, variants, scope: null, enabled: true, ...(note ? { note } : {}) });
const person = (name: string, role = "", organization = "", responsibilities: string[] = [], aliases: string[] = []): PersonContext =>
  ({ name, role, organization, responsibilities, aliases });
async function freshStore(keepFiles = false) {
  vi.resetModules();
  if (!keepFiles) files.clear();
  return (await import("../../stores/personalCorrectionsStore"));
}

it("loadsVersion1DocumentWithoutNotes", async () => {
  files.set("personal-corrections.json", '{"version":1,"entries":[{"id":"a","canonical":"Yinga","variants":["Jengo"],"scope":null,"enabled":true}]}');
  const { usePersonalCorrectionsStore: store } = await freshStore(true);
  await store.getState().hydrate();
  const entries = store.getState().entries;
  expect(entries.length).toBe(1);
  expect(entries[0].note).toBeUndefined();
  await store.getState().save(entries[0]);
  const written = files.get("personal-corrections.json")!;
  expect(written).toContain('"version":2');
  expect(JSON.parse(written).dismissed).toEqual([]);
});

it("entryWithoutVariantsIsValid", async () => {
  const { usePersonalCorrectionsStore: store } = await freshStore();
  const entry = term("Prezent", []);
  await store.getState().save(entry);
  const { usePersonalCorrectionsStore: restarted } = await freshStore(true);
  await restarted.getState().hydrate();
  expect(restarted.getState().entries).toEqual([entry]);
});

it("noteLongerThan200IsRejected", () => {
  expect(() => validateCorrections({ version: 2, entries: [term("Yinga", [], "a".repeat(200))] })).not.toThrow();
  expect(() => validateCorrections({ version: 2, entries: [term("Yinga", [], "a".repeat(201))] })).toThrow();
});

it("contextBlockPrioritisesTermsFoundInTranscript", () => {
  const note = "x".repeat(70);
  const block = contextBlock([term("Prezent", ["Presant"], note), term("Yinga", ["Jengo"], note)], [], "we spraken met jengo", undefined, 120);
  expect(block).toContain("Yinga");
  expect(block).not.toContain("Prezent");
});

it("contextBlockListsPeopleWithResponsibilities", () => {
  const block = contextBlock([], [person("Jan de Vries", "schade-expert", "Achmea", ["rapport opstellen"])], "", undefined, 6000);
  expect(block).toContain("Jan de Vries (schade-expert, Achmea), taken: rapport opstellen");
});

it("contextBlockAddsExtraTermsLastAndDeduped", () => {
  const block = contextBlock([term("Yinga", ["Jengo"])], [person("Jan de Vries")], "", undefined, 6000, ["Zeta", "yinga", "JENGO", "jan de vries"]);
  const lines = block.split("\n").filter(line => line.startsWith("- "));
  expect(lines[lines.length - 1]).toBe("- Zeta");
  expect(lines.length).toBe(3);
});

it("budgetSmallerThanFirstLineStillFillsWithShorterLine", () => {
  const block = contextBlock([term("Kort", []), term("Lang", [], "x".repeat(100))], [], "", undefined, 20);
  expect(block).toContain("- Kort");
  expect(block).not.toContain("Lang");
});

it("emptyInputsReturnEmptyString", () => {
  expect(contextBlock([], [], "", undefined, 6000)).toBe("");
});

it("transcriptMatchUsesWordBoundaries", () => {
  const block = contextBlock([term("AI", []), term("Zeta", [])], [], "we maintain it", undefined, 6000);
  expect(block.indexOf("- Zeta")).toBeLessThan(block.indexOf("- AI"));
});

it("unknownGlossaryVersionYieldsEmptyListForMinutes", async () => {
  const { usePersonalCorrectionsStore: store, loadCorrectionsOrEmpty } = await freshStore();
  files.set("personal-corrections.json", '{"version":99,"entries":[]}');
  await expect(store.getState().hydrate()).rejects.toThrow();
  const entries = await loadCorrectionsOrEmpty();
  expect(entries).toEqual([]);
  expect(contextBlock(entries, [person("Jan de Vries")], "", undefined, 6000)).toContain("Jan de Vries");
});

it("contextBlockUsesTheMacHeader", () => {
  expect(contextBlock([term("Yinga", ["Jengo"], "Merk")], [], "", undefined, 6000)).toBe(
    "\n\nWoordenboek en personen (juiste spelling en betekenis; corrigeer verkeerd herkende varianten stil, voeg geen feiten toe; koppel acties aan de persoon wiens taak het is):\n- Yinga (ook gehoord als: Jengo): Merk");
});
