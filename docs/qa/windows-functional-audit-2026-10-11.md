# Windows functional audit, 11 October 2026

Status: in progress. Not approved for colleagues yet.

## Environment and upgrade

Native Windows app, existing Royal TSX Dalf38 VPN session. Initial executable version 1.0.273. Updated to candidate 1.0.274 from private GitHub Actions run 37935735527, source 1c3c82652112a2f58b362b983c4b9e4c39946e15. Publication disabled.

MSI SHA-256 verified on both Mac and Windows: `a1f490f43363c41289cd05a02602e073f2166b2df11707845772d063f65fe98e`.

User confirmed the unsaved API draft was safely retained before closing. Roaming and local app data backed up under `%LOCALAPPDATA%/ThoughtVaultUpgradeBackups/1.0.274-20261011`. Elevated MSI exit 0; ProductVersion 1.0.274; notes hash before/after identical. First start triggered Avast CyberCapture scanning; no antivirus bypass or exclusion applied.

## Fresh acceptance matrix

Previous audit results are not counted as fresh acceptance.

| Area | Required checks | Current result |
| --- | --- | --- |
| Installation/data | Upgrade, reopen, notes/profiles/people/settings preserved | Notes hash preserved; other readback pending |
| Recording | Combined start, sound/silence alignment, mic/system levels, pause/resume both directions, navigation, quick notes, stop/process, keep-only | Pending |
| Widget | Fast stop during initialization, main/widget state, timers after an hour, stop/error cleanup | Source race fixed; 97 frontend tests pass; native pending |
| Multi-hour capture | At least 3 hours real elapsed capture, periodic synthetic speech and silence, pause, continuous audio/file growth, CPU/memory, final save and processing | Not started |
| Long-file processing | Read full duration, transcription at start/middle/end, safe mix memory, provider chunking/retry | Mix streaming source fix under native test |
| Imports/saved audio | File selection, supported formats, invalid input, import/reprocess, no duplicate temporary source after successful mix | Pending |
| Notes | Edit/save/reopen, search/filter, copy, available exports, word corrections in actual pipeline | Pending |
| People/profiles | Validation, create/edit/readback, participant selection, profile application | Pending |
| Processing/tasks | Progress, failed provider, retry without lost transcript, concurrent jobs, supported cancellation | Pending |
| Settings/models | Every tab, local/cloud provider discovery, recommendations and all-model override, download/cancel, key persistence | Pending; credential entry remains user-operated |
| Integrations | Calendar known event, Obsidian test note export, MCP if offered, external connection failure | Pending; use current configured services only |
| Recovery | Restart persistence, device disconnect, insufficient disk errors, interrupted processing, update while recording | Pending |

## Source findings being fixed

- Late-created recording widget ignored an idle timer snapshot and could remain after missing `recording-stopped`. Close on an authoritative idle snapshot; regression exercises active/paused/stopping followed by idle.
- Mixing loaded microphone, system and mixed output entirely into RAM. Stream equal-rate native WAV files into the existing atomic temporary output, retain different-rate compatibility, surface corrupt input rather than discarding decode errors. Native regression checks signed extremes, unequal durations and resampling. This does not prove real capture alignment or a multi-hour run.

## Outstanding investigation

Prior logs had shorter system audio than mic audio. Test timed synthetic speech separated by silence before attributing drift. Check the final mixed WAV positions, not just waveform movement or file length.

### Fresh native short capture, candidate 1.0.274

Combined capture: no pause, stop after 49.96s. Mic WAV held 696851 samples (43.55s), loopback 242272 (15.14s). Own synthetic test speech played at 09:13:48 for 15 seconds, beginning about 17 seconds after recording started. Source callbacks appended packets without timestamps; WASAPI silent intervals and capture gaps compacted the timeline. Shared active clock and timestamp-based placement are now in source, with silence/gap/overlap/jitter regressions. Installed verification still pending.

- Short native local Whisper plus configured cloud notule generation succeeded in 1.0.274, visible as the new own QA "Verslag gesprek" at 09:16. Transcript edit/export/readback still pending.
- Audio save/device errors now surface through the existing recording-error route; previously stream errors and failed sample writes were only logged or discarded.
- Stop awaits the existing completion channel instead of resetting after 60s while a large mix might still be writing.

- Real typing in the note editor reset the DOM/caret per keystroke, reversing the own test marker. Fix keeps the browser-owned editing DOM and reads/sanitizes it on save/correction; regression verifies text node and caret survive input and failed save retains the draft.
