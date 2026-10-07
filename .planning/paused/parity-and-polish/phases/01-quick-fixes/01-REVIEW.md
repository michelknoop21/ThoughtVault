---
phase: 01-quick-fixes
reviewed: 2026-06-04T10:58:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - macos/Models/Models.swift
  - macos/Services/OfflineQueue.swift
  - macos/Services/SystemAudioCapture.swift
  - macos/ViewModels/RecordingViewModel.swift
  - windows/src-tauri/src/commands/http.rs
  - windows/src/services/api.ts
  - windows/src/services/sse.ts
findings:
  critical: 2
  warning: 6
  info: 4
  total: 12
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-06-04T10:58:00Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the phase-01 quick-fix changes: Windows SSE reconnect/backoff (`sse.ts` + `http.rs`), HTTPS validation (`api.ts`), the offline-queue stable-id / retry-limit work (`Models.swift`, `OfflineQueue.swift`, `RecordingViewModel.swift`), and the audio-mix magnitude-max + duration-timer `MainActor.assumeIsolated` changes (`RecordingViewModel.swift`, `SystemAudioCapture.swift`).

The individual building blocks are mostly sound, but the **offline-queue retry loop is broken by an async race**: it decides success/failure by reading `recordingState` immediately after `uploadFile()`, which returns *before* the upload actually finishes. This defeats the entire retry-limit feature this phase added. There is also a **listener-leak / duplicate-stream defect in the Windows SSE reconnect path**. Both are correctness BLOCKERs. The remaining findings are robustness and consistency issues.

## Critical Issues

### CR-01: Offline-queue retry decision races against background upload (retry limit never works as intended)

**File:** `macos/ViewModels/RecordingViewModel.swift:861-873` (with `uploadFile` at `513`, `573-575`)
**Issue:** `processQueueOnStartupIfNeeded()` decides whether a queued item succeeded by inspecting `recordingState` right after calling `await uploadFile(url, ...)`:

```swift
let stateBefore = recordingState
await uploadFile(url, profileId: profileId)
if case .error = recordingState {        // <-- read here
    ... incrementingRetryCount ...
} else {
    offlineQueue.removeItem(item)         // <-- removed as "success"
}
```

But `uploadFile` does **not** await the upload. It spawns `uploadTask = Task { ... }` and returns immediately (`// Don't await — upload runs in background`, line 574). So at the moment the loop reads `recordingState`, the network request has not completed. The state is whatever `uploadFile` set synchronously (`recordingState = .idle`, line 509), never `.error`. Consequences:

- Every queued item is treated as an immediate success and `removeItem(item)` is called, so a genuinely failing upload is **silently dropped from the queue** and never retried — the opposite of the retry-limit feature this phase introduced.
- The `incrementingRetryCount()` / `replaceItem` branch for `.audio` items is effectively dead code.
- Looping over multiple queued audio items fires N background uploads that all reuse the single `uploadTask` slot (line 513), so each new iteration overwrites the previous `uploadTask` handle, leaking/abandoning in-flight uploads and breaking cancellation.

**Fix:** Give the queue path a synchronous (awaitable) upload that reports success/failure directly, e.g. add an internal `uploadFileAwaiting(url:profileId:) async -> Result<Void, Error>` that does the `APIService.shared.uploadAudio` call inline and returns, then branch on its result:

```swift
case .audio(let url, _, _):
    do {
        let task = try await APIService.shared.uploadAudio(fileURL: url, profileId: profileId, usePremium: usePremium) { _ in }
        await MainActor.run { self.addTask(task) }
        if !task.taskId.isEmpty { await startSSEStream(for: task.taskId) }
        offlineQueue.removeItem(item)
    } catch {
        offlineQueue.replaceItem(item, with: item.incrementingRetryCount())
    }
```

This mirrors the already-correct `.text` branch (lines 874-887), which *does* await and branch on a thrown error.

### CR-02: Windows SSE reconnect leaks event listeners and abandons the prior Rust stream, allowing duplicate/zombie streams

**File:** `windows/src/services/sse.ts:48-109`, `111-129`
**Issue:** `_startStream()` registers three Tauri listeners keyed by `eventName = sse-${Date.now()}` and then `await invoke("http_sse_stream", ...)`. That `invoke` only resolves when the Rust side returns (stream done/interrupted). When the stream is interrupted, `http.rs` emits `${event_name}-interrupted` and returns `Ok(())`, so the `invoke` promise also resolves.

Two problems:

1. **Listener leak on the normal interrupted path.** The `-interrupted` listener calls `this._clearListeners()` then `this._reconnect()`. `_reconnect` schedules a new `_startStream()` after the backoff. Good. But the original `invoke(...)` promise *also* resolves around the same time and falls through the `try` block with no further handling — there is no leak there, but on the **connect-time failure path** (the `catch` at line 103) `_clearListeners()` + `_reconnect()` is called while the listeners from this same `_startStream` were already attached, and `_reconnect` does not guard against a `reconnectTimer` already being pending from a prior interrupted event. If both an `-interrupted` event and an `invoke` rejection occur for the same stream, `_reconnect()` runs twice, scheduling **two** concurrent reconnect timers, which then start **two** parallel streams. From then on every interruption doubles the number of live streams (each with its own `Date.now()` listeners).

2. **`reconnectAttempts` is not reset on a successful data event.** It is only reset on the `-done` sentinel (line 73). A stream that delivers task updates for minutes and then briefly drops will keep its accumulated attempt count, so a long-lived healthy stream can exhaust `MAX_RECONNECT_ATTEMPTS` on its first real interruption and give up prematurely.

**Fix:**
- Guard `_reconnect()` so it is idempotent per cycle: `if (this.reconnectTimer !== null) return;` at the top (after the `isStopped` check), so overlapping interrupted+rejection events cannot schedule two timers.
- Reset `this.reconnectAttempts = 0;` inside the data-event listener (line 58) whenever a valid update is parsed, so attempt count reflects *consecutive* failures, not lifetime failures. (Note the macOS counterpart resets `reconnectAttempts` on every fresh `connect()` but has the same "no reset on data" property — worth aligning.)

## Warnings

### WR-01: `MainActor.assumeIsolated` in duration timer will crash if the timer ever fires off the main run loop

**File:** `macos/Services/SystemAudioCapture.swift:282-294`
**Issue:** `startDurationTimer()` uses `Timer.scheduledTimer(...)` and inside the closure calls `MainActor.assumeIsolated { ... }` with the comment "Timer fires on the main run loop, so assumeIsolated is safe here." `scheduledTimer` installs the timer on `RunLoop.current` at the time of the call. `startCapture()` is an `async` function on a `@MainActor` class, but the timer is created after multiple `await` suspension points (`SCShareableContent...`, `startCapture()`); the continuation is guaranteed to resume on the main actor, so in practice the current run loop is the main one. However, `assumeIsolated` is a hard precondition: if this code path is ever reached from a non-main executor (future refactor, or if `startCapture` is called from a detached context), it traps and crashes the app rather than degrading. Prefer a non-trapping hop.
**Fix:** Use the safer, non-trapping form:
```swift
durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        guard let self, let start = self.startDate else { return }
        ...
    }
}
```
or, if you want to avoid the per-tick `Task`, schedule the timer explicitly on `RunLoop.main` and keep `assumeIsolated` only after asserting `Thread.isMainThread`.

### WR-02: Pause accounting double-counts elapsed time while paused, then snaps back on resume

**File:** `macos/Services/SystemAudioCapture.swift:287-291`, `296-305`
**Issue:** While paused, the 1 Hz timer keeps firing and computes `elapsed = now - start - accumulatedPauseDuration - (now - pauseStart)`, which correctly freezes the displayed duration. But `accumulatedPauseDuration` is only added on `resumeDurationTimer()`. During a long pause the live calculation already subtracts `now - pauseStart`, and on resume `accumulatedPauseDuration += now - pauseStart` is added while `pausedAt` is cleared — so the math is consistent. The real issue is that `pauseDurationTimer()`/`resumeDurationTimer()` are gated by mode in `RecordingViewModel.pauseRecording()` (only called for `.systemAudio`/`.combined`), but the timer itself is started unconditionally in `startCapture`. For a `.combined` recording the mic recorder is paused via `audioRecorder.pauseRecording()` while the system-audio capture timer pause is also invoked — fine — but for plain `.systemAudio`, `audioRecorder` is never started yet `stopCapture`/pause paths still call `audioRecorder` no-ops. No crash, but the duration shown can diverge from the actual written audio length because ScreenCaptureKit keeps delivering (or dropping) frames during the "pause" — the capture is not actually paused, only the timer is. Flagging because the user sees a frozen timer while audio is still being recorded.
**Fix:** Document explicitly that pause only freezes the displayed counter for system-audio (the stream is not actually paused), or actually stop writing samples while paused so duration matches file length.

### WR-03: HTTPS-only enforcement silently breaks self-hosted / LAN / localhost backends

**File:** `windows/src/services/api.ts:155-169`
**Issue:** `validatedBaseUrl()` throws "Server-URL moet https gebruiken" for any non-`https:` scheme. The default backend is HTTPS, so this is fine for production, but it now makes it **impossible** to point the Windows app at a `http://localhost:port` or `http://192.168.x.x` backend for development or on-prem deployment. The macOS `validatedBaseURL()` is cited as the mirror; if macOS allows an http loopback exception (App Transport Security typically does for localhost), the two platforms now diverge. This is a deliberate hardening but is an undocumented behavior change that will surface as a hard error for anyone with a custom `server_url`.
**Fix:** Either document that custom non-HTTPS backends are unsupported on Windows, or allow an explicit loopback exception:
```ts
const isLoopback = parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1";
if (parsed.protocol !== "https:" && !(parsed.protocol === "http:" && isLoopback)) {
  throw new Error("Server-URL moet https gebruiken");
}
```

### WR-04: SSE 401 in `http_sse_stream` returns a hard error instead of triggering reconnect, so expired tokens kill the stream permanently

**File:** `windows/src-tauri/src/commands/http.rs:629-631` (interacts with `sse.ts:97-108`)
**Issue:** When the SSE GET returns a non-2xx status (e.g. 401 after token rotation, or a transient 502), `http_sse_stream` returns `Err("SSE verbinding mislukt: HTTP {status}")`. On the TS side this rejects the `invoke` and routes into `_reconnect()` — good for transient 5xx. But a 401 will reconnect up to `MAX_RECONNECT_ATTEMPTS` with the *same stale token* (the client captured `this.token` at construction and never refreshes it), guaranteeing 5 failed attempts then permanent `onError`. The retry budget is wasted on an unrecoverable auth state.
**Fix:** Distinguish auth failures from transient ones. Emit a dedicated `${event_name}-unauthorized` (or include the status in the rejection) so the TS layer can stop reconnecting and surface a re-login prompt instead of burning the backoff budget.

### WR-05: Audio mix allocates buffers sized to file length without guarding against `AVAudioFrameCount` overflow / huge allocations

**File:** `macos/ViewModels/RecordingViewModel.swift:1246-1257`
**Issue:** `AVAudioFrameCount(micFile.length)` and `AVAudioFrameCount(sysFile.length)` cast an `AVAudioFramePosition` (`Int64`) to `AVAudioFrameCount` (`UInt32`). For a ~500 MB / multi-hour 16 kHz mono recording the frame count is well within `UInt32`, but there is no upper bound: a corrupt header reporting a very large `length` would either overflow the `UInt32` cast (wrapping to a small number → truncated mix) or attempt a multi-GB `AVAudioPCMBuffer` allocation. The mix reads both files fully into RAM. The fallback-to-mic path covers allocation failure (`guard ... else { return micURL }`), so it won't crash, but a wraparound produces a silently truncated combined recording with no fallback flag set.
**Fix:** Clamp/validate before casting: `guard micFile.length >= 0, micFile.length < Int64(AVAudioFrameCount.max) else { return micURL }` (same for `sysFile`), and treat the over-limit case as a fallback so `audioMixFallbackOccurred` is set.

### WR-06: `loadSavedRecordings()` mutates `@Observable` state from a non-isolated context via fire-and-forget `Task`

**File:** `macos/ViewModels/RecordingViewModel.swift:920-943`
**Issue:** `loadSavedRecordings()` runs synchronous file I/O on the calling actor (it is called from `@MainActor` methods, so the I/O blocks the main thread — out of perf scope), then writes `self.savedRecordings` inside a detached `Task { @MainActor in ... }`. Since the function is already `@MainActor`, the trailing `Task { @MainActor in self.savedRecordings = recordings }` introduces an unnecessary async hop that defers the update to a later run-loop turn, so callers that read `savedRecordings` immediately after (e.g. `lastFailedRecording = self.savedRecordings.first { ... }` at lines 561, 569) can observe the *stale* list. The "find the just-saved recording" logic is therefore order-dependent and may set `lastFailedRecording = nil`.
**Fix:** Drop the wrapper `Task` and assign directly (the method is already `@MainActor`): `self.savedRecordings = recordings`. Move only the blocking file enumeration off-main if perf becomes a concern.

## Info

### IN-01: `_startStream` is invoked without awaiting in the reconnect timer (floating promise)

**File:** `windows/src/services/sse.ts:125-128`
**Issue:** `setTimeout(() => { this.reconnectTimer = null; this._startStream(); }, backoffMs)` calls the `async` `_startStream()` without `await`/`void`, so a rejection inside the un-awaited promise (before its own try/catch) would be an unhandled rejection. The body is wrapped in try/catch so this is currently benign, but lint rules (`no-floating-promises`) will flag it.
**Fix:** `void this._startStream();`

### IN-02: SHA-256 prefix is "stream" placeholder for >200 MB uploads, defeating its correlation purpose exactly where it matters most

**File:** `windows/src-tauri/src/commands/http.rs:194-202`
**Issue:** The `X-Upload-Sha256` header is documented (step 6) as a client↔server integrity-correlation aid, but for streamed uploads (>200 MB) it sends the literal string `"stream"`. Large uploads are precisely the case where the race-condition diagnostics were added. Not a correctness bug, but the diagnostic is absent where it's most useful.
**Fix:** Hash the temp copy in a streaming pass before upload (it has already been size-verified), or note in the header doc that the SHA is intentionally omitted for large files.

### IN-03: Magic numbers for backoff/limits duplicated across platforms without a shared source

**File:** `windows/src/services/sse.ts:11,122` and `macos/Services/APIService.swift:1128` and `macos/Models/Models.swift:606`
**Issue:** `MAX_RECONNECT_ATTEMPTS = 5`, the `pow(2, n)` capped at 16 backoff, and `QueuedItem.maxRetries = 5` are independently hard-coded in three files with comments asserting they "mirror" each other. These will silently drift.
**Fix:** Acceptable for now (cross-language), but a comment in each spot pointing to the canonical value, or a generated constants file, would prevent divergence.

### IN-04: Unused/dead `_signal` parameter and double error-parsing duplication in upload methods

**File:** `windows/src/services/api.ts:402-455` (`uploadRecording`) vs `457-533` (`uploadRecordingWithProgress`)
**Issue:** `uploadRecording` takes `_signal?: AbortSignal` but never uses it (and never passes `usePremium`, so it always uploads non-premium). The 400+ error-extraction block (lines 431-446 and 508-523) is duplicated verbatim. If only `uploadRecordingWithProgress` is wired up, `uploadRecording` is dead code.
**Fix:** Confirm `uploadRecording` is still referenced; if not, remove it. Otherwise extract the shared `parseUploadError(response)` helper and drop the unused `_signal`.

---

_Reviewed: 2026-06-04T10:58:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
