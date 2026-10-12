# cn01 parity check — macOS Home reconstruction

Status: reviewable with named gaps. Existing macOS source is visual authority; approved image is appearance reference, not evidence for new functionality.

| Catalog items | Source / condition | New position / trigger | Coverage / evidence |
|---|---|---|---|
| Search/account | HomePage toolbar, auth user | Same form submit and account button | Present; handlers unchanged. Native not tested |
| Date/greeting/name/quote | HomePage + macOS Studio header | 200px header, name gradient; empty fallback | Present; synthetic Michel and logged-out browser |
| Orb/settings/wave/status/timer | HomePage phase / handleQuickStart | Same accessible buttons/handlers, macOS sizes | Present; browser layout inspected, native pending |
| Mic / access / failure | getAudioDevices, invoke | Truthful Windows panel; beside >=780, below narrower | Present; mock input state, real permission action not tested |
| Recent fields/filter/open | SessionCard, has_notes, selectedId | Inline underlined tabs, same row action; date/time/minutes | Present; 12 synthetic notes; Opnames returns0 then Alle restores12 |
| Delete menu/confirmation/errors | Same SessionCard + DesktopDialog | Same reachable menu/dialog | Present in source; deletion not executed |
| Loading/error/retry/empty | loadRecentTranscripts unchanged | Recent section variants | Source preserved; filtered empty rendered; error/loading not tested |
| Agenda/connect/event/direct recording | calendar, same handlers | Right column >=1180, after recorder otherwise | Present in source; disconnected synthetic state rendered; live events not tested |
| Quick mic/conversation/import | Same handleQuickStart/navigation | Same three buttons | Present; browser reachable; native import not executed |
| Processing state/retry/cancel | Shared ProcessingBar | Single global task indicator, no duplicate card | Present; active38% synthetic fixture; real processing not affected |
| Brand text | Existing aside | Wide column only, per macOS | Present |

Measured browser viewports:1567x972,1200x830,1280x800,1440x900,1920x1080,640x600. All zero horizontal document overflow. Content>=1180: two columns with295px side; narrower side follows recorder. Card>=780: permission beside; narrow354px card: below. Landscape scales to.45 at narrow width. Scrolling belongs to compact body or wide main/right columns, as macOS source specifies, with scroll indicators suppressed; content remains scrollable, no actions hidden.

Visual critique/polish: removed independent compact layout; restored header200/orb89/record card301 minimum; gradient name, moon haze/glow, inline tabs; corrected nested-grid specificity after first render; permission icon now beside title. Card may grow above301 for truthful Windows permission text. Windows title bar/sidebar and platform permission copy intentionally preserved. No claim of pixel-perfect equality or native acceptance.

Validation:108 frontend tests pass (40 files), TypeScript/Vite build pass. Native package/installation, real authenticated/calendar gates, keyboard traversal of all lower actions and macOS live comparison pending. macOS app not launched or modified. No production audio/notes used.
