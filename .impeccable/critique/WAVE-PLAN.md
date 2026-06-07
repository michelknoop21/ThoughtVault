# TranscriptStudio macOS — Critique remediation wave plan

Bron: `/impeccable critique` op alle vensters (snapshot `2026-06-07T18-13-50Z__macos-app-alle-vensters.md`, app-breed 33/40).
Gebruiker koos: alle 4 clusters, localisatie volledig migreren, scope = alles incl. P2-polish (meerdere sessies).
Sequencing-principe: structuur/dedup/slop/safety EERST (verandert/verwijdert copy), localisatie-sweep ALS LAATSTE zodat definitieve strings gemigreerd worden.

Build-commando (signed, vast pad): `xcodebuild -project TranscriptStudio.xcodeproj -scheme TranscriptStudio -configuration Debug -allowProvisioningUpdates build`

## Wave 1 — Safety & duidelijke bugs ✅ DONE (build-verified)
- [x] Home: lege 0/0/0 stat-grid verbergen + `labelTertiary`→`labelSecondary` (HomeView.swift overviewSection)
- [x] Profiles: `errorMessage` in alert; edit = create-first/delete-on-success `replaceProfile()` (ProfilesView.swift)
- [x] PersonEdit: NavigationStack + Annuleer-toolbar; save `.disabled(!canSave)` op lege naam (PersonEditView.swift)
- [x] ⌘-toetsnummering sequentieel people=5/settings=6/admin=7 (ContentView.swift AppTab.keyboardShortcut)
- [x] Processing: persistente "Verder op achtergrond"-exit overlay (ProcessingView.swift processingContent)

## Wave 2 — Dedup / consistentie  ✅ DONE (commit 601c11f)
- [x] Home: 3 start-affordances → 1 primaire ctaCard (pills deden allemaal hetzelfde)
- [x] `ExportMenu` parity: "Kopieer tekst" toegevoegd aan NotuleResultView
- [~] **TranscriptCard.swift = dode code** (0 refs, hardcoded "Voltooid"-badge). 4 pbxproj-refs → BENOEMD, **handmatig in Xcode verwijderen** (niet auto i.v.m. pbxproj-corruptie-risk).
- [SKIP] Gedeelde `SegmentedTabBar`: 4 visueel verschillende patronen = over-abstractie (Karpathy). Admin-tabbar wordt in Wave 3 native (Picker).
- [DEFER] Markdown-parity in NotuleResult: vergt gedeeld `NotuleExporter`-bestand → nieuw .swift = pbxproj-edit, doen via Xcode (Wave 7).

## Wave 3 — Admin native rebuild  ✅ DONE (commit 8c40511)
- [x] Main tab-bar + log sub-tab → native segmented `Picker` (keyboard + VoiceOver)
- [x] Stat-card number: off-scale .system(36) → `TS.Font.titleBold`
- [x] Log table header: uppercase weg → sentence case
- [x] Feedback archive/restore: errors tonen (was `try?`-swallow). Primaire status-knop deed dit al.
- [x] `activityLabel`: onbekende action_types humaniseren (geen snake_case-lek)
- [SKIP] log-table → SwiftUI `Table`: rijen klappen **in-place** uit (stacktraces/payloads); Table zou die nuttige detail-view slopen. Hand-rolled behouden.
- [SKIP] SecureField/Keychain: OAuth Client IDs zijn publiek (geen secrets); YouTube-cookies zijn multi-line + server-opgeslagen → SecureField/Keychain n.v.t.

## Wave 4 — Slop-eilanden  ✅ DONE (commits b209bc1, 78404cf)
- [x] Onboarding: 7 animerende gradients → 1 rustige brand-tint; wizard UIT TabView op macOS (switch op currentStep)
- [x] Eyebrow-labels → rounded sentence-case headings: Recording (Nieuwe opname / YouTube-video / Live transcriptie), Processing (Voortgang), Profiles section headers
- [x] Processing: de-dark — glass-on-soft-gray, `.preferredColorScheme(.dark)` weg, neon-blue → brandSecondary, alle `.white.opacity` → label/border tokens
- [DEFER] Onboarding "Later instellen" + profiel-stap 6→3 velden (Wave 7); background-blobs (P3, laten)

## Wave 5 — A11y + tokens  ~PARTIAL (commits 08e841f, 50696ad)
- [x] document-titel → `TS.Font.title3Bold` (.rounded) in TranscriptDetail (×2)
- [x] a11y-labels: Login + Settings eye-toggles, model-reload, Transcript "Meer acties"-menu, titel opslaan/annuleren
- [x] PeopleDirectory intern/extern → zichtbare tekst-tag (WCAG 1.4.1) + VoiceOver
- [x] Login `.textContentType(.username/.password)` (autofill)
- [ ] **Resterende a11y-labels** (AdminView icon-buttons, overige) — TranscriptsView bleek al grotendeels gelabeld
- [TODO] Reduced-motion: schadelijke (continue/looping) gevallen AL gegated (shimmer/pulsing dot/waveform); resterende 22 files = one-shot tab/hover-springs (lage impact) — optioneel
- [TODO] 137 font-size-literals → TS.Font (groot, visueel-drift-risico; dedicated pass)
- [TODO] radius/spacing/frame-literals; dark-mode `.black` shadows / inline RGB (dedicated pass)

## Wave 6 — Localisatie  ⏳ TODO (groot, dedicated mechanical pass)
- [ ] 318 hardcoded `Text("…")` → `Localizable.strings` keys; en.lproj activeren. (mem 26472). Vereist zorgvuldige key-extractie + fallback-check; beste als losse gefocuste sweep ná de copy-veranderende waves (nu klaar).

## Wave 7 — Polish  ~PARTIAL (Login textContentType + Tasks dead code al gedaan in Wave 5b)
- [ ] Sub-44pt close-buttons hit-area (Recording/Transcripts/Tasks)
- [ ] Login: "Wachtwoord vergeten" (vergt product-keuze: support/reset-flow); "Lokaal gebruiken" terugweg/bevestiging  — [x] textContentType gedaan
- [ ] AccountView GDPR-export: echte data of hernoemen "Vraag aan"
- [ ] FloatingWidget: `.error` niet verbergen; bredere status-pill (12-char truncation weg)
- [ ] PermissionBanner: denied → "Open Systeeminstellingen" i.p.v. no-op; reduced-motion
- [ ] NotuleResult: hand-rolled toolbar → native `.toolbar`; PDF-export progress; meta-pills cap 4+n
- [ ] Recording: spacebar pauze; profiel-load 10s `Task.sleep` → echte completion
- [ ] Tasks: completed uit "actieve" lijst; dode ternary regel 301
