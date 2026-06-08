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
- [~] **font-size-sweep gedaan (build-verified):** van 149 `.system(size:)` bleek **124 = `Image`/SF-symbol icon-sizing** (hoort vast → niet in scope van een *font*-token-sweep) en de meeste resterende Text = **monospaced timers/codes** (RecordingView 56pt-timer, 2FA-codes, durations) of **layout-gekoppeld** (avatar-letter in 32pt cirkel, 9pt admin-badges → zouden naar 11 groeien). Alleen **9 nul-drift Text-sites** (vaste grootte raakt exact token-default) geconverteerd → consistentie + Dynamic Type, géén visuele verandering. Rest bewust vast gelaten (zou regressie geven).
- [TODO] radius/spacing/frame-literals; dark-mode `.black` shadows / inline RGB (dedicated pass)

## Wave 6 — Localisatie  ✅ DONE (build + runtime-verified)
- [x] **NL-tekst-als-sleutel** aanpak (SwiftUI `Text("…")` is al een `LocalizedStringKey`): nul code-wijzigingen in 66 Views, en.lproj nu live. nl/en `Localizable.strings` herschreven als volledige catalogus (410 keys: 387 plain + 17 interpolatie + 6 semantische).
- [x] Interpolatie-keys met correcte specifiers (`Int`→`%lld`, `String`→`%@`) — geverifieerd dat `String(localized:)`/`LocalizedStringKey` exact matchen (bv. `Text("Pagina \(5) van \(10)")` → "Page 5 of 10").
- [x] 6 `NSLocalizedString("sort.*"/"filter.*")` semantische keys (TranscriptsViewModel) behouden. ~120 dode semantische keys vervangen.
- [SKIP] 12 technische literals (localhost/n8n/socks URLs, UUID/yt-dlp placeholders, iOS/macOS/llama3.2) → geen en-entry; vallen terug op literal (identiek in beide talen).
- Runtime-bewijs: built bundle en.lproj → "Opslaan"→Save, "Nieuwe opname"→New recording, "Fout: boom"→Error: boom, "Bewerk Jan"→Edit Jan.

## Wave 7 — Polish  ~PARTIAL
- [x] **Recording: profiel-load 10s `Task.sleep` → echte completion** (2 sites). `loadDefaultProfile` vult altijd met defaults, dus de sleep was zinloos → `await reloadProfiles()` + directe check. Spinner verdwijnt nu bij echte completion i.p.v. na 10s. (commit)
- [x] **PermissionBanner: denied → knop-label "Open Systeeminstellingen"** i.p.v. misleidend "Toestaan". `requestMicrophone()`/`requestSpeechRecognition()` openden al Settings bij denied (geen no-op); alleen het label klopte niet. `PermissionManager` exposed nu `microphoneDenied`/`speechRecognitionDenied`. (commit)
- [DEFER] FloatingWidget `.error` zichtbaar houden: vergt nieuwe dismiss-knop + error-reset in widget (`actionButtons` heeft `default: EmptyView()`); fout wordt al getoond in main window + menubar → lage netto-waarde, matige churn.
- [DEFER] PermissionBanner reduced-motion: alleen one-shot expand-spring (lage impact, Wave 5 al zo beoordeeld).
- [DEFER] NotuleResult native `.toolbar`-rewrite: visueel-risicovolle herstructurering; meta-pills cap + PDF-progress = aparte kleine items.
- [DEFER] Sub-44pt close-buttons hit-area: fiddly per-site, frame-wijzigingen kunnen layout verschuiven; lage impact.
- [DEFER] Recording spacebar-pauze: bare `.space` shortcut is intrusief (botst met scroll/default-button); vergt zorgvuldig focus-scopen.
- [DEFER] Tasks completed-filter: `activeTasks` komt 1:1 van `getActiveTasks()` API — client-side filteren kan legitieme data verbergen; backend-gedrag eerst bevestigen. "Dode ternary r.301" = stale (relativeTimeString is in gebruik).
- [PRODUCT] Login "Wachtwoord vergeten": vergt keuze support-mail vs reset-flow. AccountView GDPR-export: echte data-export bouwen of knop hernoemen "Aanvragen". → Michel beslissen.
- [NOTE] `macos/Services/FloatingWidgetController.swift` = orphan (niet in pbxproj/build); dup van `FloatingWidgetPanel.swift`. Handmatig opruimen in Xcode wanneer gewenst.
