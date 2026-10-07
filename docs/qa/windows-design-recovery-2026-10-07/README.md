# Windows desktop design recovery, 2026-10-07

Reference: current macOS MainSidebar.swift, RecordingView+Studio.swift,
RecordingView+Inspector.swift, HomeView, TranscriptsView, ProfilesView,
PeopleDirectoryView and TasksView. Existing approved Windows NorthStar CSS reused.

| Screen | Change | Evidence |
| --- | --- | --- |
| Navigation | Mac geometry, collapse, recent local notes, new vault artwork | All captures; recent navigation test |
| Home | Existing restored composition, visible settings icon | home captures |
| Recording | Workspace, timer, waveform, bottom source/profile bar, fixed inspector, phase-correct transport | recording captures; idle/live/paused regression |
| Notes | Centered 860px card list; full detail after selection; sort/date/tag filters, menu and bulk actions kept | transcripts captures; detail capture |
| Tasks | Shared card and status surfaces; existing retry/actions retained | tasks captures; existing local retry test |
| Profiles | Full-width cards and section headers; create/edit/default actions retained | profiles captures |
| People | Aligned searchable directory rows, keyboard edit, delete confirmation retained | people captures |
| Settings | Six approved tabs, processing side panels, current local/cloud providers retained | settings captures |

All seven routes checked at 1024x768 and 1440x900 without document horizontal overflow.
Screenshots render actual React components in a temporary browser harness.
Content prefixed Voorbeeld is review sample data, not user data.
Native recording, credentials, Windows hardware detection and provider requests cannot
be proved by this browser harness. MSI installation/launch/data preservation is a
separate Windows CI check. The attempted current Mac UI capture timed out; Mac layout
comparison uses the current SwiftUI source and existing approved visual references.
No claim of pixel-identical native rendering or real-device audio verification.

Validation: frontend production build and all 51 Vitest tests passed.
Keyboard regression covers note activation versus the nested More options button.

## Published Windows verification

- Version: 1.0.259. Application source: a93ee6ce270bf3abb24c475072cd58f7c8464d7f.
- GitHub Actions run: https://github.com/michelknoop21/ThoughtVault/actions/runs/37650954043, success.
- Windows: 51 frontend tests, 19 Rust tests, release MSI build passed.
- MSI upgrade, renamed executable, two app starts and saved-note preservation passed.
- Live updater and private download listing report Windows 1.0.259.
- Live installer returned HTTP 200 with noindex, nofollow, noarchive, nosnippet.
- Downloaded live MSI equals retained CI artifact, SHA256:
  3f853b665ff39d4075a00650a32dd04ee64aebca341b4cfe934775f661c1ea15.
- Live updater signature equals retained CI signature.
- This confirms build, installation and publication; it does not establish real-device recording or cloud-provider operation.
