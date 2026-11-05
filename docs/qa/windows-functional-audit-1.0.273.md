# Windows functional audit, 9 October 2026

Status: in progress. This is not a complete functional signoff.

## Environment and evidence

The installed native Windows application is exercised interactively through Royal TSX, existing Dalf38 VPN session. Windows 11 Pro Education, AMD Ryzen 7 5700X3D, 48 GB RAM. Browser fixtures are not used as native evidence. Initial installed version: 1.0.271.

Synthetic test audio and identifiable QA records are used. Existing recordings, notes, credentials and calendar configuration are preserved. QA fixtures remain identifiable; the test vocabulary entry is disabled and scoped to the QA profile.

Candidate source: `ab20dda225cffeb48a0bbfebb92001daec5508b9`, branch `codex/personal-corrections`. Build [37930058756](https://github.com/michelknoop21/ThoughtVault/actions/runs/37930058756), explicit mirror ref `codex/windows-functional-1.0.273`, production configuration, publication disabled. Installed via elevated MSI, exit 0, executable ProductVersion 1.0.273. Existing notes SHA-256 unchanged after upgrade.

## Native checks on 1.0.271

| Function | Result | Evidence / limit |
| --- | --- | --- |
| Start, close, restart, navigate | Pass | Real executable; persisted person survives restart. |
| Combined recording | Partial | Starts and creates widget and audio; RDP silence does not prove incoming meeting audio. |
| Quick note | Pass | Saved during recording and read back after reopening editor. |
| Main/widget pause and resume | Fail, source fixed | Main pause froze main timer but widget continued; widget pause did not update main state. |
| Stop without processing | Fail, source fixed | Two attempts reported timeout after audio was finalized; widget continued until timeout. |
| Audio import with local Whisper | Crash, candidate fix pending | Synthetic WAV, Small model loaded, inference crashed with Windows exception 0xc000001d. |
| People create/edit/search | Pass | Empty name disables save; own QA name, role, organisation and alias saved and read back, including after restart; alias search matches. |
| Notulen profile create/edit | Pass | Empty profile rejected; own instruction/description/sections persist; writing style changed to Technisch. Upgrade persistence still pending. |
| Ollama Cloud connection | Pass | Connection test succeeds; model refresh lists 18 models. Generation awaits Whisper regression test. |
| Selected dropdown text | Pass in exercised dropdowns | Cloud model and correction scope selected rows legible; native menu uses dark text on light selected background. |
| Personal vocabulary | Pass for management | Own correction saved, scoped to QA profile, read back, disabled and opened for editing. Actual pipeline application still pending. |
| Microsoft 365 calendar | Partial | Existing account shown connected; Home loads without error. Known-event retrieval / fresh OAuth not exercised. |
| Obsidian | Blocked | Disabled, no API key configured, local service unreachable. Connection test reports unavailable correctly. |
| Feedback | Pass | Empty copy disabled; own QA text copied with success message. Nothing submitted externally. |
| Windows permission settings link | Pass | Opens actual Windows microphone settings. Existing microphone permissions already enabled; no changes made. |
| General update-check preference | Pass for setting | Switched off, navigated away/back, state retained, restored on. Public update/install flow not exercised. |
| Tasks window | Partial | Empty-state and navigation work; processing task lifecycle requires working inference. |

## Fixes

`4b913f6`: recording completion delivered directly from the audio thread instead of relying on draining visualization events. Main and widget pause/resume/stop state share native events and a synchronized timer snapshot. Stop without processing remains in stopping state until finalization, then saves its quick note and closes the widget; it does not trigger the AI pipeline.

`ab20dda`: build Whisper with GGML_NATIVE OFF, AVX2 ON, AVX512 OFF and BMI2 OFF. Build-server CPU features must not determine instructions shipped to desktops. CI checks the actual CMake cache and executes an ignored, explicit model-backed Whisper inference smoke test after building the MSI. Real desktop verification is still required: CI inference alone cannot prove this PC's compatibility.

## Automated checks

Frontend: 90 tests in 34 files passed; production frontend build passed. New regression tests cover pause/resume synchronization without the recording page mounted. Native regression checks completion without consuming visualization events. Candidate CI passed: 25 native tests, plus the separate model-backed Whisper inference test, self-contained runtime and MSI upgrade/start/storage checks. MSI SHA-256: `deede69a888c35cbfb32c50e51790600ce9dfde96a9a9b0f9ebe5fc75d0eac5d`. The downloaded Windows MSI matches this hash. Native Small inference completed on the actual Ryzen PC without a crash.

## Remaining acceptance

Complete follow-up candidate regression: synthetic import through Whisper and Ollama, note editing/search/export, saved-recording import, and vocabulary application. Actual microphone/meeting capture, unconfigured external providers and Obsidian export cannot be inferred from source or synthetic tests.

## Native 1.0.273 regression

- Main/widget pause and resume synchronize in both directions, including with RecordingPage unmounted. Duration remains 00:19 during an extended pause.
- Combined capture with synthetic Windows SoundPlayer audio exercised; waveform responds. Native capture levels still need numerical confirmation.
- Stop without processing finalizes promptly and closes widget. It now exposes a redundant-close `window not found` error. Removed the duplicate normal close in the follow-up source.
- Home incorrectly displayed an idle/new recording while the widget was active. Follow-up source shows current recording and preserves its mode.
- Synthetic WAV import completes Whisper Small inference without the illegal-instruction crash. Ollama generation fails after transcription via WebView fetch. Follow-up source routes official Ollama Cloud generation through the existing native HTTP proxy, matching model retrieval.
- API-key save showed only a generic failure. Follow-up source reports sanitized keyring storage errors; no credential was read, changed or submitted by the audit agent.
- Replace native confirmation messages in recording, model removal and note replacement with the existing ThoughtVault DesktopDialog.

## Model advice, follow-up candidate

Advice is provisional CPU guidance, not hardware compatibility or a measured speed promise. Current selection is preserved, all models remain accessible through “Alle modellen tonen”, and local processing/download are not disabled by recommendations. Unknown/invalid hardware gives no fabricated recommendation. Limited resources warn about duration and suggest cloud as an alternative. System-drive free space is not used to filter models because it may differ from the actual model storage volume. Total RAM and logical thread count do not measure free memory, CPU throughput or ongoing meeting load.

Primary references: [whisper.cpp model disk/memory table](https://github.com/ggml-org/whisper.cpp), [Jan hardware-fit guidance](https://www.jan.ai/docs/desktop/quickstart), [LM Studio memory estimation](https://lmstudio.ai/docs/cli/local-models/load). LLM memory requirements are not copied into Whisper thresholds. Windows currently ships CPU inference; no GPU acceleration is assumed. Model speed recommendations require future real hardware timing evidence to calibrate.
