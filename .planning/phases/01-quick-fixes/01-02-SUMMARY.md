---
phase: 01-quick-fixes
plan: "02"
subsystem: cross-platform-parity
tags: [windows, macos, offline-queue, https-enforcement, parity]
dependency_graph:
  requires: []
  provides: [C-02, C-03]
  affects: [windows/src/services/api.ts, macos/Models/Models.swift, macos/Services/OfflineQueue.swift, macos/ViewModels/RecordingViewModel.swift]
tech_stack:
  added: []
  patterns: [WHATWG URL parser for scheme enforcement, UUID-based queue identity]
key_files:
  created: []
  modified:
    - windows/src/services/api.ts
    - macos/Models/Models.swift
    - macos/Services/OfflineQueue.swift
    - macos/ViewModels/RecordingViewModel.swift
decisions:
  - "Use WHATWG URL parser (new URL()) for Windows https enforcement — scheme is lowercased automatically, no manual case-folding needed"
  - "QueuedItem id added as named associated value with default — existing call sites (.audio(url: url)) keep compiling unchanged"
  - "decodeIfPresent with UUID fallback for id — legacy persisted items gain a stable id on first load after update"
metrics:
  duration: "~10 minutes"
  completed: "2026-06-04"
  tasks_completed: 2
  files_modified: 4
---

# Phase 01 Plan 02: Validation + Offline-Queue Integrity Parity Summary

One-liner: https scheme enforcement for Windows custom server URL and id-based offline-queue identity for macOS, both aligned to the reference platform.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Enforce https on Windows custom server URL (C-02) | 65d0461 | windows/src/services/api.ts |
| 2 | macOS QueuedItem stable id + shared retry-limit constant (C-03) | 8748c03 | macos/Models/Models.swift, macos/Services/OfflineQueue.swift, macos/ViewModels/RecordingViewModel.swift |

## What Was Built

**C-02 (Windows https enforcement):** Added `validatedBaseUrl(): string` private method to `APIService` in `windows/src/services/api.ts`. Uses the WHATWG `URL` parser (which lowercases the scheme automatically), trims whitespace from the raw value, and rejects any scheme that is not exactly `https:` with a Dutch error message. All four outbound code paths (`request()`, `uploadRecording`, `uploadRecordingWithProgress`, `getStreamUrl`) now route through `validatedBaseUrl()`. Mirrors the macOS `validatedBaseURL()` contract.

**C-03 (macOS queue identity + retry limit):** `QueuedItem` in `Models.swift` now carries an `id: String` associated value on both `.audio` and `.text` cases, defaulting to `UUID().uuidString`. The `id` is Codable; `init(from:)` uses `decodeIfPresent` with a UUID fallback so legacy persisted items load cleanly. `encode(to:)` writes the id. `incrementingRetryCount()` preserves the existing id. `QueuedItem.maxRetries = 5` is the single shared constant (aligns with Windows `MAX_RETRIES = 5`). `OfflineQueue.indexOfItem` now matches on `$0.id == item.id` — no JSONEncoder comparison. `RecordingViewModel` uses `QueuedItem.maxRetries` (was hardcoded `10`).

## Verification

- `cd windows && npx tsc --noEmit` — passed (no errors)
- `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` — **BUILD SUCCEEDED**

## Deviations from Plan

**1. [Rule 1 - Bug] Updated all QueuedItem pattern matches in RecordingViewModel**
- **Found during:** Task 2 — adding the `id` associated value changed the arity of both enum cases
- **Issue:** Pattern matches `.audio(let url, _)` and `.text(let t, let pid, _)` in RecordingViewModel.swift (lines 850, 862, 874) and `.audio(let url, _)` in OfflineQueue.swift `queuedAudioURLs` would fail to compile with the new three-argument cases
- **Fix:** Updated all patterns to include the extra `_` wildcard for `id`: `.audio(let url, _, _)`, `.text(let t, let pid, _, _)`, etc.
- **Files modified:** macos/ViewModels/RecordingViewModel.swift, macos/Services/OfflineQueue.swift
- **Commit:** 8748c03 (included in Task 2 commit)

## Known Stubs

None.

## Threat Flags

None — changes are entirely within existing trust boundaries defined in the plan's threat model. T-01-02-A and T-01-02-B are now mitigated.

## Self-Check: PASSED

- windows/src/services/api.ts — modified, tsc clean
- macos/Models/Models.swift — modified, BUILD SUCCEEDED
- macos/Services/OfflineQueue.swift — modified, BUILD SUCCEEDED
- macos/ViewModels/RecordingViewModel.swift — modified, BUILD SUCCEEDED
- Commits 65d0461 and 8748c03 exist in git log
