---
phase: 2
slug: people-directory
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-05
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | macOS: XCTest (`TranscriptStudioTests`); Windows: vitest ^4.1.0 |
| **Config file** | macOS: scheme `TranscriptStudioTests`; Windows: `vite.config.*` (no separate vitest config) |
| **Quick run command** | macOS: `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests -only-testing:TranscriptStudioTests/<Suite>` · Windows: `cd windows && npx vitest run <file>` |
| **Full suite command** | `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests` · `cd windows && npx vitest run` |
| **Estimated runtime** | ~90 seconds (macOS build+test); ~10 seconds (Windows vitest) |

---

## Sampling Rate

- **After every task commit:** Run the relevant `-only-testing:` subset (macOS) / `npx vitest run <file>` (Windows)
- **After every plan wave:** Run full `xcodebuild test` + full `npx vitest run`
- **Before `/gsd:verify-work`:** Both suites green + URLSession grep gate passes + manual seed smoke on a live M365 machine
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-mig | data | 1 | B-01 / A-04 | — | SchemaV3 migration preserves existing self `PersonProfile` + all `TranscriptRecord`; `emails == []`, `isInternal` value preserved | unit (in-memory ModelContainer) | `xcodebuild test ... -only-testing:TranscriptStudioTests/MigrationTests` | ⚠️ extend (V1→V2 only) — ❌ W0 | ⬜ pending |
| 02-crud | service | 2 | B-01, B-02 | — | Directory CRUD round-trip (insert→fetch→update→delete) returns only `isSelf == false` entries | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/PersonDirectoryServiceTests` | ❌ W0 | ⬜ pending |
| 02-graph | graph | 2 | B-03 | — | Graph attendee decode maps `emailAddress.address` into `CalendarEvent.attendees` from fixture JSON | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/GraphAttendeeDecodeTests` | ❌ W0 | ⬜ pending |
| 02-dedup | service | 2 | B-03, D-10 | — | Dedup filters known emails + self/account email; falls back to normalized name | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/PersonDirectoryServiceTests` + `npx vitest run` | ❌ W0 | ⬜ pending |
| 02-nonet | service | 2 | D-11 / B-(local) | T-data-exfil | `PersonDirectoryService` contains no `URLSession` reference | static grep gate | `! grep -q "URLSession" macos/Services/PersonDirectoryService.swift` | ❌ W0 (plan verify step) | ⬜ pending |
| 02-win | windows | 4 | B-01, B-04 | — | Windows people store round-trip + tag edit; distinct localStorage key from singleton self store | unit | `cd windows && npx vitest run src/stores/__tests__/peopleDirectoryStore.test.ts` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> **Per research A1 (MEDIUM risk):** the SchemaV3 migration test (02-mig) MUST be authored RED first — adding a `[String]` collection to an already-persisted row (the existing self profile) is a new scenario for this codebase and must be proven by a failing-then-passing migration test, not assumed lightweight.

---

## Wave 0 Requirements

- [ ] Extend `TranscriptStudioTests/MigrationTests.swift` — add PersonProfile-survival V2→V3 case (B-01 / A-04); author RED first (research A1)
- [ ] `TranscriptStudioTests/PersonDirectoryServiceTests.swift` — CRUD + dedup stubs (B-01 / B-02 / D-10)
- [ ] `TranscriptStudioTests/GraphAttendeeDecodeTests.swift` + fixture JSON (B-03; assert `emailAddress.address` key per research A2)
- [ ] `windows/src/stores/__tests__/peopleDirectoryStore.test.ts` — round-trip + dedup (B-01 / B-04 / D-10)
- [ ] URLSession grep gate as an explicit plan verification step (D-11)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Agenda-seed review sheet appears after recording stops for an event with attendees, per-person confirm (no auto-commit) | B-03 (success criterion 2) | Requires a live Microsoft 365 account with a calendar event that has real attendees; depends on the recording→stop pipeline and the new `activeMeeting` linkage | On a signed-in M365 machine: start a recording linked to a calendar event with ≥2 attendees, stop it, confirm the "Voeg deelnemers toe aan directory?" sheet lists only new (deduped) attendees, confirm one and decline one, verify only the confirmed person persists with `isInternal == nil` |
| New "Mensen" navigation entry visible + reachable on both platforms | B-02 (D-04) | Visual/navigation presence | macOS: sidebar shows Mensen tab (collapsed + expanded); Windows: `/people` route reachable from nav |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags (`npx vitest run`, not `vitest` watch)
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
