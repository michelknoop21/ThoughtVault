---
phase: 02-people-directory
plan: 04
subsystem: ui-views
tags: [swiftui, apptab, recordingviewmodel, peopledirectory, seedreview, crud, attendees, swift6]

requires:
  - phase: 02-people-directory/02-03
    provides: PersonDirectoryService CRUD + CalendarEvent.attendees + newSeedCandidates

provides:
  - AppTab.people: Mensen sidebar tab with SF Symbol person.2/person.2.fill + key "7"
  - PeopleDirectoryView: searchable directory list, CRUD with confirmationDialog delete
  - PersonEditView: LabeledContent form with segmented tri-state picker + comma-separated tags
  - SeedReviewSheet: per-person confirm sheet, no auto-commit, dedup before presentation
  - RecordingViewModel.activeMeeting: CalendarEvent linkage set at recording start sites
  - RecordingViewModel.pendingSeedAttendees: View-layer signal for seed sheet trigger

affects:
  - 02-05 (Windows parity reference for UI patterns)

tech-stack:
  added: []
  patterns:
    - "AppTab: case people uses key '7' (not '6') — admin already owns '6'"
    - "activeMeeting captured before stopAndUpload branches; cleared after capture"
    - "pendingSeedAttendees observed via onChange in macOSView for safe post-idle presentation"
    - "InternalStatus enum maps Bool? to Picker-friendly CaseIterable"
    - "SeedCandidate displayName: email prefix split on ._- then capitalized"
    - "selfEmail union: MicrosoftGraphService.shared.accountEmail ?? CalendarService.shared.microsoftAccountEmail ?? self-profile first email"

key-files:
  created:
    - macos/Views/PeopleDirectoryView.swift
    - macos/Views/PersonEditView.swift
    - macos/Views/SeedReviewSheet.swift
  modified:
    - macos/App/ContentView.swift
    - macos/ViewModels/RecordingViewModel.swift
    - ThoughtVault.xcodeproj/project.pbxproj

key-decisions:
  - "AppTab.people uses keyboard shortcut '7' (not '6' as UI-SPEC originally drafted) — admin case already binds '6'; plan PLAN.md explicitly resolved this conflict"
  - "pendingSeedAttendees set before upload branch selection so all paths (local/onDevice/cloud/offline) trigger the seed signal uniformly"
  - "Dedup runs in onChange observer before sheet presentation — sheet only appears when newSeedCandidates returns non-empty (D-07)"
  - "PersonEditView uses a private InternalStatus enum to bridge Bool? and segmented Picker CaseIterable requirement"
  - "Task 4 human-verify auto-approved in yolo mode — live M365 verification deferred to user post-deploy"

requirements-completed: [B-01, B-02, B-03, B-04]

duration: 10min
completed: 2026-06-07
---

# Phase 2 Plan 04: macOS People Directory UI + Agenda-Seed Trigger Summary

**Mensen sidebar tab, searchable CRUD directory, tri-state intern/extern form, and per-person seed review sheet with dedup — no auto-commit on agenda attendees**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-06-07T13:40:00Z
- **Completed:** 2026-06-07T13:50:35Z
- **Tasks:** 4 (3 auto + 1 checkpoint auto-approved in yolo mode)
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments

- Added `case people` to `AppTab` enum with SF Symbol `person.2`/`person.2.fill`, keyboard shortcut `"7"` (admin retains `"6"`), sidebar title "Mensen"; `tabContent` routes `.people` to `PeopleDirectoryView`
- Added `var activeMeeting: CalendarEvent?` and `var pendingSeedAttendees: [String]?` to `RecordingViewModel`; wired `activeMeeting` at the two recording start sites in ContentView; cleared on cancel; captured attendees before `stopAndUpload` branches
- Created `PeopleDirectoryView`: `searchable` list, status dot (brandAccent/brandSecondary/labelTertiary), `confirmationDialog` delete, empty/loading/error/no-results states, toolbar "Persoon toevoegen" CTA
- Created `PersonEditView`: `LabeledContent` form mirroring `ProfileSettingsView`; `Picker(.segmented)` tri-state via private `InternalStatus` enum; `splitAndTrim` for aliases + expertiseTags; transient "Opgeslagen" + checkmark 2s on save
- Created `SeedReviewSheet`: checkbox list defaulting ON; pluralized "Voeg {n} personen toe" button disabled at 0 checked; "Overslaan" secondary; confirm path calls `seedPerson()+add()` with `isInternal=nil`; dedup runs before presentation in `onChange(pendingSeedAttendees)` — sheet skipped when no new candidates
- Registered all 3 new view files in `project.pbxproj` (AA000072-AA000074 / FA000072-FA000074)

## Task Commits

1. **Task 1: Mensen tab + RecordingViewModel activeMeeting** — `fde2fb2` (feat)
2. **Task 2: PeopleDirectoryView + PersonEditView** — `cca515b` (feat)
3. **Task 3: SeedReviewSheet + seed trigger** — `1837d8a` (feat)
4. **Task 4: Human-verify** — auto-approved in yolo mode (no code changes)

## Files Created/Modified

- `/macos/Views/PeopleDirectoryView.swift` — new: searchable directory list, CRUD, status dots
- `/macos/Views/PersonEditView.swift` — new: LabeledContent form, tri-state Picker, tags
- `/macos/Views/SeedReviewSheet.swift` — new: per-person checkbox confirm, no auto-commit
- `/macos/App/ContentView.swift` — AppTab.people + activeMeeting wiring + seed sheet trigger
- `/macos/ViewModels/RecordingViewModel.swift` — activeMeeting + pendingSeedAttendees
- `/ThoughtVault.xcodeproj/project.pbxproj` — 3 new view files registered

## Decisions Made

- AppTab.people keyboard shortcut `"7"` — `"6"` already owned by admin; plan explicitly resolved this conflict before execution
- `pendingSeedAttendees` set before the upload-path branch so all four paths (local/onDevice/cloud/offline) uniformly trigger the seed signal
- Dedup runs in the `onChange` observer, not inside `stopAndUpload` — guarantees sheet only appears post-idle, preventing Pitfall 3
- `InternalStatus` private enum bridges `Bool?` to `Picker`'s `CaseIterable` requirement cleanly
- selfEmail union in `onChange`: `MicrosoftGraphService.shared.accountEmail ?? CalendarService.shared.microsoftAccountEmail ?? self-profile.emails.first` (Open Item 3 resolved)

## Deviations from Plan

None — plan executed exactly as written. UI-SPEC key collision already pre-resolved in plan text (use "7" not "6").

## Known Stubs

None. All three views are fully wired to `PersonDirectoryService`. `PeopleDirectoryView` reads from `directoryPeople()`. `PersonEditView` calls `service.add()`/`service.update()`. `SeedReviewSheet` calls `service.seedPerson()+service.add()`. No placeholder data.

## Threat Surface Scan

No new network endpoints or auth paths introduced. All persistence routes through `PersonDirectoryService` (no `URLSession`). T-02-06 mitigation confirmed: `SeedReviewSheet` requires per-person checkbox confirm; unchecked/skipped never persisted. T-02-07 mitigation confirmed: `directoryPeople()` filters `isSelf==false` — self-profile never appears in directory list. T-02-08: no network calls in any of the three new views.

## Self-Check: PASSED

Files exist:
- `/Volumes/SSD/Projects/transcript-studio-native/macos/Views/PeopleDirectoryView.swift` — confirmed
- `/Volumes/SSD/Projects/transcript-studio-native/macos/Views/PersonEditView.swift` — confirmed
- `/Volumes/SSD/Projects/transcript-studio-native/macos/Views/SeedReviewSheet.swift` — confirmed

Commits exist:
- `fde2fb2` feat(02-04): Mensen tab + RecordingViewModel activeMeeting linkage — confirmed
- `cca515b` feat(02-04): PeopleDirectoryView + PersonEditView — confirmed
- `1837d8a` feat(02-04): SeedReviewSheet + post-recording seed trigger — confirmed

Build: BUILD SUCCEEDED (CODE_SIGNING_ALLOWED=NO)

Acceptance criteria:
- `grep -c "case people" ContentView.swift` = 1 ✓
- People keyboardShortcut returns "7", admin returns "6" (no double-bind) ✓
- `grep -c "var activeMeeting: CalendarEvent?" RecordingViewModel.swift` = 1 ✓
- `searchable + confirmationDialog + Persoon toevoegen` in PeopleDirectoryView ✓
- `Picker + splitAndTrim + Wijzigingen opslaan` in PersonEditView ✓
- `Nieuwe deelnemers gevonden + Overslaan + newSeedCandidates + seedPerson` in SeedReviewSheet ✓
- `newSeedCandidates` called in ContentView before sheet presentation ✓

---
*Phase: 02-people-directory*
*Completed: 2026-06-07*
