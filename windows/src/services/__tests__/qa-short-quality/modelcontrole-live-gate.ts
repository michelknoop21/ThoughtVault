// QA-only. Place beside modelcontrole-regressiefixtures.json in
// windows/src/services/__tests__/qa-short-quality/ in the existing Mac test tree.
// Import explicitly in the existing DOM-enabled test route. No automatic calls.
import { auditNotule } from "../../notuleAudit";
import fixture from "./modelcontrole-regressiefixtures.json";

type Request = (system: string, user: string) => Promise<string>;
type Unit = { id: string; text: string };
type Verdict = { id: string; status: string; evidence: string[] };
type Report = { source: Verdict[]; notes: Verdict[]; uncertain: boolean };
function validSide(value: unknown, units: Unit[], references: Unit[], statuses: string[]): value is Verdict[] {
  if (!Array.isArray(value) || value.length !== units.length) return false;
  const ids = new Set(units.map(unit => unit.id));
  const refs = new Set(references.map(unit => unit.id));
  return value.every(entry => entry && typeof entry.id === "string" && ids.delete(entry.id)
    && statuses.includes(entry.status) && Array.isArray(entry.evidence)
    && entry.evidence.every((id: unknown) => typeof id === "string" && refs.has(id))
    && new Set(entry.evidence).size === entry.evidence.length
    && (entry.status !== "non_factual" || entry.evidence.length === 0)
    && (!["covered", "supported"].includes(entry.status) || entry.evidence.length > 0));
}
type Evidence = {
  kind: "request" | "response";
  case_name: string;
  system?: string;
  user?: string;
  response?: string;
};

/** Use the existing approved provider adapter, never a mock or an exported key.
 * Call once per code/prompt revision: four cases, no retries. Record only these
 * fictional prompts/model texts, never transport headers or credential data.
 */
export async function runShortModelGate(
  request: Request,
  record: (evidence: Evidence) => void,
) {
  const results = [];
  for (const testCase of fixture.cases) {
    // Exact production constraint selection from llm.ts at commit132b9e1.
    // This still tests the real audit function, not the complete UI/generator.
    const constraints = [...new Set((testCase.source.match(/(?:[^.!?\n]|(?<=\d)\.(?=\d))+[.!?]?/gu) ?? [])
      .map(sentence => sentence.trim())
      .filter(sentence => /\b(niet|geen|niets|nooit|zonder|vervalt|vervallen|afgewezen|afgekeurd|afwezig|onbeslist|onbekend|not|never|without|cancelled|canceled)\b|open vraag/iu.test(sentence)))];
    let calls = 0;
    let accepted = false;
    let reason = "";
    let payload: { source: Unit[]; notes: Unit[] } | undefined;
    let report: Report | undefined;
    try {
      await auditNotule(testCase.source, testCase.html, "", async (system, user) => {
        calls++;
        if (calls > 1) throw new Error("QA: unexpected additional audit request");
        payload = JSON.parse(user.slice(user.indexOf("\n") + 1));
        record({ kind: "request", case_name: testCase.name, system, user });
        const response = await request(system, user);
        record({ kind: "response", case_name: testCase.name, response });
        try { report = JSON.parse(response.trim()); } catch { report = undefined; }
        return response;
      }, constraints);
      accepted = true;
    } catch (error) {
      reason = error instanceof Error ? error.message : String(error);
    }
    const wellFormed = !!(payload && report && typeof report.uncertain === "boolean"
      && validSide(report.source, payload.source, payload.notes, ["covered", "non_factual", "missing", "uncertain"])
      && validSide(report.notes, payload.notes, payload.source, ["supported", "non_factual", "contradiction", "unsupported", "uncertain"]));
    // A transport error, malformed JSON or unrelated rejection is not a negative PASS.
    let targetFinding = false;
    if (wellFormed && payload && report) {
      if (testCase.name === "tweede_actie_ontbreekt") {
        const id = payload.source.find(unit => unit.text.includes("Iris controleert de inhoud"))?.id;
        targetFinding = report.source.some(unit => unit.id === id && unit.status === "missing");
      } else if (testCase.name === "tegenstrijdige_toestemming") {
        const id = payload.notes.find(unit => unit.text.includes("Klantgegevens mogen toch"))?.id;
        targetFinding = report.notes.some(unit => unit.id === id && unit.status === "contradiction");
      } else if (!testCase.expect_accept) {
        targetFinding = report.uncertain || report.source.some(unit => unit.status === "uncertain");
      }
    }
    results.push({
      name: testCase.name,
      expected_accept: testCase.expect_accept,
      accepted,
      reason,
      calls,
      well_formed_report: wellFormed,
      target_semantic_finding: targetFinding,
      pass: calls === 1 && wellFormed && (testCase.expect_accept ? accepted : !accepted && targetFinding),
    });
  }
  return { pass: results.every(result => result.pass), results };
}
