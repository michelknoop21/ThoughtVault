// How much detail a generated notule keeps. "volledig" is the complete notule as before, and every missing
// choice falls back to it. Same texts and numbers as macos/Services/NotuleDetailLevel.swift.
import type { NotuleDetailLevel, Profile, Transcript } from "../types";

const LEVELS: NotuleDetailLevel[] = ["kort", "normaal", "volledig"];
const level = (value: unknown): NotuleDetailLevel | undefined =>
  LEVELS.includes(value as NotuleDetailLevel) ? value as NotuleDetailLevel : undefined;

/** The user's choice for this profile (settings `profile_detail_levels`), else the profile's default (an enriched
 * profile carries the bundled one), else volledig. */
export function effectiveDetailLevel(profile: Pick<Profile, "id" | "detail_level">, choices: Record<string, string> = {}): NotuleDetailLevel {
  return level(choices[profile.id]) ?? level(profile.detail_level) ?? "volledig";
}

const hundreds = (value: number) => Math.round(value / 100) * 100;

/** Target notule length in characters for a transcript of `transcriptCharacters`, a multiple of 100; null at volledig. */
export function targetLength(detail: NotuleDetailLevel, transcriptCharacters: number): number | null {
  if (detail === "volledig") return null;
  const [factor, low, high] = detail === "kort" ? [0.06, 1500, 4000] : [0.15, 2500, 8000];
  return hundreds(Math.min(Math.max(factor * transcriptCharacters, low), high));
}

/** The upper bound named in the prompt: 1.3 times the target, rounded to a multiple of 100. */
export const maximumLength = (target: number) => hundreds(1.3 * target);

/** Dutch thousands separator: 2400 becomes "2.400". */
export function dutchNumber(value: number): string {
  return value < 1000 ? String(value) : `${dutchNumber(Math.floor(value / 1000))}.${String(value % 1000).padStart(3, "0")}`;
}

// {L} is the target length, {M} the upper bound. detailLevelParity.test.ts checks these texts against the Swift file.
export const KORT_BLOCK = "Detailniveau Kort: schrijf een beknopte notule van ongeveer {L} tekens, hooguit {M}. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Laat bijzaken, achtergrond, voorbeelden, anekdotes, herhalingen en zijpaden weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau en de secties van het profiel; laat secties weg die alleen bijzaken zouden bevatten.";
export const NORMAAL_BLOCK = "Detailniveau Normaal: schrijf een notule van ongeveer {L} tekens, hooguit {M}. Neem altijd op: besluiten, acties met actiehouder en termijn, bedragen en getallen bij een besluit of actie, en ontkenningen en voorwaarden bij een besluit of actie. Geef per hoofdonderwerp in één of twee zinnen de context. Laat zijpaden, anekdotes, herhalingen en details zonder gevolg voor een besluit of actie weg; een weggelaten bijzaak is geen fout. Dit detailniveau gaat vóór het detailniveau van het profiel.";

/** The block appended at the very end of the draft user message; empty at volledig, so that message is unchanged. */
export function draftBlock(detail: NotuleDetailLevel, transcriptCharacters: number): string {
  const target = targetLength(detail, transcriptCharacters);
  if (target === null) return "";
  return "\n\n" + (detail === "kort" ? KORT_BLOCK : NORMAAL_BLOCK)
    .replace("{L}", dutchNumber(target)).replace("{M}", dutchNumber(maximumLength(target)));
}

export const AUDIT_SUFFIX_TEXT = "Deze notule is bewust beknopt. Een bronzin die in de notule ontbreekt en alleen een bijzaak bevat, krijgt status minor met lege evidence in plaats van missing. minor is NOOIT toegestaan voor besluiten, acties, actiehouders, termijnen, bedragen, getallen, ontkenningen, verboden, voorwaarden, afwezigheid of open vragen; ontbreken die, dan blijft het missing. Twijfel je of iets een bijzaak is, kies missing. Gebruikersnotities (Q) zijn nooit minor.";

/** Added as a last line to the single-request audit prompt and to COVERAGE_SYSTEM; empty at volledig. */
export const auditSuffix = (detail: NotuleDetailLevel) => detail === "volledig" ? "" : "\n" + AUDIT_SUFFIX_TEXT;

/** Source statuses the content audit accepts from the model: minor only below volledig. */
export const sourceStatuses = (detail: NotuleDetailLevel) =>
  ["covered", "non_factual", "missing", "uncertain", ...(detail === "volledig" ? [] : ["minor"])];

/** The level a transcript's notule was generated with, for the same profile only; undefined for older transcripts. */
export function storedDetailLevel(transcript: Pick<Transcript, "profile_id" | "detail_level" | "notule_usage">, profileId: string): NotuleDetailLevel | undefined {
  if (transcript.profile_id !== profileId) return undefined;
  return level(transcript.detail_level ?? transcript.notule_usage?.detail_level);
}

/** The choices after picking `detail` for `profile` in the profile settings; the profile's own default removes the override. */
export function chooseDetailLevel(choices: Record<string, NotuleDetailLevel>, profile: Pick<Profile, "id" | "detail_level">, detail: NotuleDetailLevel): Record<string, NotuleDetailLevel> {
  const rest = { ...choices };
  delete rest[profile.id];
  return detail === level(profile.detail_level) ? rest : { ...rest, [profile.id]: detail };
}

/** The level regenerating `transcript` with an (enriched) `profile` starts from, and the one the regenerate dialog
 * preselects: the stored level when the profile stays the same, else the profile's effective level. */
export function regenerateDetailLevel(transcript: Pick<Transcript, "profile_id" | "detail_level" | "notule_usage">,
  profile: Pick<Profile, "id" | "detail_level">, choices: Record<string, string> = {}): NotuleDetailLevel {
  return storedDetailLevel(transcript, profile.id) ?? effectiveDetailLevel(profile, choices);
}
