import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { expect, it } from "vitest";
import { auditFixture, sourceFixture } from "../notuleAuditFixtures";
import { runShortModelGate } from "./modelcontrole-live-gate";

it("does not count transport failures or malformed replies as semantic rejection", async () => {
  for (const reply of [async () => { throw new Error("offline"); }, async () => "not JSON"]) {
    const result = await runShortModelGate(reply, () => {});
    expect(result.pass).toBe(false);
    expect(result.results).toHaveLength(6);
    expect(result.results.every(item => item.calls === 1 && !item.pass && !item.well_formed_report)).toBe(true);
  }
});

it("does not count fabricated all-positive evidence as a passed model gate", async () => {
  const result = await runShortModelGate(async (_system, user) => auditFixture(user), () => {});
  expect(result.pass).toBe(false);
  expect(result.results.map(item => item.pass)).toEqual([true, false, false, false, false, false]);
});

it("recognizes targeted schema-valid findings in synthetic harness self-checks", async () => {
  const result = await runShortModelGate(async (_system, user) => {
    const input = JSON.parse(user.slice(user.indexOf("\n") + 1));
    if (!input.notes) {
      if (input.source.startsWith("En 70% mensen")) {
        const report = JSON.parse(sourceFixture(user)); report.uncertain = true;
        return JSON.stringify(report);
      }
      return sourceFixture(user);
    }
    const report = JSON.parse(auditFixture(user));
    if (input.source.some(unit => unit.text.startsWith("En 70% mensen"))) {
      report.uncertain = true;
    } else if (input.notes.some(unit => unit.text.includes("schriftelijke goedkeuring geven"))) {
      const id = input.notes.find(unit => unit.text.includes("schriftelijke goedkeuring geven")).id;
      Object.assign(report.notes.find(unit => unit.id === id), { status: "unsupported", evidence: [] });
    } else if (!input.notes.some(unit => /Iris (beoordeelt|controleert) .*inhoud/u.test(unit.text))) {
      const id = input.source.find(unit => unit.text.includes("Iris controleert de inhoud")).id;
      Object.assign(report.source.find(unit => unit.id === id), { status: "missing", evidence: [] });
    } else if (input.notes.some(unit => unit.text.includes("Het budget bedraagt 15.000 euro"))) {
      const id = input.notes.find(unit => unit.text.includes("Het budget bedraagt 15.000 euro")).id;
      Object.assign(report.notes.find(unit => unit.id === id), { status: "contradiction", evidence: [] });
    } else if (input.notes.some(unit => unit.text.includes("Klantgegevens mogen toch"))) {
      const id = input.notes.find(unit => unit.text.includes("Klantgegevens mogen toch")).id;
      Object.assign(report.notes.find(unit => unit.id === id), { status: "contradiction", evidence: [] });
    }
    return JSON.stringify(report);
  }, () => {});
  expect(result.pass).toBe(true);
});

// Opt-in evidence preparation/replay only; this test never makes provider calls.
it.runIf(process.env.TV_AUDIT_MODE === "prepare" || process.env.TV_AUDIT_MODE === "replay")(
  "prepares exact production audit prompts or replays preserved real provider responses",
  async () => {
    const directory = process.env.TV_AUDIT_DIR;
    if (!directory) throw new Error("TV_AUDIT_DIR is required");
    const dir = resolve(directory);
    mkdirSync(dir, { recursive: true });
    let currentCase = "";
    const prepare = process.env.TV_AUDIT_MODE === "prepare";
    const result = await runShortModelGate(async (_system, user) => {
      if (prepare && currentCase.endsWith(".source")) return sourceFixture(user);
      if (prepare) throw new Error("QA preparation only; no provider request");
      return readFileSync(resolve(dir, `${currentCase}.response.txt`), "utf8");
    }, evidence => {
      currentCase = evidence.case_name;
      if (evidence.kind === "request") {
        const path = resolve(dir, `${currentCase}.request.json`);
        const json = JSON.stringify({
          model: "gpt-oss:120b",
          messages: [{ role: "system", content: evidence.system }, { role: "user", content: evidence.user }],
          stream: false,
        }, null, 2) + "\n";
        if (prepare) writeFileSync(path, json, { flag: "wx" });
        else expect(readFileSync(path, "utf8")).toBe(json);
      }
    });
    writeFileSync(resolve(dir, prepare ? "PREPARATION.json" : "REPLAY.json"), JSON.stringify({
      mode: prepare ? "prepared_only_no_provider_calls" : "real_response_replay",
      ...result,
    }, null, 2) + "\n", { flag: "wx" });
    if (prepare) expect(result.results.every(item => item.calls === 2)).toBe(true);
    else expect(result.pass).toBe(true);
  },
);
