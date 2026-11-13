groep: Instellingen en account
samenvatting: Kies of je audio op je eigen apparaat of in de cloud wordt getranscribeerd, en welk model de notule schrijft.
beeld: media/mac-instellingen-verwerking.png

# Instellingen

Het **Instellingen**-scherm bereik je via de navigatiezijbalk (of met `Cmd+5`). Het bevat de volgende secties:

## Verbinding

- **Server URL**, de URL van de ThoughtVault-server. Moet beginnen met `https://`.
- Klik op **Opslaan** om de URL te bewaren.
- Onder het veld zie je de verbindingsstatus: **Verbonden** (groen bolletje) of **Niet verbonden** (rood bolletje).

## Notulen generatie

- **AI-provider**, kies welke AI-dienst je notulen genereert:
  - **Cloud (Server)**, via de server (standaard).
  - **Ollama**, lokale AI via Ollama.
  - **LM Studio**, lokale AI via LM Studio.
  - **Apple Intelligence**, Apple's eigen AI (vereist macOS 26+).
- **Eigen profielen beheren**, opent het profielbeheerscherm (zie [Profielen](profielen.html)).

## Profielen

- **Standaard profiel**, het profiel dat automatisch wordt geselecteerd bij een nieuwe opname. Kies uit de beschikbare profielen of stel in op **Geen standaard**.

## Spraakherkenning

- **Transcriptie op apparaat**, schakel in om audio lokaal te transcriberen zonder deze naar de server te sturen. Dit is sneller en privacyvriendelijker, maar niet op alle apparaten beschikbaar.
- Wanneer uitgeschakeld, wordt audio geüpload naar de server voor transcriptie via Whisper.

## Permissies

Overzicht van de vereiste systeemtoestemmingen met hun status (**Verleend** of **Geweigerd**):

| Permissie | Waarvoor nodig |
|-----------|---------------|
| **Microfoon** | Audio-opnames maken |
| **Spraakherkenning** | Lokale transcriptie op het apparaat |
| **Schermopname** (macOS) | Systeemgeluid opnemen bij videocalls |

Klik op **Systeeminstell. openen** om direct naar de privacy-instellingen van je besturingssysteem te gaan.

## Agenda

- **Agendabron**, kies tussen **Apple Agenda** en **Microsoft 365** (als geconfigureerd).
- **Apple Agenda**, toont of de agenda is gekoppeld. Klik op **Agenda koppelen** als er nog geen toegang is.
- **Microsoft 365**, klik op **Verbinden met Microsoft 365** om in te loggen. Na verbinding zie je je accountnaam.
- **Aankomende vergaderingen**, een lijst van komende vergaderingen uit je agenda.
- **Automatische vergaderdetectie**, schakel in om meldingen te ontvangen wanneer een videocall (Teams, Zoom, Meet) start.

## Account

Toont je naam, e-mailadres en rol (**Admin** of **Gebruiker**). Klik om naar het volledige [Accountbeheer](account.html) te gaan.

- **Touch ID / Face ID inloggen**, schakel biometrisch inloggen in of uit.
- **Uitloggen**, log uit met een bevestigingsvraag.

## Feedback

- **Probleem melden of suggestie**, open het feedbackformulier om een bugrapport of suggestie in te dienen.

## Over

- **Versie**, het huidige versienummer van de app.
- **Platform**, macOS of iOS.

## Updates

- **Controleer op updates**, schakel in om automatisch een melding te tonen op de homepage als er een nieuwe versie beschikbaar is.
