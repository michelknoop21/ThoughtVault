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
| Home | Seen with real existing notes and agenda | Pending candidate |
| Recording idle / inspector | Seen | Pending candidate |
| Tasks empty state | Seen | Pending candidate |
| Notulen list / detail | Seen | Pending candidate |
| People empty / add person | Seen; corrected form verified | Pending candidate |
| Settings, all seven tabs | Current native 263 reviewed | Pending candidate |
| Participants / saved recordings | Current native 263 reviewed, list expanded | Pending candidate |
| Regenerate / retranscription profile sheet | Collapsed Mac layout fixed and regenerate sheet natively verified | Pending candidate |
| Tags | Previous native reference reviewed | Pending candidate |
| Feedback modal | Account location confirmed; existing Mac button has no presented sheet | Pending candidate |

## Boundaries

Platform-specific capture/transcription engines remain genuine: Windows Whisper/Windows capture, macOS WhisperKit/Apple Speech/Apple permissions. No fake Apple Intelligence capability on Windows. The existing local Windows application does not gain a ThoughtVault login merely to copy an older Mac account screen.

No private notes, API keys or native screenshots are committed. This file is a review record, not a full signoff until the pending native candidate checks are complete. Real live meeting capture, provider connectivity and destructive actions require separate functional evidence.

The existing macOS feedback button only sets showBugReportSheet; no sheet is attached. No feedback was submitted. This functional gap is separate from the visual placement correction on Windows and remains open.
