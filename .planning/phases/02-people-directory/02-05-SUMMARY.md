---
phase: 02-people-directory
plan: 05
subsystem: windows-people-directory
tags: [windows, react, zustand, people-directory, graph-api, seed-review, typescript]

requires:
  - phase: 02-people-directory/02-01
    provides: RED Windows vitest scaffold (peopleDirectoryStore.test.ts)
  - phase: 02-people-directory/02-02
    provides: macOS PersonProfile parity reference (emails + nullable isInternal)

provides:
  - Windows PersonProfile with emails: string[] and isInternal: boolean | null
  - usePeopleDirectoryStore (collection, key people-directory-store, CRUD + dedup)
  - Graph attendee emailAddress.address fix (was .email — silent undefined)
  - PeoplePage at /people (search, list, add/edit/delete with confirm)
  - PersonEditModal (comma-separated tags, tri-state intern/extern/onbekend)
  - SeedReviewSheet (per-person checkboxes, deduped, non-auto-commit)
  - pendingSeedAttendees wiring: set on calendar-event start, read-and-cleared on stop
  - peopleDirectoryStore.test.ts GREEN (4/4 tests)
  - jsdom + test-setup.ts for vitest store tests

affects:
  - windows/src/types.ts (PersonProfile type extended)
  - windows/src/stores/personProfileStore.ts (emails field added)
  - windows/src/stores/recordingStore.ts (pendingSeedAttendees field)
  - windows/src/pages/RecordingPage.tsx (stop wiring)
  - windows/src/components/calendar/CallAlertOverlay.tsx (start wiring)
  - windows/src/App.tsx (route + Ctrl+6)
  - windows/src/components/layout/Sidebar.tsx (Mensen nav item)

tech-stack:
  added:
    - jsdom (dev dependency — vitest jsdom environment for store tests)
  patterns:
    - "zustand persist collection store: people[]: PersonProfile[] with isSelf:false invariant"
    - "Distinct localStorage key per store (people-directory-store) — Pitfall 4 mitigated"
    - "jsdom + Map-backed localStorage mock in setupFiles so persist captures storage at import time"
    - "Tri-state isInternal: boolean | null via <select> — null=Onbekend default for seeded entries"
    - "Comma-separated tag inputs (splitAndTrim) matching Phase 1 onboarding convention"
    - "pendingSeedAttendees: set on calendar-triggered start, read-and-cleared on stop (bounded scope)"

key-files:
  created:
    - windows/src/stores/peopleDirectoryStore.ts
    - windows/src/pages/PeoplePage.tsx
    - windows/src/pages/PersonEditModal.tsx
    - windows/src/pages/SeedReviewSheet.tsx
    - windows/src/test-setup.ts
  modified:
    - windows/src/types.ts
    - windows/src/stores/personProfileStore.ts
    - windows/src/stores/recordingStore.ts
    - windows/src/services/microsoftGraph.ts
    - windows/src/pages/RecordingPage.tsx
    - windows/src/components/calendar/CallAlertOverlay.tsx
    - windows/src/App.tsx
    - windows/src/components/layout/Sidebar.tsx
    - windows/vite.config.ts
    - windows/tsconfig.json

key-decisions:
  - "jsdom installed as dev dependency (standard vitest peer); Map-backed localStorage mock in setupFiles ensures persist captures working storage at module-import time (before test environment URL is set)"
  - "SeedReviewSheet rendered inside RecordingPage (not IdleState/ActiveState sub-components) so it has access to seedCandidates state"
  - "pendingSeedAttendees set only in CallAlertOverlay (calendar-triggered start), not in HomePage quick-start (no event attendees) — bounded scope per plan"
  - "personProfileStore upsert also updated with emails: [] to satisfy PersonProfile interface after type change"

metrics:
  duration: ~17min
  completed: 2026-06-07
  tasks: 3
  files: 14
---

# Phase 2 Plan 05: Windows People Directory Summary

**Cross-platform parity delivered: PersonProfile extended with emails + nullable isInternal, people-directory-store with CRUD + dedup, Graph .email bug fixed, /people page with add/edit/delete + tri-state + comma tags, SeedReviewSheet confirms attendees per-person — peopleDirectoryStore.test.ts GREEN (4/4)**

## Performance

- **Duration:** ~17 min
- **Started:** 2026-06-07T12:58:06Z
- **Completed:** 2026-06-07T13:15:00Z
- **Tasks:** 3
- **Files modified:** 14 (5 created, 9 modified)

## Accomplishments

- Extended `PersonProfile` with `emails: string[]` (dedup key, D-02) and changed `isInternal: boolean` to `boolean | null` (tri-state, D-01) — Windows-parity with macOS SchemaV3
- Created `usePeopleDirectoryStore` with collection state (`people: PersonProfile[]`), CRUD actions, `createDefaultPerson` factory (isInternal:null, emails:[], isSelf:false), and `newSeedCandidates` dedup helper — all with distinct localStorage key `people-directory-store` (Pitfall 4 mitigated, T-02-09)
- Fixed Graph attendee key bug: `a.emailAddress?.email` → `a.emailAddress?.address` (T-02-11; Graph v1.0 documented key)
- Turned `peopleDirectoryStore.test.ts` GREEN: 4/4 tests pass (round-trip, factory defaults, distinct key, dedup)
- Created `PeoplePage.tsx`: search on name+aliases+emails, settings-group list rows with status dot, hover-reveal delete with inline confirm ("Weet je het zeker?"), empty/search-empty states, Dutch copy per UI-SPEC
- Created `PersonEditModal.tsx`: comma-separated tag inputs for aliases + expertiseTags (consistent with Phase 1 onboarding), `<select>` tri-state defaulting to Onbekend, 2s "Opgeslagen" feedback, error state
- Wired `/people` route in App.tsx + Ctrl+6 keyboard shortcut + People24Regular sidebar nav item "Mensen"
- Created `SeedReviewSheet.tsx`: per-person checkboxes (default ON), pluralized confirm button, "Overslaan" secondary, D-10 self-email footnote, only confirms checked rows (T-02-10)
- Added `pendingSeedAttendees: string[]` to recordingStore — set in CallAlertOverlay on calendar-triggered start, read-and-cleared in RecordingPage.handleStopRecording on stop; SeedReviewSheet shown only when `newSeedCandidates` returns non-empty deduped list
- Added jsdom + Map-backed localStorage mock (setupFiles) so zustand persist stores can be tested

## Task Commits

1. **Task 1: types + peopleDirectoryStore + Graph fix** — `2f5eadc` (feat)
2. **Task 2: PeoplePage + PersonEditModal + route/nav** — `9dc64fa` (feat)
3. **Task 3: SeedReviewSheet + pendingSeedAttendees wiring** — `b42048a` (feat)

## Files Created/Modified

- `/windows/src/types.ts` — PersonProfile: emails: string[], isInternal: boolean | null
- `/windows/src/stores/personProfileStore.ts` — added emails: [] to new-profile factory
- `/windows/src/stores/peopleDirectoryStore.ts` — collection store, key people-directory-store, CRUD + dedup
- `/windows/src/services/microsoftGraph.ts` — attendee .email → .address fix
- `/windows/src/stores/recordingStore.ts` — pendingSeedAttendees field + set/clear actions
- `/windows/src/pages/PeoplePage.tsx` — directory list page at /people
- `/windows/src/pages/PersonEditModal.tsx` — add/edit form with comma tags + tri-state
- `/windows/src/pages/SeedReviewSheet.tsx` — post-stop attendee confirm sheet
- `/windows/src/pages/RecordingPage.tsx` — stop handler reads+clears pending, shows sheet
- `/windows/src/components/calendar/CallAlertOverlay.tsx` — sets pendingSeedAttendees on calendar-start
- `/windows/src/App.tsx` — Route /people + Ctrl+6 + PeoplePage import
- `/windows/src/components/layout/Sidebar.tsx` — People24Regular nav item Mensen (Ctrl+6)
- `/windows/src/test-setup.ts` — Map-backed localStorage mock for vitest
- `/windows/vite.config.ts` — test.environment=jsdom + setupFiles
- `/windows/tsconfig.json` — exclude test files from main build

## Decisions Made

- **jsdom installed as dev dependency** — standard vitest optional peer dependency; Map-backed mock in `setupFiles` solves the zustand persist initialization timing issue (zustand captures `localStorage` reference at module-import time, before jsdom's URL-based storage is set up)
- **SeedReviewSheet in RecordingPage root** — not in sub-components (`IdleState`/`ActiveState`) so it has React state access from the parent
- **pendingSeedAttendees bounded scope** — only `CallAlertOverlay.handleRecord` sets it (calendar-triggered recording), not `HomePage.handleRecordMeeting` (no attendee data available there from the quick-start path)
- **personProfileStore updated** — the `emails: []` field added to the factory to satisfy the extended `PersonProfile` interface; `isInternal: true as boolean | null` explicit cast keeps the self-profile semantics

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] vitest jsdom environment not configured; localStorage unavailable**
- **Found during:** Task 1 test run
- **Issue:** `peopleDirectoryStore.test.ts` calls `localStorage.clear()` and zustand persist needs `localStorage.setItem` — both fail with `not a function` in the default vitest node environment
- **Fix:** Added `environment: "jsdom"` to `vite.config.ts`, installed `jsdom` as devDependency, created `src/test-setup.ts` with a Map-backed localStorage that zustand can capture at import time (avoids jsdom URL-initialization timing issue)
- **Files modified:** `windows/vite.config.ts`, `windows/src/test-setup.ts`, `windows/tsconfig.json` (test exclusion)
- **Impact:** 4/4 tests now GREEN

**2. [Rule 3 - Blocking] test-setup.ts included in main TypeScript build**
- **Found during:** Task 2 build verification
- **Issue:** `tsconfig.json` includes all of `src/`, causing `test-setup.ts` to be type-checked against browser types (error: `Cannot find name 'global'`)
- **Fix:** Added `"exclude": ["src/test-setup.ts", "src/**/__tests__/**"]` to tsconfig.json; changed `global` to `window` in test-setup.ts
- **Files modified:** `windows/tsconfig.json`, `windows/src/test-setup.ts`

**3. [Rule 3 - Blocking] SeedReviewSheet JSX placed inside IdleState sub-component scope**
- **Found during:** Task 3 build verification
- **Issue:** JSX was appended to the wrong function (`IdleState`) instead of `RecordingPage`, causing TS2304 (seedCandidates not in scope)
- **Fix:** Moved SeedReviewSheet render into RecordingPage's return statement (before closing div)

## Known Stubs

None. All directory data flows are fully wired: store → UI → localStorage persistence. The seed wiring is complete end-to-end (calendar event → attendees → dedup → sheet → addPerson).

## Threat Surface Scan

No new threat surface beyond what the plan's threat model already covers:
- `people-directory-store` localStorage key is distinct (T-02-09 mitigated)
- SeedReviewSheet requires per-person confirm (T-02-10 mitigated)
- Graph `.address` fix ensures dedup/self-filter operate on real email values (T-02-11 mitigated)

## Self-Check: PASSED

Files exist:
- `/Volumes/SSD/Projects/transcript-studio-native/windows/src/stores/peopleDirectoryStore.ts` — confirmed
- `/Volumes/SSD/Projects/transcript-studio-native/windows/src/pages/PeoplePage.tsx` — confirmed
- `/Volumes/SSD/Projects/transcript-studio-native/windows/src/pages/PersonEditModal.tsx` — confirmed
- `/Volumes/SSD/Projects/transcript-studio-native/windows/src/pages/SeedReviewSheet.tsx` — confirmed

Commits exist:
- `2f5eadc` feat(02-05): Windows types + peopleDirectoryStore + Graph attendee fix
- `9dc64fa` feat(02-05): PeoplePage + PersonEditModal + /people route + Ctrl+6 nav
- `b42048a` feat(02-05): SeedReviewSheet + pendingSeedAttendees wiring post-recording-stop

---
*Phase: 02-people-directory*
*Completed: 2026-06-07*
