# Phase 2: UX Review - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 2-UX Review
**Areas discussed:** Review-uitvoering, Heuristiek-kader, Prioritering-rubriek, Bevindingen-format

Note: advisor-mode research/comparison-table flow overgeslagen op verzoek van de developer-profiel-directive ("concrete recommendation, not long trade-off matrices"). In plaats daarvan concise opties met aanbeveling.

---

## Review-uitvoering

| Option | Description | Selected |
|--------|-------------|----------|
| Hybride (live + code) | Live waar representatief, code-inspectie als vangnet (Windows native effects renderen niet op macOS) | |
| Volledig live | Beide apps echt draaien en doorklikken met screenshots | ✓ |
| Alleen code-inspectie | SwiftUI + React broncode heuristisch lezen, geen build/run | |

**User's choice:** Volledig live — "Ik heb CrossOver op Mac draaien dus optie 2 is mogelijk" (echte Windows-binary draait op de Mac).
**Notes:** Gestructureerde expert review per flow, per platform, met parity-pass. 5 kernflows apart doorlopen op macOS én Windows. Per flow drie checks: task completion, heuristische check, platform parity check. Geen user testing in deze fase.

---

## Heuristiek-kader

| Option | Description | Selected |
|--------|-------------|----------|
| Nielsen + HIG/Fluent | Nielsen's 10 als basis + Apple HIG (macOS) + Fluent 2 (Windows) voor parity-checks | ✓ |
| Alleen Nielsen's 10 | Puur de 10 usability heuristics | |
| Eigen checklist per flow | Maatwerk-checklist per kernflow | |

**User's choice:** Nielsen + HIG/Fluent.
**Notes:** Nielsen als gemeenschappelijke basis voor álle bevindingen; HIG/Fluent specifiek voor platform-specifieke conventie-afwijkingen (belangrijk bij macOS/Windows-app).

---

## Prioritering-rubriek

| Option | Description | Selected |
|--------|-------------|----------|
| Severity × frequentie + parity-boost | Severity gewogen met frequentie; parity-gaps +1 niveau | ✓ |
| Puur severity | Blokkeert = P1, hindert = P2, cosmetisch = P3 | |
| Impact × effort | Quick wins eerst | |

**User's choice:** Severity × frequentie + parity-boost, mét nuance: **lichte triage-regel, géén numerieke scorematrix**.
**Notes:** Basisprioriteit op taakimpact (P1 kritiek / P2 belangrijk / P3 polish). Frequentie-regel: ±1 niveau bij hoogfrequent/centraal vs edge case. Parity-boost: +1 niveau bij macOS↔Windows-verschil in gedrag/feedback/terminologie/navigatie/herstel/vindbaarheid; niet boosten voor puur cosmetische platform-eigen verschillen. Effort telt niet mee in Phase 2 (Phase 4). Per finding kort noteren waarom P1/P2/P3.

---

## Bevindingen-format

| Option | Description | Selected |
|--------|-------------|----------|
| één markdown-tabel + IDs | FINDINGS.md met stabiele FND-IDs, vaste kolommen | ✓ |
| Per-platform bestanden | Aparte macOS + Windows lijsten | |
| Per-finding records | Los markdown-blok per bevinding | |

**User's choice:** Eén `FINDINGS.md` met stabiele FND-IDs als source of truth.
**Notes:** Kolommen: ID, Prio, Platform, Flow, Titel, Heuristiek/richtlijn, Severity, Frequentie, Parity, Impact, Fix-hint, Evidence. Gestandaardiseerde waarden. IDs niet hernummeren. Optionele korte detailsectie onder de tabel voor complexe P1/P2-items. Phase 4-plannen (02-01 macOS / 02-02 Windows) verwijzen naar FND-IDs i.p.v. dupliceren. Geen per-platform bestanden als primair format — gezamenlijke lijst is juist de Phase 2-output.

## Claude's Discretion

- Bewoording van losse bevindingen en heuristiek-mapping per item.
- Invulling van de optionele detailsecties.
- Evidence-vorm per finding (screenshot-ref / scherm-aanduiding / timestamp).

## Deferred Ideas

None — discussie bleef binnen de phase-scope (alleen HOE, geen nieuwe capabilities).
