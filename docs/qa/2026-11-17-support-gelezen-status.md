# Supportbadge en alles als gelezen markeren

Vervolg op `4d16d17c` in branch `fix/ios-support-badge-20261117`.

## Gedrag

- Een eigen melding, crashrapport of logupload verhoogt de badge niet. Alleen
  zichtbare supportantwoorden (ADMIN/AI) tellen mee; eigen, interne en onbekende
  systeemrollen tellen niet mee. Dezelfde definitie voedt de lijst en de teller.
  Een nieuwe eigen logupload wist een bestaand ongelezen supportantwoord ook niet
  en laat een al gelezen supportantwoord niet opnieuw oplichten.
- In Mijn meldingen staat Alles als gelezen markeren, op iOS, macOS en Windows.
  Dit gebruikt één serveractie voor alle eigen meldingen, ook buiten de eerste
  pagina. De gesprekken blijven bewaard.
- De server legt de leesdatum aan het begin van de actie vast. Een later
  supportantwoord blijft ongelezen. De apps verversen de serverstatus in plaats
  van de teller blind op nul te zetten. Bij fouten blijft de vorige teller staan
  en verschijnt een veilige foutmelding met mogelijkheid om opnieuw te proberen.

## Bronnen en uitrolvolgorde

1. Hub: `/Volumes/SSD/Projects/thoughtvault-support-read-hub`, branch
   `fix/support-read-state-20261117`, basis `c8f75cc`. Nieuwe geauthenticeerde
   widgetroute `POST /tickets/read-all`. Eén geparameteriseerde UPDATE, beperkt
   tot instanceId en externalUserId; andere gebruikers en JSON-leesmarkeringen
   blijven buiten de wijziging. Geen migratie nodig.
2. Relay: `/Volumes/SSD/Projects/thoughtvault-support-read-relay`, branch
   `fix/support-reply-read-state-20261117`, basis `2760142`. Nieuwe route met de
   bestaande installatie-authenticatie en limiter. De gebruikersidentiteit komt
   uitsluitend uit de geauthenticeerde installatie, nooit uit de aangeleverde body.
3. Appbranch: SwiftUI en Windows gebruiken die relayroute. Instellingen vermeldt
   expliciet dat het versturen van een foutrapport niet meetelt.

Eerst hub, dan relay, daarna apps uitrollen. Geen productie-uitrol, push,
TestFlight-upload of MSI-installatie uitgevoerd.

## Bewijs

Bewijsmap: `/Volumes/SSD/Projects/task-evidence/thoughtvault-support-read-all/`.

- Hub: 72 routetests geslaagd; TypeScript-typecontrole geslaagd. Inclusief geen
  badge voor een crashrapport/eigen log, wel een supportantwoord, afbakening van
  de bulkactie, ongewijzigde andere identiteiten en een later nieuw antwoord.
- Relay: 88 tests geslaagd, met mockhub en in-memory SQLite. Nieuwe bulkroute
  getest op authenticatie, identiteitsbinding en foutdoorgifte.
- macOS: 82 native SupportRelayTests/SupportViewModelTests geslaagd, ook na de
  laatste UI-aanpassing. Crashrapport verandert de teller niet; bulkactie
  ververst de teller, behoudt een nieuw antwoord, en behoudt de teller bij fouten.
- Windows-bron: 112 component-/servicetests geslaagd op de Mac; TypeScript en
  Vite-productiebuild geslaagd. Dubbel klikken, fout/retry, behoud van meldingen,
  verdwijnende stippen/teller en geauthenticeerde POST gecontroleerd.
- iOS: simulatorbuild arm64/x86_64 geslaagd. Op een aparte iPhone 17 Pro-simulator
  (iOS 27) de echte knop aangeklikt: twee meldingen blijven staan, de ongelezen
  stip verdwijnt, de knop wordt uitgeschakeld en Instellingen toont 0. De nieuwe
  knop heeft een gemeten raakvlak van 44 pt hoog. Screenshots en AX-bomen bewaard.

De hub-UPDATE is in de routetests gemockt; er is geen echte PostgreSQL-integratie-
of live supportproef uitgevoerd. De iOS-schermproef gebruikt voorbeeldgegevens.
De echte relayactie en foutpaden zijn apart geautomatiseerd getest.

## Open Windows-proef

Een aparte, gehashte bronkopie en begrensd testprofiel zijn op Dalf38 klaargezet.
De importaanvraag `7fa4331a6030477cbc3c4307a80d79cd` bleef queued: de dispatcher
had een verouderde heartbeat. Er waren geen actieve buildjobs/child-workers,
geen maintenance-stop en geen gewijzigde geïnstalleerde scripts sinds zijn start.
Een herstart van uitsluitend Dalf38-Dispatcher werd door Taakplanner geweigerd
(`0x800710e0`). Andere diensten, apps en instellingen zijn niet aangepast.
Voor de eigen wachtende aanvraag is een stopverzoek vastgelegd; de status blijft
queued zolang de dispatcher niet verwerkt. Een daadwerkelijk uitgevoerde Windows-
proef en WebView2-/MSI-acceptatie blijven open. De taakgebonden bronkopie op
Dalf38 blijft beschikbaar voor hervatting na herstel van de testworker.

## Opruimen

De aparte simulator en zijn appdata zijn verwijderd. De eigen interne simulator-
en npm-logs zijn eerst naar de externe bewijsmap gekopieerd, via SHA-256
gecontroleerd en daarna verwijderd: 282.624 bytes interne opslag vrijgemaakt.
Builds, dependencies, venv en bewijs staan op de externe SSD. Gedeelde caches en
bestanden van andere sessies zijn behouden.
