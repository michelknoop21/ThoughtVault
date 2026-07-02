---
phase: 01-self-profile-foundation
plan: "00"
subsystem: testing
tags: [tdd, red-tests, swiftdata, migration, personprofile]
dependency_graph:
  requires: []
  provides:
    - ThoughtVaultTests/MigrationTests.swift
    - ThoughtVaultTests/PersonProfileTests.swift
  affects:
    - Plan 01-01 (must implement PersonProfile + AppMigrationPlan to make these GREEN)
tech_stack:
  added: []
  patterns:
    - XCTest in-memory ModelContainer scaffold
    - Swift Testing @Suite/@Test/@MainActor with #expect assertions
key_files:
  created:
    - ThoughtVaultTests/MigrationTests.swift
    - ThoughtVaultTests/PersonProfileTests.swift
  modified: []
decisions:
  - "Used XCTest for MigrationTests (store setup/teardown) per PATTERNS.md recommendation"
  - "Used Swift Testing (@Suite/@Test/#expect) for PersonProfileTests per existing codebase convention"
  - "upsertSelfProfile helper inlined in test file — tests the logic directly, not via singleton LocalTranscriptStore"
  - "expertiseTags: [String] included in test helper to match amended PersonProfile contract (A-05)"
metrics:
  duration: "1m49s"
  completed_date: "2026-06-05"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 01 Plan 00: Wave 0 RED Test Scaffolds Summary

**One-liner:** XCTest + Swift Testing RED scaffolds asserting V1→V2 migration survival and isSelf upsert create/update/skip behaviour against not-yet-built `PersonProfile` + `AppMigrationPlan`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RED migration test — TranscriptRecord survives V1→V2 | 9a93c1b | ThoughtVaultTests/MigrationTests.swift |
| 2 | RED PersonProfile upsert tests — create / update / skip | 598fc3f | ThoughtVaultTests/PersonProfileTests.swift |

## What Was Built

Two test files in `ThoughtVaultTests/` that lock the contract for Plan 01's data layer before any production code exists:

**MigrationTests.swift** — `XCTestCase` subclass `MigrationTests` with one test `testTranscriptRecordSurvivesV1ToV2Migration`. Builds an in-memory `ModelContainer` referencing `AppMigrationPlan` and `PersonProfile`, seeds a `TranscriptRecord`, saves, fetches back, and asserts `id` survival and `count == 1`. References `AppMigrationPlan.self` (not yet built) → compile fails until Plan 01 lands.

**PersonProfileTests.swift** — Swift Testing `@Suite("PersonProfile Tests")` with three `@MainActor @Test` functions:
1. `upsertCreatesRecordOnEmptyStore` — after one upsert with name "Michel", fetching `isSelf==true` yields exactly one record with name "Michel"
2. `upsertUpdatesInPlaceWhenSelfExists` — two upserts keep singleton count at 1, role reflects second call
3. `skipCreatesNoRecord` — no upsert → zero `isSelf` records (D-07 skip path)

A private `upsertSelfProfile(in:)` helper mirrors `LocalTranscriptStore.upsertSelfProfile` but operates on an arbitrary in-memory context. `expertiseTags: [String]` parameter included per the A-05 amendment to match the final `PersonProfile` contract.

## RED State Confirmed

Both test files build-fail (cannot find type `PersonProfile`, `AppMigrationPlan`) until Plan 01 implements them. Verified with negated grep:

```
! xcodebuild test ... -only-testing:ThoughtVaultTests/MigrationTests ... | grep -q "TEST SUCCEEDED"
→ RED CONFIRMED

! xcodebuild test ... -only-testing:ThoughtVaultTests/PersonProfileTests ... | grep -q "TEST SUCCEEDED"
→ RED CONFIRMED
```

No production code was modified in this plan.

## Deviations from Plan

None — plan executed exactly as written. The `expertiseTags` parameter was added to the `upsertSelfProfile` helper in `PersonProfileTests.swift` to align with the A-05 amendment (already noted in STATE.md blockers/concerns and in PLAN.md frontmatter `requirements: [A-02, A-04, A-05]`). This is not a deviation — it follows the plan's requirements.

## Known Stubs

None. These are test files only; no production data flows or UI rendering is involved.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. Test-only code, in-memory containers only.

## Self-Check: PASSED

- [x] `ThoughtVaultTests/MigrationTests.swift` exists
- [x] `ThoughtVaultTests/PersonProfileTests.swift` exists
- [x] Commit 9a93c1b exists (`test(01-00): add RED MigrationTests`)
- [x] Commit 598fc3f exists (`test(01-00): add RED PersonProfileTests`)
- [x] Both files reference `PersonProfile` and `AppMigrationPlan` (grep confirmed)
- [x] RED state verified for both test targets
