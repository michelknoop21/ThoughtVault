# ThoughtVault Windows: installatie en gebruik voor de interne pilot

Status 13 november 2026: **1.0.320 is de vrijgave voor collega's** (besluit van
Michel, zie [Besluiten van 13 november](#besluiten-van-13-november)). De versie staat
op de downloadpagina en in de updatefeed; bestaande installaties met automatisch
bijwerken krijgen haar vanzelf. Oudere versies verderop in dit document zijn
uitsluitend herstelreferenties.

## Stand van 1.0.320

| Onderdeel | Gemeten op 13 november |
|---|---|
| Bron | `main` op `dd726c5`, tag `v1.0.320` |
| Windows-build | GitHub Actions-run 43236189080 op `dd726c5`, geslaagd inclusief de stappen "Verify installed app and upgrade" en "Upload to server" |
| Download | `ThoughtVault_1.0.320_x64.msi` op de downloadpagina uit [AUTOMATISCHE-UPDATES.md](AUTOMATISCHE-UPDATES.md); `releases.json` noemt dezelfde versie |
| SHA-256 MSI | `3cb6e66d6f98677e4e1213ec289073917b97407518acaefad61ce9a997030201` |
| Updatefeed | `/releases/windows/stable.json` meldt 1.0.320, gepubliceerd 12 november 14:38 UTC, met signature |
| macOS en iOS | TestFlight build 320, geüpload op 12 november vanaf `v1.0.320`. Zichtbaar voor interne testers. Een externe testgroep vraagt Beta App Review en die is niet aangevraagd |

Controleer de download vóór installatie:

```powershell
Get-FileHash .\ThoughtVault_1.0.320_x64.msi -Algorithm SHA256
```

Twee dingen kloppen nog niet buiten Windows. De downloadpagina biedt voor macOS
`TranscriptStudio-1.0.242.dmg` aan: stuur Mac-collega's daar niet heen, hun route
is TestFlight. En de App Store Connect-API antwoordde op 13 november met
`403 REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`: in App Store Connect moet eerst een
overeenkomst worden geaccepteerd voordat de TestFlight-stand opnieuw te lezen is
of een build naar een externe groep kan.

## Besluiten van 13 november

Michel heeft de open punten uit de [blockerlijst van 9 november](qa/colleague-rollout-2026-11-09/STATUS.md)
beslist:

- Blocker 2 (volledige flow, tien stabiele runs), 3 (verse identiteit op een schone
  installatie) en 5 (vijf werkdagen pilot) vervallen als poort. Ze zijn niet
  alsnog uitgevoerd.
- Notulen lopen via OpenRouter met `mistralai/mistral-large-4-0`. Dat model
  haalde in de evaluatie van 9 november 17 van 18 feiten, tegen 9 van 18 voor
  `gpt-oss:120b` (DEC-060). Die evaluatie liep via Ollama Cloud, niet via OpenRouter.
- Transcriptie blijft lokaal met Whisper Medium (ongeveer 1,5 GB download).
- Elke collega krijgt een eigen OpenRouter-sleutel van Michel. Yinga betaalt het gebruik.
- Vragen en meldingen gaan via het Support-scherm in de app; op Windows is dat de
  knop **Feedback**.

Een rollback naar een eerdere versie is niet bewezen; de CI dekt installatie,
signature en upgrade.

## Proef met OpenRouter op Dalf38

Op 13 november is 1.0.320 via de beheerlaag op Dalf38 geïnstalleerd (job
`726ad82672a04b95aeca605aedc042d2`, back-up van de appdata vooraf). Daarna is de
route via de instellingen van de app zelf ingericht en één fictieve proefopname
van ongeveer een halve minuut tot notule gemaakt (scenario `tv320-openrouter-20261113`).

- De notule kwam zonder reviewreden, met titel "Besluit interne proef Waddespoor met
  voorwaarden en controles", en bevatte alle feiten uit het transcript.
- Het logbestand toont vier modelverzoeken naar `mistralai/mistral-large-4-0`
  (concept, broncontrole, inhoudscontrole, contextsuggesties), alle vier `outcome=ok`.
- De app haalde zelf 470 modellen op bij OpenRouter; de sleutel is via het
  sleutelveld en **Opslaan** gezet.

**Test verbinding** meldt in 1.0.320 bij OpenRouter **Niet bereikbaar**, terwijl de
notule wel lukt. De knop vraagt alleen het Ollama-eigen pad `/api/tags` op, dat
OpenRouter niet kent. De fix (`98172df`, de knop gebruikt dezelfde controle als de
modellijst) staat op `feat/prospectflow-koppeling` en zit niet in 1.0.320. Tot die
versie uit is: knop overslaan en de route controleren met een proefopname.

**Tijdsduur.** De proefopname van een halve minuut duurde op Dalf38 (Ryzen 7 5700X3D,
48 GB) ruim negen minuten van **Stop en verwerk** tot notule. Ruim zes minuten
gingen op aan de stap vóór het eerste modelverzoek (transcriptie met Whisper Medium
op de processor), daarna ruim drie minuten aan het schrijven en controleren van de
notule. Een vergadering van een uur is met deze route niet gemeten; reken op
aanzienlijk langer en laat de app openstaan tot de taak klaar is.

## Eerste start en eerste notule

Deze instructie hoort bij de MSI van 1.0.320. Installatie voor de hele pc vraagt
Windows-beheerrechten; ontwikkeltools zijn niet nodig.

1. Installeer de aangeleverde MSI en open ThoughtVault met je eigen Windowsaccount.
   Lokale verwerking vereist geen ThoughtVault-account.
2. Bij de eerste start vraagt het scherm **Even voorstellen** om je naam en
   e-mailadres. Zonder die twee gaat de app niet verder. Ze dienen om je meldingen
   te beantwoorden en gaan mee met automatische foutrapporten; dat versturen zet
   je uit bij **Instellingen → Account**. Gebruik je werkadres: de koppeling met
   Prospect Flow gebruikt het later om conceptoffertes op jouw naam te zetten.
3. Open **Instellingen → Verwerking**. Kies bij Transcriptie het model **Medium**,
   klik op de downloadknop en wacht op de gereedmelding (ongeveer 1,5 GB). Een
   ontbrekend model bewaart de opname met een herstelmelding.
4. Kies bij Notulen generatie de tegel **Ollama** en vul in:
   - Ollama URL: `https://openrouter.ai/api`
   - Model: `mistralai/mistral-large-4-0`
   - API-sleutel: de OpenRouter-sleutel die je van Michel hebt gekregen. Het veld
     heet "API-sleutel (alleen Ollama Cloud)", maar de sleutel gaat mee naar elk
     HTTPS-adres.

   Gebruik alleen je eigen sleutel en geef haar niet door. Ze wordt in de
   Windows-kluis opgeslagen. Sla **Test verbinding** over: in 1.0.320 meldt die
   bij OpenRouter onterecht **Niet bereikbaar**. De lijst bij **Model** toont wel
   of het adres en de sleutel werken.
5. Controleer microfoontoegang bij **Windows-instellingen → Privacy en beveiliging
   → Microfoon**, inclusief toegang voor bureaubladapps. Kies in ThoughtVault je
   bron en microfoon. Gebruik eerst een korte fictieve proefvergadering.
6. Neem op, pauzeer/hervat indien nodig en kies **Stop en verwerk**. De audio wordt
   lokaal getranscribeerd. Bij een externe notulenprovider wordt het transcript
   naar die provider gestuurd. Gebruik uitsluitend gegevens die daarvoor zijn toegestaan.
   Een opname van een halve minuut duurde op een snelle desktop ruim negen minuten;
   laat de app openstaan tot de taak klaar is.
7. Controleer transcript en notulen tegen de opname: namen, bedragen, acties,
   termijnen, ontkenningen en voorwaarden. Een reviewconcept is nog geen
   goedgekeurde notule; verbeter de bron of beoordeel het concept vóór gebruik.
   Bij een fout blijven opname en beschikbare transcriptie behouden; hervat bewust.
8. Bewerk en bewaar je notule, open haar opnieuw en gebruik TXT/PDF-export.
   Controleer ook het geëxporteerde document voordat je het deelt.

Agenda en Obsidian zijn optioneel. Voor de eerste notule zijn ze niet nodig.
Loopt er iets mis, meld het dan via **Feedback** in de app. Daar kun je ook het
logbestand tonen en meesturen.

## Koppeling met Prospect Flow

Van een notule een conceptofferte in Prospect Flow maken zit **niet in 1.0.320**.

- Serverkant: live op prospectflow.yinga.ai sinds 13 november (`42175951`). Prijzen
  komen uit de catalogus, een genoemde prijs alleen als hij letterlijk in het
  transcript staat, en twijfelregels krijgen in Prospect Flow het label **Controleren**.
- Client: op `feat/prospectflow-koppeling`, nog niet naar `main`. Windows-tests en
  typecheck groen; de Swift-kant wacht op een compileer- en testronde.
- **Mijn inbox** in Prospect Flow (eigen conceptoffertes onder **Leads**, met teller)
  staat op `wt/mijn-inbox` en is nog niet geland. ThoughtVault stuurt daarvoor het
  e-mailadres van **Even voorstellen** mee; komt dat overeen met je inlognaam in
  Prospect Flow, dan staat de offerte op jouw naam.

De koppeling komt met een volgende ThoughtVault-versie. Adres en API-sleutel van
Prospect Flow regelt Michel per collega.

## Historische kandidaat 1.0.296

De nieuwe lokale MSI-kandidaat is **1.0.296**, broncommit
`132b9e190ff56e6529b10e4c52f5fafe9a6c97d8`, met de bedragfix, aanvullende
inhoudscontrole en apart behoud van afgewezen concepten.
Bestand: `build/windows-pilot-20261030/ThoughtVault_1.0.296_x64.msi`, met de eigen
`.sig` en `SHA256SUMS.txt` in dezelfde map. De oorspronkelijke updaterkey is
teruggevonden en gecontroleerd; de sleutel ontbreekt dus niet meer als voorziening.
Dit pakket is nog **geen geaccepteerde pilotrelease**. Zie de afzonderlijke
[acceptatiematrix van 29 oktober](qa/windows-pilot-2026-10-29.md).

SHA-256 MSI: `af178ed1ecff90e0939959f666124b870c499316c7f42105922dfd2111141aa2`.
De MSI is voor de hele machine (`ALLUSERS=1`); reken voor een standaardaccount
op beheerdershulp. De werkelijke UAC-/installatieproef staat afzonderlijk in de matrix.

Een afgewezen generatie krijgt geen voltooidstatus. Het transcript, eerdere
notulen en een afzonderlijk concept blijven beschikbaar voor inhoudelijke
beoordeling. De extra controle gebruikt dezelfde ingestelde provider en hetzelfde
model: één extra request, geen garantie op foutloze inhoud. Onzeker bewijs,
complexe niet controleerbare opmaak of meer dan 64.000 tekens/400 zineenheden
vraagt review. Controleer bedragen, ontkenningen, acties en voorwaarden tegen de
hoorbare opname. Bronfouten door transcriptie kan deze controle niet bewijzen.
De nieuwe praktijkacceptatie staat nog open; de onderstaande VM-resultaten
gelden uitsluitend voor de eerdere MSI 1.0.295.

## Parallels-proef: bereik en voorwaarden

De aanvullende testomgeving is een bestaande Windows 11 Pro ARM64-VM (build
26100, 4 vCPU, 8 GiB RAM), met actieve Defender en reeds aanwezige WebView2.
De x64-MSI wordt daar onder emulatie getest. Dit bewijst geen schone installatie,
prestaties of audio op een native x64-collega-laptop. De acceptatiematrix houdt
beide omgevingen apart; uitrol blijft NO-GO zolang verplichte proeven openstaan.

In deze VM is de normale upgrade van 1.0.262 naar 1.0.295 geslaagd (msiexec
exitcode 0). Defender-scans van MSI en geïnstalleerde appmap inclusief worker
zijn voltooid zonder waargenomen detectie. Alle 285 appdatabestanden bleven vóór
eerste start gelijk in hash, grootte en tijdstempels. Dit bewijst nog geen
werkelijke transcriptie, herstart of volledige UI-keten. De app is zichtbaar gestart;
de exacte worker gaf bij uitsluitend `--help` exitcode 0 met actieve Defender en
zonder waargenomen detectie. Dit controleert alleen het laden van de worker.

De normale editor, opslaan, opnieuw openen, normale appherstart en TXT/PDF-export
zijn aanvullend met één fictief record getest. Beide proef-PDF's zijn leesbaar en
doorzoekbaar. De editor verwijderde een dubbele HTML-titel; de aparte zichtbare
titel en bestaande body bleven behouden. Deze technische controles keuren de
inhoud niet goed: de proefnotule bevat onjuiste en ontbrekende informatie.
Controleer transcript en notulen daarom steeds tegen de oorspronkelijke opname.

Een snapshot vóór installatie en een volledige lokale veiligheidskopie van beide
gebruikte appmappen zijn gemaakt. De kopie is op alle 285 bestanden gecontroleerd
op hash, grootte en tijdstempels. Terugzetten en daarna openen/afspelen/bewerken
zijn daarmee nog niet bewezen. De bestaande gebruikers-VM is niet beschikbaar
voor crash- of onderbroken-upgradeproeven.

Het aangetroffen oudere `ggml-small.bin` is geen Faster Whisper-modelset. De voor
Faster Whisper gebruikte Small-set bestaat uit vier bestanden (486,2 MB totaal)
en wordt niet door deze MSI meegeleverd. Kopieer of download modellen pas na de
voorafgaande modelkeuze en controle; start geen verwerking om de beschikbaarheid
uit te proberen, omdat dat een automatische download kan veroorzaken.

## Eerdere installer (herstelreferentie)

Bewaarde testinstaller, **niet uitrollen**: **ThoughtVault 1.0.294 x64**, broncommit `92abce850a0a8cfd7ebfa4a6e18bf086b9bfb12a`.

Bestand: `build/windows-pilot-20261028/ThoughtVault_1.0.294_x64.msi`. Bijbehorende `.sig` behouden en cryptografisch gecontroleerd. De bronfixes uit commit `b58d3a2c01e7f0cfb8442a186e65ef7f1a21a17a` zitten niet in deze eerdere MSI; gebruik deze uitsluitend als herstelreferentie.

SHA-256: `39e01dab4979c9ef3dd5e6ea8cb2d6fcf6a26de1b1f4a51b3cfe53c18227cc39`.

Controleer vóór installatie met PowerShell:

```powershell
Get-FileHash .\ThoughtVault_1.0.296_x64.msi -Algorithm SHA256
```

Sluit ThoughtVault vóór installeren of bijwerken. Start de MSI via de bestaande installatieroute; een upgrade kan beheerdersrechten vragen. De MSI heeft voorlopig geen Windows-uitgeverssignering en kan **onbekende uitgever** tonen. Omzeil geen beveiligingsblokkade, voeg geen antivirusuitzondering toe en verlaag geen Windows-beveiliging. Bij een blokkade: bewaar de melding en laat de pilotbeheerder deze onderzoeken.

## Afzonderlijke portable testbuild

Op Dalf38 is **1.0.295-pilot.1** gebouwd uit broncommit `e2bf26ee8803d3d6770600418a20d5dc7ed4d3dd`, inclusief beide fixes. Alleen voor lokale acceptatie, **niet uitrollen**. Geen MSI/updaterpakket gemaakt; normale updaterconfiguratie en sleutel blijven intact.

Locatie: `%TEMP%\ThoughtVault-Pilot295\ThoughtVault_1.0.295-pilot.1_x64_portable.zip`. SHA-256: `b44d701730a53d3eb549ad2eaf7ac040a256ad4f9a9202fe2c61b782fa7ef639`. Pak volledig uit, behoud `resources` naast de EXE en sluit andere ThoughtVault-kopieën vóór starten. Maak eerst de volledige back-up uit Back-up en herstel: deze testbuild hergebruikt de bestaande gebruikersopslag. Modellen en providers zijn niet meegeleverd.

Windows-start, 147 frontendtests, 36 native tests en leesbare WAV-checkpoints na procescrash zijn bevestigd. **Herverwerking is geblokkeerd door Avast IDP.HELU.PSD11 op de Faster Whisper-worker.** Geen blokkade omzeilen; eerst laten onderzoeken. Lokale Ollama-generatie bereikt de bestaande inhoudscontrole maar die weigert ontbrekende bronbeperkingen; geen nieuwe notulen opgeslagen. Zie het [pilotbewijs](qa/windows-pilot-2026-10-28.md).

## Eerste inrichting

ThoughtVault start zonder ThoughtVault-account in lokale modus; daarbij wordt de serverwizard overgeslagen. Controleer **Instellingen → Verwerking** vóór de eerste verwerking:

- Voor opnemen: een werkende, toegestane microfoon; voor gecombineerde opname ook de gewenste Windows-geluidsuitvoer.
- Voor transcriberen: het geselecteerde model moet gereed zijn. De huidige standaard is Whisper Medium, circa 1,5 GB download. Start geen verwerking met een ontbrekend model: de bestaande verwerking kan automatisch downloaden.
- Voor notulen: een bereikbare, ingestelde provider én een aanwezig model. De standaard is lokale Ollama op `http://localhost:11434`, model `llama3.2`; ThoughtVault installeert hiermee geen Ollama-server of Ollama-model.

Gebruik alleen een vooraf gecontroleerde inrichting. Een nieuwe modeldownload of provider vereist eerst uitleg over noodzaak, omvang, hardware en eventuele kosten. De Dalf38-testdesktop heeft 48 GiB RAM; prestaties daar zijn geen laptopadvies. Agenda en Obsidian zijn niet nodig voor de basiswerkketen.

## Wat de MSI meelevert

De app, Faster Whisper 1.2.1 (Python-worker met CTranslate2/ONNX-afhankelijkheden),
NeMo Speech 0.2.0 en de bijbehorende app-local Microsoft-runtime-DLL's zijn
onderdeel van de bundel. De VAD-licentie is inbegrepen. De bestaande
runtimecontrole bepaalt of hiervoor nog een losse Visual C++-installatie nodig is.

Transcriptiemodellen, Ollama-server en Ollama-modellen, LM Studio en
cloudcredentials zijn geen onderdeel van dit pakket. Kies voor een kosteloze
pilot alleen een reeds aanwezige lokale provider en vooraf gecontroleerd model;
een lokale instelling alleen bewijst niet dat het model al aanwezig is.
WebView2 is evenmin als vaste runtime ingebed: de standaard MSI-route kan bij
ontbreken van WebView2 een Microsoft-bootstrapper downloaden. Laat deze
voorwaarde vóór installatie door de beheerder controleren; dit is geen volledig
offline installatiepakket voor een lege Windows-pc.

## Dagelijks gebruik

1. Kies Microfoon of Gecombineerd en het gewenste notulenprofiel. Controleer dat de geluidsbron de gewenste vergadering bevat.
2. Start opname, pauzeer waar nodig en stop. Bewaar zonder verwerken als model/provider nog niet gereed is.
3. Volg transcriptie en notulenverwerking in Taken. Een foutmelding betekent niet dat alle vooraf opgeslagen gegevens verloren zijn: controleer Notulen en Opgeslagen opnames.
4. Open transcript en notulen afzonderlijk. Controleer namen, bedragen, ontkenningen, besluiten, verboden en deadlines tegen de bron. Verbeter onjuistheden vóór delen; een groene status bewijst geen juiste inhoud.
5. Sla bewerkingen op, open het resultaat opnieuw en exporteer. Open de geëxporteerde TXT/PDF ook zelf ter controle.

## Back-up en herstel

Sluit de app en controleer dat opname/verwerking gestopt is. Maak een gedateerde kopie van **beide volledige mappen**:

```text
%APPDATA%\nl.prezent.transcript-studio
%LOCALAPPDATA%\nl.prezent.transcript-studio
```

De eerste bevat onder meer `local-transcripts.json`; de tweede onder meer `Recordings` en het WebView-profiel met lokale instellingen. Neem ook een eventueel afwijkende opnamemap mee. Behoud ook aanmaakdatums: Opgeslagen opnames gebruikt deze. Gebruik bijvoorbeeld Windows Robocopy met `/E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ` naar een nieuwe, lege back-upmap; gebruik geen `/MIR` of verwijderopties. Een gewone Copy-Item-kopie kan de aanmaakdatum veranderen. Controleer naast hashes de CreationTimeUtc van audiobestanden. Een TXT/PDF-export is geen volledige back-up. Vergelijk bestandsaantallen en SHA-256 van alle bestanden. Bewaar de back-up afgeschermd: hij kan audio, notulen en browserprofielgegevens bevatten.

Herstellen: sluit de app, bewaar eerst de huidige mappen als afzonderlijke veiligheidskopie en herstel de twee appmappen op hun oorspronkelijke locaties. Controleer hashes vóór appstart. Start daarna de app en controleer instellingen, notulen en audio. Bewaar beide veiligheidskopieën totdat de controle klaar is. Windows-kluisgegevens kunnen accountgebonden zijn; een mapkopie bewijst geen overdraagbaarheid van providercredentials naar een andere pc of gebruiker. Voer die zo nodig opnieuw in via de bestaande instellingen, nooit als platte tekst in de back-up.

Volledige bestandsback-up en herstel zijn op Dalf38 bij dezelfde gebruiker geslaagd (595 Local- en 12 Roaming-bestanden); 66 bestaande audio-aanmaakdatums zijn apart uit de bewaarde originelen hersteld en gecontroleerd. Overzetten naar een andere pc is niet getest; zie [pilotbewijs](qa/windows-pilot-2026-10-28.md). Bij crash of vastgelopen verwerking: bewaar de oorspronkelijke audio en bestaande notulen, herstart en gebruik bestaande herverwerking. Verwijder geen bestanden om een foutmelding weg te krijgen.
