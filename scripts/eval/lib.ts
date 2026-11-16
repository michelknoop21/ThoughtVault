// Pure helpers for the notule evaluation: scoring, summary, and the privacy guards for result files.
import { execFileSync } from "node:child_process";
import { chmodSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, resolve, sep } from "node:path";

export interface Fact { id: string; any: string[] }

/** Both fact files: a list of plain search terms, or objects {id, fact, any}. Only id and terms are kept. */
export function loadFacts(json: { facts: (string | { id: string; any: string[] })[] }): Fact[] {
  return json.facts.map((f, i) => typeof f === "string"
    ? { id: `f${String(i + 1).padStart(2, "0")}`, any: [f] }
    : { id: f.id, any: f.any });
}

const ENTITIES: Record<string, string> = { "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&euro;": "€" };

export function htmlToText(html: string): string {
  return html.replace(/<style\b[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ")
    .replace(/&[a-z#0-9]+;/gi, e => ENTITIES[e.toLowerCase()] ?? " ")
    .replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
}

export function scoreFacts(text: string, facts: Fact[]) {
  const hay = text.toLowerCase();
  const missing = facts.filter(f => !f.any.some(t => hay.includes(t.toLowerCase()))).map(f => f.id);
  return { found: facts.length - missing.length, total: facts.length, missing };
}

/** Items in the "Even nalopen" section, the warnings the app's audit appends. */
export function nalopenCount(html: string): number {
  const at = html.indexOf("<h2>Even nalopen</h2>");
  return at < 0 ? 0 : (html.slice(at).match(/<li>/g) ?? []).length;
}

export interface RunResult { commit?: string;
  model: string; conversation: string; rep: number; detail: string;
  found: number; total: number; missing: string[];
  chars: number; words: number; nalopen: number;
  durationMs: number; costUsd: number; costKnown: boolean; error: string | null;
}

const mean = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;

export function summaryTable(runs: RunResult[], totalCost: number): string {
  const rows = ["| Model | Gesprek | Runs | Feiten (gem.) | Min-max | Kosten USD (gem.) | Duur s (gem.) | Even nalopen (gem.) | Fouten |", "|---|---|---|---|---|---|---|---|---|"];
  const keys = [...new Set(runs.map(r => `${r.model}\t${r.conversation}`))];
  for (const key of keys) {
    const [model, conversation] = key.split("\t");
    const group = runs.filter(r => r.model === model && r.conversation === conversation);
    const ok = group.filter(r => !r.error);
    const f = ok.map(r => r.found);
    rows.push(`| ${model} | ${conversation} | ${group.length} | ${ok.length ? `${mean(f).toFixed(1)}/${ok[0].total}` : "-"} | ${f.length ? `${Math.min(...f)}-${Math.max(...f)}` : "-"} | ${mean(group.map(r => r.costUsd)).toFixed(4)} | ${(mean(group.map(r => r.durationMs)) / 1000).toFixed(1)} | ${ok.length ? mean(ok.map(r => r.nalopen)).toFixed(1) : "-"} | ${group.filter(r => r.error).length} |`);
  }
  return `${rows.join("\n")}\n\nTotale kosten: USD ${totalCost.toFixed(4)}\n`;
}

/** Throws when `dir` lies inside the git worktree this script belongs to. Symlinks are resolved. */
export function assertOutsideRepo(dir: string): void {
  const top = realpathSync(execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: import.meta.dirname, encoding: "utf8" }).trim());
  let probe = resolve(dir);
  const tail: string[] = [];
  while (true) {
    try { probe = realpathSync(probe); break; } catch { tail.unshift(probe.slice(dirname(probe).length + 1)); probe = dirname(probe); }
  }
  const real = resolve(probe, ...tail);
  if (real === top || real.startsWith(top + sep)) throw new Error("Resultaten mogen niet in de git-worktree staan.");
}

/** mkdir -p with mode 700 on every new directory. */
export function secureDir(dir: string): void {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  chmodSync(dir, 0o700);
}

export function secureWrite(file: string, data: string, append = false): void {
  writeFileSync(file, data, { mode: 0o600, flag: append ? "a" : "w" });
  chmodSync(file, 0o600);
}
