# Plan: foutrapporten, meldingen en bijwerken in ThoughtVault

Getoetst aan `origin/main` op 1.0.311 (commit d94a2fe, 10 november 2026) van de app-repo en `origin/main` van `transcript-studio-backend` (7909542). Regelnummers hieronder komen van die commits. Geen tijdsinschattingen.

## 1. Context

Michel kan nu niet zien wat er bij een gebruiker misgaat. Er is geen logbestand, de meldknop kopieert naar het klembord (macOS, Windows) of doet niets (iOS), en de oude feedbackroutes vragen een login die niet meer bestaat. Updates zijn op macOS en Windows handwerk via een banner.

Eindbeeld: een mislukte opname, transcriptie of notule en elke crash komen zonder tussenkomst van de gebruiker als melding met afgeschermd logbestand in de feedback-hub (voorvoegsel `TV`). Gebruikers sturen zelf een melding vanuit de app en lezen het antwoord in "Mijn meldingen" en per e-mail. macOS (buiten de App Store) en Windows downloaden updates stil en installeren ze bij afsluiten.

## 2. Besluiten (vast, niet heropenen)

1. Geen login. Bij de eerste start een verplicht scherm voor naam en e-mailadres, ook voor bestaande gebruikers direct na de update, zonder "Later" en zonder bevestigingsmail.
2. Elke installatie maakt een willekeurig kenmerk plus geheim, bewaart die lokaal en meldt zich daarmee aan bij de relay. Het kenmerk is de `userId` richting de hub.
3. Antwoorden verschijnen in de app ("Mijn meldingen", ongelezen-teller) en per e-mail vanuit de hub.
4. Automatisch versturen, zonder vraag, alleen bij een crash en bij een opname, transcriptie of notule die mislukt of vastloopt. Dezelfde fout van dezelfde installatie wordt één melding met een teller (vervolgbericht in de thread). Overige fouten alleen in het lokale log.
5. Geen schermafbeelding bij automatische meldingen. Een afbeelding bij een eigen melding is een latere stap.
6. Inhoud: de Nederlandse foutzin die de gebruiker zag, de stap (opnemen, transcriberen, notule), de letterlijke foutmelding, het klikpad (namen van schermen en knoppen, geen getypte tekst), app-versie, OS, apparaat, logbestand.
7. Logbestand per platform. Titels, bestandsnamen, deelnemers en e-mailadressen worden bij het wegschrijven vervangen door een kort stabiel kenmerk. Transcript- en notuletekst nooit. Bewaartermijn zeven dagen of 5 MB.
8. Automatisch versturen staat standaard aan, met een schakelaar in Instellingen. Het eerste-startscherm legt in twee zinnen uit wat er bij een fout verstuurd wordt en wat nooit. Zelf melden werkt altijd.
9. Relay: routes zonder login in de bestaande FastAPI-container `n8n_transcript_studio`. De hub-sleutel staat alleen daar. De apps bevatten geen hub-sleutel en geen instelscherm voor de koppeling.
10. De apps praten met een pad onder `https://thoughtvault.yinga.ai`, dat doorstuurt naar de container.
11. Bijwerken: stil downloaden, installeren bij afsluiten of eerstvolgende start, nooit tijdens opnemen of verwerken. Standaard aan, schakelaar plus knop "Zoek naar updates". macOS via Sparkle, Windows via de Tauri-updater. De `APP_STORE`-build krijgt deze knoppen niet.
12. Zonder internet bewaart de app de melding en verstuurt hem later.
13. Crash herkennen met een markering die bij nette afsluiting wordt gewist.
14. Hub-tool "ThoughtVault", slug `thoughtvault`, één instance, voorvoegsel `TV`, shadow uit. Aanmaken pas bij uitvoering en na akkoord.
15. De oude feedbackmodule blijft staan als dode code. De Windows-widget en `crashReporter.ts` gaan naar de relay.
16. iOS doet mee via de gedeelde Swift-code. Android bestaat niet meer.

## 3. Architectuur

De apps sturen JSON naar `https://thoughtvault.yinga.ai/support/...`. De bestaande `yinga-caddy` op n8n01 herschrijft dat pad naar `/tstudio/api/support/...` en geeft het door aan `172.17.0.1:5678` met `Host: n8n.prezent.nl`, precies zoals hij nu al de updaterfeeds doorgeeft (`scripts/infra/thoughtvault-releases.caddy`, blok `@updater`). In de container controleert de relay kenmerk en geheim, houdt hij limieten bij, onthoudt hij welke fout bij welk ticket hoort, en roept hij de widget-API van de hub aan met `x-instance-key` en `x-widget-user`. Het logbestand reist als tekstveld in de JSON mee; de relay zet het om naar een `.txt`-bijlage. Zo hoeven de apps geen multipart te bouwen.

```
app (macOS/iOS/Windows)
   │  JSON + X-TV-Installation + X-TV-Secret
   ▼
thoughtvault.yinga.ai/support/*        (yinga-caddy, n8n01)
   │  uri replace /support/ → /tstudio/api/support/
   ▼
n8n_transcript_studio  routes/support.py   (SQLite/Postgres: installaties, fout→ticket)
   │  x-instance-key, x-widget-user = installatiekenmerk
   ▼
feedback.yinga.ai/api/widget/*         (hub, instance TV)
   │  antwoord van Michel
   └──► e-mail aan de gebruiker, en via GET /support/... terug in de app
```

## 4. Relay-contract

Alle routes onder `/tstudio/api/support`, buiten de app als `https://thoughtvault.yinga.ai/support`. Alles JSON. Behalve de aanmelding dragen alle verzoeken de headers `X-TV-Installation` (kenmerk) en `X-TV-Secret` (geheim). De relay vergelijkt `sha256(geheim)` met de opgeslagen hash; mis = 401. Verzoeken zonder `Origin` passeren de bestaande CSRF-middleware al; Swift `URLSession` en reqwest sturen er geen.

| Route | Velden | Limiet | Op de hub |
| --- | --- | --- | --- |
| `POST /installations` | `installationId` (UUID), `secret` (32 bytes, base64url) | 5 per uur per IP | geen hubaanroep; nieuw = 201, zelfde id en geheim = 200, zelfde id met ander geheim = 409 |
| `POST /reports` | `kind` (`auto`/`manual`), `category` (`BUG`/`FEATURE_REQUEST`/`QUESTION`, auto altijd `BUG`), `stage` (`opnemen`/`transcriberen`/`notule`/`crash`, leeg bij handmatig), `shownMessage` of omschrijving (max 5000), `errorText` (max 2000), `fingerprint` (alleen auto, 16 tot 64 hex), `clickPath` (max 30 regels van 80 tekens), `appVersion`, `os`, `device`, `platform`, `name`, `email`, `occurredAt`, `log` (max 1 MB tekst) | 20 per uur per installatie, 60 per uur per IP, verzoek max 1,5 MB (anders 413) | zie hieronder |
| `GET /tickets` | geen | 120 per uur per installatie | `GET /tickets/mine?limit=50` |
| `GET /unread-count` | geen | idem | `GET /unread-count` |
| `GET /tickets/{id}/messages` | geen | idem | `GET /tickets/:id/messages` (markeert gelezen), 403 wordt 404 |
| `POST /tickets/{id}/messages` | `body` (max 5000) | idem | `POST /tickets/:id/messages`, 403 wordt 404 |

`POST /reports` werkt in twee stappen omdat de hub bij het aanmaken geen logbestand aanneemt:

1. Nieuwe melding: multipart `POST /api/widget/tickets` met `category`, `description` (de zin die de gebruiker zag of zijn eigen tekst, plus stap en foutmelding), `userId` = kenmerk, `userName`, `userEmail`, `releaseVersion` = app-versie, `module` = stap, `environment` = platform, `browserInfo` = "ThoughtVault <platform> <versie> / <os> / <apparaat>", en `diagnostics` als JSON met stap, foutmelding, klikpad, versie, OS, apparaat, tijdstip en teller.
2. Daarna `POST /api/widget/tickets/:id/messages` met body "Logbestand van dit apparaat" en het log als bijlage `thoughtvault-log.txt` (`text/plain`) in het veld `attachments`.

Ontdubbelen alleen bij `kind=auto`: de relay zoekt (`installationId`, `fingerprint`) op. Bestaat de koppeling, dan haalt hij `GET /tickets/:id` op. Status `RESOLVED` of `CLOSED`: nieuw ticket en koppeling overschrijven (een bericht op een gesloten ticket heropent hem in de hub niet, zie `ticketActions.ts` r.108). Anders: teller ophogen en een vervolgbericht "Opnieuw opgetreden (n keer), laatste keer <tijd>" met het nieuwe log als bijlage. Antwoord aan de app: `{ticketId, ref, repeated, count}`. Een 429 van de hub gaat als 429 terug, zodat de app de melding in zijn wachtrij houdt.

Opslag: twee tabellen in de database die de backend al gebruikt (SQLAlchemy, `init_database()` maakt nieuwe tabellen aan via `Base.metadata.create_all`, `APP/database.py` r.102-108):
- `support_installations`: `id` (PK), `secret_hash`, `created_at`, `last_seen_at`.
- `support_issues`: `installation_id`, `fingerprint`, `ticket_id`, `count`, `first_seen`, `last_seen`, uniek op (`installation_id`, `fingerprint`).

Bescherming zonder login: kenmerk plus geheim per installatie, de limieten in de tabel, een maximale grootte per verzoek, en de hub scoped elke ticketroute op `x-widget-user`, zodat de ene installatie de meldingen van een andere niet kan lezen. De IP-limiet leunt op de bestaande `get_remote_address` in `APP/middleware/rate_limiting.py` r.22-27, die het eerste `X-Forwarded-For`-adres neemt; dat adres kan een client zelf meesturen. De limiet per installatie is daarom de echte rem, de IP-limiet is een extra drempel tegen massaal aanmelden.

## 5. Fasen

Fase b en c hangen af van fase a. Fase d staat los en kan parallel.

De pilot start pas als fase a, b, c en het Windows-deel van d af en bewezen zijn. Alle pilotgebruikers beginnen dan met dezelfde functies en niemand krijgt later een verplicht scherm na een update.

### Fase a: relay, hub-registratie, doorverwijzing

Backend (`APP` = `transcript-studio-backend/src/insanely_fast_whisper_api/app`):
- Nieuw `APP/routes/support.py` (doel onder 300 regels): de zes routes, `_call_hub(method, path, installation_id, ticket_scoped=False, **kwargs)` overgenomen uit `/Volumes/SSD/Projects/ProspectFlow/app/routers/feedback.py` (r.155-215), omgezet naar `httpx.AsyncClient` omdat `httpx==0.28.1` in `requirements.txt` gepind staat en `requests` niet. Foutantwoorden via `raise_api_error` uit `APP/errors.py`, limieten via `@limiter.limit(...)` uit `APP/rate_limiting.py` (zoals `routes/auth.py` r.386), met `key_func` op `X-TV-Installation` voor de limiet per installatie.
- Nieuw `APP/support_models.py`: de twee tabellen op de bestaande `Base`. `APP/models.py` heeft al 747 regels en groeit daarom niet.
- `APP/database.py` `init_database()`: één import van `support_models`, zodat `create_all` de tabellen kent.
- `APP/config.py`: `feedback_hub_url = _env_field("https://feedback.yinga.ai", "FEEDBACK_HUB_URL")` en `feedback_hub_instance_key = _env_field("", "FEEDBACK_HUB_INSTANCE_KEY")`. Zonder sleutel antwoorden de routes 503.
- `APP/app.py`: import naast r.970-981 en `api_router.include_router(support_router)` naast r.983-993.
- `.env.example`: de twee namen. Op de server de waarden in `.env`; de compose in de repo laadt `.env` via `env_file`, dus een extra regel onder `environment:` is alleen nodig als de servercompose afwijkt.
- Nieuw `tests/test_support_relay.py`: hubaanroepen vervangen door een nepfunctie, gevallen: aanmelden idempotent en 409 bij ander geheim, fout geheim 401, te groot 413, tweede identieke auto-melding wordt bericht met teller 2, gesloten ticket geeft nieuw ticket, hub-403 wordt 404, ontbrekende hub-sleutel 503. Referentie voor de testvorm: `ProspectFlow/tests/test_feedback.py`.

Infra en hub (na akkoord van Michel):
- Hub: `connect_tool` met slug `thoughtvault`, naam "ThoughtVault", domein `thoughtvault.yinga.ai`, `refPrefix` `TV`, shadow uit. Controle op 10 november via `list_tools` en `list_instances`: `thoughtvault` bestaat nog niet, `TV` is vrij. De sleutel gaat direct in de server-`.env`, niet in een repo of chat.
- Caddy: in `scripts/infra/thoughtvault-releases.caddy` een blok `@support path /support/*` met `uri replace /support/ /tstudio/api/support/` en dezelfde `reverse_proxy 172.17.0.1:5678 { header_up Host n8n.prezent.nl }`, boven de `handle`-fallback naar de website. Het live Caddyfile eerst back-uppen, zoals `scripts/deploy-website.sh` dat doet.
- Deploy backend: bestanden syncen en `docker restart n8n_transcript_studio`. Let op: `docs/BACKEND.md` staat niet op main van de app-repo, alleen in de verouderde werkmap; de deploystappen komen daarom uit het projectinstructiebestand in de repo-root (sectie Backend) en die werkmapkopie.

Bewijs: `pytest tests/test_support_relay.py` groen. Daarna met curl tegen `https://thoughtvault.yinga.ai/support`: aanmelden, één auto-melding, dezelfde melding nog eens. In de hub via `list_tickets` precies één ticket `TV-1`, via `get_ticket` de diagnostics, het bericht met `thoughtvault-log.txt` en het vervolgbericht met teller 2. Testticket daarna sluiten met `set_ticket_status`.

### Fase b: macOS en iOS

Nieuwe Swift-bestanden, elk in de targets `ThoughtVault` en `ThoughtVault AppStore` (het project gebruikt expliciete bestandsverwijzingen, geen gesynchroniseerde mappen):

- `macos/Services/AppLog.swift`: `struct AppLog(category:)` met `info`, `warning`, `error` die naar `Logger` en naar het bestand schrijven. Een `actor LogFile` leest regels uit een `AsyncStream`, zodat de volgorde klopt en aanroepers synchroon blijven. Bestand in `AppEnvironment.supportDirectory/Logs/thoughtvault.log` (die map wijst onder tests al naar een tijdelijke map, `ThoughtVaultApp.swift` r.7-15). Roteren naar `thoughtvault.1.log` bij 2,5 MB; bij de start `.1` weggooien als die ouder is dan zeven dagen. `tail(maxBytes:)` levert maximaal 1 MB. `LogRedact.mask(_:)` maakt van een titel, bestandsnaam, deelnemer of adres een kenmerk als `k-3fa29c` (eerste zes hex van SHA-256, CryptoKit). Een vangnet in het schrijfpad maskeert e-mailadressen en absolute paden. Debugregels gaan niet naar het bestand. Hier ook de crashmarkering `Logs/session.open`: `beginSession() -> Bool` (stond hij er nog: vorige sessie gecrasht) en `endSession()`.
- `macos/Services/SupportRelay.swift`: `actor`. Kenmerk in UserDefaults (`supportInstallationId`), geheim via `KeychainService.shared.save` niet-gesynchroniseerd, naam en e-mail in UserDefaults (`supportName`, `supportEmail`). Geen van deze sleutels in `SettingsSyncService.keys` (r.21), zodat een tweede apparaat een eigen kenmerk krijgt. Eigen `URLSession`, niet `APIService`, want `APIService.request` blokkeert in lokale modus (r.201). Wachtrij als JSON-bestanden in `Logs/outbox/`, alleen metadata; het log wordt pas bij verzenden gelezen, zodat een crashmelding na herstart het log van de vorige sessie meeneemt. Leegmaken bij de start en zodra `NetworkMonitor.shared.isConnected` weer waar wordt.
- `macos/ViewModels/SupportViewModel.swift`: `@MainActor @Observable final class` met `unreadCount`, meldingen, thread, `report(stage:shown:error:)` voor automatische meldingen en `submit(...)` voor eigen meldingen. Vingerafdruk: SHA-256 over stap plus foutmelding zonder cijfers, eerste 16 hex. Ongelezen ophalen bij de start, bij activeren van de app en elke 15 minuten.
- `macos/Views/SupportIdentityView.swift`: naam en e-mail (eenvoudige vormcontrole), knop "Doorgaan", de twee zinnen uit besluit 8, bijvoorbeeld: "Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee." Teksten via `Localizable.strings` (nl en en), tokens `TS.*`, kleuren `Color.brandPrimary`, geen em-dash.
- `macos/Views/SupportViews.swift`: meldformulier (categorie, omschrijving), "Mijn meldingen" (lijst met status en ongelezen-stip) en thread met antwoordveld.
- `macos/Views/SettingsView+Support.swift`: `feedbackSection` en `updatesSection` verhuizen uit `SettingsView.swift` (r.1491-1511 en r.1546-1566) naar dit bestand. `SettingsView.swift` heeft 1686 regels; deze verhuizing en het schrappen van het klembordsheet (r.95-118, plus `showBugReportSheet`, `feedbackTitle`, `feedbackDescription`) maken hem kleiner. De sectie krijgt "Melding maken", "Mijn meldingen" met teller, de schakelaar "Foutrapporten automatisch versturen" (`@AppStorage("supportAutoReport")`, standaard aan) en naam en e-mail om te corrigeren.

Haakpunten in bestaande code:
- Identiteitspoort in `RootView` (`ThoughtVaultApp.swift` r.127-139): eerst `SupportIdentityView` zolang naam of e-mail ontbreekt, daarna de bestaande keuze tussen `OnboardingView` en `ContentView`. Zo ziet een nieuwe gebruiker het scherm bij de eerste start en een bestaande gebruiker direct na de update, zonder `hasCompletedOnboarding` te raken. De naam wordt voorgevuld uit het eigen profiel dat de onboarding via `LocalTranscriptStore.upsertSelfProfile` opslaat, als dat bestaat. De `.task`-blokken met opnameherstel hangen aan de `WindowGroup` en blijven dus draaien.
- Mislukte transcriptie en notule: één punt, `RecordingViewModel.updateTask` (r.1391). Vóór het overschrijven de oude status bewaren; bij overgang naar `.error` met een andere melding dan "Geannuleerd door gebruiker." de stap afleiden uit de oude status (`.transcribing` of `.uploading` wordt transcriberen, `.generatingLocal` wordt notule) en `report` aanroepen. Dit dekt lokale transcriptie (r.852), opslaan (r.888), notule (`RecordingViewModel+Notule.swift` r.89, r.97), opnieuw genereren (r.148, r.151) en uploads (r.662, r.670). De cloudroute via `handleSSEEvent` blijft buiten beeld: die hangt aan de server-login die niet meer bestaat.
- Mislukte opname: `didSet` op `recordingState` (r.19), alleen bij overgang naar `.error`. Instructies aan de gebruiker zijn geen softwarefout en worden overgeslagen via een vaste lijst in het view model: de meldingen van r.330, r.453, r.467, r.474 en r.533. Dit is een bewuste vereenvoudiging: een nieuwe instructiezin moet aan die lijst worden toegevoegd.
- Vastlopen: bestaande time-outs zetten een hangende stap al om in `.error` en komen zo via `updateTask` binnen (initialisatie WhisperKit `LocalTranscriber.swift` r.402, watchdog `OnDeviceTranscriber.swift` r.142, LLM-verzoeken 300 s, pollingvangnet r.1251). Geen nieuwe watchdog. Uitzondering die geen time-out heeft: het transcriberen zelf met WhisperKit (alleen het laden van het model is begrensd, `LocalTranscriber.swift` r.401; r.80 waarschuwt voor stil hangen). Daarom schrijft `updateTask` bij elke statuswissel de lopende stap in de crashmarkering `session.open`. Staat de markering er bij de start nog, dan krijgt de melding die stap mee ("gestopt tijdens transcriberen") in plaats van de kale stap `crash`. Hetzelfde op Windows via `session_begin` en `updateBackgroundTask`.
- Crash: `beginSession()` in de eerste `.task` van `ThoughtVaultApp`; `true` geeft een melding met stap `crash`. `endSession()` op macOS bij `NSApplication.willTerminateNotification`; op iOS bij `scenePhase == .background` (en opnieuw `beginSession` bij `.active`), omdat iOS een app op de achtergrond zonder afsluitbericht kan beëindigen.
- Klikpad: logregels met categorie `Klikpad`, zodat het pad na een crash in het log staat. Bronnen: `ContentView` `.onChange(of: selectedTab)` (r.104), het instellingentabblad in `SettingsView+Studio.swift`, het openen van de meld- en meldingenschermen, en de actiemethoden van `RecordingViewModel` (starten, pauzeren, hervatten, stoppen, annuleren, importeren). Het rapport neemt de laatste 30 van die regels.
- Logger overzetten: in de 28 bestanden met `Logger(subsystem: "com.buildmind.ThoughtVault", category:)` die declaratie vervangen door `AppLog(category:)`; de 9 interpolaties met `privacy:` worden gewone strings. De 39 `os_log`-aanroepen in `RecordingViewModel.swift` gaan naar `AppLog`. `DebugLogger.error` en `CrashReporter.recordError` schrijven intern via `AppLog`, zodat hun bestaande aanroepers (Keychain, OfflineQueue, MicrosoftGraph) in het log landen.
- Gevoelige logregels op main, via `LogRedact.mask`: `AudioChunker.swift` r.196, `GoogleAuthService.swift` r.208, `LocalTranscriber.swift` r.194, `MeetingNotificationService.swift` r.103, `MicrosoftGraphService.swift` r.240, `OnDeviceTranscriber.swift` r.129, `VaultFolderStore.swift` r.166, `AuthViewModel.swift` r.143, plus de `os_log`-regels met bestandsnamen in `RecordingViewModel.swift` (bij uitvoering opnieuw grep'en op `lastPathComponent` en `filename`).
- Meldknop: in Instellingen (Account-tab macOS, "Over ThoughtVault" op iOS, `SettingsView+iOS.swift` r.96-103) en op macOS in het Help-menu via `CommandGroup(replacing: .help)` met een `Window`-scene voor het meldformulier. Ongelezen-teller op het instellingenitem in `MainSidebar` en op het iOS-instellingentabblad.
- `macos/PrivacyInfo.xcprivacy`: naam en crash- of diagnosegegevens toevoegen (e-mailadres staat er al), doel `AppFunctionality`.

`RecordingViewModel.swift` (1555 regels) is te groot om verder te laten groeien. De wijzigingen daar blijven bij een `didSet`, een paar regels in `updateTask` en vervanging van logaanroepen; opsplitsen valt buiten deze opdracht en is een apart besluit.

Bewijs:
- Nieuwe tests `ThoughtVaultTests/AppLogTests.swift` (maskeren van e-mail en pad, stabiel kenmerk, rotatie bij 2,5 MB, `tail` max 1 MB, crashmarkering) en `ThoughtVaultTests/SupportRelayTests.swift` (vingerafdruk gelijk bij andere cijfers, overgeslagen instructiezinnen, wachtrij bewaren en leegmaken met een `URLProtocol`-stub). `xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS'` groen, en een build van schema `ThoughtVault AppStore`. Geen tests terwijl `/Applications/ThoughtVault.app` draait.
- Handmatig op een screenshotbuild in eigen container (nooit onder de echte bundle-ID): transcriptie laten mislukken (bijvoorbeeld zonder geïnstalleerd WhisperKit-model, `modelNotInstalled`) en tweemaal herhalen; in de hub één `TV`-ticket met teller 2 en log. App met `kill -9` stoppen en starten: crashmelding. Wifi uit, fout opwekken, wifi aan: melding komt alsnog binnen. Antwoord via `reply_ticket`: teller in de app en de thread tonen het.
- Schermafbeeldingen van identiteitsscherm, meldformulier, Mijn meldingen en thread op macOS en in de iOS-simulator (simulator daarna afsluiten).

### Fase c: Windows

Rust (`windows/src-tauri/src`):
- Nieuw `applog.rs`: regels toevoegen aan `<app_data_dir>/logs/thoughtvault.log` met std-bestandsfuncties (geen nieuwe crate), roteren bij 2,5 MB naar `.1`, `.1` weg na zeven dagen, maskeren van e-mailadressen en paden met een kleine tokenfunctie. Commands `log_write(level, category, message)`, `log_tail(max_bytes)`, `session_begin() -> bool`. Een macro die naar bestand en stderr schrijft vervangt de 45 `eprintln!`-aanroepen, die in een release verloren gaan door `windows_subsystem = "windows"` (`main.rs` r.1).
- `lib.rs`: `std::panic::set_hook` die de panic in het log zet; `.run(generate_context!())` wordt `.build(...)` plus `.run(|_, event| ...)` die bij `RunEvent::Exit` de markering wist; commands registreren in `generate_handler!`.
- Unit-tests in `applog.rs` voor rotatie, maskeren en markering.

TypeScript (`windows/src`):
- Nieuw `services/appLog.ts`: `log.info/warn/error` via `invoke("log_write")`, `mask(value)` voor een stabiel kenmerk, en eenmalig `console.warn`/`console.error` doorsturen naar het log (41 aanroepen; bij uitvoering die lijst nalopen op titels). Klikpad: route-wissel in `App.tsx` via `useLocation` en één `click`-listener op `document` die bij een `button` het `aria-label` of de zichtbare tekst (max 40 tekens, gemaskeerd) logt.
- Nieuw `services/supportRelay.ts`: aanmelden, melden, meldingen, teller, thread, bericht, via de bestaande Tauri-command `proxy_request` (`commands/http.rs` r.26), niet via `api.request`, dat `server_url` en `X-User-Token` gebruikt. Geheim via de bestaande `storeCredential`/`loadCredential` (Windows Credential Manager).
- Nieuw `stores/supportStore.ts` (zustand `persist`): kenmerk, naam, e-mail, `auto_report` (standaard `true`), wachtrij met alleen metadata, `unreadCount`. Leegmaken bij de start en op het `online`-event.
- `services/crashReporter.ts`: `window`-fouten en `unhandledrejection` gaan alleen naar het log, niet meer naar `POST /feedback`. Het bestand krijgt `reportFailure(stage, shown, error)` voor automatische meldingen.
- Haakpunten: `stores/recordingStore.ts` `updateBackgroundTask` (r.141) als gedeeld punt voor transcriptie en notule, bij overgang naar `status: "failed"` met stap uit de vorige status (dekt `localPipeline.ts` r.182, `RecordingPage.tsx` r.172 en r.183, `App.tsx` r.345 en r.357). Opname heeft geen gedeeld punt: `hooks/useGlobalRecordingHandler.ts` (listener `recording-error`, r.70-75) en de `catch` in `RecordingPage.tsx` `handleStartRecording` (r.215-219). Crash: `session_begin()` bij het opstarten van `App.tsx`, plus `ErrorBoundary.componentDidCatch` (`components/ui/ErrorBoundary.tsx` r.23) als UI-crash.
- Identiteitspoort: nieuw `components/support/IdentityGate.tsx`, in `ProtectedRoutes` (`App.tsx`) vóór de onboardingcontrole van r.378. Die controle slaat de wizard in lokale modus over, dus de poort moet ervoor staan om bestaande lokale gebruikers te bereiken.
- `components/FeedbackWidget.tsx` (443 regels): data uit `supportRelay` in plaats van `api.submitFeedback`, `getMyFeedback`, `getUnreadFeedbackCount` en `markFeedbackRead`; de klembordtak voor lokale modus vervalt; categorieën naar `BUG`/`FEATURE_REQUEST`/`QUESTION`; statuslabels naar het hub-enum `NEW`, `IN_PROGRESS`, `WAITING_FOR_USER`, `RESOLVED`, `CLOSED`; het titelveld vervalt omdat de hub alleen een omschrijving kent. De thread met antwoordveld komt in nieuw `components/support/SupportThread.tsx`, zodat de widget niet over de 500 regels gaat. `components/__tests__/FeedbackWidget.test.tsx` bijwerken.
- `components/settings/AccountTab.tsx`: schakelaar "Foutrapporten automatisch versturen" en naam en e-mail. Ongelezen-teller op het instellingenitem in `components/layout/Sidebar.tsx`.
- `App.tsx` telt 561 regels. Omdat hij toch wordt aangeraakt: `OfflineQueueBanner` (vanaf r.47) zonder gedragswijziging naar een eigen bestand, bewezen met `npx vitest run`.
- CSP in `tauri.conf.json` laat `https://thoughtvault.yinga.ai` al toe, en het verkeer loopt via Rust; geen wijziging nodig.

Bewijs: `cd windows && npx vitest run && npm run build` en `cd windows/src-tauri && cargo test --lib` groen. MSI bouwen en installeren volgens `docs/WINDOWS-BUILD-WORKFLOW.md`. Op de Windows-pc: lokale verwerking laten mislukken en herhalen (één `TV`-ticket met teller 2 en log), proces via Taakbeheer stoppen en starten (crashmelding), netwerk uit en aan (melding komt na). Schermafbeeldingen van identiteitspoort, widget en thread via de bestaande `desktop-review.tsx`-pagina's (route voor de poort toevoegen) met `pw screenshot` op 1920×1080, 1440, 1280, 390 en 320.

### Fase d: bijwerken

Stand op 10 november: ThoughtVault heeft nog geen gebruikers. De pilot op macOS loopt via TestFlight, dat zelf bijwerkt, dus daar is niets te bouwen. Het macOS-deel hieronder wordt pas uitgevoerd als er een rechtstreekse download naast TestFlight of de App Store komt. Het Windows-deel gaat wel door.

macOS, uitgesteld (alleen `#if os(macOS) && !APP_STORE`):
- `macos/Info.plist` r.48-51: `SUAllowsAutomaticUpdates` van `false` naar `true` en `SUAutomaticallyUpdate` van `false` naar `true`. Met `SUAllowsAutomaticUpdates = NO` geeft Sparkle `automaticallyDownloadsUpdates` altijd `NO`, wat de code ook zet (Sparkle-documentatie, `SPUUpdater.automaticallyDownloadsUpdates`). `SUEnableAutomaticChecks` blijft `false`: de app houdt zijn eigen zesuurslus aan.
- `macos/Services/UpdateCheckService.swift`: in `prepareUpdater` `automaticallyDownloadsUpdates` gelijkzetten aan de schakelaar `checkForUpdates` (alleen bij wijziging, Sparkle bewaart de waarde zelf); in `checkForUpdate` `checkForUpdatesInBackground()` in plaats van `checkForUpdateInformation()`, dat alleen meldt en niet downloadt. Sparkle installeert een gedownloade update bij afsluiten; staat de app lang open, dan vraagt Sparkle na `SUScheduledImpatientCheckInterval` zelf om te installeren. Nieuwe `checkNow()`: `lastCheck = nil` en `controller.checkForUpdates(nil)`; de bestaande `shouldPostponeRelaunchForUpdate` houdt installatie tegen zolang `isBusy()`.
- `SettingsView+Support.swift`: schakelaar heet "Automatisch bijwerken" met uitleg, plus knop "Zoek naar updates". `ThoughtVaultApp.swift`: `.environment(updateCheckService)` ook op de `Settings`-scene (r.100-108), anders crasht die bij het lezen van de service. `SettingsView+iOS.swift` r.99: `updatesSection` achter `#if os(macOS) && !APP_STORE`; op iOS doet die schakelaar nu niets.

Windows:
- `hooks/useUpdateCheck.ts`: bij een gevonden update en `check_for_updates` direct `update.download()` zonder vraag; elke zes uur opnieuw kijken; luisteren naar een `window`-event `tv-check-updates` voor de knop. Bij `getCurrentWindow().onCloseRequested`: is er een download klaar en is er niets bezig (dezelfde voorwaarde als `UpdateBanner.tsx` r.16), dan `preventDefault()` en `update.install()`. Op Windows sluit de updater de app zelf af en start de MSI in `passive`-modus (Tauri-documentatie, updater-plugin), wat een klein voortgangsvenster toont. De download zit in het geheugen; sluit de gebruiker af vóór hij klaar is, dan downloadt de volgende start opnieuw en installeert bij die afsluiting. Mogelijk is de permissie `core:window:allow-destroy` nodig in `capabilities/default.json`; bij uitvoering vaststellen.
- `components/ui/UpdateBanner.tsx`: "Nu bijwerken" roept `install()` aan als de download klaar is, anders `downloadAndInstall()` zoals nu.
- `components/settings/GeneralTab.tsx` r.28-30: tekst "Automatisch bijwerken" en knop "Zoek naar updates" die `tv-check-updates` verstuurt.

Bewijs: de checks uit `docs/AUTOMATISCHE-UPDATES.md` (`python3 scripts/test-publish-release.py`, vitest, build, cargo test, xcodebuild test). Met twee echte releases op het dev-kanaal (`dev.xml`, `dev.json`): versie N installeren, N+1 publiceren, app starten, wachten, afsluiten en opnieuw openen; Instellingen toont N+1. Tweede ronde met een lopende opname tijdens het afsluiten: er wordt niet geïnstalleerd. `docs/AUTOMATISCHE-UPDATES.md` bijwerken met het nieuwe gedrag.

### Fase e: privacyverklaring

Er bestaat nog geen privacytekst voor ThoughtVault, in de repo noch op de website. De veelgestelde vragen op de site (`docs/design/high-end-yinga/index.html`) zeggen alleen dat lokale verwerking lokaal blijft; over foutrapporten staat er niets.

- Nieuwe pagina `privacy.html` naast `index.html`, in dezelfde opmaak, met wat ThoughtVault verwerkt (naam, e-mailadres, installatiekenmerk, app-versie, apparaat, klikpad, afgeschermd log), waarvoor (fouten oplossen en meldingen beantwoorden), wat nooit meegaat (opnames, transcripties, notules, titels), waar het staat (n8n01 en de feedback-hub), hoe lang, en hoe je het uitzet of bezwaar maakt. Bewaartermijn: twaalf maanden na het sluiten van een melding.
- Afhankelijkheid buiten dit plan: de feedback-hub ruimt nu niets op (geen opruimtaak in `feedback-hub/backend/src`). Het verwijderen van gesloten meldingen met bijlagen na twaalf maanden wordt een aparte taak in de hub-repo, voor alle aangesloten tools. In die repo is een andere sessie actief; daar eerst afstemmen. Tot die taak af is, ruimt Michel met de hand op.
- Het concept schrijft de uitvoerder; Michel stelt de tekst vast voordat hij live gaat. `scripts/deploy-website.sh` kopieert nu drie vaste bestanden (r.12-14), dus de nieuwe pagina komt in die lijst.
- Link naar de pagina in de voettekst van de site, op het naamscherm en bij de schakelaar in Instellingen (macOS, iOS, Windows).
- Privacylabel in App Store Connect bijwerken met naam en diagnosegegevens, gelijk aan `macos/PrivacyInfo.xcprivacy` uit fase b.

Bewijs: `python3 scripts/check-website.py`, de pagina op 1920, 1440, 1280, 390 en 320 met `pw screenshot`, en de link vanuit elke app opent de pagina. Deze fase hoort bij de voorwaarde voor de pilotstart.

Afronding over alle fasen: besluit vastleggen als DEC-062 in `docs/DECISIONS.md` (hoogste op main is DEC-061; nummer vlak voor gebruik op de remote controleren).

## 6. Dode code die blijft staan

- Backend: `APP/routes/feedback.py`, het model `Feedback` (tabel `feedback`, `APP/models.py` r.652) en de feedbackfuncties in `APP/db_operations.py`. De router blijft geregistreerd (`APP/app.py` r.971 en r.983).
- macOS: het Feedback-tabblad in `macos/Views/AdminView.swift` (o.a. r.1920) en `getAdminFeedback`/`getAdminFeedbackPendingCount` in `macos/Services/APIService.swift` (r.907, r.929).
- macOS: `macos/Services/CrashReporter.swift` (`configure()` wordt nergens aangeroepen), `macos/Services/Analytics.swift` (geen aanroepers), `macos/Views/OnboardingViewiOSStub.swift` (lege extensie). `DebugLogger.swift` blijft, met emoji-niveaus die alleen in DEBUG verschijnen.
- Windows: de feedbackonderdelen van `pages/AdminPage.tsx`, `getFeedback`/`updateFeedback`/`deleteFeedback`/`getFeedbackPendingCount` in `services/api.ts` (r.633-662), en na fase c ook `submitFeedback`, `getMyFeedback`, `getUnreadFeedbackCount`, `markFeedbackRead` (r.930-958) en de types `FeedbackSubmission`/`UserFeedback` in `types.ts` (r.319-333).
- Windows: Rust-command `download_and_run_installer` (`commands/system.rs` r.155), geregistreerd in `lib.rs` maar zonder aanroeper in `windows/src`.

## 7. Open punten voor de eigenaar of de infrastructuur

Opgelost op 10 november:
- De machines. `thoughtvault.yinga.ai` en `feedback.yinga.ai` wijzen in de DNS allebei naar `3.69.205.209`, het adres dat het projectinstructiebestand voor de backend noemt. Website, hub en container staan dus op n8n01. Een tweede domeinnaam is niet nodig: de relay verplaatsen kan later door de Caddy-route aan te passen.
- De doorverwijzing. Die komt in het blok `thoughtvault.yinga.ai` van `/home/michelk/yinga/caddy/Caddyfile` op n8n01 en wordt in fase a gezet, na akkoord van Michel, met een kopie vooraf en `caddy validate` voor het herladen.
- `docs/BACKEND.md` staat bewust buiten de repo (`.gitignore` r.44). Het lokale bestand is de bron voor de deploystappen.
- De privacytekst: er komt een volledige privacyverklaring, zie fase e.
- De cloudsessie "Logbestanden opslag en ophalen" hoort volgens Michel niet bij ThoughtVault. In de repo staat op geen branch of worktree werk aan dit onderwerp.

Nog open:
1. Geeft poort 5678 op n8n01 `/tstudio/api/` door aan de container, en komt het live Caddyfile overeen met `scripts/infra/thoughtvault-releases.caddy`? Niet gecontroleerd. Eerste stap van fase a: het live bestand lezen en één verzoek naar een bestaande route sturen.
2. Bereikt de container de hub? De hub staat op dezelfde machine, maar het is niet getest. In fase a één testverzoek vanuit de container, ook om te kiezen tussen `https://feedback.yinga.ai` en een intern adres zoals ProspectFlow gebruikt.
3. Wijkt de compose op de server af van die in de repo (`env_file: .env`)? Zo ja, dan moeten de twee nieuwe namen ook onder `environment:`.

## 8. Risico's

Het e-mailadres wordt niet gecontroleerd. De hub mailt elk antwoord naar wat de gebruiker heeft ingevuld; een tikfout stuurt Michels antwoord naar een vreemde. Beperking: het adres staat zichtbaar en wijzigbaar in Instellingen, en antwoorden bevatten geen loginhoud.

Het hublimiet is tien nieuwe meldingen per uur per installatie, gedeeld tussen automatische en eigen meldingen, en zestig berichten per uur. Het ontdubbelen houdt herhaalde fouten binnen één ticket; een 429 laat de melding in de wachtrij staan tot later. Een installatie die in een uur meer dan tien verschillende fouten heeft, meldt de rest pas het volgende uur.

Het verplichte scherm staat tussen de gebruiker en de app tot naam en e-mail zijn ingevuld. Wie weigert, kan niet opnemen. Omdat er nog geen gebruikers zijn, raakt dit niemand midden in bestaand werk; de poort blijft wel zo gebouwd dat hij ook na een update verschijnt. Opnameherstel draait door, omdat dat aan de `WindowGroup` hangt. Screenshot- en testroutes (`IOSDebug`-launch-args, `desktop-review.tsx`) hebben een debug-voorvulling nodig, anders blijven ze op dit scherm hangen.
