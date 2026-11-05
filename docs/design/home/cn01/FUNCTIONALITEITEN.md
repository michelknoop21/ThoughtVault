# cn01 — Home: macOS appearance, existing Windows behavior

Visual authority: ../thoughtvault-home-northstar-approved.png and macos/Views/HomeView+{Studio,Card,Side,Panels}.swift, Components/HomeDecor.swift. Windows source: windows/src/pages/HomePage.tsx. No new account, agenda, favorites, plan or storage features inferred from the illustration.

| Existing field/action | Condition and expected result | Position in parity implementation |
|---|---|---|
| Search text + submit | All users; trim query, transcripts store searchQuery, navigate /transcripts | Fixed top search |
| Account/settings | Auth user /account; otherwise /settings | Top right existing button |
| Date, greeting, name/email fallback, quote | Local date/hour; first name/email, empty fallback | macOS 200px header, gradient name |
| New/current/paused recording | Recording phase; preserve mode while active; navigate /recording | Main orb and truthful state copy |
| Recording settings | All users, /settings | Settings control left of orb |
| Wave, ready status, idle timer | Decorative wave; timer only idle | Recorder controls |
| Microphone detection and error | getAudioDevices input detection, unknown on failure; never claim granted access | Permission panel beside only main width >=780 |
| Manage permission | open_microphone_settings; failure gives Windows manual instructions | Panel button and alert |
| Recent title, note/audio icon, date, preview | Same local+remote listing scope; sanitized existing preview | Bordered recent list |
| Alle/Opnames/Notulen filters | notule_html/has_notes; aria-pressed | Inline recent heading tabs |
| Open note | selectedId then /transcripts | Entire existing row button |
| Row menu + deletion confirmation | Existing local/remove or api/delete, error surfaced; cancel safe | Right row menu, existing dialog |
| Loading / error / retry / empty | Same loadRecentTranscripts; local does not require backend | Recent section variants |
| Empty first recording | microphone mode if idle, /recording | Empty section button |
| Today agenda / connect | Calendar connection; future first3; settings to connect | Side panel, below recorder at content<1180 |
| Meeting time/platform/subject/direct recording | Existing events; combined+autoStart if idle; navigate /recording | Existing agenda card/actions retained |
| Quick audio / conversation / import | Existing navigation/mode handlers | Quick capture panel |
| Background status/progress/retry/cancel | Existing shared ProcessingBar owns task state/actions | Single global bar; no duplicate Home panel |
| Brand message | Decorative; only wide columns | Right column bottom |

Responsive conditions are macOS HomeLayout: content >=1180 two columns; main >=780 permission beside; main >=820 tagline; compact side panels after recorder. Existing Windows native title bar/sidebar preserved. No production data is used in browser fixtures.
