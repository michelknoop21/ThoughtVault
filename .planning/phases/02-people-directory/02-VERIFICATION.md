---
phase: 02-people-directory
verified: 2026-06-07T16:10:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Verify macOS directory CRUD + live agenda-seed flow"
    expected: |
      1. Build + run signed app from /Applications. Press Cmd+6 — Mensen tab opens (also check
         collapsed 52px icon + expanded sidebar state). Sidebar shows 'Mensen' with person.2 icon.
      2. Click 'Persoon toevoegen', fill naam + rol + expertise (comma-separated) + pick 'Extern',
         save — 'Opgeslagen' appears and row shows a blue status dot. Edit it, change to 'Intern'
         (green dot). Delete via trash button + confirmationDialog, confirm it's gone.
      3. On a machine signed into M365: start recording linked to calendar event with >=2 real
         attendees, stop it. Confirm 'Nieuwe deelnemers gevonden' sheet lists ONLY new (deduped)
         attendees and NOT the current user. Uncheck one, confirm the rest. Reopen Mensen — only
         confirmed people present, each showing gray 'Onbekend' dot.
    why_human: "Live Microsoft 365 account required for end-to-end seed flow; UI appearance (dot
      colors, tri-state picker, sidebar transitions) cannot be verified programmatically."
  - test: "Verify Windows directory CRUD + Ctrl+6 navigation"
    expected: |
      Navigate to /people with Ctrl+6 (or sidebar Mensen item). Add a person with comma-separated
      expertiseTags + Onbekend status, save, verify persistence across page reload. Edit to Intern,
      delete with inline confirm.
    why_human: "Tauri 2 Windows UI requires running app; visual states and localStorage persistence
      across reloads require manual inspection."
---

# Phase 2: People Directory — Verification Report

**Phase Goal:** De gebruiker beschikt over een lokale directory van collega's en bekende externen die hij handmatig kan beheren en (semi-)automatisch kan aanvullen vanuit agenda-deelnemers.
**Verified:** 2026-06-07T16:10:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Gebruiker kan persoon toevoegen/bewerken/verwijderen via directory-UI op macOS én Windows | VERIFIED | `PeopleDirectoryView.swift` (267 lines), `PersonEditView.swift` (244 lines) with `confirmationDialog` delete; `PeoplePage.tsx` (259 lines), `PersonEditModal.tsx` (313 lines). Build SUCCEEDED. |
| SC-2 | Na vergadering met agenda-deelnemers prompt "Voeg deelnemers toe?" — handmatig per persoon, geen auto-commit | VERIFIED | `SeedReviewSheet.swift` checks `newSeedCandidates` before presentation; `ContentView.swift:260` only presents when list non-empty; unchecked entries not persisted. Windows `RecordingPage.tsx` stop handler mirrors pattern. |
| SC-3 | Nieuw via agenda-seed toegevoegde personen: `isInternal = nil` (onbekend), corrigeerbaar | VERIFIED | `PersonDirectoryService.seedPerson()` line 107: `isInternal: nil`. Windows factory: `isInternal: null`. PersonEditView/Modal provide tri-state picker (Intern/Extern/Onbekend). |
| SC-4 | `PersonDirectoryService` bevat geen URLSession-referenties | VERIFIED | `grep -c "URLSession" PersonDirectoryService.swift` = 0. macOS service accesses `LocalTranscriptStore.shared.container.mainContext` only. |
| SC-5 | Directory-entries gebruiken hetzelfde `PersonProfile`-model; `expertiseTags` per persoon bewerkbaar (B-04) | VERIFIED | macOS: `PersonEditView.swift` lines 60/115/184/209/220 wire `expertiseTags` via comma-separated TextField + `splitAndTrim`. Windows: `PersonEditModal.tsx` lines 27/74 same. `isSelf == false` invariant enforced at both stores. |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `macos/Models/PersonProfile.swift` | `emails: [String]` + `isInternal: Bool?` | VERIFIED | Line 28: `var emails: [String]`, line 33: `var isInternal: Bool?` |
| `macos/Models/AppMigrationPlan.swift` | `AppSchemaV3` + `v2ToV3` lightweight stage | VERIFIED | Lines 37–60: enum + lightweight stage, no custom stage, `MigrationStage.custom` count = 0 |
| `macos/Services/PersonDirectoryService.swift` | CRUD + dedup, no network | VERIFIED | 130+ lines, `static let shared`, `add() throws`, `update() throws`, 0 URLSession references |
| `macos/Services/CalendarService.swift` | `attendees: [String] = []` + `organizer: String? = nil` | VERIFIED | Lines 38/40 with defaults (all 5 construction sites kept compiling) |
| `macos/Services/MicrosoftGraphService.swift` | `emailAddress.address` decode | VERIFIED | Lines 311–312: `compactMap { $0.emailAddress?.address }` |
| `macos/Views/PeopleDirectoryView.swift` | Searchable list with CRUD | VERIFIED | 267 lines, `searchable`, `confirmationDialog`, `Persoon toevoegen` CTA |
| `macos/Views/PersonEditView.swift` | Edit form with tri-state picker | VERIFIED | 244 lines, `InternalStatus` enum, segmented `Picker`, `splitAndTrim`, "Wijzigingen opslaan" |
| `macos/Views/SeedReviewSheet.swift` | Per-person confirm sheet | VERIFIED | 165 lines, "Nieuwe deelnemers gevonden", "Overslaan", `newSeedCandidates` call |
| `windows/src/types.ts` | `emails: string[]` + `isInternal: boolean \| null` | VERIFIED | Line 86: `emails: string[]`, line 88: `isInternal: boolean \| null` |
| `windows/src/stores/peopleDirectoryStore.ts` | Collection store, key `people-directory-store` | VERIFIED | Line 88: `name: "people-directory-store"`, CRUD + `newSeedCandidates` |
| `windows/src/pages/PeoplePage.tsx` | Directory list at /people | VERIFIED | 259 lines, search filter, status dots, delete confirm |
| `windows/src/pages/PersonEditModal.tsx` | Add/edit form | VERIFIED | 313 lines, comma tags, tri-state `<select>`, "Wijzigingen opslaan" |
| `windows/src/pages/SeedReviewSheet.tsx` | Per-person seed confirm | VERIFIED | 206 lines, `addPerson` on confirm only, "Overslaan" secondary |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ContentView AppTab.people` | `PeopleDirectoryView` | `case .people` switch arm | VERIFIED | `ContentView.swift` line 539: `case .people:` routes to `PeopleDirectoryView()` |
| `RecordingViewModel.pendingSeedAttendees` | `SeedReviewSheet` | `onChange` observer in ContentView | VERIFIED | `ContentView.swift:251–260`: onChange calls `newSeedCandidates`, only presents when non-empty |
| `PersonDirectoryService` | `LocalTranscriptStore.shared.container` | `mainContext` CRUD | VERIFIED | `PersonDirectoryService.swift:31`: `_container = LocalTranscriptStore.shared.container`; `context` computed via `_container.mainContext` |
| `MicrosoftGraphService GraphEvent decode` | `CalendarEvent.attendees` | `emailAddress.address` compactMap | VERIFIED | Lines 311–312 in MicrosoftGraphService.swift |
| `App.tsx Route /people` | `PeoplePage` | `<Route path="/people">` | VERIFIED | `App.tsx:346`: `<Route path="/people" element={<PeoplePage />} />` |
| `Windows newSeedCandidates` | `usePersonProfileStore` self-profile emails | Import + `getState().profile` | VERIFIED | `peopleDirectoryStore.ts:4,63,73`: CR-02 fix confirmed |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `PeopleDirectoryView` | `people: [PersonProfile]` | `PersonDirectoryService.shared.directoryPeople()` → SwiftData fetch with `isSelf==false` predicate | Yes — SwiftData FetchDescriptor query | FLOWING |
| `SeedReviewSheet` (macOS) | `candidates: [SeedCandidate]` | `newSeedCandidates(from:selfEmail:)` → deduped from directoryPeople() emails | Yes — live dedup from store | FLOWING |
| `PeoplePage` (Windows) | `people: PersonProfile[]` from `usePeopleDirectoryStore` | Zustand persist → localStorage `people-directory-store` | Yes — real Zustand store, 4/4 tests GREEN | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| macOS build succeeds | `xcodebuild build CODE_SIGNING_ALLOWED=NO` | `** BUILD SUCCEEDED **` | PASS |
| Windows vitest store tests | `npx vitest run peopleDirectoryStore.test.ts` | `4 passed (4)` | PASS |
| URLSession not in PersonDirectoryService | `grep -c URLSession PersonDirectoryService.swift` | `0` | PASS |
| AppTab.people keyboard shortcut | `grep 'return "6"' ContentView.swift` for people | people="6", admin="8" (WR-04 applied) | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| B-01 | 02-02, 02-03, 02-04, 02-05 | Personen lokaal vastleggen: naam, aliassen, rol, intern/extern, organisatie | SATISFIED | PersonProfile model + edit form on both platforms |
| B-02 | 02-04, 02-05 | Toevoegen/bewerken/verwijderen via directory-UI (beide platforms) | SATISFIED | CRUD fully wired on macOS + Windows; confirmed by build |
| B-03 | 02-03, 02-04, 02-05 | Semi-automatisch aanvullen vanuit agenda-deelnemers, gebruiker in controle | SATISFIED | SeedReviewSheet per-person confirm, no auto-commit; dedup runs before presentation |
| B-04 | 02-02, 02-04, 02-05 | Zelfde `expertiseTags` als zelf-profiel, bewerkbaar via directory-UI | SATISFIED | `expertiseTags` field in PersonEditView (macOS) + PersonEditModal (Windows); comma-separated consistent with Phase 1 onboarding |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `macos/Services/PersonDirectoryService.swift` | 85 | `try? context.save()` in `delete(_ person:)` — swallows delete-save errors | WARNING | CR-01 fixed `add()` and `update()` to `throws`, but the non-ID `delete(_ person:)` overload still discards save errors silently. The `deletePerson(id:)` overload (line 89) correctly `throws`. The UI uses `PersonDirectoryService.shared.delete(_:)` (PeopleDirectoryView) which swallows failures. Low severity: delete failures are rarer and less data-loss-critical than add/update, but inconsistent. |
| `windows/src/pages/SeedReviewSheet.tsx` | 118–120 | Duplicate name derivation inside `rows.map` uses old single-word capitalize (no `split(/[._-]/)`), bypassing the WR-03 fix at lines 34–39 | WARNING | For emails like `j.smith@co.com`, the row label renders "J.smith" instead of "J Smith". The `displayName` helper at line 34 (used at line 157 as the confirmed person's name) IS correctly fixed. Visual inconsistency in the list row labels only; no data-correctness impact. |

No `TBD`, `FIXME`, or `XXX` markers found in any phase-2 source files.

---

### Human Verification Required

#### 1. macOS Directory UI + Live Agenda-Seed Flow

**Test:** Build + run the signed app from `/Applications` (TCC grants preserved). Verify:
1. `Cmd+6` opens the Mensen tab. Sidebar shows correct icon collapsed (52px) and label expanded.
2. "Persoon toevoegen" → fill naam/rol/expertise/Extern → save → confirm "Opgeslagen" + blue dot. Edit → Intern → green dot. Delete → confirmationDialog → gone.
3. On M365 machine: start recording linked to calendar event with ≥2 real attendees → stop → confirm "Nieuwe deelnemers gevonden" sheet shows only new people (NOT the current user). Uncheck one, confirm rest. Reopen Mensen: only confirmed present, all with gray Onbekend dot.

**Expected:** All three steps pass without issues.
**Why human:** Live M365 account required for the seed end-to-end path; UI dot colors, tri-state picker appearance, and sidebar state transitions are not verifiable via grep.

#### 2. Windows Directory CRUD + Ctrl+6

**Test:** In the Tauri Windows app, press `Ctrl+6` (or click Mensen in sidebar). Add a person with comma-separated expertiseTags + Onbekend status; save; reload the page/app; confirm data persisted. Edit to Intern; delete with inline confirm; confirm removed.

**Expected:** All steps pass; localStorage key `people-directory-store` holds the data (distinct from `person-profile-store`).
**Why human:** Tauri 2 Windows app requires running the actual binary; visual rendering and localStorage persistence across reloads require manual observation.

---

### Gaps Summary

No blocking gaps. All 5 success criteria are satisfied in code. Two warnings were found:

1. **`PersonDirectoryService.delete(_ person:)` still uses `try? context.save()`** — the CR-01 fix correctly addressed `add()` and `update()`, but this `delete` overload was missed. `deletePerson(id:)` is fixed. Impact is low (delete failures are not data-loss events), but inconsistency with the CR-01 intent is noted.

2. **Windows `SeedReviewSheet.tsx` lines 118–120: duplicate name derivation bypasses WR-03 fix** — the row *label* in the sheet uses the old single-word capitalize. The confirmed person's `name` field (written to the store) uses the corrected helper at line 34. Visual only; no correctness impact on stored data.

Neither warning blocks the phase goal. Phase goal is substantively achieved pending human sign-off on live UI behavior.

---

_Verified: 2026-06-07T16:10:00Z_
_Verifier: Claude (gsd-verifier)_
