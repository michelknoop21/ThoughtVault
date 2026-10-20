# Windows visual review through Royal TSX

Date: 2026-10-08. Observed installed ThoughtVault: 1.0.262, confirmed in General settings.
Environment: existing Dalf38 VPN connection in Royal TSX, Windows 11 Pro Education. This is a different machine from the Parallels VM. Review used actual clicks in the installed Windows app, not the desktop-review browser fixture.

## Observed coverage

| Surface | Observation |
| --- | --- |
| Home | Regular window and small window; recording controls, recent note, agenda and quick actions visible; content scrolls |
| Recording | Regular and small window, idle state; inspector moves below workspace at small width; start control and source/profile selectors remain reachable |
| Tasks | Regular and small window; empty state only |
| Documents | Regular and small window; populated list, filters, note detail, back navigation and action toolbar |
| People | Regular and small window; empty state and add-person form; form closed without saving |
| General settings | Regular and small window; update switch and installed version |
| Processing settings | Regular and small window; recommendation, transcript model, provider fields and lower privacy sections reached by scrolling |
| Notes settings | Regular and small window; template selection and expanded profile management in regular window |
| Calendar settings | Regular and small window; connected account state, no connection changed |
| Obsidian settings | Regular and small window; fields visible, no export or settings changes submitted |
| Account settings | Regular and small window; upper form inspected |
| Advanced settings | Regular and small window; server field and buttons inspected |
| Recording participants | Empty directory dialog opened and closed |
| Saved recordings | Populated dialog opened and closed; no recording removed or processed |
| Note tags | Empty tag dialog opened and closed; no tag added |
| Regenerate note | Template dialog opened and cancelled; no processing started |

Windows native system menu was used to reduce window size. Screen raster was approximately 1204 x 832 initially and 652 x 632 after resizing; these include native window borders and caption, not measured CSS viewport dimensions. Native keyboard resizing worked. Dragging the window border did not visibly resize it in this session.

## Findings

1. Recording transport icons were left aligned within round buttons in installed 1.0.262, visible at both sizes. The shared `.studio-round` rule did not center its contents. Local source now uses inline-flex with centered alignment and zero padding for start, pause/resume, stop and quick note. This change is not yet installed on the remote PC.
2. Floating feedback button overlaps the right edge of some settings fields at small size. Scrolling can expose the field, but this remains an unresolved visual issue.
3. Recording studio can leave substantial unused space in very large windows. No new layout change made on the basis of this inspection alone.

## Limits

This is a visual inspection of the states listed above, not a full macOS parity sign-off. Live recording, pause/resume, floating recording widget, waveform calibration with sound, active/error tasks, populated people and editing, full onboarding, all profile editor dialogs, OS file selectors, destructive confirmations and backend/Obsidian operations remain unverified in this native review. No private desktop screenshots or user note contents were added to the repository. Screenshots were viewed in the computer-use tool only.

User preference: continue real Windows visual QA through Royal TSX. Parallels and Coherence observation worked, but injected clicks did not visibly navigate there in the preceding attempts; Royal TSX clicks did.

Additional observation: native maximize was tested through the caption button. Processing settings then showed the actual CPU/RAM panel and recommendation in the right column, with all main fields visible in the large remote desktop. Sidebar Settings and Yinga footer remained at the bottom. The local CSS correction passed TypeScript/Vite production build and `git diff --check`. No MSI build, installation, push or release was performed for this correction.
