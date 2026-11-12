import { expect, it, vi } from "vitest";
import { AUDIT_CONCURRENCY, AuditFinding, COVERAGE_SYSTEM, MAX_AUDIT_PARTS, MAX_NOTE_CHECKS, NOTE_SYSTEM, UNCITED_SYSTEM, auditNotule } from "../notuleAudit";

// Long meetings (DEC-065): coverage per part, then one check per notule sentence. Same scenarios as
// NotuleAuditPartsTests.swift.
type Unit = { id: string; text: string };
type Item = { id: string; status: string; evidence: string[] };
type Report = { uncertain: unknown; source?: Item[]; notes?: Item[] };
type Input = { source?: Unit[]; notes: Unit[]; evidence?: Unit[]; context?: Unit[] };

interface Options {
  /** N-IDs that preserve a source unit in step 1; none means non_factual. */
  cover?: (id: string) => string[];
  coverage?: (report: Report, input: Input) => void;
  note?: (report: Report, input: Input) => void;
  uncited?: (report: Report, input: Input) => void;
  /** Replaces the whole reply, or throws. */
  reply?: (user: string) => string | undefined;
  /** Milliseconds each request takes, by user message. */
  delay?: (user: string) => number;
}

const input = (user: string): Input => JSON.parse(user.slice(user.indexOf("\n") + 1));
const kind = (user: string) => user.startsWith("Inhoudsaudit deel") ? "coverage" : user.startsWith("Notulezin controleren") ? "note" : "uncited";

function model(options: Options = {}) {
  // ended: user messages in the order their requests finished.
  const live = { running: 0, peak: 0, ended: [] as string[] };
  const request = vi.fn(async (_system: string, user: string) => {
    live.running++;
    live.peak = Math.max(live.peak, live.running);
    await new Promise(resolve => setTimeout(resolve, options.delay?.(user) ?? 0));
    live.running--;
    live.ended.push(user);
    const replaced = options.reply?.(user);
    if (replaced !== undefined) return replaced;
    const data = input(user);
    const report: Report = { uncertain: false };
    if (kind(user) === "coverage") {
      report.source = data.source!.map(unit => {
        const evidence = options.cover?.(unit.id) ?? [];
        return { id: unit.id, status: evidence.length ? "covered" : "non_factual", evidence };
      });
      options.coverage?.(report, data);
    } else if (kind(user) === "note") {
      report.notes = data.notes.map(note => ({ id: note.id, status: "supported", evidence: data.evidence!.map(unit => unit.id) }));
      options.note?.(report, data);
    } else {
      report.notes = data.notes.map(note => ({ id: note.id, status: "non_factual", evidence: [] }));
      options.uncited?.(report, data);
    }
    return JSON.stringify(report);
  });
  return Object.assign(request, { live });
}

const calls = (request: ReturnType<typeof model>, which: string) => request.mock.calls.filter(([, user]) => kind(user) === which);
const ids = (units: Unit[] | undefined) => (units ?? []).map(unit => unit.id);
/** The first notule ID of a step-2 request, undefined for other requests. */
const noteId = (user: string) => kind(user) === "note" ? input(user).notes[0].id : undefined;
const points = (count: number) => Array.from({ length: count }, (_, i) => `Punt ${i + 1} is besproken.`).join(" ");
const longSource = `${points(400)} Sam belt vrijdag de klant.`;
const sam = "<p>Sam belt vrijdag de klant.</p>";

it("keeps the single unchanged request within the limit", async () => {
  const request = vi.fn(async () => JSON.stringify({ uncertain: false, source: [{ id: "T1", status: "covered" }], notes: [{ id: "N1", status: "supported", evidence: ["T1"] }] }));
  await auditNotule("Sam belt vrijdag.", "<p>Sam belt vrijdag de klant.</p>", "", request);
  expect(request).toHaveBeenCalledTimes(1);
  const [system, user] = request.mock.calls[0] as unknown as [string, string];
  expect(system).not.toContain("lange meeting");
  expect(user.startsWith("Inhoudsaudit (geen generatie):\n")).toBe(true);
});

it("checks a long meeting in two steps: coverage per part, then one request per cited notule sentence", async () => {
  const request = model({ cover: id => id === "T401" || id === "Q1" ? ["N1"] : [] });
  await auditNotule(longSource, sam, "Klant bellen.", request);
  expect(request).toHaveBeenCalledTimes(3);
  const [first, second] = calls(request, "coverage");
  expect(first[0]).toBe(COVERAGE_SYSTEM);
  expect(first[1].startsWith("Inhoudsaudit deel 1 van 2 (geen generatie):\n")).toBe(true);
  // 400 units minus the notule and the quick note leaves 398 transcription sentences per part.
  expect(ids(input(first[1]).source)).toEqual([...Array.from({ length: 398 }, (_, i) => `T${i + 1}`), "Q1"]);
  expect(ids(input(second[1]).source)).toEqual(["T399", "T400", "T401", "Q1"]);
  for (const [, user] of [first, second]) expect(input(user).notes).toEqual([{ id: "N1", text: "Sam belt vrijdag de klant." }]);
  const [[system, user]] = calls(request, "note");
  expect(system).toBe(NOTE_SYSTEM);
  expect(input(user)).toEqual({
    notes: [{ id: "N1", text: "Sam belt vrijdag de klant." }],
    evidence: [{ id: "T401", text: "Sam belt vrijdag de klant." }, { id: "Q1", text: "Klant bellen." }],
    context: [{ id: "T398", text: "Punt 398 is besproken." }, { id: "T399", text: "Punt 399 is besproken." }, { id: "T400", text: "Punt 400 is besproken." }],
  });
});

it("keeps every step-1 request within the character budget", async () => {
  const sentence = (letter: string) => `${letter.repeat(39_999)}.`;
  const request = model({ cover: id => id === "T2" ? ["N1"] : [] });
  // Three parts fit; the step-2 request with the cited sentence and its neighbours does not, so it is never sent.
  await expect(auditNotule(["a", "b", "c"].map(sentence).join(" "), "<p>Kort verslag.</p>", "", request)).rejects.toThrow("te groot");
  expect(request).toHaveBeenCalledTimes(3);
  for (const [, user] of calls(request, "coverage")) {
    const data = input(user);
    expect(data.source).toHaveLength(1);
    expect([...data.source!, ...data.notes].reduce((length, unit) => length + unit.text.length, 0)).toBeLessThanOrEqual(64_000);
  }
});

it("accepts exactly MAX_AUDIT_PARTS parts and rejects one more without a request", async () => {
  const request = model({ cover: id => id === "T1" ? ["N1"] : [] });
  await auditNotule(points(399 * MAX_AUDIT_PARTS), "<p>Punt 1 is besproken.</p>", "", request);
  expect(calls(request, "coverage")).toHaveLength(MAX_AUDIT_PARTS);
  expect(calls(request, "note")).toHaveLength(1);
  const more = model({ cover: id => id === "T1" ? ["N1"] : [] });
  await expect(auditNotule(points(399 * MAX_AUDIT_PARTS + 1), "<p>Punt 1 is besproken.</p>", "", more)).rejects.toThrow("te groot");
  expect(more).not.toHaveBeenCalled();
});

it("rejects more than MAX_NOTE_CHECKS notule sentences without a request", async () => {
  const request = model();
  const html = `<p>${Array.from({ length: MAX_NOTE_CHECKS + 1 }, (_, i) => `Besluit ${i + 1} is genomen.`).join(" ")}</p>`;
  await expect(auditNotule(points(300), html, "", request)).rejects.toThrow("te groot");
  expect(request).not.toHaveBeenCalled();
});

it.each([
  ["an unknown id", (report: Report) => { report.source![0].id = "T999"; }],
  ["a missing id", (report: Report) => { report.source!.pop(); }],
  ["a duplicate id", (report: Report) => { report.source![1].id = report.source![0].id; }],
  ["evidence outside the notule", (report: Report) => { report.source![0] = { id: "T1", status: "covered", evidence: ["N9"] }; }],
  ["covered without evidence", (report: Report) => { report.source![0] = { id: "T1", status: "covered", evidence: [] }; }],
  ["missing with evidence", (report: Report) => { report.source![0] = { id: "T1", status: "missing", evidence: ["N1"] }; }],
])("rejects a step-1 reply with %s before merging", async (_name, change) => {
  const request = model({ cover: id => id === "T401" ? ["N1"] : [], coverage: change });
  await expect(auditNotule(longSource, sam, "", request)).rejects.toThrow();
  // Both parts run side by side; step 2 never starts.
  expect(request).toHaveBeenCalledTimes(2);
});

it("rejects an uncertain part and stops asking", async () => {
  const request = model({ coverage: report => { report.uncertain = true; } });
  await expect(auditNotule(longSource, sam, "", request)).rejects.toThrow("De inhoudscontrole is onzeker; beoordeel het concept");
  // Both parts run side by side; step 2 never starts.
  expect(request).toHaveBeenCalledTimes(2);
});

/** The part number of a step-1 request ("Inhoudsaudit deel 2 van 3"), undefined for other requests. */
const partNumber = (user: string) => kind(user) === "coverage" ? Number(user.split(" ")[2]) : undefined;

it("runs the coverage parts side by side", async () => {
  const request = model({ cover: id => id === "T401" ? ["N1"] : [], delay: user => partNumber(user) === 1 ? 300 : 0 });
  await auditNotule(longSource, sam, "", request);
  expect(request.live.ended.map(partNumber).filter(Boolean)).toEqual([2, 1]);
});

it("merges the parts in part order, whichever part finishes first", async () => {
  // Part 1 says the quick note is kept by N1, part 2 says by N2: both notule sentences must cite it.
  const html = "<p>Sam belt vrijdag de klant. Punt 1 is besproken.</p>";
  const stepTwo: string[][] = [];
  for (const slowPart of [1, 2]) {
    const request = model({
      cover: id => id === "T401" ? ["N1"] : id === "T1" ? ["N2"] : [],
      coverage: (report, data) => {
        report.source = report.source!.map(item => item.id === "Q1" ? { id: "Q1", status: "covered", evidence: [data.source![0].id === "T1" ? "N1" : "N2"] } : item);
      },
      delay: user => partNumber(user) === slowPart ? 200 : 0,
    });
    await auditNotule(longSource, html, "Klant bellen.", request);
    const notes = calls(request, "note").map(([, user]) => user).sort();
    expect(notes.map(user => ids(input(user).evidence))).toEqual([["T401", "Q1"], ["T1", "Q1"]]);
    stepTwo.push(notes);
  }
  expect(stepTwo[0]).toEqual(stepTwo[1]);
});

it("reports the first failing part even when a later part failed first, and starts no further parts", async () => {
  // Six parts. Part 1 is slow and uncertain, part 2 fails at once, parts 3 and 4 finish after part 2.
  const request = model({
    coverage: (report, data) => { if (data.source![0].id === "T1") report.uncertain = true; },
    reply: user => partNumber(user) === 2 ? '{"source":[' : undefined,
    delay: user => { const part = partNumber(user); return part === 1 ? 300 : part === 2 || !part ? 0 : 100; },
  });
  await expect(auditNotule(points(399 * 6), "<p>Punt 1 is besproken.</p>", "", request)).rejects.toThrow("De inhoudscontrole is onzeker; beoordeel het concept");
  expect(calls(request, "coverage").map(([, user]) => partNumber(user))).toEqual([1, 2, 3, 4]);
});

it("rejects unreadable JSON in part 2 after exactly two requests", async () => {
  const request = model({ cover: id => id === "T401" ? ["N1"] : [], reply: user => user.startsWith("Inhoudsaudit deel 2") ? '{"source":[' : undefined });
  await expect(auditNotule(longSource, sam, "", request)).rejects.toThrow("De inhoudscontrole leverde geen bruikbaar controlebewijs; beoordeel het concept");
  expect(request).toHaveBeenCalledTimes(2);
});

it.each([["missing", "De notule mist broninformatie: Klant bellen."], ["uncertain", "De bron is onvoldoende duidelijk: Klant bellen."]])(
  "rejects a quick note that one part marks %s, even when another part covers it", async (status, message) => {
    const request = model({
      cover: id => id === "T401" || id === "Q1" ? ["N1"] : [],
      coverage: (report, data) => {
        if (data.source![0].id !== "T1") report.source = report.source!.map(item => item.id === "Q1" ? { id: "Q1", status, evidence: [] } : item);
      },
    });
    await expect(auditNotule(longSource, sam, "Klant bellen.", request)).rejects.toThrow(message);
    for (const [, user] of calls(request, "coverage")) expect(ids(input(user).source)).toContain("Q1");
  });

it.each([
  ["contradiction", "De notule spreekt de bron tegen: Sam belt vrijdag de klant.", "Dit klopt misschien niet met wat er is gezegd: “Sam belt vrijdag de klant.”"],
  ["unsupported", "De notule bevat een onbevestigde bewering: Sam belt vrijdag de klant.", "Dit staat in de notule, maar is misschien niet zo gezegd: “Sam belt vrijdag de klant.”"],
  ["uncertain", "De bewering is onvoldoende duidelijk: Sam belt vrijdag de klant.", "Dit is misschien niet helemaal goed samengevat: “Sam belt vrijdag de klant.”"],
])("rejects a %s notule sentence in step 2 with its finding", async (status, message, finding) => {
  const request = model({ cover: id => id === "T401" ? ["N1"] : [], note: report => { report.notes = [{ id: "N1", status, evidence: [] }]; } });
  const error = await auditNotule(longSource, sam, "", request).then(() => null, (error: unknown) => error);
  expect(error).toBeInstanceOf(AuditFinding);
  expect((error as AuditFinding).message).toBe(message);
  expect((error as AuditFinding).finding).toBe(finding);
});

it("does not let support for one notule sentence overrule an uncertain other", async () => {
  const request = model({
    cover: id => id === "T401" ? ["N1", "N2"] : [],
    note: (report, data) => { if (data.notes[0].id === "N1") report.notes = [{ id: "N1", status: "uncertain", evidence: [] }]; },
  });
  await expect(auditNotule(longSource, "<p>Sam belt de klant. Sam belt vrijdag de klant.</p>", "", request))
    .rejects.toThrow("De bewering is onvoldoende duidelijk: Sam belt de klant.");
});

it("sends uncited notule sentences together without evidence: a heading passes, an invented claim does not", async () => {
  const request = model({ cover: id => id === "T401" ? ["N2"] : [] });
  await auditNotule(longSource, "<h2>Verslag</h2><p>Sam belt vrijdag de klant.</p>", "", request);
  const [[system, user]] = calls(request, "uncited");
  expect(system).toBe(UNCITED_SYSTEM);
  expect(input(user)).toEqual({ notes: [{ id: "N1", text: "Verslag" }] });
  const invented = model({ cover: id => id === "T401" ? ["N2"] : [], uncited: report => { report.notes = [{ id: "N1", status: "unsupported", evidence: [] }]; } });
  await expect(auditNotule(longSource, "<p>Joris betaalt de rekening.</p><p>Sam belt vrijdag de klant.</p>", "", invented))
    .rejects.toThrow("De notule bevat een onbevestigde bewering: Joris betaalt de rekening.");
});

it("rejects support that cites only the context", async () => {
  const request = model({ cover: id => id === "T401" ? ["N1"] : [], note: report => { report.notes = [{ id: "N1", status: "supported", evidence: ["T400"] }]; } });
  await expect(auditNotule(longSource, sam, "", request)).rejects.toThrow("Ongeldig controlebewijs");
});

it("shows a qualification across a part boundary as context for the action it qualifies", async () => {
  const source = `${"Hallo allemaal. ".repeat(398)}De volgende opdracht is alleen een fictief voorbeeld. Sam deelt vrijdag het klantbestand.`;
  const html = "<p>Actie: Sam deelt vrijdag het klantbestand.</p>";
  const cover = (id: string) => id === "T400" ? ["N1"] : [];
  const request = model({ cover });
  await auditNotule(source, html, "", request);
  const [first, second] = calls(request, "coverage");
  expect(input(first[1]).source!.at(-1)).toEqual({ id: "T399", text: "De volgende opdracht is alleen een fictief voorbeeld." });
  expect(input(second[1]).source).toEqual([{ id: "T400", text: "Sam deelt vrijdag het klantbestand." }]);
  const check = input(calls(request, "note")[0][1]);
  expect(ids(check.evidence)).toEqual(["T400"]);
  expect(check.context).toContainEqual({ id: "T399", text: "De volgende opdracht is alleen een fictief voorbeeld." });
  for (const [status, reason] of [["contradiction", "De notule spreekt de bron tegen"], ["unsupported", "De notule bevat een onbevestigde bewering"]]) {
    const strict = model({ cover, note: report => { report.notes = [{ id: "N1", status, evidence: [] }]; } });
    await expect(auditNotule(source, html, "", strict)).rejects.toThrow(`${reason}: Actie: Sam deelt vrijdag het klantbestand.`);
  }
});

it("rejects an invented deadline that only the notule contains", async () => {
  const request = model({ cover: id => id === "T401" ? ["N1"] : [], note: report => { report.notes = [{ id: "N1", status: "unsupported", evidence: [] }]; } });
  await expect(auditNotule(`${points(400)} Sam deelt het klantbestand.`, "<p>Sam deelt vrijdag het klantbestand.</p>", "", request))
    .rejects.toThrow("De notule bevat een onbevestigde bewering: Sam deelt vrijdag het klantbestand.");
  expect(input(calls(request, "note")[0][1]).evidence).toEqual([{ id: "T401", text: "Sam deelt het klantbestand." }]);
});

// Ten notule sentences, each preserving its own source sentence T391 to T400.
const tenSource = points(401);
const tenHtml = `<p>${Array.from({ length: 10 }, (_, i) => `Punt ${391 + i} is besproken.`).join(" ")}</p>`;
const tenCover = (id: string) => {
  const number = Number(id.slice(1));
  return id.startsWith("T") && number >= 391 && number <= 400 ? [`N${number - 390}`] : [];
};

it("reports a failed step-2 request and starts no new requests after the first problem", async () => {
  // N1 fails before the others finish, so no completion can start a fifth check first.
  const request = model({ cover: tenCover, reply: user => { if (noteId(user) === "N1") throw new Error("offline"); return undefined; },
    delay: user => noteId(user) && noteId(user) !== "N1" ? 50 : 0 });
  await expect(auditNotule(tenSource, tenHtml, "", request)).rejects.toThrow("De inhoudscontrole leverde geen bruikbaar controlebewijs; beoordeel het concept");
  // Two coverage parts, then only the first window.
  expect(request).toHaveBeenCalledTimes(2 + AUDIT_CONCURRENCY);
});

it("passes a cancellation on instead of turning it into an audit result", async () => {
  const abort = new DOMException("Aborted", "AbortError");
  const request = model({ cover: tenCover, reply: user => { if (kind(user) === "note") throw abort; return undefined; } });
  await expect(auditNotule(tenSource, tenHtml, "", request)).rejects.toBe(abort);
});

it("never runs more than AUDIT_CONCURRENCY step-2 requests at once", async () => {
  const request = model({ cover: tenCover, delay: () => 5 });
  await auditNotule(tenSource, tenHtml, "", request);
  expect(calls(request, "note")).toHaveLength(10);
  expect(request.live.peak).toBe(AUDIT_CONCURRENCY);
});

it("does not let a slow first check hold back the others, and still reports in order", async () => {
  const request = model({ cover: tenCover, delay: user => noteId(user) === "N1" ? 300 : 0 });
  await auditNotule(tenSource, tenHtml, "", request);
  const ended = request.live.ended.map(noteId).filter(Boolean);
  expect(ended).toHaveLength(10);
  expect(ended.at(-1)).toBe("N1");
  expect(request.live.peak).toBeLessThanOrEqual(AUDIT_CONCURRENCY);

  // The fast N2 fails first, N3 and N4 finish after it without starting N5, and the slow N1 is reported.
  const failing = model({
    cover: tenCover,
    note: (report, data) => {
      if (data.notes[0].id === "N1") report.notes = [{ id: "N1", status: "unsupported", evidence: [] }];
      if (data.notes[0].id === "N2") report.notes = [{ id: "N2", status: "contradiction", evidence: [] }];
    },
    delay: user => { const id = noteId(user); return id === "N1" ? 300 : id === "N2" || !id ? 0 : 100; },
  });
  await expect(auditNotule(tenSource, tenHtml, "", failing)).rejects.toThrow("De notule bevat een onbevestigde bewering: Punt 391 is besproken.");
  expect(calls(failing, "note")).toHaveLength(AUDIT_CONCURRENCY);
});

it("reports a contradiction in a later part as a contradiction, not as missing evidence", async () => {
  const request = model({
    cover: id => id === "T1" ? ["N1"] : id === "T401" ? ["N2"] : [],
    note: (report, data) => { if (data.notes[0].id === "N2") report.notes = [{ id: "N2", status: "contradiction", evidence: [] }]; },
  });
  await expect(auditNotule(longSource, "<p>Punt 1 is besproken. Sam belt maandag de klant.</p>", "", request))
    .rejects.toThrow("De notule spreekt de bron tegen: Sam belt maandag de klant.");
});
