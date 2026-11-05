# Windows density parity, 1.0.269 candidate

Reference: installed macOS 1.0.268 and current native source, notably MainSidebar,
HomeLayout, RecordingView StudioLayout and SettingsView. Measurements are logical
points / CSS pixels, never screenshot raster pixels. Native window caption controls
remain platform specific. Browser fixtures contain synthetic data and block capture
and provider traffic. They do not establish installed WebView or microphone behavior.

| Surface | Shared geometry |
| --- | --- |
| Navigation | 238 wide, 52 collapsed; 45 rows, 17 glyphs, 40 x 48 logo |
| Home | Fixed 51 search, independent wide column scroll, 200 greeting, minimum 301 recording card, 89 record button |
| Recording | 309 inspector, 90 bottom bar; native short-height threshold 720 |
| Recording transport | 100 primary, 74 secondary; waveform bounded above transport |
| Settings | 40 tabs, adaptive 150 columns, 20 card padding; 342 side column at 1100 |
| Lists | Content centered with maximum width 860 |
| Tasks | Compact 52 toolbar and centered empty state |
| Floating widget | 470 x 60; 120 x 32 waveform, 15 timer, 32 pause button; scaled monitor origin in logical coordinates |
| Person sheet | All six fields and actions visible at supported minimum size |

Regression checks: studioLayout.test.ts asserts native landmarks and waveform bounds
through the 720 height breakpoint. check-density.py measures sidebar, inspector,
bottom-bar dimensions/placement, waveform overlap, greeting and card minimum sizes.
An old sticky bar or 240 sidebar fails these checks. Home notes intentionally scroll
below the native greeting and recording card, rather than compressing both to bring
the first note above the fold.

Validation: frontend build and 79 tests; browser matrices for 56 route/window sizes,
36 density/DPR measurements, 21 settings tab sizes, 6 onboarding steps and 3 person
sheet sizes. Native installed candidate review is recorded separately after CI.
No saved recordings, notes, people or provider configuration are replaced.

Negative control: injecting the former 208px sidebar and sticky bottom control bar
makes the measured parity checks reject both. The restored measurements pass again
after removing those rules. macOS was recording during the final candidate work,
so it was left running and not updated or navigated after detecting active capture.

## Built artifact and installed review

Windows CI run [37906510311](https://github.com/michelknoop21/ThoughtVault/actions/runs/37906510311)
passed for source e2500e631d531a85a08b0d51a7632f1ebaa8767a, version 1.0.269.
This includes native verification, MSI packaging, self-contained C++ runtime,
installation/upgrade, two starts and preservation of saved notes on the CI host.
Publication was disabled. MSI SHA256:
`8468f79244a76cbd6f2a5d858ffa2f4c016172b213592e272b8bb196d841456e`.

The Royal TSX Dalf38 VPN review resumed on 2026-10-09 after the capture failure.
The existing 1.0.268 installation was upgraded to 1.0.269 with installer exit 0.
The executable and Settings > General both reported 1.0.269. Existing notes were
backed up locally without reading their contents; SHA256 stayed identical after
installation, navigation, normal exit and the second start. The second process
reported Responding: True. No capture or provider request was initiated.

Native coverage at a 1200 x 800 client area: Home, idle recording, Tasks, Notulen
list and existing detail, People, and all seven settings tabs. Longer Processing
and Notulen settings were scrolled to inspect their bottom actions. The six-field
Person sheet fitted without scrolling and was cancelled without saving. The Yinga
footer credit remained compact. At 880 x 600, recording and Home were also viewed
with the sidebar collapsed; the Person sheet still fitted with all fields/actions.
The maximized People screen and expanded/collapsed sidebar were reviewed too.

This is visual acceptance for the inspected states against the macOS geometry
reference, not a blanket pixel-perfect signoff. Narrow native recording selects
ellipsize their selected values, while the inspector retains the full source and
profile labels. macOS was left untouched because an earlier observation found
active capture. Active recording, native floating widget, provider calls and every
possible modal state remain outside this installed review. The floating widget
was checked in the fixture and geometry tests, not during a native recording.
