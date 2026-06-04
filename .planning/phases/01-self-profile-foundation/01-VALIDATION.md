---
phase: 1
slug: self-profile-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-04
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (macOS) — `TranscriptStudioTests` scheme |
| **Config file** | `TranscriptStudio.xcodeproj` scheme `TranscriptStudioTests` (already configured) |
| **Quick run command** | `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests -only-testing:TranscriptStudioTests/PersonProfileTests CODE_SIGNING_ALLOWED=NO` |
| **Full suite command** | `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests CODE_SIGNING_ALLOWED=NO` |
| **Estimated runtime** | ~60 seconds (quick) / ~3–5 min (full, includes build) |

---

## Sampling Rate

- **After every task commit:** Run quick command (`PersonProfileTests`)
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds (quick), full suite at wave merge

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-W0-01 | 00 | 0 | A-04 | — | N/A | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/MigrationTests` | ❌ W0 | ⬜ pending |
| 1-W0-02 | 00 | 0 | A-02 | — | N/A | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/PersonProfileTests` | ❌ W0 | ⬜ pending |
| 1-mig-01 | — | 1 | A-04 | — | Existing `TranscriptRecord` data survives V1→V2 lightweight migration (no wipe, no crash) | unit (in-memory container) | `xcodebuild test ... -only-testing:TranscriptStudioTests/MigrationTests` | ✅ via W0 | ⬜ pending |
| 1-prof-01 | — | 1 | A-02 | — | `upsertSelfProfile` creates record on empty store | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/PersonProfileTests` | ✅ via W0 | ⬜ pending |
| 1-prof-02 | — | 1 | A-02 | — | `upsertSelfProfile` updates in-place when `isSelf==true` record exists (singleton) | unit | same | ✅ via W0 | ⬜ pending |
| 1-prof-03 | — | 1 | A-02 | — | Skipping onboarding creates no `PersonProfile` record | unit | same | ✅ via W0 | ⬜ pending |
| 1-set-01 | — | 2 | A-03 | — | Settings editor calls upsert and persists profile across restart | integration (manual) | manual — UI interaction | N/A | ⬜ pending |
| 1-onb-01 | — | 2 | A-01 | — | Onboarding self-profile step appears between `schermopname` and `klaar`, is skippable | manual | `xcodebuild build CODE_SIGNING_ALLOWED=NO` + visual inspection | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `TranscriptStudioTests/MigrationTests.swift` — covers A-04. In-memory V1 container with pre-seeded `TranscriptRecord`, reopen with V2 `SchemaMigrationPlan`, assert records survive.
- [ ] `TranscriptStudioTests/PersonProfileTests.swift` — covers A-02 upsert logic (create path, update-in-place path, skip = no record).
- [ ] No framework install needed — XCTest already configured.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Onboarding step renders between schermopname and klaar, skippable | A-01 | SwiftUI/React onboarding flow is visual; no headless assertion for layout/skip UX | Build + launch fresh install (clear `hasCompletedOnboarding`), step through onboarding, confirm self-profile step appears and "Overslaan" works |
| Settings editor saves + persists across restart | A-03 | Cross-restart on-device persistence + UI interaction on both platforms | Edit profile in Settings, quit + relaunch app, confirm values persist (macOS SwiftData + Windows zustand persist) |
| Windows persistence parity (zustand persist) | A-02/A-03 | Windows path is React/Tauri — not covered by XCTest | `npm run tauri dev`, fill profile, restart, confirm localStorage-backed values persist |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (manual UI tasks isolated to Wave 2)
- [ ] Wave 0 covers all MISSING references (MigrationTests, PersonProfileTests)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s (quick run)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
