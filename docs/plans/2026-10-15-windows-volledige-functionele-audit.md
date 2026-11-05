# Windows volledige functionele audit — uitvoeringsplan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to execute this plan task-by-task. Dit document autoriseert geen publicatie en bevat nog geen implementatie.

**Goal:** Een Windows-app die transcripties betrouwbaar afrondt, de bedoelde transcriptie-engines werkelijk kan downloaden en gebruiken, en dezelfde soundwave als macOS toont.

**Architecture:** Controleer de geïnstalleerde app van opname tot blijvende opslag en heropening. Koppel iedere fout aan één verwerking en scheid audioherkenning, notulengeneratie, opslag en weergave. Gebruik de bestaande macOS-wave als exacte ontwerp- en gedragsreferentie.

**Tech Stack:** Windows/Tauri/Rust, React/TypeScript, lokale transcriptie-engines, geconfigureerde notulenproviders; macOS SwiftUI als visuele referentie.

## Aanleiding en bewijsgrens

Michel meldt op 15 oktober dat iedere transcriptie een fout geeft, alleen Whisper downloadbaar is en de Windows-wave afwijkt van macOS. Behandel dit als de primaire reproductieopdracht; eerdere afzonderlijke PASS-resultaten sluiten deze klachten niet af.

Laatste auditwaarneming: Regenereren van eigen gedeeltelijk resultaat op 15 oktober 10:07–10:08 toont Voltooid; de eerder geverifieerde opslaglocatie meldt daarna nog has_notesfalse. Eerst actuele opslagidentiteit en leespad bewijzen voordat dit als dataverlies of succesvolle opslag wordt bestempeld.

Parakeet-kandidaat289 is niet geïnstalleerd. De succesvolle Dev-build heeft een andere applicatie-identiteit; een geschikte private productie-identiteitbuild ontbrak bij de eerdere controle. De actuele geïnstalleerde versie moet opnieuw worden vastgesteld. Bestaande NVIDIA-experimenten zijn geen bewijs van een leverbare engine.

## Werkwijze en bescherming

- Werk in /Volumes/SSD/codex-worktrees/windows-responsive-main/thoughtvault-native, branch codex/personal-corrections. Bewaar bestaande wijzigingen en NVIDIA-experimenten.
- Gebruik Royal TSX en de bestaande Dalf38 VPN. Neem vóór interactie verse appstatus en screenshot op. Bij gebruikerswerk: stop invoer.
- Gebruik eigen synthetische Nederlandse fixtures C/D/continuous en de bestaande eigen lange opname. Inspecteer alleen eigen inhoud of markerbooleans; geen privéopnamen, notities of sleutels.
- Maak vóór onderbrekingsproeven een gecontroleerde backup; vóór upgrade een volledige actuele backup van de werkelijk gebruikte opslag. Geen echte schijf vullen of gebruikershardware uitschakelen.
- Geen macOS-build/installatie/appstart voor deze audit. Bestaande bron en referentiebeelden zijn autoriteit. Kandidaat286 nooit installeren.
- Iedere bevinding krijgt build/source, fixture, exacte stappen, verwacht/werkelijk gedrag, foutfase, bewijs en herteststatus. Gebruik PASS, FAIL, BLOCKED of NOT TESTED; geen verzamel-PASS voor gedeeltelijke dekking.

## 1. P0 — Fout na iedere transcriptie

**Te onderzoeken bestanden:** windows/src/stores/recordingStore.ts, windows/src/stores/tasksStore.ts, windows/src/pages/TasksPage.tsx, windows/src/services/llm.ts, windows/src-tauri/src/transcribe/mod.rs. Lokaliseer daarnaast de actuele opslag-, event- en foutafhandelingscode vóór wijzigingen.

1. Leg versie, executable, proces, source/artifact en huidige model/providerkeuzes vast zonder credentials.
2. Verifieer welk opslagbestand de lopende app daadwerkelijk schrijft; vergelijk wijzigingstijd en eigen record-ID met de UI. Sluit meerdere instanties/opslagpaden uit.
3. Reproduceer met eigen D via import en via nieuwe opname; noteer de exacte foutmelding, fase, tijd en taak-ID. Geen fout wegklikken vóór vastlegging.
4. Volg één verwerking afzonderlijk door: import/capture → normalisatie → transcriptie → partial-save → notulen → definitieve opslag → UI-completion.
5. Vergelijk taskstatus, globalbar, detail en opslag na voltooiing en na normale herstart. Controleer dezelfde ID, duur, transcript, notulen en aantal records.
6. Herhaal met transcriptie zonder notulen, transcriptie plus notulen, regenereren en retry na gecontroleerde providerfout. Zo wordt de falende fase aantoonbaar.
7. Onderzoek pas daarna de oorzaak. Voeg voor een bewezen fout één gerichte regressietest toe in de bestaande testsuite en herstel de gedeelde oorzaak.

**Acceptatie:** tien opeenvolgende korte verwerkingen over import en opname zonder onverwachte fout; iedere eindstatus klopt met blijvende opslag en heropening. Opzettelijke providerfout geeft een begrijpelijke fout, behoudt transcript en herstelt zonder onbedoeld nieuw record. Een mislukte notulengeneratie wordt niet als mislukte audioherkenning gepresenteerd.

## 2. P1 — Engines downloaden, selecteren en werkelijk gebruiken

**Te onderzoeken bestanden:** windows/src/components/settings/ProcessingTab.tsx, windows/src-tauri/src/transcribe/mod.rs, windows/src-tauri/src/transcribe/nvidia.rs, build/runtime-verpakking en modelcache. Isolated Parakeet-bron: /tmp/thoughtvault-parakeet-cpu, gecontroleerde kandidaat58371104bb33e5c4da11582d7086f0cdaf599601; opnieuw verifiëren vóór gebruik.

Maak voor Whisper, Faster Whisper en NVIDIA Parakeet afzonderlijk een leveringsmatrix:

| Onderdeel | Vereist bewijs per engine |
|---|---|
| Beschikbaarheid | Zichtbaar in de echte geïnstalleerde app, met eerlijke CPU/GPU-voorwaarden |
| Download | Nieuw model/runtime downloaden, voortgang, fout, afbreken en hervatten |
| Integriteit | Model/runtimeversie, hash, benodigde DLLs en correcte pakketidentiteit |
| Selectie | Keuze blijft behouden na herstart; bestaande keuze wijzigt niet stilzwijgend |
| Uitvoering | Native diagnose bewijst welke engine daadwerkelijk draait; geen verborgen fallback |
| Kwaliteit | Eigen C/D/continuous: duur correct en verwachte markers aanwezig |
| Snelheid | Zelfde fixture/hardware: koude en warme run, totale wachttijd, inferentietijd indien meetbaar, RAM/VRAM |
| Fallback | Ontbrekend/corrupt model of ongeschikte GPU geeft duidelijke herstelroute |

Faster Whisper is een aparte uitvoeringsengine; alleen een Whisper-model downloaden bewijst Faster Whisper niet. Verifieer of deze engine al bestaat, gedeeltelijk bestaat of nog gebouwd moet worden en noteer dat expliciet. Voor Parakeet gelden dezelfde eisen; een los benchmarkprogramma of een dropdown telt niet als appintegratie.

**Acceptatie:** alle drie gewenste engines zijn geleverd en native getest, of een ontbrekend onderdeel staat expliciet als blokkade op de oplevering. Downloadbaar, selecteerbaar en daadwerkelijk gebruikt zijn drie aparte controles. De volledige audit is niet groen zolang een gevraagde engine ontbreekt.

## 3. P1 — Soundwave gelijk aan macOS

**Referentie:** macos/Views/Components/WaveformView.swift en macos/Services/AudioEnvelopeProcessor.swift; lokaliseer de werkelijk gebruikte macOS-wave op Home en Opnemen. **Windows:** windows/src/components/recording/WaveformVisualizer.tsx en bestaande WaveformVisualizer-tests; controleer callers Home/RecordingWidget/RecordingPage.

1. Leg vanuit bestaande referenties de geometrie, lagen, kleuren, gloed, lijnbreedte, uitslag en animatietiming vast.
2. Leg ook het gedrag vast: stilte, normale stem, luide piek, pauze, hervatten en stoppen. Gebruik dezelfde invoerniveaus en tijdlijn voor beide visualisaties.
3. Vergelijk op gelijke inhoudsafmetingen en schaal; beoordeel een animatiefragment naast stilstaande beelden.
4. Maak de kleinste gedeelde Windows-aanpassing die alle gebruikte wavevarianten bereikt; voorkom een afzonderlijke cosmetische Home-wave.
5. Controleer echte audioreactiviteit, soepele overgang, geen clipping, beperkt CPU-gebruik en reduced-motiongedrag.

**Acceptatie:** macOS-uiterlijk én beweging herkenbaar gelijk bij dezelfde invoer, op Home en Opnemen. Geen willekeurig bewegende decoratie als vervanging voor audioreactiviteit. Native Windows-visuele beoordeling vereist; een frontendtest is onvoldoende.

## 4. Volledige functionele matrix

| Gebied | Scenario's en acceptatie |
|---|---|
| Opname | Microfoon, systeemgeluid, gecombineerd; start/pauze/hervat/stop; correcte duur en behouden audio |
| Imports | WAV en overige geclaimde formaten, onjuist/ontoegankelijk bestand, korte en lange audio; geen stille mislukking |
| Wachtrij | Twee overlappende eigen jobs, unieke taakstatus, één globalbar, resultaatlink bij de juiste taak |
| Notulen | Standaard en eigen profiel, secties/volgorde, lege secties, titel, Nederlands, retry/regenereren |
| Opslag | Afsluiten/heropenen, partial, eigen backup/herstel, geen verloren of onbedoeld dubbele records |
| Herstel | Normaal sluiten en force-stop vóór transcript en na partial; melding over onderbroken werk; handmatig herstel |
| Foutpaden | Provider onbereikbaar, model ontbreekt, download onderbroken, gecontroleerde geïsoleerde schrijffout en deviceverlies |
| Bibliotheek | Zoeken/filteren/openen, recente lijst, juiste duur/titel, lege/loading/errorstatus, veilige annuleerroute |
| Export | Eigen TXT/PDF/clipboard; juiste inhoud en cancel/save; geen onverwachte markup of verloren navigatie |
| Integraties | Bekend toegestaan agenda-testevent en positieve Obsidian-export; unavailable is BLOCKED, geen PASS |
| Layout | Home/Opnemen/Taken/Settings/Detail: 1200×830, circa1567×974 en gemaximaliseerd, idle/actief/fout |
| Toegankelijkheid | Toetsenbord, focus na dialogen, labels/contrast, alle acties bereikbaar, reduced motion |
| Duur en hardware | Volledige eigen190:57-opname verwerkt/heropend; fysieke oudere Dell apart van CPU-affinityproxy |
| Installatie | Juiste identiteit, gecontroleerde MSI/hash/runtime, verse backup, upgrade behoudt data/instellingen |

Bestaande PASS-resultaten blijven bewijs voor hun toenmalige build en scenario. Herhaal relevante regressies na een wijziging; vul ontbrekende scenario's aan in plaats van dezelfde korte test eindeloos te herhalen.

## 5. Gates en oplevering

1. **Diagnosegate:** fout na iedere transcriptie reproduceerbaar en fase/oorzaak bewezen, inclusief opslagdiscrepantie.
2. **Correctiegate:** gerichte regressietest faalt vóór de fix en slaagt erna; relevante frontend/native tests en Windows-build slagen.
3. **Pakketgate:** geschikte private build met juiste identiteit, source/head/runtime/hash; geen productiepublicatie.
4. **Native gate:** veilige installatie en complete matrix op het werkelijke Windows-systeem. Geen afgerondeclaim op basis van CI alleen.
5. **Oplevering:** auditrapport met bewijs per rij, overzicht resterende blokkades, vergelijkende engineprestaties en soundwavebeelden/animatie. Iedere FAIL wordt opgelost en hertest of blijft een expliciete releaseblokkade.

**Verificatiecommando's na wijzigingen:** vanuit windows `npx vitest run` en `npm run build`; vanuit windows/src-tauri de relevante `cargo test`-tests. Gebruik docs/WINDOWS-BUILD-WORKFLOW.md voor de actuele Windows-CI/installatiegates. Platformafhankelijke tests draaien op Windows; Mac-resultaten vervangen die niet.

**Buiten deze planstap:** implementatie, builds, installatie, commits, pushes en publicatie. Niet onderzocht in deze planstap: de actuele oorzaak van Michels foutmelding, huidige engineleverbaarheid en live wavepariteit. Dat zijn de eerste uitvoeringsopdrachten.


## Uitvoering 15 oktober — kandidaat 1.0.290

Michel heeft na het plan expliciet de correctie en volledige uitvoering geautoriseerd. De bovenstaande beperking “buiten deze planstap” beschrijft alleen het oorspronkelijke schrijven van het plan. Uitvoering gebeurt geïsoleerd op `codex/windows-audit290`; de oorspronkelijke dirty NVIDIA-experimenten blijven behouden.

| Gate | Huidig bewijs | Status |
|---|---|---|
| Tegenstrijdige notulenstatus | HTML aanwezig, has_notes=false na lokaal regenereren; gerichte regressies falen voor en slagen na correctie | Broncorrectie PASS; native hertest OPEN |
| Onverwachte fout bij iedere transcriptie | Eén eigen korte import op288 foutloos; tien opeenvolgende import/opnameverwerkingen ontbreken | OPEN |
| Frontend/native regressies |110 frontendtests, TypeScript/Vite en35 Windows native tests geslaagd;3 modelafhankelijke native tests genegeerd | Gewone regressies PASS |
| Parakeet runtime | Vers model met gepinde hash, CPU,11outputs,Alex62/Monday62 in54.5093249s | Runtime PASS; appintegratie OPEN |
| Faster Whisper runtime | Werkelijke1.2.1 CPU/int8 packaged startup en ondertekende CRT-afhankelijkheden gecontroleerd | Runtime PASS:3.9916073s,Alex1/Monday1,progress100; appintegratie OPEN |
| Soundwave | Gedeelde amplitude/spectrumverwerking, geometrie en timing vergeleken; supportglow gelijkgetrokken | Bron/test PASS; native motion OPEN |
| Installatie en levering | Geen geschikte volledige private CI/MSI voor290; geen installatie verricht | BLOCKED |
| Overige functionele matrix | Herstelmelding, device/writeerrors, positieve integraties, full190:57 en fysieke oudere Dell ontbreken nog | OPEN |

Gedetailleerde bron-, proces-, fixture- en uitkomstgegevens staan in `docs/qa/windows-functional-audit-2026-10-11.md`. Runtimeproeven vervangen geen installatie- of native acceptatiebewijs.
