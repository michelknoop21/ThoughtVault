---
target: "https://thoughtvault.yinga.ai/"
total_score: 19
max_score: 36
na_heuristics: 7
p0_count: 1
p1_count: 3
timestamp: 2026-10-07T14-19-39Z
slug: thoughtvault-yinga-ai
---
Method: dual-agent (A: designreview · B: detector en browsermetingen)

# Critique thoughtvault.yinga.ai, 7 oktober 2026

## Design Health Score

| # | Heuristiek | Score | Kernpunt |
|---|---|---|---|
| 1 | Zichtbaarheid van systeemstatus | 3 | Demo toont voortgang en pauze. De downloadrijen tonen geen versie, grootte of signaal dat je de site verlaat. |
| 2 | Aansluiting op de echte wereld | 2 | "vault" en "Obsidian-vault" staan in de H1 en de lead en worden nergens uitgelegd. |
| 3 | Controle en vrijheid | 3 | Escape sluit menu en dialoog. Download opent een tab op een ander domein zonder weg terug. |
| 4 | Consistentie en standaarden | 1 | Download landt op een anders genoemd en anders vormgegeven product. De primaire knopstijl gaat nooit naar download. |
| 5 | Foutpreventie | 1 | Geen versie of bestandsnaam op de pagina. De doelpagina bood in de test een ARM64-MSI uit maart aan als "Windows". |
| 6 | Herkenning boven herinnering | 3 | Labels zijn helder. De accountvereiste staat pas onderaan (y 5834 van 6315 px). |
| 7 | Flexibiliteit en efficiëntie | n/a | Landingspagina voor eenmalig bezoek. |
| 8 | Esthetiek en minimalisme | 3 | Rustig. Dezelfde slogan komt vijf keer terug en 12px is de meest gebruikte lettergrootte. |
| 9 | Herstel van fouten | 1 | `/releases/` op het eigen domein toont "Versie niet beschikbaar" met dode knoppen. Elk contact is `mailto:`. |
| 10 | Hulp en documentatie | 2 | Zeven eerlijke FAQ-items. Geen installatie-uitleg, privacyverklaring of supportpagina. |
| **Totaal** | | **19/36** | **Acceptabel (53%)** |

## Design Specificity Verdict

De schil is een sjabloon, het midden is productspecifiek, en de pagina verkoopt een ander product dan PRODUCT.md beschrijft.

LLM-beoordeling: PRODUCT.md noemt Nederlandse zakelijke gebruikers die betrouwbare notulen willen. De pagina verkoopt een Obsidian-notitietool. In HTML en script komt "vault" 32 keer voor, "notulen" 14 keer en "vergader" 2 keer. De voorbeeldnotitie start op het profiel "Idee", omdat `chooseProfile('idea')` de in de HTML gemarkeerde "Vergadering" overschrijft. De zwevende pill-navigatie, de eyebrows met "01 / VASTLEGGEN", lila op bijna-zwart met radiale gloed en Geist als enig lettertype passen op elk SaaS-product. Dat is de look die PRODUCT.md als anti-referentie noemt. Geen van de app-kleuren `#9048F0`, `#6048F0` of `#D890F0` staat in de CSS. Productspecifiek zijn de demo in vier stappen, de profielwisselaar, de keuze Lokaal of Cloud en de twee echte macOS-screenshots.

Deterministische scan: de CLI gaf één regel (`overused-font`, Geist, `index.html:11`). In de browser meldde de detector 79 treffers: `ai-color-palette` 65, `radial-spotlight-glow` 4, `line-length` 7, `nested-cards` 5, `numbered-section-labels` 3, `overused-font` 1. Van de 65 kleurtreffers zijn 43 de losse balkjes van één golfvorm; het gaat om ongeveer 6 vlakken en 10 tekstelementen. `nested-cards` op `div.nav-core` en `text-occlusion` zijn vals-positief. De detector en de review komen op hetzelfde uit: paars-op-donker, gloed, genummerde labels en Geist.

Overlays: de injectie lukte alleen in een headless testbrowser. Er is geen zichtbare overlay in een browser van de gebruiker. Screenshot met overlays: `scratchpad/critique-b/out/detector-overlay-1440-full-grant.png`.

## Overall Impression

De pagina is rustig en technisch verzorgd, en de demo legt het product in vijftien seconden uit. Hij stelt de verkeerde vraag centraal (waar bewaar ik mijn gedachten) en laat de bezoeker op het beslissende moment los op een pagina van een ander merk. De grootste winst zit in de downloadroute.

## What's Working

- De hero-demo is pauzeerbaar, heeft een voortgangsbalk per stap en pijltjesnavigatie, stopt buiten beeld en toont bij reduced motion direct de eindstap. Het onderschrift zegt eerlijk "Een verkort voorbeeld."
- De copy is gewoon Nederlands zonder gedachtestreepjes. De FAQ noemt zelf de grenzen: "Controleer vóór het delen altijd namen, besluiten en actiepunten."
- De basis klopt: bodytekst 8,52:1, skip-link, `inert` mobiel menu met focus-trap, 0 console-fouten, geen horizontale scroll van 320 tot 1920 px.

## Priority Issues

**[P0] Download stuurt de bezoeker naar een ander merk op een ander domein.**
Beide downloadrijen wijzen naar `https://n8n.prezent.nl/tstudio/download/#download`. Die pagina heet "Transcript Studio", heeft een licht thema met roze accent en een logo dat 502 gaf. In de test stonden er `TranscriptStudio-1.0.242.dmg` (30 juni) en, via auto-detectie op een Mac, `TranscriptStudio_1.0.42_arm64.msi` (12 maart). `ThoughtVault_1.0.257_x64.msi` zat achter een klein linkje. Een voorzichtige gebruiker ziet een andere naam, een n8n-hostnaam en een installer met weer een andere naam, en haakt af. Fix: zet het downloadblok op thoughtvault.yinga.ai met directe links naar bestanden met de naam ThoughtVault, en toon versie, grootte en datum. De installers geven al 200 onder `/releases/`. Commando: `/impeccable harden`.

**[P1] De pagina verkoopt een Obsidian-tool, niet betrouwbare notulen.**
H1, titel, og-tags en het standaardprofiel wijzen op persoonlijk kennisbeheer. "Notulen" verschijnt voor het eerst als bijzin in de lead. Fix: open met de uitkomst van een overleg, laat het voorbeeld op "Vergadering" starten, en maak Obsidian één feature en één FAQ. Commando: `/impeccable clarify`.

**[P1] De knophiërarchie staat op zijn kop en de accountvereiste komt te laat.**
De primaire knop in de hero ("Zie hoe het werkt") scrolt 101 px naar een demo die op 1440 px al naast de tekst staat. Download is een tekstlink van 14px. In de downloadsectie wint "Plan een demo". De app werkt alleen met een account dat je op de site niet kunt aanmaken. Fix: kies één actie. Loopt toegang via Yinga, maak dan "Vraag toegang aan" primair met "Al een account? Download" ernaast. Commando: `/impeccable shape`.

**[P1] Geen vertrouwenslaag op de spannende momenten.**
"privacy" en "AVG" komen 0 keer voor. De cloudtekst noemt geen verwerker, land of bewaartermijn. De sterkste geruststelling, "Audio verlaat je apparaat niet.", staat alleen als kleine tekst in een screenshot. Bij de download staat geen uitgever of ondertekening. Fix: een blok "Waar gaan je opnames heen" onder "03 / REGIE" met server, land en bewaartermijn, een privacypagina, en versie plus uitgever onder elke downloadrij. Commando: `/impeccable harden`.

**[P2] Site en app zijn twee visuele merken, met toegankelijkheidsgaten.**
De site is alleen donker, de app is licht en donker met violet en ronde koppen. De focusring `#c6a6fa` haalt 1,70:1 op de lichte sectie en is daar op de profielknoppen onzichtbaar. Tekst onder 4,5:1, alles 12px: "Van gesprek naar overzicht" 2,81, de labels in `.vault-route` 3,26, de plustekens 3,28, de stapnummers 3,80. Klikdoelen: footerlinks 20 px hoog, demoknoppen 36 tot 40 px. Commando: `/impeccable colorize`, daarna `/impeccable polish`.

## Persona Red Flags

**Jordan (eerste bezoek):** leest "vault" en "Obsidian-vault" in de eerste twee zinnen zonder uitleg. Klikt op de grote knop en er gebeurt bijna niets. Klikt op "Download voor macOS", komt bij "Transcript Studio" en denkt op de verkeerde site te zijn.

**Riley (stresstest):** `/releases/` toont "Versie niet beschikbaar" met knoppen naar `#`. De pagina belooft "Windows 11 · x64 en ARM64", terwijl de ARM64-build 1.0.42 uit maart is en x64 1.0.257 van vandaag. De vergrote screenshot toont een debugregel die begint met "live ondevice true fmt". Zonder JavaScript zijn de voorbeeldnotitie en de hele featurelijst leeg.

**Casey (mobiel, één hand):** download is het vierde menu-item en staat op 6363 van 7418 px, onder "Plan een demo". De tik levert een DMG- of MSI-pagina op die op een telefoon niets doet. De vaste navigatie neemt 103 van 844 px in.

**MKB-manager die verantwoordelijk is voor notulen:** ziet nergens een echte notule met aanwezigen, besluiten en actiehouders. Op de vraag over gegevens luidt het antwoord "Dat hangt af van je gekozen verwerking". Er spelen drie namen (Yinga, Prezent, prezent.nl als downloadhost) zonder uitleg wie de opnames bewaart.

## Minor Observations

- `thoughtvault-mark.png` is 625 kB voor een weergave van 72x88 px en is 67% van het paginagewicht.
- De navigatie is 110 px hoog op desktop door dat logo.
- In de notulensectie staat een `h3` vóór zijn `h2` in de DOM; de demo bevat twee `h2`'s.
- "Voor jouw werkplek" linkt naar `#download`; het label zegt dat niet.
- De uppercase labels zijn met de hand getypt, waaronder het Engelse "THOUGHT → VAULT".
- De meta description eindigt op het Engelse "Developed by Yinga."
- Geen favicon (`/favicon.ico` geeft 404).

## Questions to Consider

- Is ThoughtVault een notulenproduct voor organisaties of een Obsidian-tool voor individuen? De pagina zegt het ene, PRODUCT.md het andere.
- Als niemand de app kan gebruiken zonder account van Yinga, waarom is dit dan een downloadpagina en geen pagina om toegang aan te vragen?
- Waarom ziet de voordeur van een lichte, violette app eruit als het donkere sjabloon van een ander bedrijf, en de downloadpagina als dat van een derde?

## Niet geverifieerd

De inhoud en ondertekening van de installers, welke installer een echte Windows-machine krijgt, en of de 502's op `n8n.prezent.nl` blijvend zijn.
