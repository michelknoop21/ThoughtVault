# Density audit

**Verdict:** the oversized footer branding and narrow/short Home density defect
are fixed. Six main surfaces pass the measured layout contracts across 36
viewport/scale combinations. This is browser-fixture evidence, not an interactive
Parallels sign-off.

| Surface | Archetype / scroll owner | Coverage and result |
| --- | --- | --- |
| Home | Page; independent recent sidebar | 8 synthetic notes; primary action and first complete note visible at every measured size |
| Recording | Workbench; studio when stacked | Idle state; transport reachable; one purposeful studio scroll on small windows |
| Notes | Master/detail; list and detail | 8 synthetic notes; list context visible; detail checks in the existing responsiveness audit |
| People | Directory; page | One synthetic person; sparse-data coverage limit |
| Settings | Form; page | Processing density matrix plus 7 materially different tabs in check-settings.py; primary setup action visible; remaining fields intentionally scroll |
| Tasks | Processing overview; page | Empty state only; populated queue density untested |
| Onboarding | Scrollable setup | All six steps checked for clipped controls at 640x560 |
| Profile / person / participant / note dialogs | Modal content | Existing narrow-window checks retained; not all loading/error variants rerun in this density pass |
| Native OS dialogs / floating recorder / Parallels | Native windows | Untested interactively in this pass |

## Dimensions and evidence

Measured CSS viewports: 640x560, 900x560, 1280x800, 1440x900, 1920x1080
at DPR 1, plus 1440x900 at DPR 2 (2880x1800 raster). Browser zoom and text scale
are 100%; body text remains 14px. Browser safe-area insets are zero. The smallest
fixture reserves space from the app's 640x600 native minimum for the Windows
caption. Real Windows display scale, caption dimensions and input routing are
not established by this fixture.

`density-measurements.json` records each surface's logical/raster size, DPR,
zoom, heading and first-data rectangles, scrolling viewport/content extents,
fixed control height and screenshot path. Four representative screenshots are
stored beside this report; the rest are local audit captures under /tmp.

At 1920x1080, recording controls occupy 91.5px (8.5% of working height), below
the desktop review signal of 20%. Settings tabs are 42px and scroll with the
form; they are not fixed workspace chrome. Wide layouts at equal logical size
retain identical logo/content geometry at DPR 1 and 2.

## Fixes and regressions

The credit logo was 72x31px beside an 11px label with a 14.3px text line. It is
now 42x18px, preserving the original transparent vector artwork and proportions.
The regression failed before the fix: `Footer logo dominates credit: 31px`.

At 640x560, the first Home note started at y=580.7 and was entirely below the
viewport. It now spans y=485.7..553.7 and is fully visible. The regression fails
unless the entire first row fits. Narrow recording-card controls move below the
copy instead of squeezing it into a narrow column. In short, narrow windows,
the decorative quote and redundant recording label yield their space to content.
Useful descriptions, permission details and actions remain available. Larger
and taller layouts preserve those decorations.

Settings use smaller vertical card padding, 32px card icons, 16px card headings,
and more compact summaries. The horizontal field/action alignment is preserved.
No browser zoom, global scaling, hidden overflow or reduced body/control text
was used to pass the audit.

The expected page scrolls in Home and Settings are intentional. The stacked
recording inspector belongs to the same studio scroll; it does not create an
unrelated page scrollbar. Keyboard focus, Escape and dialog restoration were
checked in the existing responsiveness pass. Full native keyboard/hardware/audio
workflows remain unverified. Console/provider errors from blocked fixture calls
are separate from layout evidence; this audit does not prove service connectivity.
