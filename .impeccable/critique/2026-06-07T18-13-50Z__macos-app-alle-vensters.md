---
target: macos app alle vensters
total_score: 33
p0_count: 2
p1_count: 7
timestamp: 2026-06-07T18-13-50Z
slug: macos-app-alle-vensters
---
# TranscriptStudio macOS — Critique van alle vensters

Native SwiftUI app, beoordeeld tegen Apple macOS HIG + de eigen design-intentie (PRODUCT.md/DESIGN.md). Drie geïsoleerde assessments: twee design-director reviews (kern-workflow + periferie/shell) en één mechanische token/HIG/a11y-scan. De web-detector/browser-helft van /impeccable is niet van toepassing (geen HTML/CSS).

## Design Health per venster

| Venster | Score | Verdict |
|---|---|---|
| PeopleDirectory | 39/40 | Referentie. Native, eerlijk, alle states |
| SeedReviewSheet | 39/40 | Tekstboek one-job confirm sheet |
| Tasks | 38/40 | Schoonste HIG-fit |
| PermissionBanner | 38/40 | Progressive disclosure goed gedaan |
| Recording | 36/40 | Sterkste hoofdscherm; live-reassurance top |
| Transcripts | 36/40 | Echte native list; te veel filter-chrome |
| Settings | 37/40 | System-Settings-stijl, rustig, native |
| Account / ProfileSettings | 37/40 | Production-grade 2FA; GDPR-export is stub |
| CallAlert | 37/40 | Sterke actie-hiërarchie; top-stripe slop-tell |
| FloatingWidget | 35/40 | Premium native HUD; verbergt zich bij error |
| PersonEdit | 35/40 | Geen Cancel; laat naamloze personen toe |
| Login | 34/40 | Schoon; "Lokaal" zonder terugweg, geen wachtwoord-reset |
| Processing | 32/40 | Forced dark mode, geen exit tijdens verwerken |
| NotuleResult | 32/40 | Branded HTML goed; twee export-systemen |
| Onboarding | 31/40 | 7 animerende gradients, wizard in TabView |
| Profiles | 31/40 | Edit = delete+recreate (dataverlies); dode error-state |
| Home | 28/40 | 3 concurrerende start-knoppen, lege stat-cards |
| Admin | 26/40 | "Cluttered enterprise tool" letterlijk; hand-rolled table |

**App-breed gemiddelde: ~33/40 — "Good" band.** Geen broken UX; de basis is een goed gebouwde native app. De winst zit in consistentie, een paar slop-eilanden, en mechanische schuld.

## AI-slop verdict

Niet breed slop — er is echte brand-craft (WaveformView/SCSiriWaveform, de mic-knop met concentrische ringen, de notule-HTML CSS, completion-checkmark spring). Maar er zijn duidelijke slop-eilanden:
- **Admin** = generiek admin-dashboard: identieke stat-card grid, badges overal, side-stripe severity-accent, uppercase tracked table-headers, hero-metrics. Alleen branded via accentkleur.
- **Onboarding** = 7 animerende multi-stop gradient-achtergronden + herhaalde hero-icon-in-tinted-circle → richting "consumer-cute" anti-referentie.
- **Home** = zero-value hero-metric stat-grid (toont "0 / 0 / 0" op dag één).
- **Pervasieve tell:** tiny uppercase getrackte eyebrow-labels boven secties ("NIEUWE OPNAME", "LIVE TRANSCRIPTIE", "VOORTGANG", "YOUTUBE VIDEO") in Home/Recording/Processing/Profiles.

## Top systemische problemen (over vensters heen)

### P0
1. **Localisatie compleet omzeild — 318 hardcoded `Text("…")`, 0 localization-calls.** `Localizable.strings` (nl+en) bestaat en is gevuld, maar wordt nergens aangeroepen; de `en.lproj` is dode code. Schendt expliciete CLAUDE.md-regel. Grootste mechanische schuld.
2. **ProcessingView: geen exit tijdens normale verwerking.** Full-screen geforceerde wachttijd zonder cancel/achtergrond tot error of 2-min stall. Blokkeert de gebruiker op een lang bestand.

### P1
3. **Hand-rolled controls waar native bestaat.** Admin herbouwt een tab-bar (matchedGeometryEffect) én een data-table (vaste kolommen + handmatige paginatie) die SwiftUI `Table`/`Picker` gratis geven — verliest sorteren/selectie/keyboard/VoiceOver. 4 losse segmented-tab-bars (Admin×2, NotuleResult, Transcripts) die één component moeten zijn.
4. **Dubbele componenten / uiteenlopende capaciteit voor identieke content.** Twee transcript-cards (`TranscriptCard` met hardcoded "Voltooid"-badge vs `TranscriptListCard`), twee export-menu's (Result PDF/TXT vs Detail PDF/MD/TXT/Copy), drie start-affordances op Home.
5. **Dode/ongetoonde error-state.** Profiles zet `errorMessage` bij elke fout en rendert die nergens; Account routeert naam-fouten naar de GDPR-sectie; widget verbergt zich bij `.error`. Patroon: error toewijzen → nooit tonen.
6. **Destructieve/lossy ops zonder vangnet.** Profiles edit = delete-dan-recreate → profiel weg bij netwerkfout tussenin. PersonEdit slaat naamloze personen op en heeft geen Cancel.
7. **Reduced-motion in 22 van 27 files genegeerd.** Correct patroon bestaat in 5 files; 57 animatie-sites, slechts ~12 gated op `accessibilityReduceMotion`.
8. **35 van 56 icon-only buttons zonder `.accessibilityLabel`** — VoiceOver leest rauwe SF-Symbol-namen of niets.
9. **137 hardcoded font-sizes (83 buiten de schaal), 24 verschillende waarden.** Volledig gebouwde `TS.Font`-schaal grotendeels omzeild; geen echte type-schaal meer. Brand-drift: belangrijkste document-titel niet `.rounded`.

### P2
10. **ProcessingView verlaat het design-systeem** — forced dark mode + bespoke dark-SaaS gradient + neon-blue, breekt glass-on-soft-gray en de licht→donker→licht peak-end-boog.
11. **Home: concurrerende start-CTA's + lege stat-grid** (verberg bij 0).
12. **Settings "Verwerking"-tab** overschrijdt cognitief budget in local mode (5 secties + ~10-control Ollama-blok).
13. **Color-only meaning** — PeopleDirectory intern/extern is een kleur-only dot, óók verborgen voor VoiceOver.
14. **Dark-mode-fragiele kleuren** — 11 `.black.opacity` shadows (onzichtbaar op donker), 2 light-only `Color(red:)` gradients, 7 inline RGB die `Color+Brand` omzeilen.
15. **`labelTertiary` (#999 licht) voor betekenisvolle body/label-tekst** (Home-stats, card-datums) — terugkerend WCAG-AA contrastrisico.
16. **Sub-44pt icon-only close-buttons** op banners (Recording/Transcripts/Tasks).
17. **~145 spacing/frame-literals + 10 radius-literals** buiten de tokenschaal (icon-frames 32/28/24 als de-facto naamloze schaal).

## Wat werkt (behouden + als interne referentie gebruiken)
- Empty states zijn consistent uitstekend: specifieke copy + één verb-first CTA, en ze onderscheiden "nog niets" van "geen resultaten".
- Eerlijke error-feedback met inline "Opnieuw"-recovery op elke async-surface; destructieve acties altijd bevestigd op naam.
- Local-first dataladen met nette server-failure-degradatie, consistent toegepast.
- Echte brand-craft waar het telt: WaveformView, mic-knop, notule-HTML, completion-spring, de floating recording-HUD (NSPanel + observation-tracking) = premium native werk.
- **Gezondste schermen als referentie:** PeopleDirectory, SeedReviewSheet, PermissionBanner, Settings — native, eerlijk, volledig-gestate, nul slop. **Zwakste = Admin** (hoogste ROI).

## Persona-red-flags
- **Alex (power user):** geen spacebar-pauze tijdens opname; ⌘-toetsnummering is kapot (settings=5, people=6, admin=8, 7 ontbreekt); hand-rolled Admin-table zonder keyboard-traversal.
- **Sam (a11y):** 35 ongelabelde icon-buttons; reduced-motion grotendeels genegeerd; intern/extern alleen via kleur + verborgen voor VoiceOver.
- **Jordan (first-timer):** Onboarding-wizard in een TabView laat stappen overslaan/door-swipen; profiel-stap toont 6 velden tegelijk; Home's drie start-knoppen verwarren "waar begin ik".
- **Riley (stress-tester):** Profiles edit kan een profiel verliezen; PersonEdit maakt "Naamloos"; widget verbergt errors.
