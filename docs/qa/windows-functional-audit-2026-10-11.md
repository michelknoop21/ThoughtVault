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

- Native TXT export created Downloads/Verslag gesprek.txt (559 bytes). Markdown and HTML files verified in Downloads: 577 and 703 bytes respectively, 09:25:54 and 09:26:01. PDF click silently produced no print window in native WebView, because it depended on an empty popup. Replaced with an in-app print iframe, escaped title and sanitized note body; native retest pending.

### Additional fresh native checks, 1.0.274

- Existing own QA person retained after upgrade. Added expertise `Functionele audit 20261011, opnamecontrole`, saved, closed and reopened; exact text retained.
- General update preference toggled off, navigated away and back; off retained. Restored original on preference.
- Microsoft 365 remains connected; no known calendar-event proof yet. Account page correctly describes login-free local operation.
- Obsidian remains disabled with no API key; test connection returns `Niet bereikbaar` for its configured local endpoint. Successful vault export cannot be accepted until a service is available.
- System advice initially displayed unavailable while CIM data were still loading, then correctly recommended Medium without altering the selected Small model. Separate read-only system check returned Ryzen 7 5700X3D, AMD64, 48 GB, 16 threads, Windows 11, 770 GB free. Avast blocked the separately encoded diagnostic command; no protection disabled. This does not establish a persistent app detection failure. Fix labels pending advice as loading, with regression preserving the selected model.
- Long local-compatible transcripts previously sent as a single unbounded request. Mirror macOS thresholds (8000 characters locally/unknown model, 64000 hosted GPT-OSS), summarize every chunk before applying the final profile, and reject nonshrinking intermediate output rather than silently truncate. Tests preserve Unicode, start/middle/end, participants, quick notes and profile template. This is not yet native multi-hour processing proof.
- Latest frontend verification: 102 tests across 37 files and TypeScript/Vite build pass. Native audio changes are in candidate 1.0.275, CI run 38121287866, source ea82f9ede95e394ae4afa762010cfb6a5c38ed84, publication disabled. Native retest and 3-hour elapsed recording remain outstanding.

### Candidate 1.0.277

- Windows CI 38121287866 compiled successfully but failed two mixer regressions: Windows refuses replacing the microphone file while the owned WAV readers remain open. Candidate 1.0.276 run 38122129138 cancelled because it carries the same defect. Explicitly drop both readers before atomic replacement and buffer the output WAV writes. Five focused local mixer tests pass; Windows rerun pending.
- Native 1.0.274 reprocessing of the own QA capture generated a second notule at 09:42. Importing `ThoughtVault-QA-invalid-20261011.wav` shows an in-app audio-format error and leaves capture idle; no crash.
- Saved recording delete and age cleanup previously permanently removed audio immediately. Both now use the existing app confirmation sheet; cancellation and acceptance regression passes. No existing user audio deleted during audit.
- Candidate 1.0.277: 103 frontend tests across 38 files and TypeScript/Vite build pass. No installed candidate acceptance or multi-hour capture claim yet.

### Native 1.0.274 additional acceptance

- Title search `Verslag` returns the two own QA notes; nonsense search returns the empty state. Content search `Alex` returns no results despite matching raw transcription. Windows filtered titles only, unlike macOS title/raw transcript/tags. Local source fix and one focused search regression pass; installed retest pending.
- Own 09:42 note: adding QA tag succeeds. One-time `Duitvalt` to `ThoughtVault` correction with remember unchecked updates the note and shows saved confirmation; raw transcription remains unchanged. Transcript copy verified through Windows clipboard readback of this own QA fixture.
- Ollama Cloud auto-discovered 18 models, stored key indicator present without exposing the key, native test connection shows connected. Local preset fills http://localhost:11434 and missing local service shows an actionable model-discovery error. Original cloud selection is being restored.
- Three-hour synthetic PCM mix stress passes locally in release mode (4.98s): exact 172800000 sample duration, start/middle/end markers and adjacent silence intact. Added an explicit Windows CI stress gate. This validates large-file processing, not three elapsed hours of native capture.
- Original Ollama settings restored and visually verified: https://ollama.com, gpt-oss:120b, saved key still present. Candidate 1.0.278 frontend: 104 tests in 39 files, TypeScript/Vite pass.

### Further native acceptance and concurrent processing

- Own QA notulen profile updated with `Opslagcontrole 20261011`, saved and reopened; description retained. Creating an empty profile rejects with the in-app message that name and instruction are mandatory. Existing default stays Standaard.
- Add-person dialog fits without scrolling; blank and whitespace-only names keep creation disabled. Existing own QA person found in participant picker and selected; recording sidebar shows one participant.
- Concurrent transcription used a global unscoped number event, allowing one import to overwrite another task's progress. Scope native progress by task request ID and filter in the existing listener. Serialize CPU-heavy Whisper inference to avoid loading simultaneous model contexts. Focused regression sends one task's progress to both listeners and verifies the other task remains unchanged.
