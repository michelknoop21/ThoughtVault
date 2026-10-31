# Windows-pilot 1.0.295 — 29 oktober 2026

## Actuele vervolgkandidaat — 30 oktober

Nieuwe kandidaat **1.0.296**, bron `132b9e190ff56e6529b10e4c52f5fafe9a6c97d8`,
staat in `build/windows-pilot-20261030/`. MSI SHA-256:
`af178ed1ecff90e0939959f666124b870c499316c7f42105922dfd2111141aa2`.
Bedragfix, aanvullende bron-/notulevalidatie en apart conceptbehoud zijn gebouwd
via Dalf38; oorspronkelijke updaterhandtekening en negatieve verificatie geldig.
206 frontendtests op Mac en Windows; Windows Rust 36 geslaagd en 3 bestaande
ignored; alle 886 verpakte resources en drie runtimecontroles gecontroleerd.
Zie [validatie en grenzen](windows-validation-2026-10-30.md) en
`build/windows-pilot-20261030/BEWIJSRAPPORT.md` voor huidige eigenaren en gates.

**Uitrol blijft NO-GO.** Inmiddels zijn upgrade naar 1.0.296, Defender-scans,
gegevensbehoud en normale herstart bewezen in de bestaande ARM64-Parallels-VM.
De Dennenbrug-proef is veilig afgewezen met apart conceptbehoud. De daarna
uitgevoerde Opname10-proef (eerste minuut) levert echter een geaccepteerde notule
met stellige numerieke invulling van onbegrijpelijke bronpassages. Dit is geen
kwaliteits-GO; het historische auditantwoord ontbreekt. Werkelijke waargenomen
import-tot-opslagtijd is circa 906 seconden; de procesmeting eindigde vóór de
volledige verwerking en bewijst geen volledige ketenpiek.

Mac-vervolgonderzoek: alle 26 gedeelde bewijsbestanden hashgelijk; screenshot
daadwerkelijk bekeken. Vier vaste gevallen door de echte productie-auditprompt
voorbereid, nul providercalls. QA-gate en zelftests toegevoegd: 209 frontendtests
geslaagd, één standaard overgeslagen opt-in prepare/replay-proef; de TypeScript-
gate afzonderlijk strict getypecheckt. Dit zijn hulpmiddeltests, geen echte
modelantwoorden. Geen productfix of nieuwe kandidaat zonder echte falende baseline.
Zie `windows/src/services/__tests__/qa-short-quality/README.md` en gedeeld
`RESULTATEN/MAC-OPNAME10-AUDIT-20261030/MAC-ONDERZOEK.md`.

De actuele gedeelde matrix onderscheidt beperkte proeflevering voor korte opnames
van algemene uitrol. Ook de beperkte proef blijft NO-GO zolang inhoudskwaliteit,
echte gebruikersronde, toepasselijke native-x64-proef en veilig herstel ontbreken.
Brede duur-/crash-/upgradeonderbrekingsacceptatie blijft afzonderlijk open voor
algemene uitrol. Michel stelt geluidsherstel uit; geen nieuwe luisterronde gevraagd.
Onderstaande resultaten blijven historisch bewijs voor exact MSI 1.0.295.

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

## Aanvullende Parallels-proef — afzonderlijk acceptatiespoor

Uitsluitend hetzelfde MSI/`.sig`-paar wordt getest; geen bouw in Parallels.
Windows heeft beide bestanden naar de lokale QA-map gekopieerd en weer terug.
Grootte en beide SHA-256-hashes zijn gelijk. De retourkopie is op de Mac opnieuw
cryptografisch geverifieerd met de productie-updaterkey, inclusief trusted comment
en afwijzing van een fysiek gewijzigde MSI-testkopie.
`parallels/guest-roundtrip-updater-verification.json` en `opdracht2-kandidaat.json`.

De bestaande VM `Windows 11` (ID `f18536f1-97e4-422d-bd5c-54c09d0e33d8`)
draait Windows 11 Pro 10.0.26100, build 26100, **ARM64** volgens Windows zelf.
Vier virtuele Apple Silicon-processors, 8.583.708.672 bytes RAM en 234.883.624.960
bytes vrij op C: bij inventarisatie. Dit is een bestaande gebruikers-VM met
ThoughtVault 1.0.262, WebView2 156.0.4314.50 en bestaande appgegevens: **geen
schone installatieomgeving**. Een x64-proef hier betreft emulatie op ARM64,
geen native x64-laptopacceptatie. `windows.json`, `opdracht2-inventarisatie.json`
en `relevante-apps.json` in `parallels/`.

Het interactieve token is niet verhoogd; Explorer draait in dezelfde sessie.
UAC: EnableLUA=1, ConsentPromptBehaviorAdmin=5, ConsentPromptBehaviorUser=3,
PromptOnSecureDesktop=0. De gecontroleerde SmartScreen-registrywaarde ontbreekt:
effectieve status OPEN. Smart App Control-registrywaarde is 2; geen UI-verificatie.
Het opgevraagde AppLocker-XML bevat geen regels. Geselecteerde afwezige
beleidswaarden bewijzen niet dat al het effectieve bedrijfsbeleid bekend is.
Geen beveiligingsinstelling of execution policy gewijzigd.

Defender meldt Normal, actieve antivirus, realtime-, gedrags- en tamperbescherming.
AV/NIS-definities 1.463.22.0, bijgewerkt 29 oktober 04:53:57 UTC, leeftijd 0.
Deze baseline is geen bewijs van een voltooide scan of werkelijke transcriptie.
`parallels/defender.json`.

Vóór installatie én Codex-installatie is via Parallels de snapshot
`ThoughtVault-pre-MSI295-20261029` gemaakt (ID
`b303b91e-4d52-4d44-a210-8c458e80ca58`, geregistreerd 29 oktober 10:52:40).
Snapshotmetadata en hostconfiguratie staan in `parallels/` in de pakketmap.
Daadwerkelijk terugzetten is niet getest; deze gebruikers-VM wordt niet voor
onderbrekingsproeven gebruikt.

Daarnaast is met gesloten app een volledige lokale veiligheidskopie van beide
appmappen gemaakt: 283 Local- en 2 Roaming-bestanden. Bron vóór/na en kopie hebben
gelijke aantallen, SHA-256, grootte, CreationTimeUtc en LastWriteTimeUtc; geen
ontbrekende of extra bestanden. Geen gebruikersdata naar de Mac gekopieerd.
Dit is kopiebewijs, nog geen herstelbewijs. `parallels/opdracht2-backup.json`.

De normale upgrade van 1.0.262 naar 1.0.295 eindigt met **msiexec exitcode 0**
(11:45:18–11:45:28 CET), zonder vereiste herstart. De geïnstalleerde app meldt
FileVersion/ProductVersion 1.0.295. De geïnstalleerde worker is exact 9.948.555 bytes
met de afgesproken SHA-256 `2de9ea9a870d57b25dc9b7b76d09c4f2aa33364d5f6bb05fc9f9822357cb471a`.
MSI, app en worker zijn Authenticode NotSigned. De app bleef tijdens installatie
zelf gesloten. Vóór de eerste appstart zijn alle 285 appdatabestanden opnieuw
vergeleken: hash, grootte en beide tijdstempels gelijk aan de veiligheidskopie.
`opdracht3-installatie.json`, `opdracht3-msi-installatie-technisch.log`,
`opdracht3-bestanden-na.json` en `opdracht3-databehoud.json`.

Met Defender Normal en realtimebescherming actief zijn twee CustomScans
voltooid: MSI 11:44:03–11:44:13 (scan-ID 85AE40F6-3A83-43E1-8C77-6AB87FE6F16D)
en geïnstalleerde appmap inclusief worker 11:46:41–11:46:43 (scan-ID
3722C91A-10AF-4598-AB80-4FEDC562BFB0). Operational-events 1000/1001 bevestigen
start en voltooiing van beide scans; geen gekoppelde fout/annulering en nul
relevante detecties of detectie-events tot 11:47:47. Defender en workerhash zijn
na afloop ongewijzigd. **Bestandsscanacceptatie op deze ARM64-VM**, geen bewijs
van werkelijke transcriptie. `opdracht3-*-scan-bewijs.json`,
`opdracht3-defender-eind.json` en `opdracht3-eindcontrole.json`.

Na installatie heeft de Windows-sessie de geïnstalleerde app gestart. De
hoofdsessie heeft het echte Parallels-scherm bekeken: het beginscherm is zichtbaar,
zonder loginwizard of zichtbare fout, opnametimer 0:00 en 'Microfoon gevonden'.
Dit bewijst geen microfoonmachtiging of opgenomen audio. Het is een bestaand
profiel; eerste inrichting vanuit een leeg standaardaccount blijft OPEN.
De exacte worker heeft uitsluitend `--help` uitgevoerd: 12:51:01 CET,
exitcode 0, dezelfde SHA-256 en grootte. De eerste registratie had een null-exitcode;
daarom zijn beide oorspronkelijke resultaten bewaard en is alleen dezelfde
helpaanroep herhaald met directe proces-exitregistratie. Defender bleef Normal
met realtimebescherming en definities 1.463.22.0; nul relevante detecties/events
sinds de fasevoorcontrole. Dit bewijst loadercompatibiliteit onder ARM64-emulatie,
geen daadwerkelijke transcriptie. Bewijs: `parallels/OPDRACHT4.md`,
`opdracht4-workerstart-herhaling.json`, stdout/stderr en `opdracht4-eindcontrole.json`.

Het eerder onveranderde scherm is geen bewezen VM- of appcrash: de Windows-agent
voltooide daarna zijn rapportoverdracht en zestig wachtcontroles tot 13:05:46 CET.
Michel meldt vervolgens dat de omgeving nog draait. Er is geen reset of crashactie
uitgevoerd. De hostbediening geeft bij de volgende poging `Sky Computer Use native
pipe startup failed`; daarmee is geen nieuwe visuele beoordeling beschikbaar.
De agent stopte zijn afgesproken wachtfase na tien minuten zonder nieuwe opdracht.
Twee bestaande offline Windows-stemmen zijn aangetroffen (David en Zira, en-US);
er is geen audio afgespeeld of gesynthetiseerd.

Het Windows-sessierapport noemt een door Michel afgehandelde beheerdersvraag.
De hoofdsessie heeft die vraag niet zelf gezien; een algemene 'done' op een
Codex-goedkeuring bewijst geen Windows-UAC-vraag of uitgeverswaarschuwing.
De exacte gebruikerswaarneming hiervan blijft OPEN totdat die is bevestigd.

Alleen het oudere `ggml-small.bin` van 487.601.967 bytes is in de bekende
modelmappen aangetroffen. De vier Faster Whisper-modelbestanden en een lokale
notulenprovider zijn daar niet aangetoond. Geen modeldownload gestart.

De computerbediening bereikt Parallels-menu's, maar gastinvoer werkt niet.
Parallels CLI-gastuitvoering vereist volgens de geïnstalleerde editie Pro/Business.
Op uitdrukkelijk verzoek heeft Michel de officiële ARM64 Codex CLI 0.161.0 via
winget geïnstalleerd en zich zelf aangemeld. Een lokale QA-werkmap en expliciete
Codex-goedkeuringen maken technische opdrachten en rapportoverdracht mogelijk.
Geen remote toegang, nieuwe credentials of Windows-beveiliging ingesteld.
Het inventarisatiescript werd door execution policy geweigerd; afzonderlijke
normale inventarisatieopdrachten zijn gebruikt, zonder policywijziging of bypass.
GUI-proeven volgen hier niet automatisch uit.

| Aanvullend acceptatiepunt | Stand | Bewijs / begrenzing |
|---|---|---|
| VM-architectuur en baseline | GO | Windows bevestigt ARM64, build 26100, 4 vCPU, 8 GiB, actieve Defender en actuele definities. Effectief beveiligingsbeleid slechts gedeeltelijk vastgesteld. |
| Snapshot vóór installatie | GO | Snapshotmetadata met naam, datum en ID aanwezig; herstelproef nog OPEN. |
| Schone omgeving en native x64-representativiteit | NO-GO | Bestaande gebruikers-VM op ARM64; geen representatieve schone x64-collega-laptop. |
| Overdracht en updaterintegriteit | GO | Gast-retourkopie heeft beide oorspronkelijke hashes; productiehandtekening geldig en gewijzigde MSI afgewezen. |
| Lokale volledige veiligheidskopie | GO | 285 bestanden volledig gelijk in hash, grootte en beide tijdstempels; daadwerkelijk herstel OPEN. |
| Normale upgrade 262 → 295 | GO | ARM64-VM, msiexec exit 0, versie en exacte worker bevestigd; alle 285 appdatabestanden gelijk vóór eerste start. Geen herstartproef; exacte UAC-/waarschuwingswaarneming OPEN. |
| Defender-bestandsscans | GO | MSI en volledige geïnstalleerde appmap/worker: gekoppelde events 1000/1001, geen detectie; actieve Defender 1.463.22.0. Geen uitvoeringsbewijs. |
| Appstart na upgrade | GO | Home daadwerkelijk bekeken via Parallels; geen loginwizard of zichtbare fout. Geen leeg profiel of bewezen opname. |
| Workerstart met actieve Defender | GO | Exacte worker `--help`, exit 0; hash behouden, Defender actief en nul relevante detecties/events. Alleen loadercompatibiliteit onder ARM64-emulatie. |
| Werkelijke transcriptie met actieve Defender | OPEN | Nog niet uitgevoerd; Faster Whisper-model ontbreekt. Toestemming voor overdracht bestaande modelset afzonderlijk gevraagd. |
| Editor, opslaan, heropenen en normale appherstart | GO binnen documentinhoud | Windows-agent bediende normale UI; marker behouden na lijstnavigatie en herstart. Oorspronkelijke body en aparte titel behouden, dubbele H1 verwijderd. Zie opdracht 7. |
| TXT/PDF-export en teruglezen | GO voor deze fictieve notule | Vier echte app-exports; hashes, exacte TXT-markerwijziging, PDF-rendering, tekstlaag en zoeken gecontroleerd. Hoofdsessie bekeek de renderingen. |
| Volledige korte/lange audioketen, procesboommeting, back-up/herstel | OPEN / inhoud NO-GO | Korte uitvoer inhoudelijk afgekeurd; audio niet gehoord, kanaalbron onbewezen, meetvenster dekt verwerking niet, geen herstelproef. Dalf38 blijft afzonderlijk. |
| Onderbroken upgrade | OPEN | Geen eigen wegwerpkopie zonder gebruikerswerk beschikbaar. |

### Hernieuwde controle van bediening

Na de vervolgopdracht meldt `prlctl list -a` de bestaande VM opnieuw als running.
De hostbedieningssessie is veilig opnieuw verbonden (alleen CUA-runtime gereset,
geen VM-reset); `getApp` faalt al met `Sky Computer Use native pipe startup failed`.
Geen verse schermafbeelding of gastinvoer mogelijk via dit kanaal. Dit is geen
bewijs van een Windows-vastloper. Een korte handmatige Kladblokproef is gevraagd:
klik in een nieuw tekstvlak en typ `TV295 bedieningstest`, zonder opslaan.
Michel bevestigt daarna: “kladblok staat open en done”. Handmatige bediening
is daarmee door de gebruiker bevestigd; geen agent-screenshotbewijs. De
aansluitende `getApp`-poging geeft opnieuw dezelfde native-pipe-fout. De
agentbediening blijft geblokkeerd; een Windows-vastloper is niet aangetoond.
Geen blinde toetsen, procesonderbreking, beveiligingswijziging of nieuwe
praktijkproef uitgevoerd. De korte keten blijft geblokkeerd op betrouwbare
beeld-/invoerbediening. Bewijs: `parallels/control-reconnect-status.json`.

### Windows-agent: vervolgacceptatie

`parallels/VERVOLG-ACCEPTATIE.md` bevestigt uitsluitend terminaltoegang,
x64-PE 1.0.295 op ARM64 en actieve Defender. Geen nieuwe praktijkproef uitgevoerd.
De herhaalde Kladblokvraag is ingetrokken: handmatige bediening was al bevestigd.
De gedeelde opdracht 5 vraagt uitsluitend selectieve inventarisatie van bestaande
niet-geheime verwerkingsinstellingen. Geen credentialwaarden, providerrequests,
modeloverdracht of verwerking toegestaan. De korte en lange keten blijven OPEN.

### Korte handmatige microfoonproef: verwerking voltooid, inhoud afgekeurd

Michel heeft cloudverwerking van uitsluitend fictieve proefinhoud toegestaan.
De screenshots tonen lokale **Whisper Small** (`small`, GGML), niet Faster Whisper,
en Ollama Cloud `https://ollama.com`, model `gpt-oss:120b`. De eerdere ontbrekende
Faster Whisper-set blokkeert deze afzonderlijke GGML-route niet. Voor deze route
is `ggml-small.bin` door de Windows-agent gerapporteerd: 487.601.967 bytes,
SHA-256 `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`.
De groene UI-status controleert bestandsaanwezigheid; geen bewezen modelwerking.

De eerste keten strandde zichtbaar op “Vul je Ollama Cloud API-sleutel in bij
Instellingen” (55%). Michel rapporteert daarna geslaagde verwerking en deelt
transcript en notulen voor een opname van 36 s, weergegeven als 29 oktober 15:39.
Dit is gebruikersbewijs, geen zelfstandig gecontroleerde audio/store/providerlog.
Technische voltooiing is gerapporteerd; inhoudelijke acceptatie is **NO-GO**:

- Het transcript bevat `Norbakker`, `Denenbrug`, `BTV` en het onbegrijpelijke
  `Er mogen geen klant gereversen naar externe diensten`.
- De notulen maken daarvan in besproken onderwerpen een verbod op het
  doorverwijzen van klanten naar externe diensten: de bedoelde beperking over
  klantgegevens is niet betrouwbaar behouden.
- Noors inhoudscontrole op donderdag 12 november ontbreekt als expliciete actie;
  het transcript bevat hier al een beschadigde zin. De notulen bevatten bovendien
  de losse besluitregel `Niet 15.`.
- Het budget 12.450 versus 15.000, alleen interne proef en Milans technische
  controle op woensdag 11 november 16:00 zijn wel herkenbaar behouden.

Geen vastgestelde implementatiefout of exacte oorzaak: eerst originele audio
naast transcript beoordelen, vervolgens prompt/modeluitvoer naast notulen. Geen
speculatieve correctie, regeneratie of versoepeling van inhoudscontrole uitgevoerd.
De gemelde meetdeadline 15:12:53 ligt vóór de weergegeven recordtijd 15:39;
volledige procesboommeting van deze verwerking is zonder ruwe logs onbewezen.
Bewerken/heropenen/export, systeemgeluid en de 45-minutenproef blijven OPEN.
Bewijs: `parallels/short-chain-user-reported-quality.json`.

### Zelfstandige editor-/exportafronding via bestaande Windows-UI-voorzieningen

Na expliciete toestemming voor bestaande UI Automation, screenshots en gerichte
Windows-input heeft de gastagent de normale app bediend zonder installatie,
rechtenverhoging of product-/beveiligingswijziging. De eerdere terminalbeperking
is voor deze proef opgeheven; geen handmatige ronde meer vereist voor editor/export.
Het bewijs staat in `parallels/OPDRACHT7-AFRONDING.md` en de gelijknamige bewijsmap
`OPDRACHT7-AFRONDING-20261029-163312`. Zelfde MSI-hash en ARM64-emulatieomgeving.

**GO binnen documentinhoud:** originele notule via de app geëxporteerd, uitsluitend
QA-marker via editor toegevoegd en opgeslagen; na lijstnavigatie en normale
appherstart zichtbaar behouden. Oude PID 4744 normaal geëindigd, nieuwe PID 2164.
De hoofdsessie bekeek het herstartbewijs en beide volledige PDF-renderingen en
controleerde de vier exportgroottes/-hashes en de voor/na-inhoud zelfstandig.
TXT bevat na bewerken exact één extra markerregel; beide PDF's zijn leesbaar,
één pagina en volgens bewaarde Edge-UIA/zoekbewijzen doorzoekbaar. Dit is afzonderlijk
van het historische Dalf38-PDF-bewijs zonder bewezen tekstlaag.

**Afwijking:** alleen `notule_html` veranderde, maar niet strikt uitsluitend met
één toevoeging: de normale editor verwijderde ook de leidende dubbele H1.
Na verwijderen van H1 uit origineel en QA-paragraaf uit nieuwe HTML zijn de bodies
bytegelijk. Aparte titel en overige recordvelden, inclusief `updated_at`, bleven
ongewijzigd. De titel is zichtbaar behouden; geen andere betekenisreparatie.
Strikte raw-HTML-eis is daarmee NO-GO. Geen vastgestelde productfix uitgevoerd.

Origineel transcript en WAV bleven volgens hashbewijs ongewijzigd. WAV is via
bestaande Windows Media Player gestart, met zichtbare voortgang; geen bewezen
ThoughtVault-interne afspeelfunctie of fysiek gehoord geluid. Inhoudelijk luisteren
blijft OPEN. Huidige bronkeuze Gecombineerd bewijst geen historische microfoonkeuze.
De WinRT-renderhelper eindigde met 0xC0000005 nadat complete PNG's waren gemaakt;
dit is behouden helperfoutbewijs, geen ThoughtVault-crashproef. IFilter faalde
0x80004002; de afzonderlijke Edge-tekst-/zoekcontrole is gebruikt voor tekstlaag.

| App-export | Bytes | SHA-256 |
|---|---:|---|
| voor.txt | 862 | `fdd071ce51329f7a2c77b081a630a8bf2d845ad33da8bb169ac543659dc5633a` |
| voor.pdf | 58.854 | `1d69312242efd1de98e59c08b2730374279fd53459e59918c4b31e8016b533ba` |
| na.txt | 898 | `307f73da0ac7196b3b1077ee99f6dcf05902223add7bfa86f8ce44523e940a7f` |
| na.pdf | 59.605 | `3f8b4f0d913d3034cb73374e9ecaa5b83e301642dd1d675ead60eda8d34c9475` |

De inhoudelijke afkeur blijft: beschadigde gegevensbeperking, ontbrekende Noor-actie
en onduidelijk besluit. De bestaande procesboommeting 15:02–15:12 dekt de opname
rond 15:33 en verwerking niet. De pre-upgradeback-up bevat dit nieuwe record/audio
niet; werkelijk herstel blijft OPEN. Geen nieuwe providercall, 45-minutenproef of
crash-/herstelproef uitgevoerd. Algemene uitrol blijft NO-GO.

### Vervolg uitrolonderzoek R1 en bronlevering — 30 oktober

De Windows-sessie heeft vóór afsluiten een tweede fictieve proef R1 voltooid en
het resultaat gedeeld in `parallels/UITROL-ACCEPTATIE.md`. De opgeslagen transcriptie
is exact gelijk aan de afgekeurde baseline; notulen variëren en behouden de
vereiste actie/gegevensbeperking nog onvoldoende. Kwaliteit blijft NO-GO.
De volledige lokale procesboommeting dekt deze run wel: 282 samples, grootste
sampleafstand 3,414 s; importbevestiging tot eerste UI-voltooiing 517,204 s.
Waargenomen begin/eindgrenzen zijn geen exacte engine-/cloudserverlatentie.
Gelijktijdige pieken: 1.683.267.584 private bytes en 1.386.536.960 working-setbytes.
Dit is ARM64-emulatiebewijs, geen native-x64-prestatieacceptatie.

Een nieuwe gesloten appmapkopie bevat 296 Local + 2 Roaming-bestanden, beide eigen
fictieve records en audio, met gelijke hashes/grootte/beide tijdstempels volgens
het gedeelde technische bewijs. Dit vult de actuele back-updekking aan; een
uitgevoerde veilige restore en accountgebonden credentialherstel blijven OPEN.

De concrete bronaanvraag is door de Mac-hoofdsessie gelezen en geleverd via
`BRON-EN-PLAN` in de gedeelde QA-root. Het bestaande bronarchief heeft de reeds
vastgelegde SHA-256; alle 261 gewone archiefbestanden zijn opnieuw bytegelijk
vergeleken met git-blobs van commit 55ecb9077588afaa1559a1d1f9b921c065746f16.
Meegeleverd zijn bestandsmanifest, actuele pilot-/installatiecriteria en aanwijzing
van bestaande Mac-testwerkmap/Dalf38-bouwroute. Dit is geen nieuwe build of test-PASS.
Afzonderlijke native-x64- en herstelomgeving zijn niet geleverd of aangetoond.

### Bedragguard: bewezen regressie en geïntegreerde bronfix — 30 oktober

Windows-brononderzoek is via `BRONONDERZOEK-20261030` ontvangen en met manifest
gecontroleerd. De huidige `windows/src/services/llm.ts` was bytegelijk aan de
opgegeven bronbaseline. De zes nieuwe integratiegevallen zijn eerst op originele
logica uitgevoerd: **6/6 falen**. De guard splitste `Niet 15.000 euro.` op de punt
tussen cijfers en accepteerde daardoor het onvolledige `Niet 15.` als constraint.

Minimale gedeelde fix: punten tussen cijfers blijven onderdeel van dezelfde zin;
trefwoorden, twee generatiepasses en fail-closed aanwezigheidsguard blijven intact.
Na fix **35 gerichte tests**, alle **153 frontendtests / 46 bestanden**,
`tsc --noEmit` en frontendreleasebuild slagen. Gewijzigde bron is bytegelijk aan
het overgedragen VM-voorstel. Logs/resultaten staan in `mac-decimal-fix-overdracht`;
zelfde materiaal is gedeeld als `RESULTATEN/MAC-INTEGRATIE-20261030`.

Dit is bron-/frontendbewijs, geen Windowsrelease- of productieacceptatie. Geen
Rust-test op Windows, nieuwe kandidaat, versiebump, signing of providercall in deze
stap. MSI 1.0.295 is ongewijzigd en bevat de fix niet. ASR-beschadiging, ontbrekende
Noor-actie, semantische consistentie, native x64 en herstel blijven aparte
kwaliteits-/omgevingsblokkades; geen versoepeling of brede betekenisreparatie.

### Kwaliteitscontract echt uitgevoerd: twee open negatieve gevallen

De Mac-hoofdsessie heeft het nieuwe overdrachtsmanifest en de bronhash gecontroleerd
en drie ongewijzigde integratietests toegevoegd. De volledige Vitest-run geeft
**154 PASS, 2 FAIL / 156 tests**, exit 1. Alle eerdere 153 tests blijven slagen;
complete transcriptdoorgifte en volledige foutloze uitvoer slagen als positieve
controle. Uitvoer zonder expliciete Noor-actie en uitvoer met toegevoegde
tegenstrijdige toestemming worden beide ten onrechte geaccepteerd voor het
vereiste kwaliteitscontract. Tests zijn niet geskipt, als verwacht-falend
geclassificeerd of afgezwakt. Geen productiepatch op deze twee tekorten gemaakt.

De huidige guard bewaakt aanwezigheid van lexicale beperkingen; dit bewijst geen
volledige positieve actiedekking of afwezigheid van tegenspraken. Nieuwe trefwoorden
of extra identieke modelprompts vormen geen aangetoonde algemene oplossing.
Log/exitcode en bronvalidatie zijn gedeeld als
`RESULTATEN/MAC-KWALITEITSCONTRACT-20261030`, lokaal bewaard in
`mac-quality-contract-overdracht`. De suite staat bewust rood op deze twee
openstaande acceptatiecriteria; geen nieuwe build, modelcall of MSI in deze stap.
De bedragfix is intact. Luisterbewijs en native-x64/herstelomgeving blijven OPEN.

## Vervolg en overdracht

Gebruik [WINDOWS-PILOT.md](../WINDOWS-PILOT.md) voor vereisten, pakketinhoud,
modelkeuze, opname, menselijke inhoudscontrole en volledige back-up/herstel.
Eerdere back-ups en afgekeurde MSI/portable-kandidaten blijven apart behouden.
Een verplicht OPEN-punt betekent totaal NO-GO; aanwezigheid van dit MSI/`.sig`-paar
is geen vrijgave naar collega's.

Geen push, publicatie, externe scanupload, betaalde provider, nieuwe sleutel of
modeldownload uitgevoerd. De apart aangevraagde Codex-installatie staat hierboven. Het beveiligings- en inhoudsprobleem is niet
door een nieuwe versie opgelost verklaard.
