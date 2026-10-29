# Windows-pilot 1.0.295 — 29 oktober 2026

**Totaal: NO-GO voor uitrol.** Eén ondertekende lokale MSI-kandidaat is gemaakt;
de verplichte schone Defender-/installatieacceptatie en volledige werkketen zijn
nog niet bewezen. GO hieronder geldt uitsluitend voor de genoemde controle.

## Pakket en bron

- Pakketmap: `build/windows-pilot-20261029/`; MSI:
  `ThoughtVault_1.0.295_x64.msi`, **111.144.969 bytes**.
- MSI SHA-256: `c212094768d98ffaa9b76e4fec48bf81e6033f1d2817ca0fe3e57ed4cb95ee8b`.
- Eigen `.sig` SHA-256: `bf4c90a37ad88a152c35a24d2d7c63972f975db1a92ea97fd2c634444f24e328`.
- Exacte pakketbron: `55ecb9077588afaa1559a1d1f9b921c065746f16`; bevat fixcommit
  `b58d3a2c01e7f0cfb8442a186e65ef7f1a21a17a`. Alleen Windows-productversies zijn
  aangepast ten opzichte van de eerdere pilotbron. Bestaande gebruikerswijzigingen
  zijn behouden en niet in deze commit opgenomen.
- Bron-ZIP SHA-256: `ea4a51e949d867b7f4f710e84e674f07e993d93119906e54ca0d5e971469a4eb`.
- Versie 1.0.295 had bij controle geen artifact in de bestaande releasemap, geen
  overeenkomstige Gitea-tag en geen GitHub-release. De Windows-stablefeed op de
  server was 1.0.267. Er is niets gepubliceerd of gepusht.

## Bouw en handtekening

Dalf38 bouwt uit de afzonderlijke `%TEMP%/ThoughtVault-Pilot295/src`-kopie, met
aanwezige npm/Cargo- en WiX-caches. `createUpdaterArtifacts`, publieke sleutel,
productie-ID `nl.prezent.transcript-studio` en updaterendpoint zijn behouden.
MSI- en executableversie zijn 1.0.295; Cargo en `VERSION` komen daarmee overeen.
De npm-packageversie 0.1.0 is de bestaande interne frontendpackage, niet de
Windows-productversie.

De Tauri-releasecompilatie slaagt in **1m34s** en WiX maakt één MSI. De Windows-
opdracht eindigt vervolgens met een fout wegens de daar ontbrekende private key.
Dit is niet als volledig geslaagde Tauri-opdracht geregistreerd. Precies die MSI
is met SHA-256-controle naar de Mac overgebracht en met de bestaande Tauri-signer
en bestaande beveiligde releasekey ondertekend. De key is beschreven in
`docs/AUTOMATISCHE-UPDATES.md`; er is geen sleutel naar Windows gekopieerd.

`verify-updater.py` in de pakketmap verifieert de productie-key-ID, Ed25519-
payloadhandtekening én trusted comment. Een fysiek gewijzigde MSI-testkopie wordt
afgewezen; de tijdelijke negatieve testkopie wordt daarna verwijderd. De
oorspronkelijke MSI en `.sig` blijven behouden. `updater-verification.json` bevat
het resultaat. Windows-uitgeverssignering ontbreekt (`NotSigned`); dit is geen
belofte van een waarschuwingvrije installatie.

## Omgevingen

**Bouw/functionele pc: Dalf38 via bestaande Royal TSX-sessie.** Windows 11 Pro
Education 10.0.22631; bureaublad toont Testmodus. De bestaande hardwaregegevens
(Ryzen 7 5700X3D, 48 GiB RAM) zijn achtergrond uit het verslag van 28 oktober,
geen nieuwe laptopmeting. Het huidige token is niet verhoogd en bevat geen
Administrators-SID.

De alleen-lezen baseline meldt Defender `AMRunningMode: Not running`,
`AntivirusEnabled: false`, `RealTimeProtectionEnabled: false`, zonder beschikbare
Defender-signatureversie/-datum. Security Center registreert Defender en Avast.
Tijdens bediening was tevens een Avast-menu met acht uitgeschakelde schilden
zichtbaar. De agent heeft antivirus, UAC of andere Windows-beveiliging niet
gewijzigd. Een Avast-resultaat op deze pc is geen Defender-acceptatiebewijs.

UAC: `EnableLUA=1`, `ConsentPromptBehaviorAdmin=0`,
`ConsentPromptBehaviorUser=3`. Smart App Control-registrywaarde
`VerifiedAndReputablePolicyState=0`. De gevraagde SmartScreen-registrywaarde
ontbrak; daaruit volgt geen bevestigde effectieve SmartScreen-status. Effectief
bedrijfsbeleid is niet volledig vastgesteld. Herstelpuntinventarisatie gaf
`Access denied`; herstelbaarheid voor een onderbroken update is niet bewezen.

**Schone acceptatieomgeving:** niet beschikbaar. Dalf38 wordt niet gewist,
heringericht of als vervanging voor een representatieve Defender-pc behandeld.

## Controleerbare matrix

Alle pakketgebonden rijen verwijzen naar bovenstaande MSI-hash. Bewijs staat in
de pakketmap, tenzij expliciet als historisch of open aangemerkt.

| Acceptatiepunt | Stand | Omgeving en bewijs |
|---|---|---|
| Bron en eerdere portable | GO | Mac: bronarchief `e2bf26e` opnieuw gehasht; ZIP-CRC en alle 888 hashes uit Windows-manifest gelijk. Beide fixbestanden gelijk aan `b58d3a2`; `local-artifact-verification.json`. MSI 294 blijft herkenbaar apart en bevat de fixes niet. |
| Vastgestelde worker | GO | Worker 9.948.555 bytes, SHA-256 `2de9ea9a870d57b25dc9b7b76d09c4f2aa33364d5f6bb05fc9f9822357cb471a`; bron, bouwscript en dependencymanifest gecontroleerd. Geen workerherbouw. |
| Bouwresources | GO | Dalf38: 885 runtimebestanden gelijk aan portable manifest. VAD LICENSE komt uit de broncommit; alleen LF/CRLF verschilt ten opzichte van de portable (inhoud gelijk). `windows/msi-source-status.txt`. |
| Versie en identiteit | GO | Dalf38: MSI ProductVersion 1.0.295, ALLUSERS=1; ProductName ThoughtVault; productie-ID en opslaglocaties behouden. `windows/msi-properties.json`, `SOURCE.json`. |
| Updaterhandtekening en negatieve proef | GO | Mac: oorspronkelijke releasekey past bij productie-publieke sleutel; MSI en trusted comment geldig; gewijzigde MSI-kopie afgewezen. `updater-verification.json`, `verify-updater.py`. |
| Frontendtests/typecheck | GO | Mac én Dalf38: 45 bestanden / 147 tests, TypeScript/Vite PASS. Bouw draait typecheck ook op de uiteindelijke versie. Logs in `windows/` en pakketroot. |
| Rust-regressies | GO | Dalf38, opnieuw op definitieve bronversie 1.0.295: 36 PASS, 3 ignored, geen resourceoverride. `windows/rust-tests-final.log`. Frontend eveneens opnieuw 147 PASS (`windows/vitest-final.log`). |
| Releasecompilatie/MSI-bundeling | GO | Dalf38: releasecompile en één WiX-MSI geslaagd; afsluitende signingfout apart verklaard en lokaal afgehandeld. `windows/msi-build.log`, `.sig`, verificatie-JSON. |
| Statische runtimecontroles | GO | Dalf38: bestaande `verify-windows-runtime.ps1` voor uiteindelijke hoofd-EXE, bron-Faster Whisper en NeMo met app-local Microsoft-DLL-controle. `windows/runtime-final-*.log`. Geen transcriptie- of antivirus-PASS. |
| MSI-payload | GO | Dalf38: WiX Dark inspecteert de MSI zonder installatie; 888 File-table-items. Exact ingepakte Faster Whisper-worker heeft de vastgestelde SHA-256 en grootte. Hoofd-EXE en NeMo eveneens gehasht; `windows/msi-payload.json`. Geen uitgepakte worker uitgevoerd. |
| Eerdere uitgepakte portable | NO-GO | Dalf38: 887 hashes gelijk, geen gewijzigde bestanden, Faster Whisper-EXE ontbreekt op het pad van de eerdere Avast-blokkade. `windows/windows-portable-integrity.json`. Niet teruggezet, vervangen of vanuit een alternatief pad uitgevoerd. De bewaarde ZIP bevat alle 888 bestanden nog wel. |
| Worker: Defender-bestandsscan én transcriptie | OPEN | Defender draait op Dalf38 niet; representatieve acceptatieomgeving ontbreekt. Geen antivirus-PASS afgeleid uit bouwen, DLL-controles of gewijzigde Avast-instellingen. |
| Geïnstalleerde worker: korte functionele transcriptie | GO | Dalf38: exact geïnstalleerde worker, vier bestaande modelbestanden vooraf SHA-256-gecontroleerd, offline Nederlandse bronfixture uit commit. Exit 0, eindvoortgang 100; Alex en maandag ieder eenmaal herkend. 3,728 s; bemonsterde piek 623.017.984 bytes voor uitsluitend het worker-hoofdproces (geen subprocessen/app/WebView). `windows/installed-worker-test.json`. Geen Defender-, laptop- of lange-inhoudsacceptatie. |
| Eerste inrichting/standaardaccount/UAC | OPEN | MSI is per-machine; beheerdershulp kan nodig zijn. Geen schone installatieproef op deze hash. WebView2-voorwaarde en modellen/provider moeten vooraf worden gecontroleerd. |
| Upgrade 294 → 295 en bestands-/metadatabehoud vóór eerste start | GO | Dalf38: normale `msiexec /passive /norestart`, exit 0; geïnstalleerde versie 1.0.295. Alle 623 Local + 12 Roaming-bestanden vóór én na upgrade gelijk aan verse back-up, inclusief inhoud en CreationTimeUtc/LastWriteTimeUtc. Worker geïnstalleerd met afgesproken hash. `windows/upgrade-result.json`, `windows/upgrade-after-before-first-launch.json`, installatielog. |
| Nieuwe volledige pre-upgradeback-up | GO | App gesloten. Dalf38: `%TEMP%/ThoughtVault-Pilot295/pre-msi295-backup-20261029`, 623 Local + 12 Roaming; alle hashes, CreationTimeUtc en LastWriteTimeUtc gelijk. `windows/pre-upgrade-backup.json`; gebruikersdata en back-up blijven op Dalf38. |
| Onderbroken update en herstel | OPEN | Geen wegwerpomgeving met aangetoond herstelpunt. Geen onderbrekingsproef op de bestaande Dalf38-installatie uitgevoerd. |
| Bronbeperkingen: veilige weigering | GO | Dalf38, geïnstalleerde MSI 295: bestaande lokale Ollama met aanwezig hermes3:8b; fictief record `local-483b76b5-0010-4c97-a0be-803ce0f48250` geregenereerd. UI meldt Mislukt wegens ontbrekende expliciete beperkingen, geen nieuwe notule opgeslagen. De volledige notulenstore is SHA-256-identiek aan de pre-upgradeback-up. `windows/local-notes-rejection.json`. Geen bewezen implementatiefout; controle niet versoepeld. |
| Bruikbare nieuw gegenereerde notulen | NO-GO | De geteste lokale Hermes3-keten levert door die inhoudsafwijzing geen bruikbare nieuwe notule. Geen nieuw providerplatform/model of betaalde cloudverwerking gebruikt. |
| Bewerken, heropenen en exports bestaande QA-notule | GO | Dalf38: uitsluitend fictief QA-record `local-54fbd8b7-b57d-4a5c-9cf3-e0dad5796825` voorzien van marker 29 oktober; opslaan, normale appherstart en marker teruggelezen. TXT 616 bytes teruggelezen. PDF 77.039 bytes lokaal opgeslagen en met Poppler gerenderd: titel, Alex, maandag 10 uur en marker leesbaar. `windows/qa-msi295.txt`, `.pdf`, `qa-msi295-pdf-render.png`. PDF heeft geen extraheerbare tekstlaag; geen zoekbare-PDF-claim. |
| Korte en 45-minutenwerkketen | OPEN | Op deze MSI geen volledige keten met afzonderlijk herkenbare microfoon/gesprek, pauze/hervatten, transcriptie, notulen, bewerken, heropenen en TXT/PDF teruglezen bewezen. |
| Inhoud, doorlooptijd en procesgeheugen | OPEN | Geen nieuwe begin/midden/eind-feitencontrole of volledige procesboommeting op dit pakket; compileertijd is geen transcriptie-/notulentijd. |
| Opnamecrash, leesbare kanalen en notulenbehoud | GO | Dalf38: gecombineerde opname met bestaande fictieve `dutch-qa.wav`, alleen gecontroleerde geïnstalleerde app-PID 18000 geforceerd gestopt. Speler gestopt/disposed. Beide WAVs zonder reparatie leesbaar: microfoon 63,005 s, loopback 48,006 s, 16 kHz mono. Volledige notulenstore SHA-256 gelijk. Herstart toont beide kanalen met duur en herverwerkingsknop. Originelen apart op Dalf38 bewaard. `windows/capture-crash*.json`. De loopbackduur verschilt bij stilte; geen bewezen synchronisatie of positief microfoon-spraakbewijs. |
| Crashaudio herverwerken met de geïnstalleerde worker | GO | Dalf38: bestaande originele loopback-WAV, SHA-256 vooraf gecontroleerd; exact geïnstalleerde worker en dezelfde vier geverifieerde modelbestanden. Exit 0, voortgang 100, Alex/maandag elk eenmaal, 3,990 s en bemonsterde piek 519.925.760 bytes alleen hoofdproces. `windows/crash-reprocess-test.json` en resultaattekst. Geen UI-notulengeneratie of volledige procesboommeting. |
| Verwerkingscrash, foutstatus en volledige UI-herverwerking | OPEN | De opnamecrash is herhaald op 295; onderbreking tijdens transcriptie/notulengeneratie en volledige UI-herverwerking zijn op dit pakket nog niet bewezen. Eerder bewijs van 294/portable blijft achtergrond. |

## Afsluiting

Oorspronkelijke providerkeuze teruggezet naar Ollama Cloud `https://ollama.com`,
`gpt-oss:120b`; opgeslagen sleutel ongemoeid gelaten en geen cloudgeneratie gestart.
De eigen tijdelijke lokale Ollama-server en zijn procesboom zijn gestopt; geen
Ollama-proces achtergebleven. ThoughtVault is normaal afgesloten. `windows/cleanup.json`.
De RDP-mapredirectie is teruggezet naar **None**; audio blijft **Leave at remote
computer**, microfoondoorgifte uit. De sessie is opnieuw verbonden.

## Vervolg en overdracht

Gebruik [WINDOWS-PILOT.md](../WINDOWS-PILOT.md) voor vereisten, pakketinhoud,
modelkeuze, opname, menselijke inhoudscontrole en volledige back-up/herstel.
Eerdere back-ups en afgekeurde MSI/portable-kandidaten blijven apart behouden.
Een verplicht OPEN-punt betekent totaal NO-GO; aanwezigheid van dit MSI/`.sig`-paar
is geen vrijgave naar collega's.

Geen push, publicatie, externe scanupload, betaalde provider, nieuwe sleutel of
model-/toolchaindownload uitgevoerd. Het beveiligings- en inhoudsprobleem is niet
door een nieuwe versie opgelost verklaard.
