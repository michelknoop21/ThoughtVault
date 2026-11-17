# Notulen samenvoegen — verificatie 17 november 2026

## Resultaat en release

Samenvoegen maakt vanaf twee bruikbare notulen een nieuwe notule. De actuele opgeslagen, eventueel handmatig bewerkte inhoud is de bron. Chronologische bronmomentopnamen en bronmetadata blijven behouden bij correcties, hergeneratie en Apple-iCloud-sync; originelen blijven bestaan. Ontbrekende serverinhoud wordt eerst opgehaald. Generatie, opslagfouten, dubbele starts, te grote invoer en annuleren zijn afgevangen. Er is geen fictieve audio of opnameduur en geen nieuwe Windows–Apple-synchronisatie.

De volledige documenthuisstijlfunctie is geïntegreerd. Yinga begint direct met de notule, zonder voorblad; HTML, Word en PDF gebruiken de gedeelde documentrenderer. De Windowswizard hergebruikt de bestaande modellendropdown met dezelfde aanbevolen modellen en prijsgrenzen als Instellingen. Dit is geen volledige dynamische OpenRouter-catalogus.

- Windows **1.0.334** is op Dalf38 geïnstalleerd, tweemaal gestart met ongewijzigde notulen en gepubliceerd op het productie-updatekanaal. Live download en feedsignatuur zijn gelijk aan de lokaal cryptografisch gecontroleerde MSI. SHA-256: `842827a8cdb9c0c6c6372110bea125515148fb510479dbd3e2aa08da32621418`.
- Apple **1.0.335** is voor iOS en macOS ingediend en door Apple VALID verklaard. Mac335 is via TestFlight geïnstalleerd en fysiek gecontroleerd. iPhone334 is fysiek gecontroleerd; de laatste correctie in335 betreft het normaliseren van een geannuleerde netwerkfout.
- Apple-artifacts zijn gebouwd vanaf `652d139e`; Windows334 vanaf `7b415da8`. Nieuwere presentatiewijzigingen uit `ee8861ca` zijn daarna zonder conflicten geïntegreerd en opnieuw regressiegetest. Die extra presentatie zit niet in deze eerdere artifacts. Release-tags wijzen daarom naar de werkelijk gebouwde commits.

## Bewijs

Alle onderstaande paden staan onder `/Volumes/SSD/Projects/task-evidence/`.

| Controle | Uitkomst | Bewijs |
|---|---|---|
| Apple volledige regressie na integratie | 616 geslaagd, 0 mislukt, 10 overgeslagen | `thoughtvault-release-1.0.335-20261117/apple-test-summary.json` |
| Windows volledige regressie na integratie | 867 geslaagd, 2 overgeslagen | `thoughtvault-release-1.0.335-20261117/windows-integration-tests.log` |
| Windows native HTTP/annulering | 13 geslaagd, inclusief sluiten echte verbinding | `thoughtvault-release-1.0.334-20261117/windows-build-final.log` |
| Gedeelde documentrenderer | 9 tests geslaagd | `thoughtvault-samenvoegen-release-20261117/documents-combined-tests.log` |
| Native Mac live model | Twee/drie bronnen, ander profiel en hergeneratie; vaste bron behouden | `thoughtvault-samenvoegen-release-20261117/native-live-evaluation.json` |
| Native Windows live model | Twee fictieve Waddespoor-notulen samengevoegd; 83 originelen exact ongewijzigd | `thoughtvault-release-1.0.333-20261117/windows-merged-proof.log` |
| Productie-iCloud op echte iPhone | Beide echte samengevoegde records aanwezig; pending=false; digest én serverDigest exact gelijk aan Mac | `thoughtvault-release-1.0.334-20261117/physical-real-sync-proof.json` |
| Fysieke CloudKit roundtrip | Mac schrijft, fysieke iPhone wijzigt, Mac verifieert bronmetadata, broninhoud en huisstijlsnapshot | `thoughtvault-samenvoegen-release-20261117/cloud-*-summary.json` |
| Native Mac annuleren335 | Status geannuleerd, geen technische foutmelding, 3 records vóór en na | `thoughtvault-release-1.0.335-20261117/native-cancel-proof.json` |
| Yinga native PDF-export | 2 pagina's; eerste pagina bevat notule, geen voorblad | `thoughtvault-release-1.0.333-20261117/pdf-verification.log` en `Yinga-samengevoegde-proefnotule.pdf` |
| Windows publicatie | Live MSI en feedsignatuur komen exact overeen | `thoughtvault-release-1.0.334-20261117/publication-verified.json` |

Native Windows334 toont het samengevoegde document zonder de eerdere `NetworkError` bij ingesloten lettertypen. De echte welkomstwizard toont de OpenRouter-modelkeuze. De profielkeuze bij Samenvoegen valt terug op een bestaand profiel als een oude opgeslagen ID niet meer bestaat; regressietest eerst rood en daarna groen. Het originele Mac-opnameprofiel Klantgesprek is na de proeven hersteld.

## Live inhoudsbeoordeling en grenzen

Met uitsluitend fictieve notulen zijn op de Mac het ingestelde OpenRouter-model `anthropic/claude-sonnet-5.5` en op Windows `mistralai/mistral-large-4-0` gebruikt. Gecontroleerd zijn overlap, unieke acties, expliciete vervanging van de opleverdatum, het onopgeloste verschil tussen budgetten, uitsluitingen en een voorwaarde vóór bestellen. De handmatig gewijzigde broninhoud is gebruikt. ASR-brontitels hadden nog de fictieve alias C4; de bewerkte inhoud gebruikte Zephyr. Er is geen algemene perfectheidsgarantie.

De inhoudscontrole leverde soms geen geldig bewijs. De app meldt dat als niet automatisch gecontroleerd / even nalopen. Eén geldige controle signaleerde daadwerkelijk een ontbrekende handmatige aanvulling. Volledigheid blijft modelafhankelijk.

Windows annuleert nu ook de echte netwerkverbinding via de gedeelde Tauri HTTP-keten, inclusief retries en audits. Reeds verwerkte tokens kunnen door de aanbieder nog worden berekend. iPad is op uitdrukkelijk verzoek buiten deze acceptatie gehouden. Geen publieke notarized Mac-DMG gemaakt: op deze machine ontbreekt een Developer ID-certificaat; Mac-distributie loopt via TestFlight.

De laatste iPhoneproef controleerde de daadwerkelijk gesynchroniseerde payload exact; de samengevoegde notule is niet opnieuw visueel op de iPhone geopend. Windows-RDP-bediening werd na het bekijken van de wizard onbetrouwbaar; de heropende wizard is niet opnieuw voltooid en er is geen nieuwe sleutel ingevoerd.

## Dalf38 en opslag

De 100% schijfbelasting kwam door twee oude loglezers die samen circa23GB geheugen gebruikten, waardoor Windows ging wisselen naar schijf. Alleen de geverifieerde loglezers en hun ouders zijn gestopt; bouwtaken bleven intact. De gedeelde logroute leest nu begrensd via FileStream, met maximaal32KiB, 100 regels, 2048 tekens per regel, 8 bestanden en een leestime-out. Zeven regressieproeven slagen, ook met UTF-16 en een64MB-regel. Beide voorheen vastlopende commando's eindigen nu binnen een seconde. Nameting: circa41GB vrij geheugen, geen paging en 0% schijfbelasting. Dit voorkomt deze oorzaak; gewone builds of antivirus kunnen uiteraard schijf-I/O veroorzaken. Zie `thoughtvault-samenvoegen-release-20261117/DALF38-LOGGUARD-20261117.md`.

Ontwikkelwerk, archives, installateurs en bewijs staan op de externe SSD. De vier eigen acceptatie-scheduled-tasks zijn verwijderd; rollbackbestanden en unieke bewijzen blijven behouden. Een eigen intern xcresult en npm-log zijn naar de SSD gekopieerd, met SHA-256 gecontroleerd en intern verwijderd: 597.930 bytes opgeruimd. Interne testhostmappen met onduidelijk eigenaarschap blijven staan. De fictieve acceptatienotulen zijn behouden; er zijn geen gebruikersnotulen verwijderd.
