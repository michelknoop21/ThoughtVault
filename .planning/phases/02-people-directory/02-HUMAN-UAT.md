---
status: partial
phase: 02-people-directory
source: [02-VERIFICATION.md]
started: 2026-06-07T16:15:00Z
updated: 2026-06-07T16:15:00Z
---

# Phase 2: People Directory — Human UAT

Code verification passed 5/5 must-haves (see 02-VERIFICATION.md). The two items
below require a running app + a live Microsoft 365 account and cannot be checked
programmatically. The phase stays **pending** until both pass.

## Current Test

[awaiting human testing]

## Tests

### UAT-1 — macOS directory CRUD + live agenda-seed flow
**Status:** pending

1. Build + run the **signed** app from `/Applications`. Press **Cmd+6** — the Mensen tab opens
   (check both the collapsed 52px icon column and the expanded sidebar). Sidebar shows 'Mensen'
   with the `person.2` icon.
2. Click **'Persoon toevoegen'**, fill naam + rol + expertise (comma-separated) + pick **'Extern'**,
   save — 'Opgeslagen' appears and the row shows a **blue** status dot. Edit it, change to **'Intern'**
   (**green** dot). Delete via the trash button + confirmationDialog; confirm it's gone (and that a
   delete failure would now surface an error, per CR-01 follow-up fix).
3. On a machine signed into **M365**: start a recording linked to a calendar event with ≥2 real
   attendees, then stop it. Confirm the **'Nieuwe deelnemers gevonden'** sheet lists ONLY new
   (deduped) attendees and **NOT** the current user (D-10). Uncheck one, confirm the rest. Reopen
   Mensen — only confirmed people present, each showing a **gray 'Onbekend'** dot (D-09).

**Why human:** Live Microsoft 365 account required for the end-to-end seed flow; UI appearance
(dot colors, tri-state picker, sidebar transitions) cannot be verified programmatically.

### UAT-2 — Windows directory CRUD + Ctrl+6 navigation
**Status:** pending

Navigate to `/people` with **Ctrl+6** (or the sidebar Mensen item). Add a person with
comma-separated expertiseTags + **Onbekend** status, save, verify persistence across a page reload.
Edit to **Intern**, delete with inline confirm. If running a live M365 seed, confirm the seed
sheet's displayed names match what gets stored (split-on-separator capitalization, per WR-03 fix).

**Why human:** Tauri 2 Windows UI requires the running app; visual states and localStorage
persistence across reloads require manual inspection.

## Gaps

None blocking — code review's 2 Critical + 5 Warning findings were fixed (see 02-REVIEW.md /
02-REVIEW-FIX.md), and the two verifier follow-up warnings (delete() throw, render-loop name
derivation) were resolved in commits e30c501 + 42eb3e4.
