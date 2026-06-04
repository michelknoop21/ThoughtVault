---
phase: 01-quick-fixes
plan: 01
subsystem: windows-sse
tags: [sse, reconnect, backoff, tauri, rust, typescript, cross-platform-parity]
dependency_graph:
  requires: []
  provides: [windows-sse-reconnect]
  affects: [windows/src/services/sse.ts, windows/src-tauri/src/commands/http.rs]
tech_stack:
  added: []
  patterns: [exponential-backoff, interrupted-vs-done-signaling]
key_files:
  created: []
  modified:
    - windows/src-tauri/src/commands/http.rs
    - windows/src/services/sse.ts
decisions:
  - Emit `{event_name}-interrupted` from Rust on stream-end-without-DONE and mid-stream chunk errors, keeping `-done` exclusively for the clean `[DONE]` sentinel
  - Route invoke() connect-time failures through the same reconnect() path as interruptions (consistent retry behavior)
  - Reset reconnectAttempts only on clean `-done`; interrupted streams that arrive after a terminal status complete normally without reconnect
metrics:
  duration: 9m
  completed: 2026-06-04
  tasks_completed: 2
  tasks_total: 2
  files_changed: 2
---

# Phase 01 Plan 01: Windows SSE Reconnect Summary

Windows SSEClient now reconnects with exponential backoff (max 5 attempts, 2→16s) after interrupted streams, closing the parity gap with macOS where transient network drops no longer surface a false "failed" status.

## What Was Built

**Task 1 — Rust stream disambiguation (`http.rs`)**

`http_sse_stream` previously emitted `{event_name}-done` in two cases: clean `[DONE]` sentinel and stream-exhausted-without-DONE. These are now distinct:

- `{event_name}-done` — emitted only when `data: [DONE]` is received (clean, successful stream end)
- `{event_name}-interrupted` — emitted when the `bytes_stream` loop exits without having seen `[DONE]` (server closed early / network drop), and also when a chunk yields an `Err` (mid-stream network error)

The data-line emit path and auth-header forwarding are unchanged.

**Task 2 — TypeScript SSEClient reconnect (`sse.ts`)**

Added reconnect state to `SSEClient`:

- `reconnectAttempts` counter (starts 0), `MAX_RECONNECT_ATTEMPTS = 5`
- `terminalReached` boolean — set when a terminal status (completed/failed/cancelled/error) arrives in the data event
- `isStopped` flag — set by `disconnect()`, prevents stale reconnects
- New listener for `{eventName}-interrupted`: if `terminalReached` → complete normally; otherwise call `_reconnect()`
- `_reconnect()`: if attempts exhausted → `onError`; else increment, compute `Math.min(2^attempts, 16) * 1000` ms backoff (2s,4s,8s,16s,16s), schedule `_startStream()` via `setTimeout`
- `disconnect()` clears any pending `reconnectTimer` and all three listeners (`data`, `-done`, `-interrupted`)
- Connect-time `invoke()` failures also route through `_reconnect()` — consistent retry on both stream-open and mid-stream failures

Backoff curve is identical to macOS (`pow(2, attempt)` capped at 16s).

## Acceptance Criteria

- [x] `cargo build` succeeds with no new warnings on http.rs
- [x] `npx tsc --noEmit` passes with no type errors
- [x] `{event_name}-interrupted` emitted on stream-end-without-DONE and chunk errors
- [x] `{event_name}-done` emitted only on `data: [DONE]`
- [x] `maxReconnectAttempts = 5`, backoff `Math.min(2^attempt, 16) * 1000`
- [x] Terminal status suppresses reconnect
- [x] `disconnect()` cancels timer and all listeners

## Deviations from Plan

None — plan executed exactly as written.

## Threat Model Coverage

| Threat | Mitigation Applied |
|--------|--------------------|
| T-01-01 Token disclosure on reconnect | Token forwarded via `X-User-Token` header only; reconnect reuses same in-memory token, never in URL |
| T-01-02 Unbounded reconnect loop | Hard cap at `MAX_RECONNECT_ATTEMPTS = 5` with growing backoff; client stops and surfaces onError after exhaustion |
| T-01-03 Malformed SSE payload on reconnect | Payload passes through existing `normalizeTaskUpdate`/JSON.parse with try/catch — unchanged |

## Self-Check: PASSED

- FOUND: windows/src-tauri/src/commands/http.rs
- FOUND: windows/src/services/sse.ts
- FOUND: .planning/phases/01-quick-fixes/01-01-SUMMARY.md
- Commit 8eefd70: fix(01-01): distinguish interrupted SSE stream from clean DONE in Rust
- Commit 0c0f92b: feat(01-01): add exponential backoff reconnect to Windows SSEClient
