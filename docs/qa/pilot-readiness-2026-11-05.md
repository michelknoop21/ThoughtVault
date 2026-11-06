# ThoughtVault pilot — 5 november 2026

## Besluit

**NIET GEREED VOOR UITROL.** Lokale code-integratie en regressietests zijn afgerond;
Windows-native acceptatie, inhoudskwaliteit, herstel en distributie zijn niet bewezen.
Gebruiker heeft iPhone/iPad-acceptatie uitgesteld. Dalf38 wordt uitsluitend via de centrale SSH-route bediend.
Er is niets gepubliceerd, geïnstalleerd op gebruikersapparaten of aan collega's verstuurd.

Actuele Windows-kandidaat: **1.0.300**, broncommit `fef23dd1d8d5df093b1eb17bd7c511e34662b22d`.
Native build, MSI/ICE, 888 payloadhashes en updaterondertekening PASS.
Installatie/rollback en opname-/inhoudsacceptatie blijven OPEN.
Zie [actueel pakketbewijs](dalf38-2026-11-06/msi300/REVIEW.md).
De onderstaande vervolgronden behouden de eerdere waarnemingen en hun eigen versies.

## Kandidaat en herkomst

Werkbranch `codex/pilot-readiness-20261105`, geïsoleerd in
`/Volumes/SSD/codex-worktrees/thoughtvault-pilot-20261105`.
Integreert uitgangscommit `fd98691` met auditbranch `71dab28` (124 ontbrekende commits).
Oorspronkelijke werkmap en ongecommitte gebruikerswijzigingen zijn behouden.
De auditbranch had alleen `.router/` en een sessieverslag ongecommit; deze zijn niet overgenomen.

Conflicten: latere SiriWave/frequentie-implementatie en tests uit auditbranch behouden;
huidige website HTML/CSS/JS en website-inspectiescript uit uitgangsbranch behouden.
NVIDIA-bestanden in de integratie zijn de reeds gecommitte Parakeet-runtime-integratie,
geen losse werkmapexperimenten. Dit blijft een brede integratie die native hertest vereist.

Aanvullende correcties:
- DOMPurify-lockversie bijgewerkt binnen bestaande dependencygrens wegens kritieke auditmelding.
- `testflight.sh [ios|macos|all] --no-upload`: lokale export zonder upload; onbekende argumenten falen.
- `build.sh`: pipefail voorkomt dat een mislukte Xcode-build door `tail` wordt verborgen.
- Swift-testcommando gebruikt het bestaande schema ThoughtVault.
- Verouderde providertest aangepast aan de bestaande gedeelde Ollama lokaal/cloud-keuze.
- Apple-versies gesynchroniseerd met VERSION 1.0.296. Dit is een bronkandidaat,
  niet hetzelfde artifact als de historische MSI 1.0.296. Voor distributie een nieuwe unieke versie vastleggen.

## Actueel bewijs

| Controle | Resultaat | Bewijs / grens |
|---|---|---|
| Windows frontend | PASS | 50 bestanden, 209 tests; 1 opt-in modelkwaliteitstest overgeslagen |
| TypeScript/Vite | PASS | `npm run build`; bundel-/Browserslistwaarschuwingen |
| Productiedependencies | PASS | `npm audit --omit=dev`: nul kwetsbaarheden; development-audit niet schoon |
| Scriptregressies | PASS | `python3 -m unittest discover -s scripts/tests -v`: 8 tests |
| macOS tests | PASS | 69 PASS, 3 SKIP; `/tmp/thoughtvault-pilot-swift-final.log` en xcresult in `/tmp/thoughtvault-pilot-derived/Logs/Test` |
| iOS compilatie | PASS | `/tmp/thoughtvault-pilot-ios.log`; unsigned generic iOS build, vóór uitsluitend Apple-versiesync |
| Native Windows x64 | UNIT PASS / ACCEPTATIE OPEN | Centrale LocalService-job: 36 Rust PASS, 3 ignored; geen MSI/GUI/hardwareacceptatie voor kandidaat |
| iPhone/iPad | UITGESTELD | Expliciete gebruikerskeuze; geen apparaatacceptatie claimen |
| macOS distributie | BLOCKED | Apple Development/Distribution aanwezig, geen Developer ID in actuele identitycheck |
| Website visueel | NOT TESTED | Inspectiescript vereist browsercontext; Node-aanroep was ongeldig, geen productfout bewezen |

De eerste Swift-run vond een verouderde verwachting dat Ollama Cloud een eigen tegel
heeft; de app biedt die via het gedeelde locatiepaneel. Na aanpassing volledige suite groen.
Drie opt-in hardwaretests zijn geen PASS. Bestaande Windows-bewijsstukken gelden uitsluitend
voor hun eigen historische bron/pakket, niet automatisch voor deze integratie.

## Verplichte native matrix

Voer iedere rij afzonderlijk op macOS en Windows uit; iOS/iPadOS volgen later.
Elke uitvoering legt commit/pakkethash, fixture, stappen, werkelijk resultaat en bewijs vast.
Alle onderstaande rijen zijn voor deze kandidaat **NOT TESTED**, tenzij BLOCKED vermeld.

| ID | Scenario / verwacht resultaat |
|---|---|
| N01 | Schone installatie, onboarding, lokale route zonder verplichte login; rechten weigeren en herstellen |
| N02 | Alle navigatie, home-acties, personen, profielen, zoeken/filteren; lege/loading/foutstatus bruikbaar |
| N03 | Microfoon/systeem/gecombineerd waar aangeboden; pauze/hervatten/stop, widget en juiste duur; bron hoorbaar |
| N04 | Alle geclaimde importformaten, stilte, ongeldig bestand, annuleren; bronbestand blijft behouden |
| N05 | Iedere aangeboden engine downloaden/selecteren/herstarten/gebruiken; echte engine-identiteit, geen stille fallback |
| N06 | Transcriptie en notulen met standaard/eigen profiel; brongetrouwe feiten, onzekerheden, bedragen en afspraken |
| N07 | Bewerken/regenereren/heropenen; has_notes consistent, afgewezen concept apart, bestaande inhoud intact |
| N08 | Taken/progress/resultaatlinks; gelijktijdige jobs, fout/annuleren/retry zonder dubbelen of schijnsucces |
| N09 | Bibliotheek en audio, verwijderen met annulering; alle exportformaten inhoudelijk controleren |
| N10 | Instellingen/providerkeuzes en credentials blijven behouden; validatie en annuleren correct |
| N11 | Eigen agenda-event en Obsidian-testmap; ontbrekende toegang BLOCKED |
| N12 | Tien opeenvolgende korte runs, verdeeld over echte opname en import; unieke opslag en heropening |
| N13 | Minimaal één uur opname; volledige audio/tekst, geheugen/procesboommeting over volledige keten |
| N14 | Geïsoleerde netwerk/provider/model/schrijffout; crash/onderbreking; echt hervatten zonder dataverlies |
| N15 | Verse back-up van werkelijk gebruikte stores; upgrade en herstel met tellingen/hashes aantonen |
| N16 | Toetsenbord/focus/toegankelijkheid; Windows 100/125/150%, klein/groot venster; native waveform met bewegend bewijs |
| N17 | Gedownload distributiepakket, identiteit, signing, installatie en rollback; hashes en bron herleidbaar |

## Oorspronkelijke uitvoering van 5 november (historisch)

1. RustDesk-bediening herstellen. Zowel codex-daemon als osascript kregen volgens gebruiker
   Toegankelijkheidstoestemming, maar verse probes blijven -25211 teruggeven. Geen TCC-reset of bypass.
   Herstart host/achtergrondproces via de gebruiker, daarna opnieuw verse observatie.
2. Dalf38 observeren: identiteit, appversie, idle opname/taken en gebruikerswerk vaststellen.
   Geen blind terminaltypen of onderbreken van actieve verwerking.
3. Bestaande Windows-buildworkflow volgen met nieuwe bronmap, source-only ZIP en SHA-256;
   `npm ci`, Vitest, frontendbuild, native Rust-tests en runtime/packageverificatie uitvoeren.
4. Eerst actuele inhoudelijke baseline met synthetische Nederlandse fixtures en bestaande provider.
   Historische Opname10-afwijzing blijft blocker; modelcontrole-hulpmiddeltests bewijzen geen inhoudskwaliteit.
   Productfix pas na reproduceerbare baseline; geen privé-audio of credentials in bewijs.
5. Alleen na pakketchecks, idle app en geverifieerde back-up installeren. Matrix invullen;
   huidige checks niet vervangen door historische PASS. Signing en herstel blijven aparte gates.

## Collega-handleiding — concept, nog niet verspreiden

Installeer uitsluitend het vrijgegeven pakket met bijbehorende versie/hash.
Maak eerst een korte eigen testopname, controleer transcript en notulen tegen de opname,
heropen het resultaat na herstart en probeer export. Controleer namen, cijfers en afspraken
zelf vóór gebruik. Meld platform, versie, stappen en foutmelding; stuur geen vertrouwelijke
opname mee. Stop bij verdwenen gegevens of vastgelopen opname en bewaar de bronbestanden.
Pilot: 3–5 collega's, vijf werkdagen, pas na afzonderlijke vrijgave en groene native gates.

## Vervolg 5 november, 11:40–11:45

Toegankelijkheid is inmiddels bruikbaar na toestemming voor Supacode: verse
System Events-proef kan RustDesk-venster `Dalf38@desktop-98b3ahb` lezen.
Remote desktop zichtbaar; er is een aparte PowerShell-tab geopend naast de bestaande
gebruikerswerk-tab. Geen installatie, providerwijziging of build uitgevoerd.
Muisinvoer via native events werkt; toetsenbordinvoer kwam onvolledig/afwijkend aan.
Een onverwachte, niet uitgevoerde commandoregel is waargenomen. Invoer gestopt en
exclusief gebruik van deze remote sessie bij de gebruiker nagevraagd. Native
appversie, idle-status en Windows-kandidaatacceptatie blijven onbewezen.

## Vervolg 5 november — Royal TSX en directe bouwverbinding

Royal TSX `Dalf38 VPN` bereikt de bestaande desktop. Twee navigatieklikken
openen Instellingen en Algemeen; geïnstalleerd: ThoughtVault 1.0.295 Windows.
Korte PowerShell-invoer (`Get-Location`) en een directorylisting werken, maar
langere invoer raakt vervormd en opent soms Windows-sneltoetsen. Geen kandidaat
geïnstalleerd; geen nieuwe native PASS afgeleid uit deze bediening.
De eerder onverwachte tekst bewijst geen tweede gebruiker: gebruiker meldt
uitsluitend lokaal MacBook-gebruik; onze invoerroute is aantoonbaar onbetrouwbaar.

Bestaande SSH-alias `windsurf` (Dalf38, poort 2222) werkt met bestaande sleutel.
`hostname`: DESKTOP-98B3AHB; account: desktop-98b3ahb/developer.
Node, npm en Git zijn bereikbaar. Cargo is niet op PATH of onder
C:/Users/developer/.cargo/bin/cargo.exe aangetroffen. Toegang tot Michels
persoonlijke Temp-map is geweigerd; geen rechtenwijziging uitgevoerd.

Uitvoeringsroute:
1. SSH voor bronoverdracht, hashes, bouwen en testlogs; Royal TSX voor app-UI.
2. Aparte bouwmap onder developer; aanwezige Rust/MSVC/runtime-caches inventariseren.
   Ontbrekende toolchain expliciet vaststellen voordat installatie wordt voorgesteld.
3. Unieke kandidaatversie, gehashte bronkopie, frontend- en Rust-tests, pakketbouw.
4. Back-up en upgradecontrole uitvoeren in de interactieve gebruikerssessie;
   SSH-account heeft geen bewezen toegang tot de werkelijke gebruikersstore.
5. Native matrix uitvoeren, blockers oplossen, pas daarna pilotpakket vrijgeven.

## Centrale beheerlaag — werkende MacBook-toegang en bouwidentiteit

De MacBook gebruikt nu alias `dalf38` met eigen sleutel (geen private sleutel in
repo/bewijs). ED25519-serverfingerprint komt overeen met de door gebruiker
opgegeven `SHA256:ZdwqpVFXsP/AWPN8Apfs3SSoMK0v6Wle1tl95a1C0zY`.
Centrale README gelezen; `dalf.ps1 status` exit 0 als niet-verhoogde developer.
Geen SSH-server, beheeraccount of centrale beheercode gewijzigd.

Gebruiker heeft een afzonderlijke Rust-toolchain onder `C:\Dalf38\tools`
expliciet goedgekeurd. Installatie via centrale LocalService-job
`f2833ec34a7e43d1866fe2bbddc90c29` exit 0: rustc/cargo 1.99.1.
CARGO_HOME=`C:\Dalf38\tools\cargo`, RUSTUP_HOME=`C:\Dalf38\tools\rustup`.
Installer SHA-256 gecontroleerd tegen de officiële rustup-download:
`38027d51d69a5d05493627a0634dbea52d6cd793c8f072d2373d3f4163eec7db`.
Geen algemene PATH-wijziging en geen persoonlijke toolchain/cache gedeeld.

213 gehashte bronbestanden uit de getrackte Windows-map van kandidaatcommit
6b31ac7 aangeleverd; SOURCE.json registreert de volledige broncommit.
Project `thoughtvault-pilot1105-v2`: npm ci + TypeScript/Vite-build via
LocalService geslaagd, job `748c988634104ad4aca0e82e7aa9ef22`, exit 0.
Eerste opdracht met cmd.exe-argumentketen faalde op syntaxis; de werkende route
gebruikt een PowerShell-bestand en bewaart iedere native exitcode.

Project `thoughtvault-native1105`, job `1c9a3ba1cb3f4a6fa433bb4615490097`:
opgeschoonde PATH uitsluitend binnen de job, bestaande VsDevCmd.bat gebruikt.
Rust/MSVC-smoke compileert, linkt en voert smoke.exe uit met zichtbare PASS.
Dit is nog geen geslaagde ThoughtVault-native build. Cargo-test en frontendtest
`43188e8476494f6d97c3b713c9fbccb3` waren bij deze notitie nog actief.
Native project gebruikt voor deze proef de actie build om cargo test te starten;
het standaard testveld van deze tijdelijke registratie is niet geaccepteerd.

Bewijs en uitgevoerde jobscripts: `docs/qa/dalf38-2026-11-05/`.
Er is geen MSI gebouwd of geïnstalleerd en geen distributie uitgevoerd.

### Efficiënte frontendketen

Losse testjob na npm ci blijkt langdurig in bronhashing te blijven; annulering
is aangevraagd, maar was nog niet afgehandeld. Niet als test-PASS tellen.
Nieuwe schone bronmap `thoughtvault-pilot1105-v3` voert npm ci, Vitest en Vite
in één centrale buildactie uit, met exitcodecontrole na iedere stap. Job:
`b0b0f347297c44778f116a9460158f02`. Bronhash vóór dependency-installatie:
`06ae18a8c8cafa160e9fefe7b05c02ba59e708e83cc305d460f225e0dc0676f0`.
Deze aanpassing raakt uitsluitend de projectaanlevering; centrale beheerlaag
blijft ongewijzigd.

### Herstel van bronaanlevering en native cache

Frontendjob 519eb4556f0a4e598ea2dc4bad572f9e: 208 PASS, 1 SKIP, één
testbestand faalt door ontbrekende gedeelde tests/fixtures/waveform-reference.json.
Aanleverfout: Windows-map was uitgevlakt. Project thoughtvault-windows1105
behoudt nu windows/ plus de getrackte tests/fixtures/. Geen app-/testcode gewijzigd.
Nieuwe gecombineerde test/buildjob: 46a3d8c218a44b4f97a90b6e160ef4b1.

Eerste cargo-testjob exit 101 wegens ontbrekende niet-getrackte runtimes.
Volgende job verifieerde 885 bestanden uit de bestaande installatie met SHA-256,
maar exit 101 wegens absolute oude Tauri-buildpaden na cacheverplaatsing.
Nieuwe job 5c68cf14ee1b43a388095a34f94be427 maakt alleen de Tauri-packagecache
schoon en herbouwt die. CARGO_TARGET_DIR staat buiten de bronmap; bestaande
CMake en LLVM zijn uitsluitend op job-PATH gezet. Geen aanvullende toolchain
geïnstalleerd, geen runtime gedownload, geen quarantainemateriaal hersteld.

Annulering van job 43188e8476494f6d97c3b713c9fbccb3 uiteindelijk bevestigd
(exit 1223); ruim 17 minuten bronhashing. Annulering was tijdens hashing niet
responsief. Centrale beheercode is niet gewijzigd.

### Frontend definitief geverifieerd op Dalf38

Job 46a3d8c218a44b4f97a90b6e160ef4b1, project thoughtvault-windows1105:
50 testbestanden PASS, 209 tests PASS, één opt-in SKIP. TypeScript/Vite-build
geslaagd, job exit 0. Alle 12 frontendartifacts via SCP opgehaald en lokale
SHA-256/lengte gelijk aan het centrale artifactmanifest. Logs in
`dalf38-2026-11-05/frontend-final`.

Native job 5c68cf14ee1b43a388095a34f94be427 faalde nog op ontbrekende
root-fixture envelope-fixture.json en frontendDist. Dit waren aanleverfouten.
Project thoughtvault-native-canonical1105 behoudt de repositorystructuur en
gebruikt de 12 geverifieerde frontendartifacts van bovengenoemde job. Alleen
de eigen app moet daardoor opnieuw worden gecompileerd. Alle aangeboden
getrackte broncode blijft gebaseerd op dezelfde kandidaatcommit.

### Native eindresultaat en runtimecorrectie

Centrale testjob `5e0479f3e8e643d4a14bdda80dc5c3c3` slaagt met exit 0:
36 Rust-tests PASS, 3 ignored; geen falende tests. Bronhash
`49d659694d977543e8d6de84eb3a2202963667a8434c837f3ba3d92cb19f9df6`.
Logs en 885 runtimehashes zijn teruggehaald in `dalf38-2026-11-05/native-final`
en `resource-provenance.json`. Hardware-/modeltests blijven expliciet OPEN.

Na herstel van de bronaanlevering trad een echte native-linkfout op: Whisper
werd met DLL-runtimes gebouwd terwijl Rust crt-static gebruikt. De gegenereerde
Visual Studio-projecten toonden MultiThreadedDLL/DebugDLL ondanks de bestaande
CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded. whisper.cpp vraagt CMake 3.5 aan;
CMake-policy CMP0091 OLD negeert die runtimekeuze. De geïnstalleerde officiële
CMake-documentatie bevestigt dit gedrag. Hertest met
CMAKE_POLICY_DEFAULT_CMP0091=NEW en uitsluitend een herbouw van whisper-rs-sys
slaagt. Dezelfde instelling is toegevoegd aan windows/.cargo/config.toml,
zodat de correctie niet afhankelijk is van deze ene jobomgeving. De groene
job gebruikte de instelling als expliciete jobvariabele; geen andere appcode
of testverwachting is aangepast om de tests groen te maken.

Werkende centrale projecten: thoughtvault-windows1105 (frontendtest/build) en
thoughtvault-native-canonical1105 (native tests met vastgelegde frontendartifacts).
Scripts en definities staan naast het bewijs. Eerdere pilot1105/v2/v3/native1105
registraties zijn tussenproeven, geen vrijgegeven buildroutes. Voor herhaling
vooraf schoon importeren: dependencies/resultaten in een bestaande bronmap
kunnen de centrale bronhashing langdurig vertragen. Centrale beheercode bleef
ongewijzigd. De schone Rust/Cargo-toolchain staat centraal onder C:/Dalf38/tools;
compiler-PATH/MSVC-omgeving wordt uitsluitend per job ingesteld.

Nog uit te voeren vóór uitrol: unieke releaseversie, MSI/signature, verse
back-up/upgrade/herstel, native matrix incl. echte opname en inhoudskwaliteit,
en afzonderlijke distributievrijgave. Deze tests zijn geen volledige releaseacceptatie.

### MSI 1.0.297 en gecontroleerde acceptatievoorbereiding

Unieke kandidaatversie 1.0.297, productbron `6ff05811314086abff94f1398dab973545725866`.
Centrale projectregistratie `thoughtvault-msi1105`; actuele bouwjob
`11f72adb15b34c80813aa5cb00023f03`, bronmanifesthash
`2632c5cf68af7c3e6a3d1e8a8f2bb737f6aa757a2a8246dbd4181609f24dec49`.
Deze aanlevering bevat de gecommitte CMP0091-correctie. De actuele job heeft
209 frontendtests PASS, één opt-in SKIP en een geslaagde frontendbuild;
releasecompilatie is bij deze notitie nog actief. Geen MSI-PASS of installatieclaim.
Aanwezige WiX 3.14 uit C:/tvb-20261001 wordt per bestand hashgelijk naar de
centrale targetcache gekopieerd; geen nieuwe WiX-installatie.

Verse back-up in de echte michel-sessie, app gesloten: 616 Local-bestanden
(1.225.797.686 bytes) en 12 Roaming-bestanden (6.464.631.527 bytes). Bron vóór/na
kopiëren en back-up hebben gelijke hashes, grootte en beide tijdstempels.
Gebruikersinhoud en volledige manifests blijven uitsluitend op Dalf38. Back-up:
C:/Users/michel/AppData/Local/Temp/ThoughtVault297-backup-20261105-143300.
Dit is kopiebewijs; daadwerkelijke herstel-/rollbackacceptatie blijft open.
De oorspronkelijke MSI 1.0.295 is teruggevonden, apart bewaard en heeft dezelfde
SHA-256 als het historische gecontroleerde pakket: c212094768d98ffaa9b76e4fec48bf81e6033f1d2817ca0fe3e57ed4cb95ee8b.
Negen bestaande modelbestanden zijn geïnventariseerd/gehasht; niets gedownload.

Een oude losse `dalf.ps1 logs -Id ad615a30c16140bdbb103ec0148a5e5e`-client,
PID 31896, gestart 12:38:46 UTC, gebruikte circa 33 GB RAM. Commandopad,
actie, job-ID en starttijd zijn via alleen-lezen procesquery bevestigd vóór
uitsluitend die client werd gestopt. Dispatcher PID 8904 en workers bleven intact;
heartbeat gecontroleerd en PowerShell-geheugen daarna weer normaal. De diepe
JSON-serialisatie van door Get-Content gedecoreerde strings is een vermoede
verklaring, geen bewezen/fixeerde centrale root cause. Gebruik voorlopig SCP of
direct Get-Content voor logbestanden; centrale beheercode is niet gewijzigd.
Eerste bouwpoging abb20637a3754496a0bf4aef736ca057 bewust geannuleerd (1223).
Huidige helper begrenst Vitest op twee workers en Cargo op twee buildtaken.

Bestaande updaterkey op de Mac gecontroleerd met een synthetisch proefbestand:
payload en trusted comment geldig, gewijzigde payload en comment afgewezen.
Dit is nog geen handtekeningbewijs voor de toekomstige MSI. Synthese met de
reeds geïnstalleerde Nederlandse Xander-stem levert een 29,89s fictieve
Waddenspoor-fixture; PCM 16kHz mono i16 en bronhash gecontroleerd. Nog niet als
opname-, ASR- of inhoudsacceptatie tellen.

Runtimeverificatiescript vindt nu de bestaande VS2022 BuildTools ook wanneer
vswhere geen registratie teruggeeft. De fallback is daadwerkelijk op de
geïnstalleerde 1.0.295 gecontroleerd; geen afzonderlijke VC++ runtime vereist.
Nieuwe kandidaat moet dezelfde controle nog doorlopen. Installatie-/rollbackscript
is geparseerd; uitvoering en gegevensbehoud blijven open tot het MSI/handtekeningpaar
is geverifieerd. Helpers en voorbereidende bewijsstukken: dalf38-2026-11-05/msi297/.

### Afwijzing 297/298 en actuele kandidaat 299

Native build 297 slaagde, maar LocalService kon Windows Installer niet bereiken
voor WiX ICE-validatie (LGHT0217). Uitgebreide pakketjob
848edabfb1d645b6a9df81758eb03f0a bevestigde die concrete fout. Geen validatie
uitgeschakeld, geen service/ACL/SSH-configuratie gewijzigd. Laatste WiX-stap in de
bestaande interactieve michel-sessie met dezelfde inputs slaagde (exit 0), met
bewaarde ICE-templatewaarschuwingen. MSI 297 is ondertekend en cryptografisch
geverifieerd, maar vervolgens **AFGEWEZEN** wegens meegebundelde read_token.exe.
Deze bestaande, ongebruikte ontwikkelhulp print een opgeslagen credential.
De helper is niet uitgevoerd; geen token opgevraagd. Hij is ook aangetroffen in
de bestaande 1.0.295-installatie. Nog geen upgrade uitgevoerd.

Kandidaat 298 voegde autobins=false toe (3fe7815). Centrale job
2c17e207d4784332860a2c58362efd40 slaagde: 209 frontendtests PASS, 1 SKIP,
frontendbuild en native releasebuild PASS. Cargo-metadata bevatte alleen
thoughtvault. Tauri bundle onder michel maakte de MSI met ICE-validatie en
faalde daarna uitsluitend op ontbrekende Windows-private updaterkey. Op de Mac
ondertekend en cryptografisch gecontroleerd. Payloadcontrole wees ook deze MSI
**AF**: Tauri's gegenereerde main.wxs bevatte nog een read_token-component.
Cargo-metadata alleen is dus onvoldoende pakketbewijs. Beide afgewezen MSI/.sig-paren
blijven apart onder build/windows-pilot-20261105/rejected-1.0.297 en rejected-1.0.298;
geen daarvan is geïnstalleerd of gepubliceerd.

De native EXE verschilt legitiem van het MSI-exemplaar door precies drie bytes
in Tauri's __TAURI_BUNDLE_TYPE_VAR_UNK-marker (UNK naar MSI). Alle overige bytes
zijn volledig vergeleken en gelijk; tauri-utils 2.8.3/src/platform.rs:349–359
bevestigt de marker. Payloadhashcontrole normaliseert uitsluitend deze bekende
bundelmarker; geen algemene uitzondering op binary-integriteit. 885 runtimefiles
moeten daarnaast afzonderlijk hashgelijk zijn en onverwachte payload wordt afgewezen.

De ongebruikte helperbron is nu verwijderd in commit
870c3f93f75620f4a932f6cacf595f7ce2850aea; unieke kandidaat **1.0.299**.
Centrale buildjob 18916d4c4d5b4251bfeb9a9f7f8074ee was bij deze notitie actief.
Frontend wordt alleen herbouwd: de helper vergelijkt de frontendbronbestanden
met de 209-PASS-baseline van job 2c17e207d4784332860a2c58362efd40 voordat de
ongewijzigde frontendteststatus wordt hergebruikt. Cargo-binarycheck, native
releasebuild en volledige nieuwe MSI-payloadcontrole blijven verplicht.
Installatie, rollback, daadwerkelijk herstel en opname-/inhoudsacceptatie zijn
nog steeds OPEN. Windows Sandbox is niet aanwezig; Dalf38 is een bestaande
gebruikersinstallatie en bewijst geen schone OS-installatie.

### Uitsluitend SSH — actuele uitvoergrens

Gebruiker heeft verduidelijkt dat verdere uitvoering uitsluitend via SSH moet
lopen. Computeruse is gestopt. Royal TSX was tijdelijk onzichtbaar voor de
schermtool en werd door gebruiker heropend; er is daarna alleen het pad naar
het 299-pakketscript ingevuld, niet uitgevoerd. Geen installatie gestart.

Job 18916d4c4d5b4251bfeb9a9f7f8074ee is inmiddels geslaagd, exit 0; native 299
gebouwd en runtimecontrole geslaagd. De nieuwe installerdefinitie verwijst niet
meer naar read_token, terwijl de oude binary nog in de cache staat. Definitieve
299-MSI en payloadacceptatie blijven open. Ook een rechtstreekse niet-verhoogde
SSH-pakketpoging faalt op Windows Installer/ICE-toegang. De bestaande centrale
laag biedt uitsluitend een vaste sessieprobe, geen installatie-/interactieve
acceptatieacties. Deze grens is beschreven in
[dalf38-ssh-acceptance-gap-2026-11-05.md](dalf38-ssh-acceptance-gap-2026-11-05.md).
Geen Windows-rechten/taakdefinities, centrale code of SSH-instellingen gewijzigd.

### Centrale MSI-route opgelost; ondertekening en waarschuwingen beoordeeld

De beheerder heeft de vaste centrale MSI-taak toegevoegd. Job
39b7f1a680c14372846bd1ca05e3cd4a slaagde, exit 0; ICE-validatie en 887 payloadhashes
PASS. Exact MSI 1.0.299 met SHA-256
b18758ab9ea2084d99f25b770a86cca3c333f5e235288f9022172a8f20647502
is via SSH opgehaald, op de Mac met de bestaande updaterkey ondertekend en
cryptografisch geverifieerd, inclusief negatieve payload-/commentaarproeven.
Ondertekend paar op Dalf38: C:/Dalf38/incoming/thoughtvault-1-0-299-signed/.
Transferhashes en teruggehaalde signature opnieuw gecontroleerd.

ICE57 is bevestigd als gemengde gebruikers-/machinebronnen in RegistryEntries
én CMP_UninstallShortcut; niet afgetekend voor brede uitrol. ICE61 is verklaard
door AllowDowngrades=yes, maar vereist expliciet upgradebeleid en bewezen
gegevenscompatibiliteit/rollback. Het log bevat daarnaast ICE03 en ICE40; hun
installatie-/herinstallatiepaden blijven onderdeel van de acceptatie. Geen
waarschuwing onderdrukt en geen template-/configwijziging in dit pakket.
Beoordeling en bewijs: [MSI-review](dalf38-2026-11-05/msi299-central/REVIEW.md).

Geïnstalleerd blijft 1.0.295. Niets geïnstalleerd of gepubliceerd. Updater-signature
is geen Authenticode: Windows rapporteert NotSigned. Installatie, rollback,
gegevensherstel en opname-/inhoudsacceptatie zijn niet door de pakketvalidatie
vervangen. De eerdere blokkade van de SSH-MSI-route is hiermee opgelost;
algemene uitrol blijft NO-GO.

### 6 november — installerfix 1.0.300 en geslaagde native build

De vaste upstream-WiX-template is met minimale wijzigingen opgenomen: HKLM voor
het machinecomponent, verwijderde gedeelde uninstallshortcut, geen automatische
downgrade/gelijkversie-upgrade en geen geforceerde REINSTALLMODE. Bestaande
product-ID, UpgradeCode, updaterkey, resources en gebruikersopslag blijven behouden.
De twee oude HKCU-padzoekopdrachten blijven als upgradecompatibiliteit aanwezig;
het nieuwe HKLM-pad heeft voorrang. De upstreamlicentie is als resource toegevoegd.

11 scripttests PASS; de scope-regressietest faalt aantoonbaar op de oorspronkelijke
upstreamtemplate. Native x64-job `6432b5df2af247978710b98664a5df68` PASS (exit 0).
De bronaanlevering bevat 223 gehashte bestanden. 173 frontendinputs komen overeen
met de eerder gecontroleerde 209-PASS-baseline; frontend opnieuw gebouwd.
MSI-aanvraag `2a1f78ee9b9d4e888094bc5982e7412b` wacht op lokale
snapshotvoorbereiding/goedkeuring volgens de centrale handleiding.

Vervolg: echte MSI/ICE- en payloadcontrole, exacte MSI op Mac ondertekenen;
daarna afzonderlijke installatie/rollback en native opname-/inhoudsacceptatie.
De huidige centrale taak installeert niets. Geen GUI-bediening hervatten of de
verpakkingstaak gebruiken als willekeurige uitvoerbrug naar een ander account.

### 6 november — MSI 1.0.300 gevalideerd en ondertekend

MSI-job `2a1f78ee9b9d4e888094bc5982e7412b` exit 0; 888 payloads geverifieerd,
geen read_token. ICE57/ICE61/ICE40 verdwenen; ICE03 voor WebView2-bootstrapper
blijft. Exact MSI SHA-256 `a1ac99e94ba06f1f5a062068ae95df099884ffe910c3e8cb579a37c034a40912`
is op de Mac ondertekend en cryptografisch geverifieerd, inclusief afwijzing van
gewijzigde payload/commentaar. Ondertekend paar terug op Dalf38 met hashcontrole.
Geïnstalleerde versie via SSH blijft 1.0.295. Zie actueel pakketbewijs bovenaan.

Gebruiker wil geen handmatige snapshotgoedkeuringen meer. De bestaande centrale
beheerbron is apart gekopieerd met behoud van Git-historie. Een beperkte automatische
route wordt voorbereid; geen blijvend verhoogde broker, nieuwe SSH-ingang of
projectgebonden beheerlaag. Centrale productiecode/taak/policy is nog niet gewijzigd.
