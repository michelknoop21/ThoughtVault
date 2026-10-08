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
