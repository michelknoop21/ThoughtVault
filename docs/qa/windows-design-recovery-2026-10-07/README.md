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
