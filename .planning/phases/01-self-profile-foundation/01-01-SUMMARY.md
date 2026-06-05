---
phase: 01-self-profile-foundation
plan: "01"
subsystem: data
tags: [swiftdata, migration, personprofile, tdd, green]
dependency_graph:
  requires:
    - TranscriptStudioTests/MigrationTests.swift (Plan 00)
    - TranscriptStudioTests/PersonProfileTests.swift (Plan 00)
  provides:
    - macos/Models/PersonProfile.swift
    - macos/Models/AppMigrationPlan.swift
    - macos/Services/LocalTranscriptStore.swift (upsertSelfProfile + fetchSelfProfile)
    - macos/Models/Models.swift (collision warning)
  affects:
    - Plan 01-02 (macOS onboarding step reads PersonProfile + calls upsertSelfProfile)
    - Plan 01-03 (Windows store; no macOS impact)
    - Phase 2 (directory reuses PersonProfile @Model via isSelf==false records)
tech_stack:
  added: []
  patterns:
    - VersionedSchema + SchemaMigrationPlan.lightweight for additive @Model
    - nonisolated(unsafe) on static var for Swift 6 strict-concurrency protocol conformance
    - fetch-first-then-insert upsert for isSelf singleton invariant
    - @MainActor on XCTestCase subclass for Swift 6 mainContext access
key_files:
  created:
    - macos/Models/PersonProfile.swift
    - macos/Models/AppMigrationPlan.swift
  modified:
    - macos/Services/LocalTranscriptStore.swift
    - macos/Models/Models.swift
    - TranscriptStudioTests/MigrationTests.swift
decisions:
  - "nonisolated(unsafe) on VersionedSchema static vars: Swift 6 strict concurrency rejects mutable global state; nonisolated(unsafe) is the prescribed workaround for protocol-required var declarations"
  - "@MainActor on MigrationTests class: container.mainContext is MainActor-isolated in SwiftData; the test class needs the same isolation to access it without actor hopping"
  - "AppMigrationPlan.swift created in Task 1 (not Task 2): the Xcode project file references it, so it must exist for the Task 1 BUILD SUCCEEDED check; full implementation landed in the same commit"
metrics:
  duration: "5m33s"
  completed_date: "2026-06-05"
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 4
---

# Phase 01 Plan 01: macOS Data Foundation Summary

**One-liner:** PersonProfile @Model + AppMigrationPlan V1→V2 lightweight migration + upsertSelfProfile/fetchSelfProfile singleton service — turns Wave 0 RED tests (MigrationTests + PersonProfileTests) GREEN.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | PersonProfile @Model + Models.swift collision warning | 69442a1 | macos/Models/PersonProfile.swift, macos/Models/Models.swift, project.pbxproj |
| 2 | VersionedSchema migration plan + wire ModelContainer | ac4377c | macos/Models/AppMigrationPlan.swift, macos/Services/LocalTranscriptStore.swift, TranscriptStudioTests/MigrationTests.swift |
| 3 | upsertSelfProfile + fetchSelfProfile singleton service | c0355b5 | macos/Services/LocalTranscriptStore.swift |

## What Was Built

**PersonProfile.swift** — `@Model final class PersonProfile` with the full D-04 field set plus `expertiseTags: [String]` (A-05). Fields: `@Attribute(.unique) id`, `name`, `role`, `organization`, `aliases: [String]`, `meetingTypes: [String]`, `expertiseTags: [String]`, `isSelf: Bool`, `isInternal: Bool`, `createdAt`, `updatedAt`. Explicit `init` with all parameters defaulted; `[String]` arrays use native SwiftData storage (no `@Attribute(.externalStorage)`), consistent with `TranscriptRecord.tags` precedent.

**AppMigrationPlan.swift** — `AppSchemaV1` (TranscriptRecord only) and `AppSchemaV2` (TranscriptRecord + PersonProfile, both listed — Pitfall 1 avoidance). `AppMigrationPlan: SchemaMigrationPlan` with `MigrationStage.lightweight(fromVersion:toVersion:)` stage. Uses `nonisolated(unsafe)` on static vars to satisfy Swift 6 strict concurrency for protocol-required mutable state.

**LocalTranscriptStore.swift** — Persistent container init replaced with `ModelContainer(for: TranscriptRecord.self, PersonProfile.self, migrationPlan: AppMigrationPlan.self, configurations: config)`. In-memory fallback updated to include `PersonProfile.self` (no migration plan on in-memory). `migrateFromDefaultStore` left untouched — still opens only `TranscriptRecord.self` (Pitfall 6 compliance). Two new methods added: `fetchSelfProfile() -> PersonProfile?` and `upsertSelfProfile(name:role:organization:aliases:meetingTypes:expertiseTags:) throws`.

**Models.swift** — Three-line `// ⚠️ COLLISION WARNING` comment inserted immediately above `struct Profile` declaration (D-05).

## Test Results

- `MigrationTests.testTranscriptRecordSurvivesV1ToV2Migration` — TEST SUCCEEDED (GREEN)
- `PersonProfileTests/upsertCreatesRecordOnEmptyStore` — passed
- `PersonProfileTests/upsertUpdatesInPlaceWhenSelfExists` — passed
- `PersonProfileTests/skipCreatesNoRecord` — passed
- Full test suite: TEST SUCCEEDED
- App: BUILD SUCCEEDED

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 concurrency: nonisolated(unsafe) on VersionedSchema static vars**
- **Found during:** Task 2 — first build attempt with AppMigrationPlan.swift
- **Issue:** Swift 6 strict concurrency rejects `static var versionIdentifier`, `static var models`, `static var schemas`, `static var stages` as "nonisolated global shared mutable state"
- **Fix:** Added `nonisolated(unsafe)` prefix to all six protocol-required `static var` declarations in AppMigrationPlan.swift
- **Files modified:** macos/Models/AppMigrationPlan.swift
- **Commit:** ac4377c

**2. [Rule 1 - Bug] Swift 6 concurrency: @MainActor on MigrationTests**
- **Found during:** Task 2 — MigrationTests first run
- **Issue:** `container.mainContext` is `@MainActor`-isolated in SwiftData; the XCTestCase subclass was not annotated, causing "main actor-isolated property 'mainContext' cannot be referenced from a nonisolated context"
- **Fix:** Added `@MainActor` to `final class MigrationTests: XCTestCase`
- **Files modified:** TranscriptStudioTests/MigrationTests.swift
- **Commit:** ac4377c

**3. [Rule 3 - Blocking] AppMigrationPlan.swift created during Task 1**
- **Found during:** Task 1 — build verification step
- **Issue:** The Xcode project file was updated to include AppMigrationPlan.swift as a build input, causing "Build input file cannot be found" error before the file existed
- **Fix:** Created AppMigrationPlan.swift with full implementation during Task 1 (file needed for project to compile; full implementation was planned anyway for Task 2)
- **Files modified:** macos/Models/AppMigrationPlan.swift (created)
- **Commit:** ac4377c (same commit as Task 2 final)

## Known Stubs

None. All production code is fully wired. No placeholder data, TODO comments, or unfilled fields in the shipped code.

## Threat Flags

No new network endpoints, auth paths, or external data paths introduced. PersonProfile is stored exclusively in the SwiftData on-device store — no backend calls, no transmitted data. Trust boundaries are consistent with the plan's threat model (T-01-01-01 through T-01-SC).

## Self-Check: PASSED

- [x] macos/Models/PersonProfile.swift exists (55 lines)
- [x] macos/Models/AppMigrationPlan.swift exists (47 lines)
- [x] macos/Services/LocalTranscriptStore.swift contains upsertSelfProfile and fetchSelfProfile
- [x] macos/Models/Models.swift contains COLLISION WARNING above struct Profile
- [x] Commit 69442a1 exists (feat(01-01): PersonProfile @Model)
- [x] Commit ac4377c exists (feat(01-01): AppMigrationPlan + MigrationTests GREEN)
- [x] Commit c0355b5 exists (feat(01-01): upsertSelfProfile + fetchSelfProfile)
- [x] MigrationTests TEST SUCCEEDED
- [x] PersonProfileTests TEST SUCCEEDED (all 3 tests)
- [x] Full test suite TEST SUCCEEDED
- [x] App BUILD SUCCEEDED
