# Windows collega-pilot — 28 oktober 2026

## Kandidaat en grenzen

- MSI-basis: `92abce850a0a8cfd7ebfa4a6e18bf086b9bfb12a`, versie `1.0.294`.
- Actuele lokale testbuild: **1.0.295-pilot.1 portable**, bron `e2bf26ee8803d3d6770600418a20d5dc7ed4d3dd`, inclusief fixes `b58d3a2c01e7f0cfb8442a186e65ef7f1a21a17a`. Alleen de afzonderlijke Windows-bronkopie heeft een versieoverride; geen MSI/updaterpakket of publicatie.
- Bestaande private kandidaat: `build/windows-294-20261020/ThoughtVault_1.0.294_x64.msi`, met bijbehorende `.sig`.
- MSI SHA-256, op 28 oktober opnieuw berekend: `39e01dab4979c9ef3dd5e6ea8cb2d6fcf6a26de1b1f4a51b3cfe53c18227cc39`. Updaterhandtekening én trusted comment cryptografisch geverifieerd met de publieke sleutel uit `tauri.conf.json`; gewijzigde payload wordt afgewezen.
- Bestaande CI-bronref verwijst nog naar exact deze commit. Gitea-main verwijst naar `eefbe0fa9ad904039e288e518dde15c503b93e59`, versie 1.0.270; deze andere bronlijn vervangt de pilotwerkboom niet.
- Bestaande gebruikerswijzigingen blijven behouden. Geen push, merge, publicatie of betaalde calls.
- Uitgeverssignering wordt overgeslagen. Windows kan **onbekende uitgever** melden. Updaterhandtekening en beveiligingscontroles blijven gelden; geen uitzonderingen of beveiligingsverlaging.

## Actuele controles

| Controle | Bewijs | Stand |
|---|---|---|
| Windows-baseline | Royal TSX / Dalf38: executable 1.0.294; Ryzen 7 5700X3D; 48 GiB RAM; app aanvankelijk gesloten | Bevestigd op Windows |
| Normale beveiligingsbaseline | Bureaublad toont Testmodus; geen instellingen gewijzigd | Geen acceptatiebewijs voor normale werklaptop |
| Lokale provider | Ollama API op 127.0.0.1:11434 bereikbaar; hermes3:8b, gemma-4-abliterated:12b en qwen3.5-abliterated:9b aanwezig | Geen nieuwe download; standaard llama3.2 ontbreekt |
| Lokale frontendregressie | 45 bestanden / 147 tests PASS; TypeScript/Vite-build PASS op Mac na npm ci --ignore-scripts | Geen Windows-runtimebewijs |
| Schone installatie / onderbroken update | Afzonderlijke schone, herstelbare Windows-omgeving ontbreekt volgens gebruiker | OPEN |
| Volledige back-up en herstel op dezelfde Windows-gebruiker | 595 Local- en 12 Roaming-bestanden teruggezet op oorspronkelijke locaties; alle aantallen/SHA-256 gelijk; appstart en eigen transcript heropenen geslaagd; eigen herstelde WAV 153,149125 s | PASS voor dezelfde machine/gebruiker; geen overdraagbaarheid van kluiscredentials bewezen |
| Dagelijkse keten en inhoud | Opnemen/pauze/hervatten/stoppen/transcriptopslag getest; notulengeneratie geblokkeerd en transcript bevat inhoudsfouten | FAIL voor pilotvrijgave |

Eerdere Windows-resultaten staan in `windows-expanded-acceptance-2026-10-19.md`; zij gelden uitsluitend voor de daar genoemde executable en scenario's. Een geslaagde technische verwerking bewijst geen juiste notulen.

## Besluit

**NO-GO voor uitrol naar collega's** zolang de open installatie- en werkketencontroles niet zijn afgerond. Aanwezigheid van een MSI is geen pilotacceptatie.

## Uitvoeringslog

- 13:25 CET: alleen-lezen Windows-query bevestigt executableversie, hardware en bestaande lokale Ollama-modellen. Eerste query had een door de bediening weggevallen padscheiding; gecorrigeerd met forward slashes. Geen installatieprobleem.
- 13:26 CET: volledige back-up gestart van de bestaande Roaming- en Local-appmappen terwijl ThoughtVault gesloten is. Uitkomst volgt; nog geen volledige back-up-PASS.
- Lokale testlogs: `/tmp/thoughtvault-pilot-vitest-20261028.log` en `/tmp/thoughtvault-pilot-build-20261028.log`. De eerste poging miste geïnstalleerde npm-dependencies; na herstel uit de bestaande lockfile beide controles geslaagd. Geen dependencyversies gewijzigd.
- Eerste volledige back-up: `%LOCALAPPDATA%/ThoughtVault-Pilot-20261028-132600/{Local,Roaming}`. App gesloten; alle 590 Local- en 12 Roaming-bestanden per SHA-256 gelijk aan bron. Geen privé-inhoud naar Mac overgebracht.
- Op verzoek van Michel RDP-audio ingesteld op **Leave at remote computer**, microfoondoorgifte vanaf Mac uitgeschakeld en sessie opnieuw verbonden. Geen algemeen Mac-volume of Windows-beveiliging gewijzigd. Dit blijft de afgesproken instelling zodat Michel lokaal kan doorwerken.
- Vaste Nederlandse bron met reeds aanwezige OneCore-stem Frank aangemaakt, zonder download of netwerkdienst. `pilot-short.wav`: 80,750 s, SHA-256 `fd4cb1a6a1b7309743f03a26e1f70d388107d53e12201f9a7c27231b5dd9b85a`. Bron en WAV blijven lokaal in de pilotmap op Dalf38.
- Native gecombineerde opname `recording_1793190956950.wav`: eindige bron éénmaal afgespeeld, speler daarna gestopt/disposed. Pauze zichtbaar op 02:26, timer bleef staan; hervatten en Stop en verwerk uitgevoerd. Op schijf één eigen record `local-483b76b5-0010-4c97-a0be-803ce0f48250`, created `2026-10-28T12:39:06.206Z`, duur 153,149125 s, `has_transcription=true`, `has_notes=false`. Systeemgeluidherkenning bewezen; geen afzonderlijk positief microfoon-spraakbewijs.
- Notulengeneratie op geïnstalleerde 294 faalt bij 55% met bereikbaarheidmelding. Diagnose op dezelfde Windows-pc: Ollama preflight met Origin `http://tauri.localhost` krijgt **403**, dezelfde lokale POST zonder WebView-origin antwoordt **OK**. Geen OLLAMA_ORIGINS-, CORS-, firewall- of andere beveiligingsinstelling veranderd.
- Afzonderlijke native procescrash met eigen opname `recording_1793191514603` en fictieve bron. Eigen app-PID 25252 gecontroleerd en geforceerd beëindigd; speler gestopt/disposed. Losse loopback-WAV: 2.629.632 bytes, microfoon-WAV: 2.621.440 bytes; bij beide is het data-chunkveld **0 bytes**. Originelen apart gekopieerd naar `crash-originals`, niet verwijderd of in-place gerepareerd. Dit bevestigt de headerfout in geïnstalleerde 294; geen herstel-PASS.
- Nieuwe volledige herstelback-up `restore-backup` na de proeven: 595 Local- en 12 Roaming-bestanden; aantallen én alle SHA-256 gelijk aan actuele bron. Herstel naar oorspronkelijke locaties voltooid; originele mappen blijven apart als `pre-restore`. Daarna alle herstelde bestanden opnieuw vergeleken: `Local: RESTORE VERIFIED 595`, `Roaming: RESTORE VERIFIED 12`, `FULL_RESTORE_HASHES_PASS`. App herstart en eigen pilottranscript via lijst opnieuw geopend. Op schijf count 1, raw en created_at exact gelijk; has_notes blijft terecht false. Herstelde eigen WAV via ffprobe: 153,149125 s. Instellingen openen na herstel en tonen behouden lokale modus en Faster Whisper Small.
- 14:18 CET: bestaande Whisper Medium geselecteerd; instellingen bevestigen model gereed, geen download. `pilot-short.wav` éénmaal geïmporteerd via eigen pilotmap; native taak `import_nWBB5k.wav` zichtbaar Transcriberen 10%. Voor de afgesproken onderbrekingsproef eigen proces geforceerd gestopt rond 14:20. Geïmporteerde WAV 2.584.044 bytes: SHA-256 vóór/na exact gelijk; volledige notulenstore eveneens exact gelijk (`AudioPreserved=true`, `NotesPreserved=true`). App opnieuw gestart. Geen voltooide Medium-herkenning, snelheidsmeting of kwaliteitsclaim.

- Na de verwerkingscrash toont Taken na herstart geen actieve taken. De 80,750 s-bron staat onder Opgeslagen opnames met herverwerkingsknop; geen automatische hervatting en geen geslaagde retry bewezen.
- Bestaande eigen fictieve QA-notule `local-54fbd8b7-b57d-4a5c-9cf3-e0dad5796825` bewerkt met QA-markering, opgeslagen en na navigatie opnieuw geopend. Markering werkelijk aanwezig in local-transcripts.json. TXT-export via de app: 544 bytes in Downloads, inhoud gelezen; markering, Alex en afspraak maandag 10 uur behouden, geen HTML-tags. Geen PDF-acceptatie of nieuwe notulengeneratie hiermee bewezen.
- Copy-Item veranderde audio-aanmaakdatums. De 66 bestaande audiobestanden op hash vergeleken met bewaarde `pre-restore`-originelen en alleen CreationTimeUtc teruggezet; assert op elke datum: `AUDIO_DATES_VERIFIED 66`. Nieuwe import niet aangeraakt. Handleiding noemt metadata behouden en controleren; geen nieuw back-upsysteem toegevoegd.
- Tijdelijke testkeuzes teruggezet naar oorspronkelijke Faster Whisper Small Nederlands CPU int8 (gereed) en Ollama Cloud `https://ollama.com`, `gpt-oss:120b`. Sleutelindicator blijft opgeslagen; geen credential gewijzigd of cloudgeneratie gestart. Geen opname, speler of verwerking achtergelaten.

## Twee noodzakelijke bronfixes — nog niet in de MSI

1. **Opnamecheckpoint:** gedeelde `write_timed_chunk` werkt WAV-header en buffer iedere geschreven audioseconde bij voor zowel microfoon als loopback. De regressie leest vóór finalize/drop: vóór fix 0 samples waar 16.000 verwacht; na fix correct leesbaar. Alle vier capture-callers behouden hun bestaande schrijffoutafhandeling. Geen garantie voor stroomuitval, en de laatste fractie vóór een checkpoint kan ontbreken. Losse kanalen worden bij een crash niet automatisch samengevoegd.
2. **Lokale notulenprovider:** Ollama en LM Studio gebruiken dezelfde bestaande native `proxy_request` als Ollama Cloud en de modellenlijst. Geen serverconfiguratie of beveiliging aangepast. URL-normalisatie voorkomt dubbel `/v1`; HTTP-fouten, ontbrekende cloudsleutel, lege concepten en broncontrole blijven fouten. Lokale provider verstuurt geen opgeslagen cloudsleutel. Voortgang komt per volledig antwoord, zoals bij de bestaande cloudroute.

Verificatie: beide nieuwe providergevallen eerst FAIL; daarna volledige Vitest 45 bestanden / 147 tests PASS en TypeScript/Vite PASS. Rust-checkpoint eerst FAIL (0 versus 16.000 samples); daarna **34 PASS / 3 ignored** op Mac. Voor uitsluitend deze lokale Rust-tests is `TAURI_CONFIG='{"bundle":{"resources":[]}}'` gebruikt: de Windows-runtimebundels ontbreken lokaal. Geen packagingconfiguratie opgeslagen of runtime-download gestart. Logs: `/tmp/thoughtvault-pilot-provider-red.log`, `/tmp/thoughtvault-pilot-vitest-final.log`, `/tmp/thoughtvault-pilot-recording-red.log`, `/tmp/thoughtvault-pilot-recording-green.log`, `/tmp/thoughtvault-pilot-build-final.log`.

De signingkey is als GitHub-secret `TAURI_SIGNING_PRIVATE_KEY` aanwezig; alleen de naam is gecontroleerd. De waarde is niet uitleesbaar en is niet in de lokale Mac/Windows-buildomgeving geladen. Geen vervangende sleutel, unsigned-updatervariant of push gebruikt. De bestaande MSI 294 bevat **geen** van bovenstaande fixes. Een volgende kandidaat moet een nieuwe versie krijgen en via de bestaande signingroute gebouwd worden.

De fixes zijn lokaal vastgelegd in commit `b58d3a2c01e7f0cfb8442a186e65ef7f1a21a17a` (geen versiebumps of publicatie). Een afzonderlijke bronreview vond geen belangrijke problemen. De lokale native route heeft een timeout van 300 seconden per modelaanroep; geschiktheid en prestaties moeten nog op een normale werklaptop worden bewezen.

## Inhoudsbeoordeling van de nieuwe opname

Broncontract: Sanne en Noor aanwezig; Amir/Lotte/Floor afwezig; 5.000 euro afgewezen en niet goedgekeurd; proef met drie collega's in bestaande testomgeving; geen productie/licenties; plafond 1.250 euro exclusief btw; Sanne begroting 30 oktober 17:00, niets bestellen, dinsdagdeadline vervalt; Noor uitnodiging voor 2 november 10:00; importprobleem zonder eigenaar/oplosdatum; bewaartermijn open en geen verwijderbesluit.

Native transcript bewaart bedragen, afwijzing, drie proefcollega's, productie-/licentieverbod, bestelverbod en vervallen deadline. Het bevat echter onder meer **Noor → Floor**, **niet goedgekeurd → niet goed gebeurd**, **geen oplosdatum → geen opperstaten** en **geen besluit → geen bestuur**. Daardoor geen inhoudelijke acceptatie. Er zijn geen notulen gegenereerd door de bevestigde providerblokkade; geen notulenkwaliteit-PASS of automatische broncorrecties. Menselijke controle blijft verplicht.

## Open voor vrijgave

- Gefixte portable binary 1.0.295-pilot.1 is gebouwd en op Windows gestart; checkpoint- en lokale-providerroute hertest (zie retry hieronder). Nieuwe MSI met bestaande updaterhandtekening en installatie-/updateacceptatie ontbreken nog.
- Schone installatie, upgrade vanaf vorige kandidaat en onderbroken update in een geschikte herstelbare omgeving. De gebruiker heeft bevestigd dat deze aparte omgeving nu ontbreekt. Dalf38 wordt hiervoor niet gewist of van beveiliging ontdaan.
- Volledige werkketen met gegenereerde notulen, bewerken/heropenen/export, 45 minuten representatieve bron, en inhoudelijke bronvergelijking op de nieuwe kandidaat. Deze volledige proef wordt niet vervangen door de korte capture of de bestaande versielogs.
- Positief bewijs van herkenbare microfoonspraak én videogesprekaudio, een gewone werklaptop en herstel tijdens notulengeneratie. Geen echt videogesprek met collega-inhoud gebruikt.
- Een volledige Medium-run en onderbouwde laptopinrichting; de korte Medium-run hierboven is bewust onderbroken. Geen nieuwe modellen, server of betaalde dienst toegevoegd.

## Lokale overdracht

`build/windows-pilot-20261028/` bevat precies één bewaarde MSI 1.0.294 met oorspronkelijke sig, SHA256SUMS, bronidentificatie, NIET-UITROLLEN-status, bronpatch, testlogs en deze documenten. Dit is een controlepakket, geen gefixte pilotrelease.

## Vervolg: lokale portable testbuild

Na afzonderlijk akkoord op de lokale route is op 28 oktober circa 16:34 CET op Dalf38 bevestigd dat Node, npm, cargo, rustc en CMake beschikbaar zijn. De eerdere tijdelijke bronmap is leeg; deze wordt niet als actuele kandidaat gebruikt.

Bronarchief uit `e2bf26ee8803d3d6770600418a20d5dc7ed4d3dd` (inclusief beide fixes, alleen Windows/scripts/tests/VERSION) overgebracht naar `%TEMP%/ThoughtVault-Pilot295/source.zip`: 5.025.617 bytes, SHA-256 `0ed9496171b12785380266b243e055260e6ceafabbb866329d0e93f098d9d630`; op Windows expliciet `SOURCE_HASH_VERIFIED` en uitgepakt in `src`. Git-werkboom en geïnstalleerde EXE blijven behouden.

HTTP via Mac-VPN-adres was onbereikbaar; de tijdelijke server is gestopt. Overdracht gebruikt uitsluitend tijdelijke RDP-map `/private/tmp/thoughtvault-pilot-transfer-20261028`; geen Home/Documenten of volledige schijf gedeeld. Audio blijft Leave at remote computer, Mac-microfoon uit.

Eenmalige driver `build-pilot.ps1` SHA-256 `a5ff07b6fd1650654394812f6a9f9da2e0a41ce29bceed60d4ab274236a97e91` gekopieerd en startcommando met `powershell -NoProfile -File` verstuurd. Driver gebruikt alleen geïnstalleerde runtimes, offline npm/cargo, regressies en `tauri build --no-bundle`, met testversie `1.0.295-pilot.1` in de afzonderlijke kopie. Assert op ongewijzigde updaterconfig en CSP. Geen MSI/signature/feedwijziging beoogd.

**Eerste bouwpoging geblokkeerd (historisch; geslaagde retry hieronder):** na tijdelijk `cgWindowNotFound` heeft Michel de bediening hersteld. Bouwproces PID33560 bevestigd. Offline npm-installatie slaagt; native Windows Vitest **45 bestanden / 147 tests PASS**, 30,10 s. De Rust-releasecompilatie stopt vóór uitvoering van regressies bij `whisper-rs-sys v0.15.0`: `could not execute .../whisper-rs-sys-680f400b919ffee3/build-script-build (never executed)`, `Toegang geweigerd. (os error 5)`. Rond dezelfde bouwpoging toont Avast eerst een veiligmelding voor een gegenereerd bouwbestand, daarna **Dreiging gedetecteerd en veiliggesteld**, `build-script-build.exe` in quarantaine. Geen exacte malwareclassificatie of false-positive aangetoond; geen uitzondering, herstel uit quarantaine, scannerwijziging of nieuwe poging langs de blokkade uitgevoerd. Driver beëindigd; ExitCode-object retourneert null, dus geen exitcodeclaim. `portable/ThoughtVault.exe` ontbreekt; geïnstalleerde executable blijft 1.0.294. De portable bouwstap en lange native opnameketen zijn niet bereikt. Logs en driver bewaard onder `build/windows-pilot-20261028/portable-attempt/`. Hervatten vereist beoordeling van de beveiligingsdetectie of een geschikte andere bestaande bouwomgeving; geen nieuwe sleutel nodig.

Correctie eerdere documentatie: GitHub API op 28 oktober 16:48 CET bevestigt `michelknoop21/ThoughtVault` openbaar (`private:false`). Geen nieuwe bronpush of CI-dispatch uitgevoerd. `publish=false` alleen is geen garantie voor private bron/artifacts.

Tijdelijke RDP-mapredirectie na logoverdracht teruggezet naar **None** (map uit lijst verwijderd, Apply & Close, sessie opnieuw verbonden). Audio blijft aan de remote kant en Mac-microfoon uit. Beide overgebrachte fixbestanden zijn op Windows opnieuw gehasht en komen exact overeen met broncommit b58d3a2.


## Retry op verzoek van Michel — 18:21–18:40 CET

De bestaande lokale bouwroute is opnieuw uitgevoerd, zonder wijziging van Avast, quarantaineherstel of uitzondering. CyberCapture scant een gegenereerd build-script; de compilatie komt nu voorbij de eerdere blokkade. Eerste retry mist `frontendDist` doordat de tijdelijke testdriver Rust vóór de frontendbouw uitvoert. Driver gecorrigeerd: eerst bestaande `npm run build`, dan native tests, dan bestaande `npm run tauri:portable` (`tauri build --no-bundle`). Geen productcodewijziging nodig.

Windows-resultaat:

- Vitest: **45 bestanden / 147 tests PASS** uit de eerste Windows-bouwpoging; dezelfde bron, geen herhaling nodig.
- TypeScript/Vite: PASS.
- `cargo test --release --locked --lib`: **36 PASS, 0 FAIL, 3 ignored**, zonder resources-override, 2,11 s testtijd.
- Portable releasebouw: PASS, 1m13s; EXE 28.088.832 bytes, ProductVersion **1.0.295-pilot.1**. SHA-256 `9221be535080488a2475d704015b2cf992554501ccee19958f959adeeb78b1f6`.
- Bestaande geïnstalleerde runtimebestanden gekopieerd naar `portable/resources`; **886 bestanden**, alle aantallen en SHA-256 gelijk aan de bron. Geen download. Bestaande `verify-windows-runtime.ps1` slaagt voor hoofd-EXE, Faster Whisper en NeMo (workers met AppLocalRuntime); inclusief bestaande Microsoft-handtekeningcontroles.
- Nieuwe volledige prelaunch-back-up: `%TEMP%/ThoughtVault-Pilot295/prelaunch-backup/{Local,Roaming}`, app gesloten; **591 Local + 12 Roaming**, alle SHA-256 gelijk. Robocopy behoudt metadata.
- Pilot gestart vanuit `%TEMP%/ThoughtVault-Pilot295/portable/ThoughtVault.exe`, eigen PID15112 en procespad gecontroleerd. Avast meldt na automatische CyberCapture-scan **bestand is veilig**. Geen bypass. Bestaande notulenlijst en instellingen (lokale Faster Whisper Small, opgeslagen Ollama Cloud-keuze/sleutelindicator) zichtbaar. Titel wordt na frontendstart weer ThoughtVault; onderscheid via ProductVersion en procespad. Geïnstalleerde 294 niet vervangen.

Voor de providertest tijdelijk bestaande lokale Ollama `http://localhost:11434`, **hermes3:8b** gekozen. Alleen fictief record `local-483b76b5-0010-4c97-a0be-803ce0f48250` geregenereerd, Standaard-profiel. Lokale HTTP/modelroute komt nu voorbij de oude CORS-blokkade, maar de bestaande broncontrole weigert het resultaat: **“De notule mist expliciete beperkingen uit de transcriptie. De bestaande notule en transcriptie zijn bewaard; er is geen nieuwe notule opgeslagen.”** Geen kwaliteitscontrole versoepeld. De volledige `local-transcripts.json` is na deze proef en de opnamecrash SHA-256-identiek aan de prelaunch-back-up (`NotesUnchanged=True`). Geen succesvolle notulengeneratie of inhoudelijke acceptatie.

Procescrash op nieuwe kandidaat tijdens gecombineerde opname met uitsluitend de bestaande fictieve WAV. Alleen eigen proces na padcontrole geforceerd gestopt; speler gestopt/disposed. `recording_1793209108071.loopback.wav`: 1.128.446 bytes, dataheader 1.120.210 bytes, **35,006563 s**; microfoonbestand: 1.128.362 bytes, dataheader 1.120.126 bytes, **35,003937 s**. Beide met ffprobe leesbaar als 16.000 Hz mono, zonder headerreparatie. Originelen apart bewaard onder `crash-pilot295`. Herstart slaagt; Opgeslagen opnames toont beide als 0:35 met herverwerkingsknop. Oude crashbestanden uit 294 tonen terecht nog geen duur. Geen automatische samenvoeging van crashkanalen of garantie voor stroomuitval/laatste fractie.

Portable ZIP: `%TEMP%/ThoughtVault-Pilot295/ThoughtVault_1.0.295-pilot.1_x64_portable.zip`, **112.480.320 bytes**, SHA-256 `b44d701730a53d3eb549ad2eaf7ac040a256ad4f9a9202fe2c61b782fa7ef639`. Bevat uitsluitend hoofdprogramma, resources en LEESMIJ; gebruikersdata/back-ups/modellen niet verpakt. Windows-bouwlogs blijven in dezelfde tijdelijke pilotbouwmap.


**Vervolg geblokkeerd om 18:41 CET:** herverwerking van de nieuwe loopback-opname via de bestaande knop start de gebundelde Faster Whisper-worker. Avast Gedragsschild meldt **Dreiging geblokkeerd — IDP.HELU.PSD11** voor `%TEMP%/ThoughtVault-Pilot295/portable/resources/faster-whisper-1.2.1/faster-whisper/faster-whisper.exe`. Deze worker was vooraf byte-identiek aan de geïnstalleerde resource. Runtime-import- en Microsoft-DLL-controles zijn dus geen bewijs dat antivirus de workeruitvoering accepteert. Geen false-positive vastgesteld, geen uitzondering/quarantaineherstel/vervangende worker of poging vanuit een ander pad. De detectie is een resterende pilotblokkade. De app bleef tijdens de blokkade op Transcriberen 10%, zonder onterechte klaar-melding. Alleen processen uit de eigen portable map gecontroleerd; worker was niet meer actief. Eigen app gestopt en herstart om de testverwerking te beëindigen. De lange opname-/transcriptie-/notulenketen blijft hierdoor open.

Oorspronkelijke instellingen na de retry zichtbaar teruggezet: lokale Faster Whisper Small Nederlands CPU int8, Ollama Cloud `https://ollama.com`, `gpt-oss:120b`, sleutelindicator opgeslagen. Geen cloudverwerking gestart. Testapp gesloten; geen opname of audiospeler achtergelaten.

Portable ZIP en technische logs lokaal overgebracht naar `build/windows-pilot-20261028/portable-295/`. Op Mac alleen archiefcontrole: ZIP-checksum/CRC en alle **888 bestands-SHA-256** gelijk aan Windows-manifest; hoofd-EXE-hash apart gecontroleerd. Dit is geen Mac-runtimeacceptatie. Pakket bevat geen audio, notulen, instellingen, back-ups of gebruikersmodellen. `NIET-UITROLLEN.txt` naast het pakket benoemt de antivirus- en inhoudsblokkade.
