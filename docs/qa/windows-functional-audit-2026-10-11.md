# Windows functional audit, 11 October 2026

Status: in progress. Not approved for colleagues yet.

### Additional export and model checks

- Native TXT readback joins adjacent headings/paragraphs in 1.0.274. Shared plain-text conversion now preserves block breaks and excludes style/script text for TXT and note copying. Full frontend suite: 106 tests in 40 files; TypeScript and Vite build pass. Native retest pending.
- Whisper recommended list and all-model override visually tested. Selected Small preserved. Medium download starts with visible progress and cancellation returns `Download geannuleerd`. Read-only file listing confirms only existing ggml-small.bin remains, no partial Medium file.
- Private candidate 1.0.277 run 38122510862 passes Windows native tests, build, CPU inference, packaged runtime and installer upgrade checks. MSI SHA256 dc095cd7d8c601a9010ed20819410efee1ded1460204f972a136c419e1bc23be matches the downloaded Windows file. Publication disabled.

## Environment and upgrade

Native Windows app, existing Royal TSX Dalf38 VPN session. Initial executable version 1.0.273. Updated to candidate 1.0.274 from private GitHub Actions run 37935735527, source 1c3c82652112a2f58b362b983c4b9e4c39946e15. Publication disabled.

MSI SHA-256 verified on both Mac and Windows: `a1f490f43363c41289cd05a02602e073f2166b2df11707845772d063f65fe98e`.

User confirmed the unsaved API draft was safely retained before closing. Roaming and local app data backed up under `%LOCALAPPDATA%/ThoughtVaultUpgradeBackups/1.0.274-20261011`. Elevated MSI exit 0; ProductVersion 1.0.274; notes hash before/after identical. First start triggered Avast CyberCapture scanning; no antivirus bypass or exclusion applied.

## Fresh acceptance matrix

Previous audit results are not counted as fresh acceptance.

| Area | Required checks | Current result |
| --- | --- | --- |
| Installation/data | Upgrade, reopen, notes/profiles/people/settings preserved | 1.0.277 installed; notes hash preserved; own note editor survives full restart; people/profile readback passes |
| Recording | Combined start, sound/silence alignment, mic/system levels, pause/resume both directions, navigation, quick notes, stop/process, keep-only | Short combined capture, pause/widget synchronization, navigation, quick note and final mix pass; keep-only pending |
| Widget | Fast stop during initialization, main/widget state, timers after an hour, stop/error cleanup | Normal pause/resume/stop pass; idle-race regression passes; hour display pending |
| Multi-hour capture | At least 3 hours real elapsed capture, periodic synthetic speech and silence, continuous audio/file growth, CPU/memory, final save and processing | Started about 10:45 CEST; numeric monitor and periodic speech running since 10:51; not completed |
| Long-file processing | Read full duration, transcription at start/middle/end, safe mix memory, provider chunking/retry | Three-hour accelerated PCM stress passes locally and Windows CI 1.0.280; actual long native transcription pending |
| Imports/saved audio | File selection, supported formats, invalid input, import/reprocess, no duplicate temporary source after successful mix | Invalid WAV rejection and own capture reprocessing pass; short final mix leaves one WAV; saved delete cancellation pending |
| Notes | Edit/save/reopen, search/filter, copy, available exports, word corrections in actual pipeline | Edit/restart persistence, tags, one-time correction, copy, MD/HTML pass. Content search and TXT fixes await installed retest. PDF file saves but follow-up navigation freezes in 1.0.277 |
| People/profiles | Validation, create/edit/readback, participant selection, profile application | Own person/profile edit/readback and blank validation pass; participant picker passes; custom profile pipeline pending |
| Processing/tasks | Progress, failed provider, retry without lost transcript, concurrent jobs, supported cancellation | Normal processing persists; tasks empty-state/refresh pass; scoped progress source regression passes; failure/retry and concurrency native pending |
| Settings/models | Every tab, local/cloud provider discovery, recommendations and all-model override, download/cancel, key persistence | Local/cloud presets/discovery, cloud connection, selected model preservation, recommended/all override, download/cancel pass. Credential entry user-operated |
| Integrations | Calendar known event, Obsidian test note export, MCP if offered, external connection failure | Microsoft 365 connected, known-event proof pending. Obsidian failure message passes; positive vault export blocked by unavailable local service |
| Recovery | Restart persistence, device disconnect, insufficient disk errors, interrupted processing, update while recording | Notes survive full restart; upgrade preserves storage. Device/disk fault and interrupted processing native pending |

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

### Installed 1.0.277 acceptance, 10:10 to 10:23

- CI 38122510862 passed native regression, packaged CPU inference, runtime and installer upgrade checks. Installed MSI SHA256 `dc095cd7d8c601a9010ed20819410efee1ded1460204f972a136c419e1bc23be` matches downloaded artifact. Backed up both local and roaming app directories; actual `local-transcripts.json` hash preserved across upgrade.
- Own combined capture `recording_1791706354744.wav`: microphone and CPAL system fallback both initialize at 44.1 kHz. Main pause/widget resume and widget pause/main resume synchronize. Navigation through Home and Settings keeps capture active. Quick note saves and reopens with exact QA text while active and paused. Stop closes widget and starts processing.
- Native log records 1874272 mono samples, 117.14 seconds of audio versus 270.69 seconds elapsed including pauses. Final WAV is 3748588 bytes; temporary loopback file absent. Numeric PCM inspection locates the two own speech fixtures at active seconds 32–39 and 89–99 with the gap retained. First fixture ends at the intentional pause. This is a short native alignment check, not three-hour acceptance.
- Editing the own 09:16 note no longer reverses typing. Saved `Kern. QA opslagcontrole 20261011: wijziging behouden na heropenen.` and read back exactly after opening another note and returning. Full app restart persistence still pending.
- PDF export opens the native print preview with the correct title, metadata and note body. Microsoft Print to PDF saves `Downloads/ThoughtVault-QA-277-20261011.pdf`, 67126 bytes, 10:23:22. PDF file creation passes. Follow-up interaction fails: navigation and processing progress freeze after printing although native processing continues. Deferred iframe cleanup is covered by the existing frontend test; native retest pending.
- The 117-second fixture completed and persisted at 10:22:41, but the UI incorrectly remained at 48% after PDF printing. The app may now be updated, since no capture or processing is active. Candidate 1.0.280 adds content search, scoped progress/serialized inference and block-preserving TXT/copy; 106 frontend tests across 40 files and TypeScript/Vite pass. CI 38123916166 has reached the three-hour PCM mixing gate; installation and native retests remain pending.

### 10:36 transcription diagnosis and PDF follow-up

- CI 38123916166 for private 1.0.280 passes all gates, including Windows three-hour accelerated PCM mixing and installer upgrade. Actual three-hour elapsed recording has not started.
- Captured second speech fixture matches its generated reference at correlation 0.99958. Cropped local Small inference recovers Alex, Monday 10:00 and the decision; full 117-second inference instead repeats invented text. No-context alone does not correct it. Standalone speech detection and bounded utterances are being tested; no production fix claimed. Diagnostic captured audio stays outside Git.
- Deferred PDF frame cleanup passes all 106 frontend tests across 40 files. Native follow-up navigation must still be verified.

### 10:42 candidate 1.0.281

- Standalone Silero VAD with padded, bounded utterances recovers both own speech fixtures from the captured file. Built-in FullParams VAD alone is bypassed by whisper-rs full_with_state, so it is not used as a fix.
- The bundled 864 KiB detector works offline and its MIT license ships with the MSI. Synthetic fixture is committed; actual recorded audio is not.
- New Small-model regression preserves Alex and Monday twice, including speech reduced to 4% amplitude after 45 seconds of silence. It passes locally in 2.8 seconds. Silence detector test and all 28 ordinary native tests pass; 3 explicit stress/model tests remain ignored in the normal suite and are separately exercised. Native Windows verification remains pending.


### Real elapsed duration test, 10:45 onward

- Combined capture 1.0.277 started about 10:45 CEST. Main and widget show matching 07:01 at 10:52. No update/restart is allowed while this capture is active. Recorder source is unchanged through candidate 1.0.281.
- Own synthetic Dutch speech plays at 15-minute intervals. PowerShell Job3 runs a three-hour monitor started at approximately 10:51:40; it does not stop or restart the app. Earliest finalization is after the completion marker, expected after 13:51 CEST.
- First CSV row: UTC 2026-10-11T08:51:50.0863935Z, PID 11116, main/system WAV sizes both 11796480 bytes. Root-process working set 36773888 and private memory 11558912 bytes; these values exclude WebView subprocesses and must not be reported as whole-app memory. CSV is `%TEMP%/ThoughtVault-duration-20261011.csv`, completion marker `%TEMP%/ThoughtVault-duration-20261011.finished.json`.
- First diagnostic job failed because its filename filter selected the loopback file; corrected the diagnostic script to exclude `.loopback.wav`. Native capture remained uninterrupted.
- Own 09:16 note editor content survives a full app restart, exact text visually read back at 10:43.
- Candidate 1.0.281 source 8e6fa7c is pushed on the owned branch. CI 38125812625 is in progress. Do not claim installed acceptance until the long capture is finalized, upgrade verified and regressions retested.
- At 10:54, deleting the own 09:42 QA note opens the app confirmation sheet with its permanent-deletion warning. Cancelling retains the note. No permanent deletion performed.
- At 10:58, widget shows active duration 12:55. PID remains 11116. CSV rows at UTC 08:56:50 and 08:57:50 show main WAV growth from 21405696 to 23322624 bytes, while system WAV remains 11796480 bytes between synthetic speech markers. Check the next marker and final PCM alignment before attributing a system-audio failure. Root-process working set is 38432768 bytes and private memory 13180928 bytes, excluding WebView processes.
- CI 38125812625 has passed frontend/native verification and the accelerated three-hour mixer gate. Packaging, packaged CPU inference and installer acceptance remain in progress.
- Thread heartbeat `thoughtvault-windows-duurtest-en-audit` continues at 15-minute intervals. It must preserve active capture, wait for three real elapsed hours and the completion marker, then finalize the own test capture before installing and retesting candidate 1.0.281.

- Heartbeat 11:11 CEST: capture remains active, widget 25:35, same PID 11116. At UTC 09:07:00 the next synthetic speech marker advances system WAV from 11796480 to 40927232 bytes, equal to the microphone file at that measurement. This resolves the earlier stalled-size concern for this interval; silence is retained by timestamp placement when subsequent audio arrives. Final PCM marker verification remains pending. At UTC 09:11:00 main WAV 48611328 bytes, system 40927232, root working set 38432768 and private memory 13156352 bytes, excluding WebView. CI 38125812625 remains in progress. No capture interruption or upgrade performed.

- Heartbeat 11:26 CEST: native observation blocked because the Mac is locked and CUA automatic unlock failed. No app action attempted; recording continuity and latest CSV cannot be newly verified until manual unlock. CI 38125812625 successfully built the Tauri app at UTC 09:00:29 and is still running packaged Whisper CPU inference; no completed MSI acceptance claimed.

- Heartbeat 12:41 CEST: Royal TSX observation available again. Capture widget 1:55:35, unchanged PID 11116. UTC 10:40:01 to 10:41:01 main WAV grows 219529216 to 221446144 bytes; system WAV 213762048 bytes reflects the latest marker with timestamp gaps preserved. Root working set 38338560 and private memory 11894784 bytes, excluding WebView. No native restart, pause or upgrade performed. CI still in packaged Whisper CPU verification started at UTC 09:00:29; current-step logs unavailable via job log endpoint while in progress, so the reason for its long duration is not confirmed.

- Heartbeat 12:56 CEST: widget active 2:10:47, PID 11116 unchanged. UTC 10:55:11 to 10:56:11 main WAV 248651776 to 250576896 bytes, system WAV 242892800 bytes. Root working set 38338560 and private memory 11894784 bytes exclude WebView. No interruption observed in this check; final audio integrity is still unverified. CI remains in the packaged CPU inference step.

- Heartbeat 13:11 CEST: widget 2:25:41, PID 11116. Main WAV grows 277782528 to 279699456 bytes across UTC 11:10:22 and 11:11:22; system 272023552 bytes. Root working set 38338560 and private memory 11894784 bytes exclude WebView. Capture untouched.
- Candidate 1.0.281 CI 38125812625 completed successfully at UTC 11:01:32: native 30 passed/3 ignored, accelerated three-hour mix 7.75s, two explicit Small CPU inference tests passed, runtime and installer upgrade passed, publication skipped. However CPU model tests took 7175.01s overall: smoke completed UTC 09:06:27 and long-silence test UTC 11:00:27. This is a serious performance acceptance concern despite correctness pass; native speed on the target Windows machine must be measured before colleagues-ready signoff. Installer download is staged after CI completion; no live upgrade during capture.
- CI performance root evidence: Silero VAD alone reports 6930201.50 ms for 1864314 samples (116.52s audio), finishing UTC 10:56:23. The delay is in speech detection, not the model download. Correctness pass is insufficient; investigate detector CPU/thread configuration before accepting long-meeting transcription. Downloaded private MSI is available under build/windows-functional-1.0.281.

- Heartbeat 13:26 CEST: native widget 2:40:42, unchanged PID 11116. Main WAV grows 304988160 to 306913280 bytes; system 301154304 bytes. Root memory unchanged. Capture untouched.
- Candidate 1.0.282 sets the shared Silero detector to one CPU thread, avoiding synchronization overhead for small sequential frames. Adds a <60s detection acceptance assertion to the existing 116.52s speech/silence regression. Local correctness regression passes in 2.81s total; Windows speed proof still required, not claimed. Candidate 1.0.281 must not be accepted for long-meeting processing merely because its tests passed.
- Candidate 1.0.282 source ee3479a pushed to origin and private build ref codex/windows-functional-1.0.282; CI 38135693836 dispatched with production channel, publish=false. Local detector measured 187.33ms for 116.52s fixture. Windows validation and native installation remain pending. Use this candidate for follow-up if CI succeeds; preserve ongoing 1.0.277 capture until completion marker.

- Heartbeat 13:41 CEST: widget active 2:55:44, PID 11116 unchanged. UTC 11:39:42 to 11:40:42 main WAV 334118912 to 336035840 bytes; system 330276864 bytes. Root working set 38338560 and private memory 11894784 bytes exclude WebView. Three-hour completion marker not yet due; capture left running. Candidate 1.0.282 CI 38135693836 is verifying frontend/native code.

- Read-only follow-up 13:44 CEST: widget 2:58:33, PID 11116 unchanged. UTC 11:42:42 to 11:43:42 main WAV grows 339877888 to 341803008 bytes; system 330276864 bytes. Root working set 38338560 and private memory 11894784 exclude WebView. Completion marker still not due before approximately 13:52; no capture action or installation performed. Candidate 1.0.282 CI remains in frontend/native verification.

- Heartbeat 13:56 CEST: native widget 3:10:34 and completion marker verified. Monitor elapsed 10812.5759794 seconds, finished UTC 11:51:52.6722832, capture recording_1791708341243.wav. After the marker, native Recording pause at 190:57, Bewaar zonder verwerken and Stoppen confirmation completed. At 13:57 app returned to idle and recording widget closed. Only this own synthetic QA capture was stopped.
- Native filesystem readback: only recording_1791708341243.wav remains for this capture prefix, length 366632260 bytes. Temporary loopback file is absent. Actual WAV header duration and begin/middle/end PCM markers remain pending. A one-request POST-only local receiver on port 18752 was started to inspect only this own QA audio; PowerShell upload was still preparing when the Mac locked. No private audio requested or published.
- At 13:59 CEST Mac lock prevents Royal TSX observation, automatic unlock failed. App has already safely finalized this capture. No upgrade attempted. Candidate 1.0.282 CI 38135693836 has passed frontend/native verification, accelerated three-hour mix and Tauri packaging; packaged CPU inference is in progress. Resume native testing after manual unlock and candidate acceptance.

- Heartbeat 14:11 CEST: candidate 1.0.282 CI 38135693836 completed successfully UTC 12:03:52. Native verification 30 passed/3 ignored, accelerated three-hour mixer 6.53s, two explicit Small CPU inference regressions passed in 686.54s, self-contained runtime and installer upgrade gates passed. Publication skipped. Silero VAD for 116.52s audio improved from 6930201.50ms in 281 to 10263.22ms in 282. Full Whisper processing on the actual target machine remains unmeasured. Private MSI downloaded; SHA256 9c765c3108e0357dcc14aa5d2c61ed9f9cab3d4df66da7f7ab1bc83b7aae0759.
- Own saved duration capture transferred locally successfully while Mac was locked. WAV header verified: mono PCM16, 16000Hz, 183316108 samples, duration 11457.25675s (3:10:57), file 366632260 bytes. Begin, middle and final reference markers located at 359.0027s, 5760.2842s and 11161.5701s. Whole-marker correlation 0.999579, 0.817358, 0.990320; no clipped samples in these markers. Middle marker has a roughly 22.94ms alignment change in its first 1.7s: independently aligned 0.5s/1s blocks correlate >0.9998, later blocks >0.9995. Do not claim pristine sample timing across the entire recording or dismiss this as environmental noise; native long-file transcription and further timeline assessment remain pending. Raw capture and numeric analysis stay in ignored build directory.
- Mac remains locked at 14:11; Royal TSX automatic unlock fails. No native upgrade or app action attempted. Remaining native PDF, TXT, search, concurrency and long-file processing checks await manual unlock.

- Follow-up 14:30 to 14:32 CEST: Royal TSX access restored. Fresh local and roaming backup at %LOCALAPPDATA%/ThoughtVaultUpgradeBackups/282-20261011. Initial local copy encountered the open WebView Cookies file; after confirming native recorder idle and closing the Windows app, repeat copy completed without errors. Backup notes and own duration WAV hashes both match originals. MSI hash matches 9c765c3108e0357dcc14aa5d2c61ed9f9cab3d4df66da7f7ab1bc83b7aae0759. Native installer completed 14:31:05, status 0, product 1.0.282. Actual binary C:/Program Files/ThoughtVault/ThoughtVault.exe reports 1.0.282; notes and saved capture hashes unchanged after installation. App launched with QA stderr/stdout; Avast performs its ordinary first-launch scan. No exclusion or bypass used. Native long-file transcription and export acceptance still pending.

- Native follow-up 14:36 to 14:40 CEST: own 190:57 saved duration capture reprocessing started using Whisper on this PC, Standard profile. Processing bar advances from 10% to 11%; native note and Home navigation remain available during processing. PID 49792, started 14:32:20, CPU 588.640625s, working set 911429632 bytes, private memory 1490292736 bytes at 14:40; these exclude WebView children. Numeric stderr confirms bounded VAD segments. Long-file completion, recovered markers and final processing time still pending. Do not interrupt this processing or start a duplicate.
- PDF regression native PASS on 1.0.282: own Notulen QA 20261011 preview opens; cancelling then Home navigation succeeds. Reopening, Microsoft Print to PDF and saving Downloads/ThoughtVault-QA-282-20261011.pdf succeeds, 54591 bytes, 14:39:25. Home navigation succeeds again and background long-file progress continues. This closes the reproduced 277 PDF follow-up freeze for both preview cancel and save on this target. TXT/content search/concurrent progress and remaining audit matrix checks remain open.

### 15:59 long-file processing failure

- Native 1.0.282 now reports failed at 20%, after starting at 14:36. PID 49792 remains unchanged; root working set drops to 37179392 bytes and private memory to 10919936 after processing exits. No restart or duplicate processing was started. Exact failure time is only bounded by the previous 15:42 active observation and 15:59 failed observation.
- Saved own duration capture hash still equals the verified backup at 16:02. Audio remains intact. Long-file transcription acceptance FAIL; colleagues-ready signoff remains blocked.
- Existing frontend discarded native string rejections, replacing them with the generic Dutch failure message. Preserve nonempty native error strings and cover this with a regression; native inference now logs errors with the failing segment's audio offset, without transcript content. Original native error is not recoverable from the existing stderr/stdout checks, so its root cause is not claimed.
- Source checks: 107 frontend tests in 40 files pass, TypeScript/Vite build passes, 28 ordinary native tests pass and 3 explicit stress/model tests remain ignored in the ordinary suite. These source checks do not prove native long-file recovery.
- An ignored standalone local diagnostic is examining only audio minutes 40–50 with the same bounded-VAD/Small decode logic. Its output contains numerical segment offsets and errors only; it does not launch the macOS app or publish audio. This diagnostic is not Windows-native proof.
- This local 40–50 minute diagnostic completed with exit 0. It did not reproduce the Windows failure. Candidate 1.0.283 adds diagnostic error preservation only; do not claim it fixes long-file inference. A new private Windows build and targeted native reproduction are required.

- Heartbeat 16:45 CEST: private 1.0.283 CI 38146290865 completed successfully on source 54cf6d268fc0208ada2d03543a0353b1604911a9, publish=false. Frontend 40 test files pass; ordinary Windows native tests 30 passed/3 ignored, explicit accelerated three-hour mixer 5.09s, two explicit CPU inference tests 473.26s. Silero processed the 116.52s fixture in 6928.42ms. Packaged runtime and MSI upgrade, two launches and saved-notes preservation passed on CI. Downloaded MSI SHA256 26e728cd9d7da8b1b54289ddbfd76bf4cec501a2b82ae19791c8c34152441c85. Target-machine installation and targeted native fault reproduction remain pending because the Mac is locked and Royal TSX automatic unlock fails; this is the same access block reported at 16:15, not a new failure. Target remains last verified 1.0.282.

### October 12 native diagnostic follow-up

- Royal TSX access restored. Verified recorder idle and previous processing failed before closing the Windows app. Fresh local/roaming backup at %LOCALAPPDATA%/ThoughtVaultUpgradeBackups/283-20261012 completed; saved notes and own duration capture hashes match originals. Redownloaded the same private CI MSI and verified SHA256 26e728cd9d7da8b1b54289ddbfd76bf4cec501a2b82ae19791c8c34152441c85 locally and on Windows.
- Native upgrade verified at 08:51: actual Program Files binary reports 1.0.283, notes and own capture hashes remain unchanged. Fresh native launch passed Avast's ordinary first-launch scan without exclusion or bypass. PID 33228, start 08:51:55. macOS app untouched.
- Created a separate own QA minutes 40–50 WAV on Windows using read-only access to the original and CreateNew for the crop: 600s, mono PCM16 16000Hz, 19200044 bytes, %TEMP%/ThoughtVault-QA-40-50-20261012.wav. No audio transfer or publication. Native import with Whisper on this PC and Standard profile started at 08:58; processing bar shows Transcriberen 10%. Do not interrupt or start a duplicate.
- At 08:58:53 PID 33228 CPU 81.90625s, working set 940531712 and private memory 1499791360 bytes, excluding WebView. Numeric VAD diagnostics enumerate bounded segments; error/failed/invalid filter returns no matches yet. QA stderr/stdout are %TEMP%/ThoughtVault-qa-283.stderr and .stdout. Completion, original error reproduction and full long-file acceptance remain pending. Version 283 provides diagnostics, not a proven inference fix.

- October 12 10:17 native targeted diagnostic reproduced a concrete failure: at 36%, "Segment lezen mislukt bij 390s: Invalid UTF-8 detected in a string from Whisper. Index: 7, Length: 1." The crop offset corresponds to 46:30 in the original capture. It was active at 09:16; exact completion/failure time is not yet logged. This proves malformed Whisper segment text aborts this native run, not that all long-file concerns are resolved.
- Michel manually retriggered the failed imported task around 10:19. At 10:20 Tasks shows import_L4fwpS.wav, Transcriberen 10%, one active row. Preserve this user-started retry; do not install, restart or duplicate while active.
- Candidate 1.0.284 reads raw segment bytes while retaining native null-pointer errors, decodes malformed UTF-8 with the standard replacement character and logs only the error and audio offset. Valid surrounding words and accented UTF-8 are preserved. A regression failed under strict decoding, then passed with the correction; ordinary local native suite 29 passed/3 ignored and release cargo check passed. Windows CI and native recovery still pending. This is a Windows source build/test, no macOS app launch or installation; shared version metadata is synchronized by the project script.
- Michel explicitly requested continuation of the visual audit for unnecessary vertical scrolling. Existing recording inspector fixed heights/margins are being investigated; no visual correction or native visual acceptance claimed yet. Full long-file inference speed, TXT/search/scoped progress and remaining matrix still open.
