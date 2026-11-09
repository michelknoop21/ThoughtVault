# ThoughtVault Windows collega-uitrol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Native uitvoering is het voorstel; de gebruiker kiest de uitvoermethode bij review.

**Goal:** ThoughtVault betrouwbaar afmaken en gecontroleerd beschikbaar maken voor Windows-collega's, met bewijs van de volledige gebruiksketen en herstel.

**Architecture:** Hergebruik de bestaande Tauri/React-app, lokale transcriptieworkers, gekozen notulenprovider en centrale SSH-jobs op Dalf38. Los eerst de werkelijk waargenomen fouten op; maak daarna één vaste releasekandidaat en test exact dat pakket. Gebruik bestaande publicatie en updatermechanismen, met een kleine collega-pilot vóór brede uitrol.

**Tech Stack:** Tauri 2, Rust, React/TypeScript, Vitest, Python unittest, PowerShell, bestaande WiX/MSI-verpakking en SSH.

**Spec:** [Windows-collega-uitrol](../specs/2026-11-09-windows-collega-uitrol.md). Lees beide documenten; de spec bevat de gecontroleerde jobs en bronhashes.

## Global Constraints

- Windows x64 eerst; iOS/iPadOS blijven uitgesteld.
- Alleen bestaande SSH-beheerlaag; geen nieuwe beheerinfrastructuur of toolchains.
- Alleen aantoonbare releaseblokkades oplossen; geen redesign of extra features.
- Ontwikkelwerk, builds, tijdelijke bestanden en bewijs op de externe SSD.
- Geen bestaande persoonlijke data, instellingen of credentials overschrijven.
- Eerste proefroute: bestaande Faster Whisper Small CPU int8 + Ollama Cloud `gpt-oss:120b`; alleen behouden na inhoudelijke en praktische acceptatie.
- Geen stille model/providerwissel, ongerichte retries of afgezwakte inhoudscontrole.
- Twee à drie Windows-collega's starten; na vijf werkdagen zonder blokkerende fouten uitbreiden.
- Een geslaagde job is alleen bewijs voor haar assertions, invoer, model, bronversie en pakket.

## Review Focus

1. Foutief of leeg ASR-resultaat wordt nooit een verzonnen, goedgekeurde notule — taak 2.
2. Een nieuwe Windows-gebruiker zonder ontwikkeltools/credentials kan werkelijk beginnen — taak 4 en 6.
3. Netwerkverlies of herstart tijdens verwerking bewaart opname en voorkomt dubbel werk — taak 3.
4. Een echte lange vergadering houdt acties aan begin, midden en einde vast — taak 5.
5. Upgrade of rollback bewaart bestaande én later gemaakte gebruikersgegevens — taak 6.

## Werkafspraak en bestanden

Werk vanaf `/Volumes/SSD/codex-worktrees/thoughtvault-pilot-20261105`, na taak 1.
De oorspronkelijke checkout bevat ander werk en wordt niet overschreven.
Vervang `RC_VERSION`, `SOURCE_COMMIT`, `NATIVE_JOB`, `MSI_REQUEST` en `JOBID` in
onderstaande voorbeelden uitsluitend door vastgelegde waarden uit het bewijs.

| Bestand/groep | Verantwoordelijkheid |
|---|---|
| `docs/qa/colleague-rollout-2026-11-09/STATUS.md` (nieuw) | Eén actuele voortgang, open blockers en bewijspaden; eerdere rapporten blijven historisch |
| `docs/qa/colleague-rollout-2026-11-09/release-manifest.json` (nieuw) | Broncommit/hash, versie, configuratie, native/MSI/signaturehash, jobs en besluit |
| `windows/src/services/localPipeline.ts`, `llm.ts`, `notuleAudit.ts` | Bestaande verwerking, generatie en inhoudscontrole |
| `windows/src/services/__tests__/…` | Gerichte regressies op aangetoonde fouten; bestaande fixtures hergebruiken |
| `windows/src-tauri/src/commands/audio.rs`, `commands/filesystem.rs`, `transcribe/`, `audio/` | Alleen aanpassen wanneer bewijs een native fout aanwijst |
| `windows/src/components/onboarding/OnboardingWizard.tsx`, `settings/ProcessingTab.tsx`, `windows/src/stores/settingsStore.ts` | Eerste start en bewezen verwerkingskeuze |
| `windows/src/components/transcripts/TranscriptDetail.tsx` en bestaande exportcaller | Bewaren/heropenen/export; caller lokaliseren vóór wijzigen |
| `scripts/qa/windows-colleague-{short,imports,long}.ps1` (nieuw indien nodig) | Incheckbare versies van bestaande Dalf38-scenario's, geen nieuwe testframeworks |
| `scripts/qa/windows-colleague-{short,imports,long}.json` (nieuw indien nodig) | Bestaande `acceptance-register`-definities met scriptsha256 |
| `windows/src-tauri/installer/main.wxs`, `tauri.conf.json`, `scripts/publish-release.py` | Bestaande installer/publicatie; alleen bewezen defecten corrigeren |
| `docs/WINDOWS-PILOT.md`, `docs/CHANGELOG.md`, `docs/RELEASE.md` | De actuele collega-instructie, wijzigingen en publicatie/herstel |

Bewijs met grote artifacts blijft onder `build/colleague-rollout-20261109/` op de
externe SSD. Commit alleen kleine controlebestanden en synthetische fixtures;
geen persoonlijke opnamen, stores, credentials of private downloadcapability.

---

### Task 1: Eén reproduceerbare bron en korte blocker-lijst

**Files:** Maak `docs/qa/colleague-rollout-2026-11-09/{STATUS.md,release-manifest.json}`;
verzoen uitsluitend gewijzigde productbestanden uit de 1.0.305-upload met de Mac-bron.

**Interfaces:** Consumeert native job `19ab8be2adf747468acd886ca132f280`, bijbehorend
source-manifest en Windows `source-provenance.json`. Produceert één `SOURCE_COMMIT`
en een bestand-voor-bestand gecontroleerde basis voor alle volgende taken.

- [x] Haal de kleine jobmetadata, source-manifesten en gewijzigde bronbestanden via SFTP naar de externe SSD; controleer SHA256 vóór gebruik. Geen hele caches ophalen.
- [x] Vergelijk de 1.0.305-bron met basis `4de88a4`; behoud de onderbouwde 301–305-fixes, hun tests en provenance in Git. Geen blind kopiëren over een checkout.
- [x] Leg de daadwerkelijke oorzaak per gefaalde korte/MP4/uurproef vast: productfout, terechte inhoudsafwijzing, of defect scenario. Houd bewijstekort apart van een productbug.
- [x] Controleer `admin-status`, actuele jobs, desktopstatus en geïnstalleerde versie; start geen concurrerende installatie of appproef.
- [x] Commit de verzoende bron en status. **Klaar:** de geïnstalleerde basis is tot bronbestanden herleidbaar en maximaal één blocker-lijst is leidend.

### Task 2: Brongetrouwe notulen die ook bruikbaar slagen

**Files:** `windows/src/services/{llm,notuleAudit,notuleValidation}.ts`;
tests `notuleAudit.test.ts`, `llm.audit-integration.test.ts`, `llm.decimal-constraints.test.ts`,
`qa-short-quality/modelcontrole-regressiefixtures.json`; bewaar nieuw echt modelbewijs in de QA-map.

**Interfaces:** Behoud `LLMService.generateNotulen(transcription, profile, onProgress?, participants?, quickNote?): Promise<string>`
en `auditNotule(source, html, quickNote, request, requiredSentences?): Promise<void>`.
Afwijzing blijft `NotuleReviewError` met bewaard concept; geen nieuwe parallelle pipeline.

- [x] Reproduceer één recente afwijzing met de echte gekozen provider/model en exacte productieprompt; bewaar requestbody en antwoord zonder headers/secrets. De Hermes-proef is geen vervangend bewijs.
- [x] Voeg voor de gevonden oorzaak een falende regressie toe. Assert: correcte parafrase mag slagen; fout bedrag `15.000` in plaats van `12.450`, ontbrekende tweede actie, omgekeerd verbod en onbegrijpelijke Opname10-bron mogen niet slagen.
- [x] Run vanuit `windows`: `npx --no-install vitest run src/services/__tests__/notuleAudit.test.ts src/services/__tests__/llm.audit-integration.test.ts src/services/__tests__/llm.decimal-constraints.test.ts`. Bevestig de nieuwe regressiefout vóór de minimale reparatie.
- [ ] Corrigeer uitsluitend de aangetoonde oorzaak in de bestaande generatie/parser/validatie; behoud onzekerheid, bronbewijs en afgewezen concepten. Maak geen uitzonderingsregel voor één voorbeeldtekst.
- [x] Herhaal gerichte tests en de bestaande prepare/replay-route met een nieuwe bewijslocatie. Beoordeel inhoud onafhankelijk van job-exitcode: bedragen, personen, acties, datums, voorwaarden en geen ononderbouwde claims.
- [ ] Verifieer drie verschillende korte fictieve vergaderingen: correcte gevallen slagen elk één keer; negatieve gevallen blijven review/afgewezen. Een altijd afwijzende audit is geen productacceptatie.
- [ ] Commit met request-/responsehashes en conclusie. **Klaar:** zowel juiste acceptatie als gerichte afwijzing aangetoond op de gekozen route.

### Task 3: Korte volledige appketen en import herstellen

**Files:** `localPipeline.ts`, bestaande recording/transcriptstores en tests;
`commands/filesystem.rs`, `transcribe/` alleen bij bewezen native oorzaak;
incheckbare bestaande korte/importscenario's onder `scripts/qa/`.

**Interfaces:** Behoud `processLocally(filePath, profileId, mode, participants?, durationSeconds?, retryTaskId?): Promise<void>`.
Hergebruik `acceptance-register -Definition …` en `acceptance-start -Name …`;
scenario's leveren resultaat-JSON met fixturehash, appversie, stappen/assertions en exports.

- [ ] Neem de bestaande korte en MP4-scenario's over; verwijder tests die op toevallige schermcoördinaten/teksten of een modelwissel in de eindcleanup steunen. Gebruik bestaande UI Automation-identiteiten en assert de waargenomen appstatus.
- [ ] Voeg een falende regressie toe voor elke aangetoonde productfout; test van een defect scenario moet op de ongewijzigde app kunnen worden gerepareerd. Run bestaande pipeline-retry- en terminaltests vóór en na reparatie.
- [ ] Repareer het gedeelde oorzaakpad. Geldige WAV/MP3/M4A/MP4/AAC/FLAC/OGG wordt leesbare audio; lege, corrupte en MP4-zonder-audio-invoer geeft begrijpelijke afwijzing zonder gegevensverlies.
- [ ] Voer de echte geïnstalleerde appproef uit: gecombineerd opnemen, pauzeren/hervatten, stoppen, gekozen transcriptie/notulen, bewerken, bewaren, herstart/heropenen, TXT en leesbare PDF. Controleer exportinhoud, niet alleen bestandsexistentie.
- [ ] Onderbreek netwerk tijdens modelverwerking; opname en transcript blijven behouden, fout/retry is duidelijk en bewust hervatten maakt geen dubbel record. Test ook herstart tijdens verwerking en geweigerde microfoontoegang.
- [ ] Laat tien opeenvolgende korte runs slagen zonder crash, hang, dubbele records of blijvend proces-/geheugengroei. Noteer duur en piek-RAM; afwijkingen tegenover de eerste warme run worden verklaard.
- [ ] Commit productfixes, scenario's en bewijs. **Klaar:** alle zeven formaten en de korte appketen slagen op één gekozen configuratie; negatieve gevallen falen gecontroleerd.

### Task 4: Eerste start voor een collega afronden

**Files:** `OnboardingWizard.tsx`, `ProcessingTab.tsx`, `settingsStore.ts`,
`windows/src/stores/authStore.ts` en bestaande gerichte tests; `docs/WINDOWS-PILOT.md`.

**Interfaces:** Gebruikt bestaande auth/credentialopslag en gekozen standaardconfiguratie;
levert een werkende startflow voor een nieuw standaard-Windowsaccount zonder ontwikkeltools.

- [ ] Loop de eerste start op een verse testidentiteit door: eigen account of bestaande lokale modus, noodzakelijke providerautorisatie, modelbeschikbaarheid, microfoontoegang en opslaglocatie.
- [ ] Test dat ontbrekende credentials/model/netwerk tot een concrete herstelactie leidt, zonder verborgen download, Michel-credential, PowerShell-opdracht of ontwikkelaar.
- [ ] Maak een falende onboarding/settings-regressie voor de aangetoonde blokkade en pas alleen die flow aan. Defaults gelden voor nieuwe gebruikers; bestaande voorkeuren blijven behouden.
- [ ] Toon voor de pilot één bewezen aanbevolen route en leg lokale transcriptie versus externe notulenverwerking begrijpelijk uit. Laat een onbewezen noodzakelijke kernfunctie niet als werkend zien; niet-kernintegraties zijn opt-in.
- [ ] Schrijf één korte collega-instructie: installeren, eerste start, opnemen, reviewconcept herkennen, export en hulp. Vul vóór verzending het echte supportcontact en toegangsproces in.
- [ ] Commit en laat de verse identiteit zonder ontwikkelaar de eerste complete notule produceren. **Klaar:** onboarding is uitvoerbaar door een collega.

### Task 5: Eén releasekandidaat bevriezen en fysiek accepteren

**Files:** `VERSION` en bestaande gesynchroniseerde configs; `release-manifest.json`;
bestaande en ingecheckte lange scenario; `STATUS.md`.

**Interfaces:** Consumeert geslaagde taken 1–4; produceert één `RC_VERSION`,
`SOURCE_COMMIT`, `NATIVE_JOB`, `MSI_REQUEST`, getekende MSI en volledige bewijsverwijzingen.

- [ ] Controleer de laatst gebruikte versies/feeds en kies één nieuw ongebruikt hoger patchnummer. Run `scripts/sync-version.sh`; run één volledige frontendtestsuite, `npm run build`, relevante Rust-tests en `python3 -m unittest discover -s scripts/tests`.
- [ ] Bouw via bestaande geregistreerde centrale native job; start `msi-request -Id NATIVE_JOB`, vervolgens `msi-run -Id MSI_REQUEST`. Controleer native provenance, alle payloadhashes, ICE-uitvoer en afwezigheid van credentialhelpers. Beoordeel resterende ICE03/WebView2-waarschuwing met een echte installatietest.
- [ ] Onderteken exact deze MSI met de bestaande Mac-updaterkey. Verifieer juiste publieke sleutel, exacte MSI-bytes en negatieve wijzigingsproef. Authenticode en updaterondertekening afzonderlijk rapporteren.
- [ ] Installeer exact die kandidaat via bestaande `package-register`/`package-upgrade`, met verse gecontroleerde gebruikersback-up. Laat de korte complete keten van taak 3 opnieuw slagen op het verpakte artifact.
- [ ] Test microfoon, systeemaudio en gecombineerd afzonderlijk. Laat iemand alleen waar nodig een vaste korte tekst fysiek inspreken en beide kanalen terugluisteren; automatiseer de overige bediening via SSH. Leg hoorbare verstaanbaarheid, pauze/hervatten en apparaatverlies vast.
- [ ] Neem ≥60 minuten representatieve, gevarieerde fictieve vergadering op met gemarkeerde feiten/acties aan begin, midden en einde; geen herhaling van één clip als enige inhoudsproef. Verwerk tot transcript/notule, heropen en exporteer; beoordeel alle gemarkeerde feiten tegen de opname.
- [ ] Meet opname-/verwerkingstijd en piek-RAM. Pilotcriterium: geen crash/hang of groeiende wachtrij; na opwarming verwerking van het uurresultaat binnen 60 minuten op Dalf38. Is de combinatie te traag of inhoudelijk onvoldoende, dan geen release; herbeoordeel de aanbevolen configuratie met dezelfde inhoudsproef.
- [ ] Commit klein bewijs en RC-manifest. **Klaar:** exact de te leveren MSI heeft volledige korte, lange en fysieke audioacceptatie. Een productwijziging erna vereist nieuw pakket en herhaling van getroffen proeven.

### Task 6: Installatie, updater en echt herstel bewijzen

**Files:** Bestaande centrale package-definities, QA-bewijs, `docs/WINDOWS-PILOT.md`;
installer-/updatercode alleen wijzigen bij bewezen fout.

**Interfaces:** Gebruik `package-install -Name …`, `package-upgrade -Name …`,
`package-rollback -Id INSTALLJOB`, `ops-status/ops-wait` uit de bestaande beheerlaag.
Produceert herstelbewijs voor de RC, geen alleen-op-fixture beheerproef.

- [ ] Installeer de RC op een verse Windows x64-gebruiker of aparte beschikbare testmachine: geen ontwikkeltools, standaardrechten/UAC, Defender actief, WebView2-afhankelijkheid gecontroleerd. Dalf38 met bestaande dependencies geldt niet als schone installatie.
- [ ] Controleer shortcuts, eerste start, gebruikersisolatie, bestanden met spaties/accenten en een 125%/150%-DPI scherm. Als geen verse omgeving beschikbaar is, noteer de ontbrekende proef en regel de eerste pilotmachine hiervoor vóór bredere uitrol.
- [ ] Test echte upgrade vanaf de bewaarde voorganger met fictieve notulen/opnamen/instellingen, en een verse manifest-gecontroleerde back-up. Heropen en speel bestaande inhoud af; voeg daarna een nieuw fictief record toe.
- [ ] Rollback de upgrade via de centrale route, controleer teruggekeerde versie en oude data, en toon dat het later gemaakte record herstelbaar bewaard is. Upgrade daarna opnieuw naar RC; laat opname/openen/export nogmaals slagen.
- [ ] Test updater met exact de RC op een afzonderlijke testinstallatie of bestaand testkanaal: correcte feed/signature installeert, gewijzigde signature wordt geweigerd. Laat de algemene stabiele feed nog ongemoeid.
- [ ] Leg packagehash, versie, install-/rollbackjobs, backupmanifest en waarneembare heropening vast. **Klaar:** installer, updater en daadwerkelijk dataherstel werken voor deze kandidaat.

### Task 7: Klaarzetten en eerste collega-pilot uitrollen

**Files:** `release-manifest.json`, `STATUS.md`, `docs/{WINDOWS-PILOT,CHANGELOG,RELEASE}.md`;
bestaande publicatiescripts en het bestaande distributiekanaal.

**Interfaces:** Consumeert alle geslaagde gates; levert één gecontroleerde Windows-download
voor de aangewezen twee à drie collega's, met identieke MSI-/signaturehashes.

- [ ] Leg namen, Windows-apparaten, eigen toegangsroute, supportcontact en pilotmoment vast. Inventariseer wie de bestaande stabiele updater ontvangt vóór wijziging van die feed.
- [ ] Verzamel één releasebesluit: bron, pakket, audio, inhoud, import/export, herstel en onboarding allemaal PASS; geen kritieke/hoge fout open. Een beperkt ondersteunde optionele functie staat expliciet in de instructie.
- [ ] Voer `python3 scripts/test-publish-release.py` uit en controleer de actuele productie-uploadprocedure. Gebruik de al bestaande beperkte distributie als de stabiele feed meer mensen raakt dan de pilot; bouw geen nieuw pilotplatform en gebruik geen andere dev-binary als vervanging voor de geaccepteerde MSI.
- [ ] Zet het geaccepteerde artifact en de instructie klaar. Vraag alleen indien nog vereist de finale publicatiegoedkeuring voor deze concrete versie, hash, bestemming en doelgroep; daarvoor is alle technische voorbereiding klaar.
- [ ] Publiceer na die goedkeuring en download vanaf de daadwerkelijke collega-URL. Vergelijk SHA256/signature, installeer op de eerste collega-machine en maak daar de eerste complete notule. Behoud voorganger en herstelprocedure.
- [ ] Lever de uitnodigingstekst aan; verzend alleen als de gebruiker dat expliciet opdraagt. **Klaar:** twee à drie collega's hebben toegang en één collega heeft aantoonbaar de complete flow doorlopen.

### Task 8: Vijf werkdagen volgen en overige collega's toelaten

**Files:** `STATUS.md`, releasebesluit en bestaande issue-/supportlijst; geen nieuw dashboard.

**Interfaces:** Gebruikt bestaande feedbackvoorziening en supportcontact;
levert een gedocumenteerd GO/NO-GO voor overige Windows-collega's.

- [ ] Laat iedere pilotcollega de eerste werkdag één echte toegestane vergadering verwerken, controleren, heropenen en exporteren. Bewaar alleen noodzakelijke geanonimiseerde probleemgegevens met toestemming.
- [ ] Houd vijf werkdagen bij: versie, complete runs, crashes/hangs, ontbrekende/verzonnen feiten, opnameproblemen, bewaarfouten en benodigde hulp. Geen volledige vergaderinhoud verzamelen voor tellingen.
- [ ] Bij dataverlies, onterechte inhoudsgoedkeuring of blokkerende kernflow: stop uitbreiding, bied gecontroleerd herstel, maak een gerichte regressie en nieuwe RC; herhaal getroffen gates vóór nieuwe pilot.
- [ ] Bij vijf werkdagen zonder deze blockers: leg gebruikerservaring en eventuele kleine beperkingen vast, stel bestaande download/feed voor de overige Windows-collega's beschikbaar en lever dezelfde startinstructie.
- [ ] Controleer eigen interne tijdelijke bestanden, verwijder vervangbare taskbestanden, verplaats te bewaren bewijs naar de externe SSD met hashcontrole en meet verwijderde allocatie. Laat actief/onduidelijk werk staan en benoem het.
- [ ] Sluit af met feitelijke versies, downloadbestemming, support/herstel en wat buiten scope blijft. **Klaar:** Windows-collega's kunnen de geaccepteerde release dagelijks gebruiken; iOS/iPadOS blijft een afzonderlijk traject.

## Uitvoeringsvolgorde en stopregels

Taken 1–4 vormen het reparatiepakket; 5–6 zijn de acceptatie van één artifact;
7 is de eerste uitrol; 8 de verbreding. Geen nieuwe inventarisatie van de hele app.
Bij een fout eerst oorzaak + gerichte regressie, daarna alleen getroffen controles
herhalen. De uurproef start pas nadat korte keten en inhoud goed zijn.

De agent voert voorbereiding, reparaties, bouwen en tests zelfstandig uit binnen
de bestaande machtiging. Menselijke afhankelijkheden zijn beperkt tot fysieke
testspraak/terugluisteren, benodigde eigen collega-identiteiten, review van dit
plan en eventueel finale publicatie als de bestemming/doelgroep nog niet is
gemachtigd. Het schema hangt af van deze proeven, geen vooraf beloofde releasedatum.

## Zelfreview

- Scope van de spec gedekt door taken 1–8; bestaande 1.0.300-controles niet opnieuw als 1.0.305-acceptatie gebruikt.
- Review Focus gekoppeld aan taken 2/3/4/5/6 met concrete positieve en negatieve proeven.
- Bestaande functies, CLI-commando's en scenario-interface behouden; geen nieuw beheerframework.
- Bronreconciliatie komt vóór reparatie; publicatie en collega-acceptatie zijn afzonderlijke opleveringen.
- Dit document plant het werk; het voert geen productwijziging, installatie of publicatie uit.
