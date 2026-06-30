---
target: macOS app (SwiftUI)
total_score: 28
p0_count: 2
p1_count: 4
timestamp: 2026-06-07T13-05-57Z
slug: macos-views-macos-app
---
# Critique: TranscriptStudio — macOS app (SwiftUI)

Target: the macOS app surfaces (`macos/Views/*`, `macos/Extensions/Theme.swift`, `Color+Brand.swift`, `App/ContentView.swift`). Source-level design review; the deterministic markup detector does not apply to SwiftUI (scanned `macos/Views`, returned empty).

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Excellent ProcessingView checklist + widget states; profile-load false-error timer, tag-error surfaces in wrong place |
| 2 | Match System / Real World | 3 | Plain verb-first Dutch, native idioms; "Systeeminstell." abbreviation |
| 3 | User Control and Freedom | 3 | Cancel confirmation, optimistic edits w/ rollback; NotuleResult is read-only, no tag delete there |
| 4 | Consistency and Standards | 2 | Two-Voice color contract broken on selection states; flat-vs-glass surface drift; tokens bypassed |
| 5 | Error Prevention | 3 | Cancel guard, disabled-until-valid login, stalled detection |
| 6 | Recognition Rather Than Recall | 3 | Good labels/auto-tab; duplicate sparkles icons, fake DOCX, unbounded tag chips |
| 7 | Flexibility and Efficiency | 3 | ⌘1-6 / ⌘R / ⇧⌘S, biometrics, AI title-gen; no bulk list actions |
| 8 | Aesthetic and Minimalist Design | 3 | Clean, one-job-per-screen; 3 competing action colors in notule bar, blobs wasted under opaque cards |
| 9 | Error Recovery | 3 | Retry-via-cloud, "Opnieuw", rollback; widget error truncated + no recovery |
| 10 | Help and Documentation | 2 | Per-section settings footers, tooltips; no in-app help/search, some empty states don't teach |
| **Total** | | **28/40** | **Good (lower band)** |

## Anti-Patterns Verdict

**LLM assessment:** This does **not** read as AI-generated. It is a coherent, genuinely branded native macOS app with a real token system (`TS.Spacing/Radius/Font`), platform-correct idioms (`NavigationSplitView`, grouped `Form`, `.confirmationDialog`, `@Observable`), and thoughtful state handling. The slop tells that exist are internal, not visual: a fake DOCX button that always errors (`NotuleResultView.swift:497-504`), a no-op 350ms search debounce that does nothing (`TranscriptsView.swift:212-218`), an orphaned `circularProgressRing` (`ProcessingView.swift:283-323`) and `showTitleEditAlert` path, and duplicate `sparkles` icons for two different actions. Against the *product* slop test (would a Linear/Raycast-fluent user trust this): mostly yes — but the magenta-everywhere selection states and the flat-vs-glass inconsistency would make a discerning user pause.

**Deterministic scan:** Not applicable — the bundled detector targets HTML/JSX markup; SwiftUI views returned no findings. No visual browser overlay available for a native macOS target.

## Overall Impression

A warm, confident, well-structured app that mostly lives up to "the Yinga Studio." The biggest opportunity is **internal consistency against its own written contract**: DESIGN.md declares two named laws — the Two-Voice color rule (magenta acts, blue navigates) and glass-default surfaces — and the macOS code breaks both in visible, systemic ways. Fixing those is what separates "looks nice" from "feels like one deliberate product on both platforms."

## What's Working

1. **State visibility is a real strength.** `ProcessingView` shows a 4-step pipeline checklist with per-step pending/active/done states and a 120s stalled-detection escape hatch (`ProcessingView.swift:172-216, 130-155`); the floating widget maps every state to a distinct indicator + live upload % (`RecordingWidgetView.swift:146-200`). This is honest feedback, not a generic spinner.
2. **Power-user efficiency.** ⌘1-6 tab switching, ⌘R quick-record, ⇧⌘S sidebar toggle (`ContentView.swift:533-557`), biometric login, AI title generation, optimistic edits with rollback (`TranscriptsView.swift:1727-1742`).
3. **Destructive-action discipline.** Recording cancel is gated by a confirmation with a non-destructive default (`RecordingView.swift:889-900`); login disabled until valid; 2FA auto-submits at 6 digits.

## Priority Issues

### [P0] The Two-Voice color contract is broken on selection states across the app
- **Why it matters:** DESIGN.md names this a law: magenta `#E50074` = actions/recording; blue `#007BC4` = navigation/selection/focus. The macOS app fills the **selected sidebar item** (`ContentView.swift:353, 595-599`), the **active date-filter pill** (`TranscriptsView.swift:306`), and the **active detail tab/segment** (`TranscriptsView.swift:1132`) with magenta. So the app's primary navigation and selection states all signal "action." This contradicts the documented system, breaks parity with the Windows app (which uses blue per DESIGN.md), and trains the user that magenta means two different things. Note the tag-filter chips one function over correctly use blue (`TranscriptsView.swift:353/361`) — so two pill rows on one screen already disagree.
- **Fix:** Swap selection fills to `Color.brandSecondary` (blue): `ContentView.swift:353` and the `SidebarNavItem` fill at `595` (+ hover tint `584/587/596`), `TranscriptsView.swift:306`, `TranscriptsView.swift:1132`. Also move magenta off non-action labels/badges: role badge `SettingsView.swift:1104-1105`, detail `profileName` `TranscriptsView.swift:1499`.
- **Suggested command:** `/impeccable colorize`

### [P0] No `prefers-reduced-motion` fallback anywhere (violates the project's stated WCAG 2.1 AA bar)
- **Why it matters:** PRODUCT.md commits to "`prefers-reduced-motion` honoured on every animation." It is honoured on none. The gap is systemic at the source: `PulsingRecordingDot` (`Theme.swift:564-585`) and all `TS.Animation` presets (`Theme.swift:170-181`) have no reduce-motion handling. Continuous `repeatForever` loops fire regardless: the recording dot (`RecordingView.swift:907,1056`), mic concentric rings (`RecordingView.swift:183-190`), 60fps waveform (`WaveformView.swift:53`), processing shimmer (`ProcessingView.swift:383-388`), and the transcripts refresh spinner (`TranscriptsView.swift:675-679`). This is a documented vestibular trigger and a WCAG 2.3.3 failure on the most motion-heavy screens.
- **Fix:** Add `@Environment(\.accessibilityReduceMotion)` once at the source: make `PulsingRecordingDot` render static when set; gate the waveform `TimelineView`/level to a flat line; drop the mic-ring pulse and shimmer; bypass `repeatForever`. A single helper modifier reused everywhere is cleanest.
- **Suggested command:** `/impeccable harden`

### [P1] The signature glass surface system is abandoned on most screens
- **Why it matters:** DESIGN.md's "Glass-Default Rule" makes translucent material the default plane; HomeView even paints decorative background blobs (`HomeView.swift:88-120`) designed to show *through* glass. But most cards are flat opaque `Color.surfacePrimary`: HomeView overview stats + recent list (`HomeView.swift:304-311, 453-460`), the recording-screen cards (`RecordingView.swift:217, 403, 970, 1020, 1075`), and the entire NotuleResultView (`62, 66, 147, 173, 263, 285`). Meanwhile the floating widget *does* use `.ultraThinMaterial` — so the premium material reads only on the one surface most users see least. The blobs are wasted because nothing translucent sits over them.
- **Fix:** Route card backgrounds through the existing `.modernCard()` / `.glassEffect` path instead of `.fill(Color.surfacePrimary)`. The modifier already exists in `Theme.swift:188-228`; this is mostly a find-and-replace plus removing the manual stroke/shadow duplicates.
- **Suggested command:** `/impeccable polish`

### [P1] The payoff screen (NotuleResultView) is read-only, emotionally flat, and ships a fake button
- **Why it matters:** This is the peak of the emotional journey (peak-end rule). Three problems: (a) it's read-only — editing only exists later in the Transcripts detail (`TranscriptsView` `saveNotuleEdits`), so a user who just finished processing must navigate away to fix a word; (b) the arrival is undramatic — `ProcessingView` builds real momentum then hard-swaps into a plain toolbar with a small "Notulen klaar" (`NotuleResultView.swift:95`), no success flourish, no "klaar in 2m14s" stat; (c) the Exporteer menu offers "DOCX" which always fails with "nog niet beschikbaar" (`NotuleResultView.swift:497-504`) — a trust-eroding fake action on the trust-and-share screen. Plus the default-styling HTML branch has no `max-width`, so prose runs edge-to-edge on a wide window (`NotuleResultView.swift:677-684, 774-781`), breaking the 65-75ch rule.
- **Fix:** Add an inline edit affordance (or a clear "Bewerk in detail" route); add a brief success transition + a meta stat; remove or disable-with-badge the DOCX item; add `max-width: 820px; margin: 0 auto;` to the default-branch body CSS.
- **Suggested command:** `/impeccable delight` (celebration) + `/impeccable clarify` (fake button / edit affordance)

### [P1] Loading uses bare spinners and several empty states don't teach
- **Why it matters:** The product register and DESIGN.md call for skeletons over spinners and empty states that teach. TranscriptsView list/detail loading is a centered `ProgressView("Laden...")` (`TranscriptsView.swift:384-388, 1002-1012`); the truly-empty transcripts state (`TranscriptsView.swift:557-573`) shows an icon + "Geen transcripties" with no CTA to start recording; NotuleResultView "Geen … beschikbaar" states offer no next step.
- **Fix:** Replace list loaders with 3-4 skeleton `TranscriptListCard` placeholders; add a "Start een opname" CTA to the empty-library state; give the absent-notule states a regenerate/retry route.
- **Suggested command:** `/impeccable onboard`

### [P2] Token system bypassed; sub-44px hit targets; missing VoiceOver labels
- **Why it matters:** Hundreds of raw `.font(.system(size:))` / hardcoded paddings/radii bypass `TS.Font/Spacing/Radius` (e.g. the 56px timer `RecordingView.swift:929`, widget layout throughout, detail title `TranscriptsView.swift:1419` which also misses `design: .rounded`). Icon-only controls fall below the 44px target (widget buttons 32×32 `RecordingWidgetView.swift:257`, card ellipsis menu `TranscriptsView.swift:897`, password eye 24×24 `LoginView.swift:167`) and several rely on `.help()` tooltips, which VoiceOver does not announce (`SettingsView.swift:579-588, 615-621`, `RecordingView.swift:769-776`).
- **Fix:** Add a `TS.Font.timerDisplay` token + sweep raw values onto the grid; expand hit areas to 44px via padding/`contentShape`; add `.accessibilityLabel` to every icon-only button (mirror the good examples already in TranscriptsView: `228, 681, 691, 903`).
- **Suggested command:** `/impeccable audit`

## Persona Red Flags

**Alex (Power User):** Strong — ⌘1-6, ⌘R, ⇧⌘S, biometrics, AI title-gen. Gap: no bulk/batch actions in the transcripts list (select-multiple, batch delete/export); the no-op debounce adds a Task per keystroke for nothing.

**Sam (Accessibility-Dependent):** This is where the app fails its own bar. Zero reduce-motion fallbacks (P0); icon-only buttons below 44px and labelled only via `.help()` tooltips VoiceOver won't read; the decorative waveform `Canvas` has no `.accessibilityHidden(true)`; ProcessingView forces `.preferredColorScheme(.dark)` (`ProcessingView.swift:167`), overriding light/high-contrast preference; WebView prose is fixed 14px with no Dynamic Type.

**Marleen (Dutch MKB professional, accountable for the notes, not a power user — project persona):** Finishes a meeting, lands on the result, spots one wrong name — and can't edit it there (must hunt to the Transcripts tab). Clicks "DOCX" to send to a colleague and it silently fails. The notule reads fine but stretches the full width of her large monitor, tiring to scan. The core promise ("send with only minor edits") has friction exactly at the finish line.

## Minor Observations

- Sidebar uses hardcoded sizes/paddings instead of tokens (`ContentView.swift:262-321`).
- LoginView forces light mode (`LoginView.swift:69`) — deliberate, but overrides user dark preference; background gradient is hardcoded hex (`30-36`).
- SettingsView has 6 tabs; rule of thumb is ≤5 — "Geavanceerd" (only Permissies) could fold into Account/Algemeen.
- Brand magenta hex is duplicated across three CSS string blocks in NotuleResultView (`545-565, 656-675, 753-772`) — drift risk vs `Color+Brand.swift`.
- Widget error label truncated to 12 chars with no recovery (`RecordingWidgetView.swift:198`); main-view error banner does have retry.
- Duplicate `sparkles` icon for both "Regenereer" and "Titel" (`TranscriptsView.swift:1315, 1343`).

## Questions to Consider

- DESIGN.md says navigation is blue — was the macOS shift to magenta selection states a deliberate redesign (then DESIGN.md + Windows should follow), or drift (then macOS should follow)? Pick one source of truth.
- If editing lives in the Transcripts detail, does NotuleResultView need to exist as a separate read-only screen at all — or should processing land directly in the editable detail?
- What would a confident "klaar!" moment look like — enough to make Marleen trust the result at a glance?
