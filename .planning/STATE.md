---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: People & Attribution
status: executing
stopped_at: Phase 1 UI-SPEC approved
last_updated: "2026-06-05T09:47:33.193Z"
last_activity: 2026-06-05
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 4
  completed_plans: 1
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-04)

**Core value:** Notulen herkennen wie-wie is en wijzen actiepunten betrouwbaar toe aan de juiste persoon op basis van lokaal opgebouwde persoons-/rolcontext — on-device, corrigeerbaar.
**Current focus:** Phase 01 — self-profile-foundation

## Current Position

Phase: 01 (self-profile-foundation) — EXECUTING
Plan: 2 of 4
Status: Ready to execute
Last activity: 2026-06-05

Progress: [███░░░░░░░] 25%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| — | — | — | — |

*Updated after each plan completion*
| Phase 01-self-profile-foundation P00 | 109 | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions zijn gelogd in PROJECT.md Key Decisions table.
Recente beslissingen die het huidige werk raken:

- Day-1: `PersonProfile` met `isSelf: Bool` dekt zowel zelf-profiel als directory-entries in één model — geen apart `SelfProfile`/`DirectoryPerson`-split
- Day-1: `SchemaMigrationPlan` MOET in Phase 1 landen vóór elk model-change; testen op echt apparaat met bestaande data (niet alleen simulator)
- Day-1: Nooit de naam `Profile` hergebruiken voor het nieuwe concept — botsing met bestaand `Profile`-type in `Models.swift:219-302`
- 2026-06-05: Scope-verrijking — attributie ook op **onderwerp→rol/expertise** (C-05, D-01), `expertiseTags` in datamodel vanaf Phase 1 (A-05), leerlus die profiel verrijkt (D-06), `source`+`confidence` per toewijzing (D-05). Requirements 15→21.
- 2026-06-05: Spike spreker-identiteit — NIET beschikbaar (`whisper_neuron.py:133-140`, één segment, geen labels/timestamps; macOS lokaal idem). v1.1 niet afhankelijk van diarisatie.

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 1 AMENDMENT vóór executie**: gefinaliseerde plannen (01-00..01-03) missen `expertiseTags: [String]` op `PersonProfile` (A-05). Toevoegen vóór start, anders 2e migratie nodig in Phase 3/4. Volg `meetingTypes`/`aliases` als `[String]`-precedent. Zie ROADMAP Phase 1 amendment-note.
- Phase 3: spike verplicht vóór planning — n8n workflow `Iq3AAf8Vk8eQ9dcZ` node-structuur + vier backend-payload-locaties + regenerate-pad (zie ROADMAP.md Phase 3 spike-taken)
- Phase 4: spike verplicht vóór planning — echte notule-HTML inspecteren + FND-008 actuele staat bevestigen
- Spreker-identiteit: spike afgerond (geen diarisatie beschikbaar) — geen blocker meer, wel scope-grens vastgelegd

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Parity & Polish | Phase 2 UX-review (macOS-deel klaar, niet afgerond) | On hold | v1.1 start |
| Android | Android parity | Deferred | Milestone scope |

## Session Continuity

Last session: 2026-06-05T09:47:33.169Z
Stopped at: Phase 1 UI-SPEC approved
Resume file: None
