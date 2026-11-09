// Pure text and merge rules of the suggestion bar (port of the macOS ContextSuggestionBarLogic).
import type { PersonSuggestion } from "../../services/contextSuggestions";
import type { PersonSnapshot } from "../../services/contextHistory";

/** "2 termen, 1 persoon"; zero counts are left out. */
export function counter(terms: number, people: number): string {
  const parts: string[] = [];
  if (terms > 0) parts.push(terms === 1 ? "1 term" : `${terms} termen`);
  if (people > 0) parts.push(people === 1 ? "1 persoon" : `${people} personen`);
  return parts.join(", ");
}

/** "Is dit Jan de Vries of Jan Smit?" */
export function ambiguousQuestion(names: string[]): string {
  if (!names.length) return "";
  const last = names[names.length - 1], head = names.slice(0, -1);
  return "Is dit " + (head.length ? head.join(", ") + " of " + last : last) + "?";
}

/** Role and organization only when the proposal has one; aliases appended case-insensitively, skipping the name and known spellings. */
export function applyRemainder(s: PersonSuggestion, snapshot: PersonSnapshot): PersonSnapshot {
  const role = s.role.trim(), organization = s.organization.trim();
  const seen = new Set([snapshot.name, ...snapshot.aliases].map(a => a.trim().toLowerCase()));
  const added = s.heardAs.map(a => a.trim()).filter(a => {
    if (!a || seen.has(a.toLowerCase())) return false;
    seen.add(a.toLowerCase());
    return true;
  });
  return { ...snapshot, role: role || snapshot.role, organization: organization || snapshot.organization, aliases: [...snapshot.aliases, ...added] };
}

/** One line per change that applying the remainder would make. */
export function changeSummary(s: PersonSuggestion, current: PersonSnapshot): string[] {
  const next = applyRemainder(s, current);
  const change = (label: string, old: string, value: string) => old ? `${label}: ${old} → ${value}` : `${label}: ${value}`;
  const lines: string[] = [];
  if (next.role !== current.role) lines.push(change("Rol", current.role, next.role));
  if (next.organization !== current.organization) lines.push(change("Organisatie", current.organization, next.organization));
  const added = next.aliases.slice(current.aliases.length);
  if (added.length) lines.push("Ook bekend als: " + added.join(", "));
  return lines;
}
