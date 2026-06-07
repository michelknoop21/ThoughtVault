---
phase: 02-people-directory
plan: 01
subsystem: testing
tags: [xcode, swiftdata, migration, xctest, vitest, zustand, graph-api, red-tests]

requires:
  - phase: 01-self-profile-foundation
    provides: PersonProfile @Model, AppMigrationPlan (V1→V2), TranscriptRecord, makeInMemoryContainer pattern

provides:
  - RED migration test for PersonProfile V2→V3 (emails==[], isInternal preserved)
  - RED PersonDirectoryServiceTests (CRUD round-trip + dedup, PersonDirectoryService undefined)
  - RED GraphAttendeeDecodeTests (emailAddress.address key, CalendarEvent.attendees undefined)
  - Graph calendarView fixture JSON (realistic Dutch names + address keys)
  - RED Windows vitest scaffold (round-trip, factory defaults, distinct key, dedup)

affects:
  - 02-02 (PersonProfile model + SchemaV3 migration — turns RED tests GREEN)
  - 02-03 (PersonDirectoryService + Graph attendee plumbing — turns RED tests GREEN)
  - 02-05 (Windows peopleDirectoryStore — turns RED Windows tests GREEN)

tech-stack:
  added: []
  patterns:
    - "RED-first TDD: tests reference not-yet-existing types to prove gaps before implementation"
    - "Test fixture embedded in Fixtures/ group + pbxproj Resources build phase"
    - "Local Decodable structs in test file mirror private production shapes (Graph decode tests)"

key-files:
  created:
    - TranscriptStudioTests/MigrationTests.swift (extended)
    - TranscriptStudioTests/PersonDirectoryServiceTests.swift
    - TranscriptStudioTests/GraphAttendeeDecodeTests.swift
    - TranscriptStudioTests/Fixtures/GraphCalendarViewResponse.json
    - windows/src/stores/__tests__/peopleDirectoryStore.test.ts
  modified:
    - TranscriptStudio.xcodeproj/project.pbxproj (new test files + Fixtures group + Resources phase)

key-decisions:
  - "Fixture JSON stored on-disk AND loaded via #file fallback so tests work in CI without a Resources phase being configured in Xcode yet"
  - "GraphAttendeeDecodeTests uses local Decodable structs (not @testable access to private MicrosoftGraphService types) to mirror the decode shape independently"
  - "pbxproj manually edited with sequential IDs (AB000004-006, FB000004-006, GG000100, BP000013) to add test files + Resources build phase"

patterns-established:
  - "Pattern: RED test compile failure is acceptable/intentional when referencing types not yet added"
  - "Pattern: Graph emailAddress.address (not .email) — verified via fixture, documented in test comment"

requirements-completed: [B-01, B-02, B-03, B-04]

duration: 10min
completed: 2026-06-07
---

# Phase 2 Plan 01: RED Test Scaffolds Summary

**Wave 0 RED test scaffolds anchoring all Phase 2 behaviors: migration survival, CRUD + dedup, Graph emailAddress.address decode, and Windows store round-trip**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-06-07T12:30:54Z
- **Completed:** 2026-06-07T12:41:00Z
- **Tasks:** 3
- **Files modified:** 6 (5 created, 1 extended, 1 pbxproj updated)

## Accomplishments
- Extended `MigrationTests.swift` with V2→V3 PersonProfile survival test (asserts emails==[] + isInternal preserved) — RED because PersonProfile has no `emails` field yet
- Created `PersonDirectoryServiceTests.swift` with CRUD round-trip + case-insensitive dedup tests — RED because PersonDirectoryService doesn't exist
- Created `GraphAttendeeDecodeTests.swift` that asserts `emailAddress.address` (not `.email`) via local decode structs + fixture — RED because `CalendarEvent.attendees` doesn't exist
- Created `Fixtures/GraphCalendarViewResponse.json` with realistic Dutch names and correct Graph `address` keys (Pitfall 2 mitigation)
- Created Windows `peopleDirectoryStore.test.ts` with 4 tests (round-trip, defaults, distinct key, dedup) — RED because module doesn't exist

## Task Commits

1. **Task 1: Extend MigrationTests V2→V3** - `6ced60f` (test)
2. **Task 2: PersonDirectoryServiceTests + GraphAttendeeDecodeTests + fixture** - `4d97c87` (test)
3. **Task 3: Windows vitest scaffold** - `d99ae41` (test)

## Files Created/Modified
- `/TranscriptStudioTests/MigrationTests.swift` - Extended with testPersonProfileSurvivesV2ToV3Migration
- `/TranscriptStudioTests/PersonDirectoryServiceTests.swift` - CRUD round-trip + dedup RED tests
- `/TranscriptStudioTests/GraphAttendeeDecodeTests.swift` - Graph address key decode RED test
- `/TranscriptStudioTests/Fixtures/GraphCalendarViewResponse.json` - Minimal calendarView fixture (1 event, 2 attendees, Dutch names)
- `/windows/src/stores/__tests__/peopleDirectoryStore.test.ts` - 4 vitest RED tests
- `/TranscriptStudio.xcodeproj/project.pbxproj` - Added 3 test files, Fixtures group, Resources build phase

## Decisions Made
- Used inline `#file` fallback path in `GraphAttendeeDecodeTests` so the fixture loads even in CI where the Resources phase may not yet be evaluated (belt-and-suspenders alongside the bundle resource approach)
- Local Decodable structs in `GraphAttendeeDecodeTests` instead of `@testable` access to private `MicrosoftGraphService` types — keeps test self-contained and independent of production implementation details
- pbxproj IDs chosen sequentially (AB000004–006, FB000004–006, GG000100, BP000013) to follow existing project conventions

## Deviations from Plan

None — plan executed exactly as written. All three test artifacts are RED against the current codebase, as required.

## Issues Encountered
- Build scheme is `TranscriptStudio` (not `TranscriptStudioTests`) — discovered on first build attempt; using `-only-testing:TranscriptStudioTests/...` with the main scheme works correctly.

## Threat Surface Scan

No new security surface introduced — this plan creates test files only. No network endpoints, auth paths, or schema changes at trust boundaries.

## Known Stubs

None. This plan only creates RED test scaffolds; there is no production implementation to stub.

## Next Phase Readiness
- Plan 02-02 turns Task 1 GREEN: add `emails: [String]` + `isInternal: Bool?` to PersonProfile, AppSchemaV3, v2ToV3 stage
- Plan 02-02/02-03 turns Task 2 GREEN: implement PersonDirectoryService + CalendarEvent.attendees
- Plan 02-05 turns Task 3 GREEN: implement `usePeopleDirectoryStore` with `people-directory-store` key

## Self-Check: PASSED

---
*Phase: 02-people-directory*
*Completed: 2026-06-07*
