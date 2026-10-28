# ThoughtVault Windows — installatie en gebruik voor de interne pilot

Status: voorbereiding, **nog niet vrijgegeven voor collega's**. Gebruik tijdens acceptatie alleen fictieve vergaderingen.

## Installer

Bewaarde testinstaller, **niet uitrollen**: **ThoughtVault 1.0.294 x64**, broncommit `92abce850a0a8cfd7ebfa4a6e18bf086b9bfb12a`.

Bestand: `build/windows-pilot-20261028/ThoughtVault_1.0.294_x64.msi`. Bijbehorende `.sig` behouden en cryptografisch gecontroleerd. De bronfixes uit commit `b58d3a2c01e7f0cfb8442a186e65ef7f1a21a17a` zitten nog niet in deze MSI; een nieuwe gesigneerde kandidaat ontbreekt.

SHA-256: `39e01dab4979c9ef3dd5e6ea8cb2d6fcf6a26de1b1f4a51b3cfe53c18227cc39`.

Controleer vóór installatie met PowerShell:

```powershell
Get-FileHash .\ThoughtVault_1.0.294_x64.msi -Algorithm SHA256
```

Sluit ThoughtVault vóór installeren of bijwerken. Start de MSI via de bestaande installatieroute; een upgrade kan beheerdersrechten vragen. De MSI heeft voorlopig geen Windows-uitgeverssignering en kan **onbekende uitgever** tonen. Omzeil geen beveiligingsblokkade, voeg geen antivirusuitzondering toe en verlaag geen Windows-beveiliging. Bij een blokkade: bewaar de melding en laat de pilotbeheerder deze onderzoeken.

## Eerste inrichting

ThoughtVault start zonder ThoughtVault-account in lokale modus; daarbij wordt de serverwizard overgeslagen. Controleer **Instellingen → Verwerking** vóór de eerste verwerking:

- Voor opnemen: een werkende, toegestane microfoon; voor gecombineerde opname ook de gewenste Windows-geluidsuitvoer.
- Voor transcriberen: het geselecteerde model moet gereed zijn. De huidige standaard is Whisper Medium, circa 1,5 GB download. Start geen verwerking met een ontbrekend model: de bestaande verwerking kan automatisch downloaden.
- Voor notulen: een bereikbare, ingestelde provider én een aanwezig model. De standaard is lokale Ollama op `http://localhost:11434`, model `llama3.2`; ThoughtVault installeert hiermee geen Ollama-server of Ollama-model.

Gebruik alleen een vooraf gecontroleerde inrichting. Een nieuwe modeldownload of provider vereist eerst uitleg over noodzaak, omvang, hardware en eventuele kosten. De Dalf38-testdesktop heeft 48 GiB RAM; prestaties daar zijn geen laptopadvies. Agenda en Obsidian zijn niet nodig voor de basiswerkketen.

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
