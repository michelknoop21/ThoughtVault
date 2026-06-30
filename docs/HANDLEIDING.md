# TranscriptStudio — Gebruikershandleiding

*Versie 1.0 — maart 2026*

---

## Inhoudsopgave

1. [Wat is TranscriptStudio?](#1-wat-is-transcriptstudio)
2. [Aan de slag](#2-aan-de-slag)
3. [Het startscherm (Home)](#3-het-startscherm-home)
4. [Opnemen](#4-opnemen)
5. [Taken](#5-taken)
6. [Notulen](#6-notulen)
7. [Profielen](#7-profielen)
8. [Instellingen](#8-instellingen)
9. [Account](#9-account)
10. [Beheer (Admin)](#10-beheer-admin)
11. [Van opname tot notulen — stap voor stap](#11-van-opname-tot-notulen--stap-voor-stap)
12. [Sneltoetsen](#12-sneltoetsen)
13. [Offline werken](#13-offline-werken)
14. [Vergaderdetectie](#14-vergaderdetectie)
15. [YouTube-transcriptie](#15-youtube-transcriptie)
16. [Veelgestelde vragen](#16-veelgestelde-vragen)
17. [Problemen oplossen](#17-problemen-oplossen)
18. [Begrippenlijst](#18-begrippenlijst)

---

## 1. Wat is TranscriptStudio?

TranscriptStudio is een app waarmee je vergaderingen opneemt, automatisch laat transcriberen en vervolgens gestructureerde notulen laat genereren door AI. Het is bedoeld voor professionals die vergaderingen, overleggen en gesprekken efficiënt willen vastleggen zonder zelf aantekeningen te hoeven maken.

De app begeleidt je van opname tot eindresultaat in drie stappen:

1. **Opnemen** — neem geluid op via je microfoon, systeemgeluid of beide tegelijk.
2. **Transcriberen** — de opname wordt automatisch omgezet naar tekst (op de server of lokaal op je apparaat).
3. **Notuleren** — AI genereert notulen in de stijl die je kiest, van zakelijk tot technisch.

Het eindresultaat is een gestructureerd verslag dat je kunt bewerken, exporteren (als PDF, Markdown of platte tekst) en delen met collega's.

TranscriptStudio is beschikbaar voor macOS en Windows. Een Android-versie is in ontwikkeling.

---

## 2. Aan de slag

### Eerste keer openen (onboarding)

Bij het eerste gebruik doorloop je een installatiewizard van zes stappen:

1. **Welkom** — introductie van de app.
2. **Microfoontoestemming** — geef de app toegang tot je microfoon.
3. **Spraakherkenning** — geef toestemming voor spraakherkenning op het apparaat.
4. **Agenda** — koppel je agenda zodat vergaderingen automatisch worden herkend.
5. **Schermopname** (alleen macOS) — geef toestemming voor het opnemen van systeemgeluid.
6. **Alles klaar!** — je kunt aan de slag.

Je kunt stappen overslaan en toestemmingen later alsnog verlenen via **Instellingen**.

### Inloggen

1. Open TranscriptStudio.
2. Voer je **E-mailadres** en **Wachtwoord** in.
3. Klik op **Inloggen**.

### Tweefactorverificatie (2FA)

Als 2FA is ingeschakeld op je account, verschijnt na het inloggen een extra scherm:

1. Open je authenticator-app (bijv. Google Authenticator of Authy).
2. Voer de **6-cijferige code** in.
3. Klik op **Verifiëren** — of wacht: de code wordt automatisch verstuurd zodra je zes cijfers hebt ingevoerd.

### Biometrisch inloggen

Als je Touch ID of Face ID beschikbaar hebt, kun je biometrisch inloggen inschakelen:

1. Ga naar **Instellingen** > **Account**.
2. Schakel **Touch ID inloggen** of **Face ID inloggen** in.
3. Bij volgende keer openen verschijnt de optie **Inloggen met Touch ID** of **Inloggen met Face ID** op het inlogscherm.

### Uitloggen

Ga naar **Instellingen** > **Account** en klik op **Uitloggen**. Bevestig je keuze in het dialoogvenster.

---

## 3. Het startscherm (Home)

Het startscherm is het eerste wat je ziet na het inloggen. Het bevat:

- **Begroeting** — een persoonlijke welkomstboodschap met je voornaam, afgestemd op het tijdstip (Goedemorgen, Goedemiddag, Goedenavond).
- **Start nieuwe opname** — de grote groene knop bovenaan brengt je direct naar het opnamevenster.
- **Snelkeuze** — twee knoppen voor veelvoorkomende scenario's:
  - **Fysieke meeting** — start een opname met alleen de microfoon.
  - **Videocall** — start een gecombineerde opname (microfoon + systeemgeluid).
- **Overzichtskaarten** — drie compacte tegels met:
  - **Actieve taken** — het aantal opnames dat momenteel wordt verwerkt.
  - **Wachtrij** — het aantal opnames dat offline wacht op upload.
  - **Recent** — het aantal recente notulen.
- **Bezig met verwerken** — als er taken actief zijn, zie je per taak de bestandsnaam, status en een voortgangsindicator.
- **Recente notulen** — de drie meest recente notulen met titel en datum. Klik op **Bekijk alles** om naar het volledige notulenoverzicht te gaan.
- **Update-banner** — als er een nieuwe versie beschikbaar is, verschijnt bovenaan een banner met een **Download**-knop.

---

## 4. Opnemen

### Opnamemodi

TranscriptStudio ondersteunt drie opnamemodi:

| Modus | Beschrijving | Wanneer gebruiken |
|-------|-------------|-------------------|
| **Microfoon** | Neemt geluid op via de microfoon van je computer | Fysieke vergaderingen in een ruimte |
| **Systeemgeluid** | Neemt het geluid op dat je computer afspeelt | Wanneer je alleen wilt vastleggen wat er via je speakers/koptelefoon klinkt |
| **Gecombineerd** | Neemt zowel microfoon als systeemgeluid op | Videocalls — zo leg je zowel de andere deelnemers als je eigen inbreng vast |

> **Let op:** Systeemgeluid en Gecombineerd zijn alleen beschikbaar op macOS en vereisen schermopname-toestemming.

### Opnametype kiezen

Op het **Opnemen**-scherm zie je het kaartje **NIEUWE OPNAME**:

1. Kies onder **Opnametype** tussen **Fysieke meeting** (microfoon) en **Videocall** (gecombineerd).
2. Kies onder **Profiel** het notulenprofiel dat past bij je vergadering (zie [Profielen](#7-profielen)).
3. Klik op de grote microfoonknop om de opname te starten.

### Tijdens de opname

Zodra de opname loopt, verandert het scherm naar de actieve opnameweergave:

- **Timer** — toont de verstreken opnameduur.
- **LIVE-indicator** — een pulserende rode stip bevestigt dat de opname actief is.
- **Waveform** — een audiovisualisatie laat het geluidsniveau in realtime zien.
- **Live transcriptie** — als spraakherkenning op het apparaat is ingeschakeld, verschijnt een live tekstweergave van wat er gezegd wordt.
- **Sessiecontext** — toont de geselecteerde opnamemodus en het gekozen profiel.

### Opname bedienen

| Actie | Wat er gebeurt |
|-------|---------------|
| **Pauzeer** | De opname wordt gepauzeerd. De timer stopt. |
| **Hervat** | De opname gaat verder waar je gebleven was. |
| **Stop en upload** | De opname wordt gestopt en direct geüpload naar de server voor verwerking. |
| **Annuleer** | De opname wordt afgebroken en verwijderd. Je krijgt eerst een bevestigingsvraag. |

### Menubalk

Tijdens een opname toont TranscriptStudio de status in de macOS-menubalk:

- **TranscriptStudio** — geen actieve opname.
- **Opname bezig** — er loopt een opname.
- **Uploaden** — een opname wordt geüpload.

Via het menubalkicoon kun je ook **TranscriptStudio openen** of de app **Stoppen**.

### Opgeslagen opnames

Onderaan het opnamescherm vind je de sectie **Opgeslagen opnames**. Dit zijn opnames die lokaal op je computer zijn bewaard — bijvoorbeeld als de upload niet lukte door een slechte verbinding.

- Klik op een opgeslagen opname om deze **opnieuw te verwerken** (reprocessen) met een profiel naar keuze.
- Klik rechts op een opname voor een contextmenu met **Opnieuw verwerken** en **Verwijderen**.
- Klik op het mapicoon om de opnamemap te openen in Finder.

---

## 5. Taken

Elke opname die je uploadt wordt een **taak** die door de verwerkingspipeline gaat. Op het **Taken**-scherm volg je de voortgang van al je taken.

### Takenstatus

Een taak doorloopt de volgende stappen:

```
Wachten → Uploaden → Converteren → Transcriberen → Getranscribeerd
   → In wachtrij → Verwerken → Voltooid
                                → Fout
```

| Status | Betekenis |
|--------|-----------|
| **Wachten** | De taak staat klaar om verwerkt te worden |
| **Uploaden** | Het audiobestand wordt naar de server gestuurd |
| **Downloaden** | De server downloadt het audiobestand (bijv. YouTube) |
| **Converteren** | Het audiobestand wordt omgezet naar het juiste formaat |
| **Transcriberen** | Spraak wordt omgezet naar tekst |
| **Getranscribeerd** | Transcriptie is klaar, wacht op notulengeneratie |
| **In wachtrij** | De taak wacht op een beschikbare AI-slot |
| **Verwerken** | Notulen worden gegenereerd |
| **Lokaal genereren** | Notulen worden lokaal op je apparaat gegenereerd |
| **Voltooid** | Klaar — je notulen zijn beschikbaar |
| **Fout** | Er is iets misgegaan |

### Taken beheren

- **Automatisch verversen** — de takenlijst wordt automatisch ververst zolang je op het tabblad bent.
- **Handmatig verversen** — klik op de verversknop (pijltje) in de werkbalk.
- **Taak annuleren** — klik op het kruisje naast een actieve taak. Bevestig je keuze.
- **Taak verwijderen** — klik op het prullenbakicoon. Bevestig je keuze. Dit kan niet ongedaan worden gemaakt.

---

## 6. Notulen

Het **Notulen**-scherm toont al je gegenereerde notulen in een doorzoekbare lijst.

### Zoeken en filteren

- **Zoeken** — typ in het zoekveld om te zoeken op titel of inhoud.
- **Sorteren** — kies via het sorteermenu tussen **Nieuwste eerst** en **Oudste eerst**.
- **Filteren op datum** — klik op een van de datumfilters:
  - **Alles** — toon alle notulen.
  - **Vandaag** — alleen van vandaag.
  - **Deze week** — van de afgelopen 7 dagen.
  - **Deze maand** — van de afgelopen 30 dagen.
- **Filteren op tags** — als je tags hebt toegevoegd aan notulen, verschijnen deze als filterchips. Klik op een tag om alleen notulen met die tag te tonen.

### Meerdere notulen selecteren

1. Klik op **Selecteer** in de werkbalk.
2. Vink de notulen aan die je wilt verwijderen.
3. Klik op **Verwijder geselecteerde** om ze in bulk te verwijderen.

### Notulen bekijken

Klik op een notule in de lijst om het detailscherm te openen. Het detailscherm heeft twee tabbladen:

- **Notulen** — de opgemaakte HTML-weergave van je notulen, inclusief opmaak, koppen en lijsten.
- **Transcriptie** — de platte tekst van de volledige transcriptie.

### Notulen bewerken

- **Titel aanpassen** — klik op het titelbewerking-icoon (cursor) in de actiebalk. Voer een nieuwe titel in en klik op **Opslaan**.
- **Notulen bewerken** — klik op het potloodicoon om de HTML-inhoud van de notulen te bewerken. Na het bewerken kun je de wijzigingen opslaan of annuleren.

### Tags beheren

Tags helpen je om notulen te categoriseren en later terug te vinden.

- **Tag toevoegen** — klik op het **+**-icoon naast de bestaande tags. Typ een tagnaam en druk op Enter of klik op het vinkje.
- **Tag verwijderen** — klik op het kruisje naast een tag.

### Exporteren

Klik op het deelicoon in de actiebalk om het exportmenu te openen:

| Optie | Beschrijving |
|-------|-------------|
| **Delen...** | Open het standaard deelvenster van je besturingssysteem |
| **PDF** | Exporteer de notulen als PDF-document |
| **Markdown** | Exporteer als Markdown-bestand |
| **Platte tekst** | Exporteer als plat tekstbestand |
| **Kopieer tekst** | Kopieer de inhoud naar het klembord |

### Opnieuw genereren

Als je niet tevreden bent met de notulen, kun je ze opnieuw laten genereren met een ander profiel:

1. Klik op **Regenereer** (het sparkles-icoon) in de actiebalk.
2. Kies een profiel in het profielselectievenster.
3. De notulen worden opnieuw gegenereerd. Je ziet een voortgangsbanner bovenaan het scherm.

### Verwijderen

Klik in de notulenlijst rechts op een notule en kies **Verwijderen**. Bevestig je keuze. Dit kan niet ongedaan worden gemaakt.

---

## 7. Profielen

Profielen bepalen de stijl en toon van de gegenereerde notulen. Je kiest een profiel voordat je een opname start, of bij het regenereren van notulen.

### Standaardprofielen

TranscriptStudio bevat vier standaardprofielen:

| Profiel | Beschrijving | Geschikt voor |
|---------|-------------|---------------|
| **Zakelijk** | Formele vergadernotulen met agenda, besluiten en actiepunten | Zakelijke vergaderingen, bestuursvergaderingen |
| **Informeel** | Informele gesprekssamenvattingen in leesbare taal | Brainstorms, 1-op-1 gesprekken, teamoverleg |
| **Technisch** | Technische focus op architectuur, bugs en sprint-items | Technische meetings, scrums, code reviews |
| **Handleiding** | Stappenplan op basis van ingesproken schermopnames | Instructievideo's, walkthroughs, schermopnames |

Standaardprofielen kunnen niet worden bewerkt of verwijderd.

### Profiel kiezen bij opname

Voordat je een opname start, kies je een profiel op het opnamescherm. Het geselecteerde profiel bepaalt hoe je notulen eruit komen te zien. Je kunt ook een standaardprofiel instellen via **Instellingen** > **Profielen**, zodat dit automatisch wordt geselecteerd.

Onder de profielkiezer zie je een korte beschrijving van het geselecteerde profiel, zodat je altijd weet wat je kunt verwachten.

### Eigen profielen aanmaken

Je kunt aangepaste profielen aanmaken voor specifieke situaties — bijvoorbeeld voor een wekelijks teamoverleg met een vast format, of voor klantgesprekken:

1. Ga naar **Instellingen** > **Notulen generatie** > **Eigen profielen beheren**.
2. Klik op **Nieuw profiel** of de **+**-knop in de werkbalk.
3. Vul de gewenste naam en beschrijving in.
4. Klik op **Opslaan**.

Je eigen profiel verschijnt daarna in de profielkiezer op het opnamescherm en bij het regenereren van notulen.

### Eigen profielen bewerken

1. Ga naar **Instellingen** > **Notulen generatie** > **Eigen profielen beheren**.
2. Klik op het bewerkicoon bij het profiel dat je wilt aanpassen.
3. Wijzig de naam, beschrijving of andere instellingen.
4. Klik op **Opslaan**.

### Eigen profielen verwijderen

1. Ga naar **Instellingen** > **Notulen generatie** > **Eigen profielen beheren**.
2. Klik op het verwijdericoon bij het profiel dat je wilt verwijderen.
3. Bevestig je keuze. Bestaande notulen die met dit profiel zijn gegenereerd blijven bewaard.

---

## 8. Instellingen

Het **Instellingen**-scherm bereik je via de navigatiezijbalk (of met `Cmd+5`). Het bevat de volgende secties:

### Verbinding

- **Server URL** — de URL van de TranscriptStudio-server. Moet beginnen met `https://`.
- Klik op **Opslaan** om de URL te bewaren.
- Onder het veld zie je de verbindingsstatus: **Verbonden** (groen bolletje) of **Niet verbonden** (rood bolletje).

### Notulen generatie

- **AI-provider** — kies welke AI-dienst je notulen genereert:
  - **Cloud (Server)** — via de server (standaard).
  - **Ollama** — lokale AI via Ollama.
  - **LM Studio** — lokale AI via LM Studio.
  - **Apple Intelligence** — Apple's eigen AI (vereist macOS 26+).
- **Eigen profielen beheren** — opent het profielbeheerscherm (zie [Profielen](#7-profielen)).

### Profielen

- **Standaard profiel** — het profiel dat automatisch wordt geselecteerd bij een nieuwe opname. Kies uit de beschikbare profielen of stel in op **Geen standaard**.

### Spraakherkenning

- **Transcriptie op apparaat** — schakel in om audio lokaal te transcriberen zonder deze naar de server te sturen. Dit is sneller en privacyvriendelijker, maar niet op alle apparaten beschikbaar.
- Wanneer uitgeschakeld, wordt audio geüpload naar de server voor transcriptie via Whisper.

### Permissies

Overzicht van de vereiste systeemtoestemmingen met hun status (**Verleend** of **Geweigerd**):

| Permissie | Waarvoor nodig |
|-----------|---------------|
| **Microfoon** | Audio-opnames maken |
| **Spraakherkenning** | Lokale transcriptie op het apparaat |
| **Schermopname** (macOS) | Systeemgeluid opnemen bij videocalls |

Klik op **Systeeminstell. openen** om direct naar de privacy-instellingen van je besturingssysteem te gaan.

### Agenda

- **Agendabron** — kies tussen **Apple Agenda** en **Microsoft 365** (als geconfigureerd).
- **Apple Agenda** — toont of de agenda is gekoppeld. Klik op **Agenda koppelen** als er nog geen toegang is.
- **Microsoft 365** — klik op **Verbinden met Microsoft 365** om in te loggen. Na verbinding zie je je accountnaam.
- **Aankomende vergaderingen** — een lijst van komende vergaderingen uit je agenda.
- **Automatische vergaderdetectie** — schakel in om meldingen te ontvangen wanneer een videocall (Teams, Zoom, Meet) start.

### Account

Toont je naam, e-mailadres en rol (**Admin** of **Gebruiker**). Klik om naar het volledige [Accountbeheer](#9-account) te gaan.

- **Touch ID / Face ID inloggen** — schakel biometrisch inloggen in of uit.
- **Uitloggen** — log uit met een bevestigingsvraag.

### Feedback

- **Probleem melden of suggestie** — open het feedbackformulier om een bugrapport of suggestie in te dienen.

### Over

- **Versie** — het huidige versienummer van de app.
- **Platform** — macOS of iOS.

### Updates

- **Controleer op updates** — schakel in om automatisch een melding te tonen op de homepage als er een nieuwe versie beschikbaar is.

---

## 9. Account

Het accountscherm bereik je via **Instellingen** > **Account**. Hier beheer je je persoonlijke gegevens.

### Profiel

- Je naam, e-mailadres en rol worden bovenaan getoond.
- **Naam wijzigen** — klik op het potloodicoon naast je naam. Voer een nieuwe naam in en klik op het vinkje om op te slaan.

### Wachtwoord wijzigen

1. Voer je **Huidig wachtwoord** in.
2. Voer je **Nieuw wachtwoord** in.
3. Voer het nieuwe wachtwoord nogmaals in bij **Bevestig nieuw wachtwoord**.
4. Klik op **Wachtwoord wijzigen**.

### Twee-factor authenticatie (2FA)

Onder de sectie **Beveiliging** beheer je 2FA:

**2FA inschakelen:**

1. Klik op **2FA activeren**.
2. Scan de QR-code met je authenticator-app (bijv. Google Authenticator, Authy).
3. Of voer de getoonde geheime sleutel handmatig in.
4. Voer de **6-cijferige verificatiecode** in uit je authenticator-app.
5. Klik op **Verifiëren**.
6. Bewaar de getoonde **backup codes** op een veilige plek. Deze kun je gebruiken als je geen toegang hebt tot je authenticator-app.

**2FA uitschakelen:**

1. Klik op **2FA deactiveren**.
2. Voer je wachtwoord in ter bevestiging.
3. Klik op **Bevestigen**.

**Backup codes opnieuw genereren:**

Klik op **Backup codes opnieuw genereren** als je je codes bent kwijtgeraakt. De oude codes worden dan ongeldig.

> **Belangrijk:** Bewaar je backup codes altijd op een veilige plek. Elke code kan slechts eenmalig worden gebruikt.

### Privacy & Gegevens (GDPR)

- **Gegevens exporteren (GDPR)** — download al je opgeslagen gegevens als bestand. Dit is je recht onder de AVG.

### Uitloggen

Klik op **Uitloggen** onderaan het accountscherm. Bevestig je keuze in het dialoogvenster. Na het uitloggen word je teruggebracht naar het inlogscherm.

### Account verwijderen

Onderaan het accountscherm vind je de optie om je account permanent te verwijderen. Dit verwijdert al je gegevens — inclusief al je notulen, transcripties en accountinformatie — en kan niet ongedaan worden gemaakt.

> **Waarschuwing:** Verwijder je account alleen als je zeker weet dat je TranscriptStudio niet meer wilt gebruiken. Neem eerst een GDPR-export als je je gegevens wilt bewaren.

---

## 10. Beheer (Admin)

Het **Admin Panel** is alleen zichtbaar en toegankelijk voor gebruikers met de rol **admin**. Niet-beheerders zien het bericht "Geen toegang — Het admin-paneel is alleen toegankelijk voor beheerders."

Het admin panel heeft zes tabbladen:

### Overzicht

Een dashboard met statistieken over het gebruik van TranscriptStudio:

- Aantal gebruikers
- Aantal notulen
- Aantal transcripties
- Aantal fouten

### Gebruikers

Beheer alle gebruikersaccounts:

- **Zoeken** — zoek op naam of e-mailadres.
- **Gebruiker aanmaken** — klik op de knop om een nieuw account aan te maken. Vul e-mail, wachtwoord, naam en rol in.
- **Gebruiker verwijderen** — klik op het verwijdericoon. Bevestig je keuze. Dit kan niet ongedaan worden gemaakt.
- **Wachtwoord resetten** — stel een nieuw wachtwoord in voor een gebruiker.
- **2FA resetten** — schakel 2FA uit voor een gebruiker die de toegang tot zijn authenticator heeft verloren.

### Uitnodigingen

Beheer uitnodigingscodes waarmee nieuwe gebruikers zich kunnen registreren:

- **Uitnodiging aanmaken** — stel het maximaal aantal keer gebruik in en een verloopdatum (in uren).
- **Uitnodiging intrekken** — maak een bestaande uitnodigingscode ongeldig.

### Feedback

Bekijk door gebruikers ingediende feedback:

- **Feedback bekijken** — lees het ingediende bericht.
- **Archiveren** — markeer feedback als afgehandeld.
- **Verwijderen** — verwijder een feedbackitem permanent.
- **Filter** — schakel tussen actieve en gearchiveerde feedback.

### Fouten

Een logboek van fouten die in het systeem zijn opgetreden:

- **Doorzoeken** — zoek in foutmeldingen op trefwoord.
- **Filteren** — filter op type, ernst of gebruiker.
- **Sub-tabbladen** — schakel tussen **Activiteit** (alle logregels) en **Fouten** (alleen foutmeldingen).
- **Details bekijken** — klik op een foutregel om de volledige foutmelding en stacktrace te zien.
- **Paginering** — blader door het logboek met 25 items per pagina.

### Instellingen

Beheerdersinstellingen voor het platform:

- **Microsoft 365** — Client ID en Tenant ID instellen voor Microsoft agenda-integratie.
- **Google OAuth** — Client ID's configureren voor macOS en Windows (nodig voor YouTube-transcriptie).
- **YouTube** — maximale videoduur instellen, extractor-instellingen aanpassen, cookies configureren en proxy instellen.

---

## 11. Van opname tot notulen — stap voor stap

Dit is het volledige proces van begin tot eind:

1. **Open TranscriptStudio** en log in.
2. Klik op **Start nieuwe opname** op het startscherm, of ga naar het tabblad **Opnemen** (`Cmd+2`).
3. Kies het **opnametype**: **Fysieke meeting** of **Videocall**.
4. Kies een **profiel** dat past bij het type vergadering.
5. Klik op de **microfoonknop** om de opname te starten.
6. **Vergader** zoals je normaal zou doen. TranscriptStudio neemt op de achtergrond op. De waveform en timer tonen dat de opname loopt.
7. Klik op **Stop en upload** als de vergadering is afgelopen.
8. De opname wordt automatisch geüpload. Volg de voortgang op het tabblad **Taken** (`Cmd+3`).
9. Wanneer de status **Voltooid** is, ga je naar **Notulen** (`Cmd+4`) om je notulen te bekijken.
10. Bewerk de titel, voeg tags toe, of exporteer de notulen als PDF.

> **Tip:** Als je niet tevreden bent met het resultaat, klik dan op **Regenereer** om de notulen opnieuw te laten genereren met een ander profiel.

---

## 12. Sneltoetsen

| Sneltoets | Actie |
|-----------|-------|
| `Cmd+1` | Ga naar **Home** |
| `Cmd+2` | Ga naar **Opnemen** |
| `Cmd+3` | Ga naar **Taken** |
| `Cmd+4` | Ga naar **Notulen** |
| `Cmd+5` | Ga naar **Instellingen** |
| `Cmd+6` | Ga naar **Admin** (alleen voor beheerders) |
| `Cmd+R` | Ga naar **Opnemen** (snelle toegang) |
| `Shift+Cmd+S` | Zijbalk in-/uitklappen |
| `Shift+Cmd+R` | Opname starten/stoppen (globale sneltoets) |

---

## 13. Offline werken

TranscriptStudio werkt ook zonder internetverbinding:

- **Opnemen** — je kunt gewoon opnames maken. Audio wordt lokaal opgeslagen.
- **Upload wachtrij** — als er geen verbinding is, worden opnames in de offline wachtrij geplaatst. Je ziet een melding: *"Geen internetverbinding"* en *"Uploads worden hervat zodra u online bent."*
- **Automatisch hervatten** — zodra je weer online bent, worden opnames in de wachtrij automatisch geüpload.
- **Handmatig uploaden** — ga naar het opnamescherm en klik bij een opgeslagen opname op **Upload nu** om handmatig te uploaden.

Op het startscherm toont de tegel **Wachtrij** het aantal items dat wacht op upload.

> **Tip:** Houd TranscriptStudio open na je vergadering als je weet dat je internetverbinding instabiel is. Zodra de verbinding hersteld is, worden alle wachtende opnames automatisch verzonden.

---

## 14. Vergaderdetectie

TranscriptStudio kan automatisch detecteren wanneer je een videocall start en je aanbieden om de opname te starten.

### Hoe het werkt

1. TranscriptStudio controleert je agenda op komende vergaderingen.
2. Wanneer een vergadering bijna begint (1 minuut van tevoren), verschijnt een melding: *"Vergadering begint binnenkort"*.
3. Je kunt kiezen:
   - **Start opname** — de opname begint direct.
   - **Sluiten** — de melding wordt gesloten.

### Videocall-detectie

Naast agenda-integratie kan TranscriptStudio ook actieve videocalls detecteren op je computer:

- **Ondersteunde apps:** Microsoft Teams, Zoom, Google Meet.
- Wanneer een videocall wordt gedetecteerd, verschijnt een macOS-systeemmelding: *"Videogesprek gedetecteerd — [appnaam] is actief"*.

### Instellen

- Ga naar **Instellingen** > **Agenda**.
- Schakel **Automatische vergaderdetectie** in of uit.

---

## 15. YouTube-transcriptie

Als YouTube-transcriptie is ingeschakeld door je beheerder, kun je ook YouTube-video's laten transcriberen:

1. Ga naar het tabblad **Opnemen**.
2. In het kaartje **YOUTUBE VIDEO**, plak je een YouTube-URL.
3. Als er een Google-account nodig is, klik op **Verbind Google Account** en log in.
4. Klik op **Transcriberen**.
5. De video wordt gedownload en verwerkt. Volg de voortgang bij **Taken**.

> **Let op:** Als de video geen ondertiteling heeft, wordt de audio gedownload en getranscribeerd via Whisper. Dit kan enkele minuten duren.

---

## 16. Veelgestelde vragen

### Opnemen

**Welke opnamemodus moet ik kiezen?**
Gebruik **Fysieke meeting** (microfoon) als je in dezelfde ruimte zit als de andere deelnemers. Gebruik **Videocall** (gecombineerd) bij online vergaderingen, zodat zowel de andere deelnemers als jijzelf worden opgenomen.

**Hoe lang kan ik opnemen?**
Er is geen tijdslimiet voor opnames. Het maximale bestandsformaat voor upload is 200 MB.

**Kan ik de opname pauzeren?**
Ja, klik op **Pauzeer** tijdens de opname. Klik op **Hervat** om verder te gaan. De timer stopt tijdens een pauze.

**Hoe weet ik of de opname loopt?**
Je ziet een pulserende rode stip met "LIVE" en een bewegende waveform. In de menubalk staat de status "Opname bezig".

**Wat gebeurt er als de app crasht tijdens een opname?**
De opname wordt lokaal opgeslagen. Bij het opnieuw openen van de app vind je de opname terug bij **Opgeslagen opnames** op het opnamescherm, waar je hem opnieuw kunt verwerken.

**Kan ik meerdere opnames tegelijk maken?**
Nee, TranscriptStudio ondersteunt één actieve opname tegelijk. Stop eerst de huidige opname voordat je een nieuwe start.

### Notulen

**Kan ik notulen opnieuw laten genereren?**
Ja, open de notule en klik op **Regenereer**. Je kunt dan een ander profiel kiezen. De nieuwe notulen vervangen de vorige versie.

**In welke formaten kan ik notulen exporteren?**
PDF, Markdown en platte tekst. Je kunt ook de tekst kopiëren naar je klembord of het standaard deelvenster gebruiken.

**Kan ik de notulen bewerken?**
Ja, klik op het potloodicoon in het detailscherm om de HTML-inhoud te bewerken. Na het bewerken kun je je wijzigingen opslaan.

**Wat is het verschil tussen de tabbladen Notulen en Transcriptie?**
Het tabblad **Notulen** toont het door AI gestructureerde verslag: met koppen, lijsten en opmaak. Het tabblad **Transcriptie** toont de letterlijke, onbewerkte tekst van alles wat er gezegd is — handig als je een specifiek citaat wilt opzoeken.

**Kan ik tags toevoegen aan notulen?**
Ja, klik op het **+**-icoon in de tagbalk van het detailscherm. Typ een tagnaam en druk op Enter. Tags helpen je om notulen te categoriseren en later snel terug te vinden via de tagfilter in de notulenlijst.

### Account

**Hoe stel ik 2FA in?**
Ga naar **Instellingen** > **Account** > **Beveiliging** en klik op **2FA activeren**. Volg de stappen om de QR-code te scannen en de verificatiecode in te voeren.

**Wat doe ik als ik mijn authenticator-app kwijt ben?**
Gebruik een van je backup codes om in te loggen. Heb je geen backup codes meer, neem dan contact op met je beheerder om 2FA te resetten.

**Kan ik mijn gegevens exporteren?**
Ja, ga naar **Account** > **Privacy & Gegevens** en klik op **Gegevens exporteren (GDPR)**.

### Verbinding

**Wat betekent "Niet verbonden"?**
De app kan geen verbinding maken met de server. Controleer je internetverbinding en de server-URL in **Instellingen** > **Verbinding**.

**Moet de server-URL beginnen met https?**
Ja, alleen beveiligde HTTPS-verbindingen zijn toegestaan.

### Machtigingen

**Waarom vraagt de app om microfoontoestemming?**
TranscriptStudio heeft microfoontoegang nodig om audio op te nemen. Zonder deze toestemming kun je geen opnames maken.

**Waarom vraagt de app om schermopname-toestemming?**
Schermopname-toestemming is nodig om systeemgeluid vast te leggen. Dit is vereist voor de modi **Systeemgeluid** en **Gecombineerd** (videocalls).

**Waarom vraagt de app om agenda-toegang?**
Met agenda-toegang kan TranscriptStudio aankomende vergaderingen tonen en je automatisch herinneren om een opname te starten.

### Overig

**Hoe weet ik welke versie ik gebruik?**
Ga naar **Instellingen** > **Over**. Daar zie je het versienummer en het platform.

**Kan ik de app op meerdere computers gebruiken?**
Ja, je kunt met hetzelfde account inloggen op meerdere apparaten. Je notulen worden via de server gesynchroniseerd.

**Wat is het verschil tussen de AI-providers?**
- **Cloud (Server)** — de snelste en meest krachtige optie. Je audio en transcriptie worden naar de server gestuurd.
- **Ollama** en **LM Studio** — draaien lokaal op je computer. Alles blijft op je apparaat, maar vereist een krachtige computer.
- **Apple Intelligence** — gebruikt Apple's eigen AI, beschikbaar op nieuwere Macs met Apple Silicon.

---

## 17. Problemen oplossen

### Kan niet opnemen

**Oorzaak:** Geen microfoontoegang.
**Oplossing:** Ga naar **Instellingen** > **Permissies** en controleer of de microfoon op **Verleend** staat. Zo niet, klik op **Systeeminstell. openen** en schakel de microfoontoegang in voor TranscriptStudio.

### Systeemaudio werkt niet

**Oorzaak:** Geen schermopname-toestemming.
**Oplossing:** Ga naar **Systeeminstellingen** > **Privacy & Beveiliging** > **Schermopname** en schakel TranscriptStudio in. Herstart de app na het verlenen van de toestemming.

### Upload mislukt

**Oorzaak:** Geen internetverbinding of bestand te groot.
**Oplossing:**
- Controleer je internetverbinding.
- Het maximum bestandsformaat is 200 MB. Als je opname groter is, overweeg een kortere opname.
- De opname is automatisch offline opgeslagen en wordt opnieuw geüpload zodra je weer verbinding hebt.

### Taak blijft hangen

**Oorzaak:** De server is overbelast of er is een fout opgetreden.
**Oplossing:** Wacht even en ververs de takenlijst. Als de status niet verandert, annuleer de taak en probeer de opname opnieuw te uploaden via **Opgeslagen opnames**.

### Inloggen lukt niet

**Oorzaak:** Verkeerd wachtwoord, verlopen sessie of 2FA-probleem.
**Oplossing:**
- Controleer of je het juiste e-mailadres en wachtwoord gebruikt.
- Als je sessie is verlopen, log opnieuw in.
- Bij 2FA-problemen: gebruik een backup code of vraag je beheerder om 2FA te resetten.

### Notulen zijn leeg of onvolledig

**Oorzaak:** De opname bevatte te weinig spraak, of de transcriptie was onvolledig.
**Oplossing:**
- Controleer of de transcriptie (tabblad **Transcriptie**) tekst bevat.
- Als de transcriptie leeg is, was de audiokwaliteit mogelijk te laag. Probeer opnieuw op te nemen in een stillere omgeving.
- Als er wel tekst is maar geen notulen, klik op **Regenereer** om de notulen opnieuw te laten genereren.

### App herkent videocall niet

**Oorzaak:** Vergaderdetectie is uitgeschakeld of de app wordt niet ondersteund.
**Oplossing:**
- Ga naar **Instellingen** > **Agenda** en controleer of **Automatische vergaderdetectie** is ingeschakeld.
- Alleen Microsoft Teams, Zoom en Google Meet worden ondersteund.

### Offline opnames worden niet verzonden

**Oorzaak:** Geen internetverbinding of de app draait niet op de achtergrond.
**Oplossing:**
- Controleer je internetverbinding.
- Houd TranscriptStudio open. De app uploadt wachtende opnames automatisch zodra er verbinding is.
- Je kunt ook handmatig uploaden via **Opgeslagen opnames**.

### Zwevend widget verschijnt niet

**Oorzaak:** De opname is gestopt of de app is geminimaliseerd.
**Oplossing:** De zwevende opname-indicator is alleen zichtbaar tijdens een actieve opname. Start een nieuwe opname om de indicator te zien.

### Export werkt niet

**Oorzaak:** De notulen bevatten geen inhoud.
**Oplossing:** Open de notule en controleer of er inhoud is op het tabblad **Notulen**. Als het tabblad leeg is, laat de notulen eerst regenereren.

### Systeemaudio kon niet worden samengevoegd

**Oorzaak:** Het samenvoegen van microfoon- en systeemaudio is mislukt.
**Oplossing:** De opname bevat in dit geval alleen het microfoongeluid. Dit is een bekende beperking bij bepaalde audioconfiguraties. Probeer het opnieuw, of gebruik de modus **Microfoon** als je alleen je eigen stem hoeft vast te leggen.

---

## 18. Begrippenlijst

| Term | Betekenis |
|------|-----------|
| **Notulen** | Het door AI gegenereerde verslag van een vergadering, op basis van de transcriptie |
| **Transcriptie** | De letterlijke tekst van alles wat er gezegd is tijdens de opname |
| **Profiel** | Een voorinstelling die bepaalt in welke stijl en toon de notulen worden gegenereerd |
| **Taak** | Een opname die door de verwerkingspipeline gaat (uploaden, transcriberen, notuleren) |
| **Wachtrij** | De lijst met opnames die offline zijn opgeslagen en wachten op upload |
| **2FA** | Twee-factor authenticatie — een extra beveiligingslaag bij het inloggen |
| **Backup codes** | Eenmalige codes waarmee je kunt inloggen als je geen toegang hebt tot je authenticator-app |
| **Provider** | De AI-dienst die de notulen genereert (Cloud, Ollama, LM Studio, Apple Intelligence) |
| **Tag** | Een label dat je aan notulen kunt toevoegen om ze te categoriseren |
| **Waveform** | De visuele weergave van het audioniveau tijdens een opname |
| **Systeemgeluid** | Het geluid dat je computer afspeelt (bijv. de stemmen van andere deelnemers in een videocall) |
| **Gecombineerd** | Een opnamemodus die zowel je microfoon als het systeemgeluid opneemt |
| **Onboarding** | De installatiewizard die je bij het eerste gebruik doorloopt |
| **SSE** | Server-Sent Events — de techniek waarmee de app realtime statusupdates ontvangt van de server |
| **Whisper** | Het spraakherkenningsmodel dat op de server wordt gebruikt voor transcriptie |
| **GDPR/AVG** | De Europese privacywetgeving die je het recht geeft je gegevens op te vragen of te laten verwijderen |
| **Regenereren** | Notulen opnieuw laten genereren door de AI, eventueel met een ander profiel |
| **Reprocessen** | Een opgeslagen opname opnieuw door de volledige verwerkingspipeline sturen |

---

*TranscriptStudio wordt ontwikkeld door Prezent Internet B.V. en aangedreven door Yinga AI.*
