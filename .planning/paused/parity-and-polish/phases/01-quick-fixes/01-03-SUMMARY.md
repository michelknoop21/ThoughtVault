---
phase: 01-quick-fixes
plan: "03"
subsystem: macos-audio
tags: [macos, audio-mix, concurrency, swift6, timer]
dependency_graph:
  requires: [01-02]
  provides: [D-01, D-02]
  affects:
    - macos/ViewModels/RecordingViewModel.swift
    - macos/Services/SystemAudioCapture.swift
tech_stack:
  added: []
  patterns:
    - Magnitude-max PCM mixing (element-wise louder-source selection)
    - MainActor.assumeIsolated for main-run-loop timer callbacks
key_files:
  created: []
  modified:
    - macos/ViewModels/RecordingViewModel.swift
    - macos/Services/SystemAudioCapture.swift
decisions:
  - "Magnitude-max (abs comparison, sign preserved) chosen over plain max() — plain max biases toward positive peaks in bipolar PCM"
  - "MainActor.assumeIsolated valid here because Timer.scheduledTimer fires on the scheduling (main) run loop — no Task hop needed"
metrics:
  duration: "~8 minutes"
  completed: "2026-06-04"
  tasks_completed: 2
  files_modified: 2
---

# Phase 01 Plan 03: Audio-Mix + Timer-Threading Bug Fixes Summary

One-liner: Element-wise magnitude-max PCM mixing for combined recordings (D-01) and MainActor.assumeIsolated for the duration timer (D-02), eliminating the averaging volume loss and the Swift 6 concurrency diagnostic.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Combined audio — element-wise max instead of average (D-01) | f28b700 | macos/ViewModels/RecordingViewModel.swift |
| 2 | SystemAudioCapture timer uses MainActor.assumeIsolated (D-02) | 19f7880 | macos/Services/SystemAudioCapture.swift |

## What Was Built

**D-01 (audio mix fix):** In `mixAudioFiles()` the per-sample mixing loop in `RecordingViewModel.swift` (~line 1271-1276) was changed from `(micSample + sysSample) * 0.5` (averaging, halves volume) to a magnitude-max: `abs(micSample) >= abs(sysSample) ? micSample : sysSample`. This picks the louder instantaneous source by absolute value and preserves its sign (preventing positive-peak bias that plain `max()` would introduce with bipolar PCM). Output is still clamped to `[-1.0, 1.0]`. The stale `// Average mix at equal volume` comment was replaced. This matches the pattern already used by the `audioLevels` computed property's waveform-merge (`max(mic[i], sys[i])` by value, but correct for levels; magnitude-max is the right approach for signed PCM samples).

**D-02 (timer threading fix):** In `startDurationTimer()` in `SystemAudioCapture.swift` (~line 283), the `Task { @MainActor in ... }` wrapper was replaced with `MainActor.assumeIsolated { ... }`. `Timer.scheduledTimer(withTimeInterval:repeats:)` fires its closure on the run loop of the thread that scheduled it — which is the main run loop (since `startDurationTimer` is called from `@MainActor` context). `assumeIsolated` allows synchronous access to `@MainActor` state (`startDate`, `accumulatedPauseDuration`, `pausedAt`, `duration`) without spawning a new Task or hopping actors. The elapsed/pause computation and `self.duration = max(0, elapsed)` assignment are unchanged.

## Verification

- `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` — **BUILD SUCCEEDED** (both tasks)
- No warnings referencing SystemAudioCapture in build output after D-02 fix
- D-01: mix loop now selects the sample with larger `abs()` value — a single active speaker keeps full volume in the combined file
- D-02: timer body no longer creates a Task; `assumeIsolated` traps at runtime if ever called off-main (fail-fast safety per T-01-03-B)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None — T-01-03-A (existing bounds guards unchanged) and T-01-03-B (assumeIsolated asserts main-actor isolation at runtime — traps rather than corrupts if invariant violated) are both addressed as planned.

## Self-Check: PASSED

- macos/ViewModels/RecordingViewModel.swift — modified, contains `abs(micSample) >= abs(sysSample)`, no `* 0.5`
- macos/Services/SystemAudioCapture.swift — modified, contains `assumeIsolated`, no `Task { @MainActor in }`
- Commit f28b700 (D-01) exists in git log
- Commit 19f7880 (D-02) exists in git log
- BUILD SUCCEEDED confirmed for both tasks
