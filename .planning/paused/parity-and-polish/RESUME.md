# ON HOLD — Parity & Polish (v1.0.134)

**Gepauzeerd:** 2026-06-04 — bewust on hold gezet om eerst de milestone **People & Attribution** te doen.
**Status bij pauze:** executing, 25% (1 van 4 fasen af).

## Stand van zaken bij pauze

- **Phase 1 — Quick Fixes:** ✅ compleet. Geshipt: C-01 (Windows SSE-reconnect), C-02 (HTTPS afdwingen Windows), C-03 (offline-queue id-identiteit + gedeelde retry), D-01 (combined-audio element-wise max), D-02 (timer-threading).
- **Phase 2 — UX Review (B-01):** 🟡 deels. Plan **02-01 (macOS)** uitgevoerd: `FINDINGS.md` aangemaakt met **14 macOS-bevindingen** (FND-001..FND-014), verificatiescript geslaagd, macOS-build SUCCEEDED. **Stond op een open human-verify checkpoint** ("approved" of correcties) toen we pauzeerden. Plan **02-02 (Windows + parity)** nog NIET gestart (vereist CI-MSI onder CrossOver).
- **Phase 3 — Windows local-first (A-01..A-05, C-04):** ⬜ niet gestart (STT-engine-keuze open: whisper.cpp-kandidaat).
- **Phase 4 — UX-fixes (B-02..B-04):** ⬜ niet gestart; gevoed door `FINDINGS.md` uit Phase 2.

## Inhoud van deze snapshot

- `PROJECT.md` — P&P-versie van het project-doc (kopie; live `PROJECT.md` is door de nieuwe milestone bijgewerkt).
- `STATE.md` — P&P-state op moment van pauze (kopie).
- `ROADMAP.md`, `REQUIREMENTS.md` — verplaatst (live versies horen nu bij People & Attribution).
- `phases/` — `01-quick-fixes/` + `02-ux-review/` (incl. `FINDINGS.md`, plannen, CONTEXT, UI-SPEC) — verplaatst.

## Hervatten (later)

1. Zet de actieve milestone (People & Attribution) opzij: verplaats live `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `.planning/phases/` naar `.planning/paused/people-and-attribution/`.
2. Herstel P&P: verplaats `ROADMAP.md`, `REQUIREMENTS.md`, `phases/` uit deze map terug naar `.planning/`.
3. Herstel `PROJECT.md`/`STATE.md` indien gewenst uit deze kopieën (of merge handmatig — `PROJECT.md` is project-breed en kan beide milestones bevatten).
4. Hervat met `/gsd-execute-phase 2` (Phase 2 stond op het 02-01 checkpoint).

`.planning/codebase/` en `config.json` zijn project-breed en gedeeld — niet verplaatst.
