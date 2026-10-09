# Windows density parity, 1.0.269 candidate

Reference: installed macOS 1.0.268 and current native source, notably MainSidebar,
HomeLayout, RecordingView StudioLayout and SettingsView. Measurements are logical
points / CSS pixels, never screenshot raster pixels. Native window caption controls
remain platform specific. Browser fixtures contain synthetic data and block capture
and provider traffic. They do not establish installed WebView or microphone behavior.

| Surface | Shared geometry |
| --- | --- |
| Navigation | 238 wide, 52 collapsed; 45 rows, 17 glyphs, 40 x 48 logo |
| Home | 51 search, 200 greeting, minimum 301 recording card, 89 record button |
| Recording | 309 inspector, 90 bottom bar; native short-height threshold 720 |
| Recording transport | 100 primary, 74 secondary; waveform bounded above transport |
| Settings | 40 tabs, adaptive 150 columns, 20 card padding; 342 side column at 1100 |
| Lists | Content centered with maximum width 860 |
| Tasks | Compact 52 toolbar and centered empty state |
| Person sheet | All six fields and actions visible at supported minimum size |

Regression checks: studioLayout.test.ts asserts native landmarks and waveform bounds
through the 720 height breakpoint. check-density.py measures sidebar, inspector,
bottom-bar dimensions/placement, waveform overlap, greeting and card minimum sizes.
An old sticky bar or 240 sidebar fails these checks. Home notes intentionally scroll
below the native greeting and recording card, rather than compressing both to bring
the first note above the fold.

Validation: frontend build and 78 tests; browser matrices for 56 route/window sizes,
36 density/DPR measurements, 21 settings tab sizes, 6 onboarding steps and 3 person
sheet sizes. Native installed candidate review is recorded separately after CI.
No saved recordings, notes, people or provider configuration are replaced.
