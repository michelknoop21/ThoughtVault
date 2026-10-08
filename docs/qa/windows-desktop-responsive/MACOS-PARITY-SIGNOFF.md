# Native macOS / Windows parity review

Date: 2026-10-08. Windows is controlled through Royal TSX, connection Dalf38 VPN.
Reference: signed macOS Release build of the same c373a8c baseline, with the person-sheet correction. The older installed Mac 1.0.255 is not the release reference.

## Corrections

- Center all round transport controls at their shared CSS owner.
- Match the Mac idle recording dot and person/tag/document inspector symbols.
- Fill wide recording windows instead of leaving a large unused lower workspace.
- Place personal profile and onboarding in Settings > Notulen, as on macOS. Keep all profile fields and persistence.
- Put feedback in Settings > Account. Use the existing modal focus, Escape and focus restoration, retaining submission/history behavior. No floating button over form fields.
- Match the people empty-state icon and center the empty-state content.
- Fit the complete person form without scrolling on both platforms. macOS uses the existing shared fields outside the grouped Form, removing the duplicate labels and unnecessary scroll container. Windows keeps all six fields, name validation, save/error handling and a fallback scroll owner for shorter unsupported viewports.
- Use narrow neutral WebView scrollbars; keep native Mac scrollbars, keyboard navigation and high-contrast fallback.
- Give the macOS profile-selection sheet an explicit content size. Previously its List collapsed to zero height; native recheck now shows all seven profiles, premium choice and Cancel. This shared sheet also serves retranscription.
- Correct the participant empty-state direction to the actual Mensen sidebar entry.

## Verification

- Signed macOS Release build succeeded; real native person sheet shows all six fields and both actions together, with no scroll area in the accessibility tree.
- Windows TypeScript/Vite build succeeded; 65 frontend tests pass. Settings regression verifies moved profile/onboarding and feedback sheet Escape/focus restoration.
- Density checks: 36 route/viewport/scale combinations passed, including 640x560 and 2x display scale. These are synthetic browser checks, not native Windows evidence.
- Person density regression fails on the previous Windows form (scroll required), then passes at 640x560, 900x560 and 1200x800. Form body 399px; scrollHeight equals clientHeight; all eight inputs/actions are inside the viewport.

## Native review matrix

| Surface | macOS native reference | Windows native recheck |
|---|---|---|
| Home | Seen with real existing notes and agenda | Native 264, regular window, existing notes preserved |
| Recording idle / inspector | Seen | Native 264, full-height workspace and centered controls |
| Tasks empty state | Seen | Pending candidate |
| Notulen list / detail | Seen | Pending candidate |
| People empty / add person | Seen; corrected form verified | Pending candidate |
| Settings, all seven tabs | Current native 263 reviewed | Pending candidate |
| Participants / saved recordings | Current native 263 reviewed, list expanded | Native 264: saved list has one scroll owner and fixed Close; participant search/empty-state correction awaits next candidate |
| Regenerate / retranscription profile sheet | Collapsed Mac layout fixed and regenerate sheet natively verified | Pending candidate |
| Tags | Previous native reference reviewed | Pending candidate |
| Feedback modal | Account location confirmed; existing Mac button has no presented sheet | Pending candidate |

## Boundaries

Platform-specific capture/transcription engines remain genuine: Windows Whisper/Windows capture, macOS WhisperKit/Apple Speech/Apple permissions. No fake Apple Intelligence capability on Windows. The existing local Windows application does not gain a ThoughtVault login merely to copy an older Mac account screen.

No private notes, API keys or native screenshots are committed. This file is a review record, not a full signoff until the pending native candidate checks are complete. Real live meeting capture, provider connectivity and destructive actions require separate functional evidence.

The existing macOS feedback button only sets showBugReportSheet; no sheet is attached. No feedback was submitted. This functional gap is separate from the visual placement correction on Windows and remains open.

## Live meeting interruption and pending correction

The canonical macOS 1.0.264 app crashed at 13:36:09 CEST during combined recording with live transcription. The triggered Core Audio thread exhausted its 544 KiB stack; its repeating frames were closure-reabstraction thunks in the optional system-audio live handler. A standalone optimized Swift 6 check reproduces SIGBUS on a 512 KiB thread with 20,000 handler reads. Storing an immutable handler value instead of returning the inout closure removes the accumulated thunks; the same check against the actual corrected source completes all 20,000 callbacks. The capture/write/error handling and live recognition request remain unchanged. A small-stack XCTest also covers clearing and replacing the handler.

The main recording waveform previously reserved a frame overlapping the live-text and transport regions, particularly at the 720 pt layout breakpoint. The corrected frame is confined between these regions; the shared Canvas is clipped so its blur cannot draw outside. A geometry regression covers seven window heights across that breakpoint.

The widget now uses a fixed dark surface rather than translucent material, readable brand-link status text, a larger existing caption token, brighter drag affordance, and dark Stop text against the existing bright red button. These source changes have not been installed during the ongoing meeting.

The crash left both PCM payloads on disk but unfinished WAV sizes. Local recovery copies received finalized RIFF/data lengths, with payload hashes unchanged. afinfo validates approximately 133.8 s of microphone audio and 66.9 s of system audio. The duration discrepancy remains an open functional issue; this is not complete meeting-capture proof. Private recovery files are outside the repository.

Native macOS test-host execution and installation are deferred until Michel ends the meeting. Independent frequency-band motion and native widget contrast/motion recheck remain pending. Windows candidate 264 CI completed successfully and was installed through Royal TSX; the existing notes file hash was unchanged. Further changed surfaces need a new candidate recheck.

Release build-for-testing with ENABLE_TESTABILITY=YES succeeded without launching the test host. Standalone optimized callback regression (20,000 iterations on 512 KiB stack), seven-height geometry assertions, and widget Rec/Stop text contrast assertions passed. The new XCTest cases are compiled but not executed during the meeting.

## Quick notes during a recording

The existing macOS quick-note popover had no save action, and persisted its text only at recording stop. Both platforms now save edits during recording/pause and provide a visible Bewaar notitie action. The existing final-audio mapping and notule processing remain unchanged. Explicitly clearing a draft removes only that recording's note; an empty processing retry preserves previously saved text. Windows retains the edited text and reports a storage failure so it can be retried.

The signed macOS test build succeeded without launching an app. An isolated Foundation check against the actual QuickNoteStore source passed draft replacement, clearing isolation, retry preservation, transcript mapping and HTML escaping. Windows TypeScript/Vite build and participant search/hidden-selection regression passed. These quick-note changes are source fixes, not installed in the running macOS meeting app.

## Completed meeting: generation limit and duplicate sources

The meeting ended with 3,589.698 seconds of combined audio. The saved transcript is linked to that combined file; the local database contains its transcription and no finalized notule. Generation logged HTTP 429 from the configured Ollama Cloud endpoint. The provider usage limit cannot be removed by an app change; the error now explains the limit and later retry. No successful regeneration is claimed.

After the mix writer closes, the combined file is reopened and read fully in bounded buffers. Its 16 kHz mono format and exact expected frame count are checked before deleting the redundant microphone source. Invalid/incomplete output falls back to the retained microphone. A deletion failure retains the valid combined file and its source; the existing source mapping prevents a duplicate session in the UI. Enumeration for age-based cleanup and direct transcript links remain unchanged.

The microphone source of this completed meeting was first archived with unchanged SHA256. After Michel requested removal, every combined PCM sample was compared with the microphone magnitude under the existing magnitude-max mixing rule (two Int16 units tolerance): no microphone samples were missing across 3,589.698 seconds. With no independent database/task references, the source was moved to the macOS Trash for recovery. The combined file and transcript links remain in place. No audio or transcript content is committed.

The signed test build succeeded. Targeted native XCTest execution passed quick-note tests plus rate-limit error and combined/source-list regressions. These source changes are not yet installed in the canonical application. Meeting monitoring was paused after Michel confirmed completion.

Source-cleanup regression covers complete readable output, frame-count mismatch, malformed audio, and refusal to delete the combined file itself. Automatic source deletion is a source change, not yet installed in the canonical application.

## Post-meeting fixes and native recheck, version 1.0.265

- macOS system-audio live callback uses immutable handler ownership. The former callback recursion is covered by 20,000 appends on a 512 KiB thread stack. Live transcript accumulation and source selection tests pass.
- Both platforms now derive seven independent frequency bands from PCM. Quiet/loud envelope calibration remains shared; no additional capture engine or waveform dependency was introduced. The widget continues animating when its nonactivating panel is in the background. Main waveform drawing is clipped to its reserved bounds.
- System capture preserves silent callback gaps on the recording timeline and excludes explicit pauses. The level watchdog returns to silence instead of leaving a stale level.
- The widget has a fixed contrast surface and enough width for paused recordings approaching ten hours; controls do not compress.
- Notes persist during recording/pause, with an explicit save action. Complete mixed audio is validated before removing the redundant microphone source. Incomplete or malformed mixes retain their source.
- Known hosted Ollama GPT-OSS models use a bounded 64,000-character input chunk instead of 8,000. Other endpoints and models retain the smaller limit. HTTP 429 has a specific provider-limit message.
- The latest completed meeting now has both a preserved transcript and a nonempty generated notule in the local database, linked to audio. This is a later read-only verification, not a claim that this session regenerated it or that provider limits cannot recur.
- macOS local Account no longer offers the removed login flow; its feedback button now opens a working local-copy form. Windows local feedback similarly avoids the old account API.
- Native Cancel buttons align with the primary actions. Disabled buttons visibly dim on both platforms. The macOS grouped settings form and feedback editor follow the existing hidden-indicator pattern; Windows uses narrow neutral scrollbars.
- Windows local Advanced now presents recording access and the existing Windows microphone-settings action. The account-server form remains available only for cloud processing. Provider selection remains in Processing. Native Windows meter colors match the app instead of the white system default.

### Evidence

- macOS final signed Release build succeeds. Full native XCTest: 65 passed, 0 failed, 2 hardware opt-in skips. The separately enabled real system-audio test passes, including quiet/normal/loud levels, silence release, and recorded wall-time agreement within 250 ms. The real microphone writer test passes its less-than-250-ms publication lag bound.
- Windows TypeScript/Vite build and 70 frontend tests pass. Local native audio Rust suite: 20 passed. Final Windows CI run 37790404576 at source a53156e passed 70 frontend tests, 21 native Rust tests and the MSI upgrade/two-start/note-preservation checks.
- The final Windows 265 MSI was installed through Royal TSX, Dalf38 VPN, with SHA256 validation, installer exit 0 and unchanged notes-file hash. MSI SHA256: ec092a14540f447fccf64603ce5ecffba69363f8eb359d2995438ef3f0d39d2c. The final native recheck confirms local Advanced permissions content, visibly dimmed disabled feedback action and neutral audio meter. The app remains idle after verification. Actual macOS 265 is installed at /Applications/ThoughtVault.app with the existing bundle identity and sandbox. Rollback apps remain available.
- Native rechecks: idle recording studio/inspector, all seven settings tab headers and primary content, participant empty state, person form and feedback dialog on both platforms. Windows 265 additionally rechecked Tasks, Notulen list/detail, tags and regeneration profile choice at the regular window size. Both person forms show all six fields and actions without scrolling.
- Native Windows 264 was additionally checked at its 652x600 client minimum: Tasks, Notulen list/detail, regeneration profile sheet, and full person form. Those unchanged layouts are not misrepresented as fresh 265 screenshots.

### Release verification

The source and this review were fast-forwarded to the authoritative Gitea main branch after final CI success. Windows stable 1.0.265 was published through the existing signed-artifact uploader. An external HTTPS check confirms stable version 1.0.265 and HTTP 200 for the 8,871,936-byte MSI; its SHA256 matches the installer verified above. The previous release manifest and Windows feed are preserved on the release server under rollback-before-265. Mac 265 is installed locally but has not been publicly distributed.

### Remaining verification boundaries

The fixed callback and audio logic have regression and real hardware evidence; a complete new videomeeting with the final app, live transcript enabled, background widget and note-save interaction has not yet been repeated. No destructive native operations or private transcript screenshots are included.

The local Mac build uses Apple Development signing. Public Mac distribution is blocked by the absent Developer ID Application identity and notarization setup. The uploader rejects non-notarized DMGs. No weaker signing or unsigned public Mac update was substituted.


## Settings refinement and Ollama discovery, version 1.0.266

The macOS settings tabs retain their existing content and navigation. All seven labels share fixed height and stable typography. They use one row when it fits and a two-row adaptive layout at compact widths, instead of requiring horizontal scrolling or splitting Geavanceerd across lines. The native final app was checked at 1x and Retina 2x scaling, including a 901x633 pt compact window with four plus three tabs. The existing original Windows Yinga SVG was converted to a vector PDF asset for the shared macOS BrandFooter, with the same 42x18 pt footprint. No replacement lettering or oversized logo was introduced.

Both platforms now present one Ollama choice with Lokaal and Cloud controls. Lokaal preselects http://localhost:11434; Cloud preselects https://ollama.com. Existing provider/storage contracts remain intact. Legacy macOS cloud configuration stored under the local Ollama provider is normalized while preserving its selected model. Model discovery runs automatically after the endpoint changes, with cancellation or stale-response protection and a manual refresh action. It reads /v1/models and falls back to /api/tags. Automatic discovery uses the stored cloud credential only for the official HTTPS ollama.com origin; a custom endpoint cannot receive that credential automatically. Existing explicit connection checks retain their configured credential behavior.

Discovery populates available choices without selecting the first model, which could be an embedding model. Existing selected models remain visible even if missing from discovery. Empty/unreachable endpoints retain manual model entry and an actionable error. Windows refreshes the model list after saving or removing its existing credential. The macOS native app automatically discovered two local models and eighteen cloud models, and retained gpt-oss:120b after switching back to Cloud. These checks only requested model lists; no private transcript, generation request, or new credential was sent.

### Current verification

- Final source candidate: 35da97d. Windows local TypeScript/Vite build passes; all 76 frontend tests in 29 files pass, including endpoint normalization, host/credential boundaries, response parsing, preset switching, retained model choices, and stale discovery responses.
- Final macOS signed Release build succeeds and codesign verification passes. Version 1.0.266 is installed at /Applications/ThoughtVault.app with its existing bundle identity and sandbox. All seven tabs were opened in the native app; the final compact check confirms complete labels and the original logo. The source remains compatible with existing iOS settings callers, but no iOS build was requested or run.
- First Windows candidate CI run 37798218220 at source 78d6654 passed 76 frontend tests, 21 native Rust tests, the app build and MSI upgrade/two-start/note-preservation checks. That candidate MSI was installed through Royal TSX with installer exit 0, SHA256 validation and unchanged notes-file hash. Installed executable version: 1.0.266. MSI SHA256: 06c49c115cc625de372618e614af3fa6c134d65e22c30a873adfd17bedb9deec; size: 8,908,800 bytes. The native Windows check automatically populated eighteen cloud models and preserved the existing model name. All seven settings headers/content were opened at the regular window size; compact 652x600 client size retains four plus three complete labels and reaches the Ollama URL/model/refresh/key actions without horizontal overflow. The first candidate exposed missing location-button styles; the final source reuses the existing action row and app button variants. Final CI run 37800818556 at 35da97d passed 76 frontend tests, 21 native Rust tests, app build and MSI upgrade/two-start/note-preservation checks. Its MSI was installed through Royal TSX with installer exit 0, SHA256 validation and unchanged notes-file hash; version 1.0.266 was confirmed. Final MSI SHA256: 239d499ad113cb5b2f63a13f21cb260893982a81cc8bd2cc2908c6c096ab7b89; size: 8,908,800 bytes. The final native check confirms styled separate Lokaal and Cloud buttons, selected Cloud, the canonical endpoint, eighteen automatically discovered models, and the original Yinga logo. Public release verification is pending.

This settings-only candidate does not claim a rerun of the previous full macOS audio/hardware suite or another complete videomeeting. Public Mac distribution still requires Developer ID signing and notarization.
