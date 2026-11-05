# Windows UI-controle 1.0.271

Controle op 9 oktober 2026 via Royal TSX, bestaande Dalf38 VPN-sessie.
De uitgangsversie was de geïnstalleerde Windows-app 1.0.270, geen browserfixture.

## Gevonden en hersteld

- Opnemen: de native popup van transparante keuzelijsten had witte,
  onleesbare opties. Alle select-opties krijgen nu expliciete oppervlakkleuren.
  De geselecteerde rij gebruikt Windows Highlight/HighlightText, ook in
  forced-colors. De gesloten velden behouden hun bestaande kleuren.
- Notulen zonder selectie: de lege detailkolom werd naast de volle lijst
  tot een smalle strook samengedrukt. De lijstweergave toont nu alleen de lijst;
  een geselecteerd document opent nog steeds de bestaande detailweergave.
- Nieuw profiel: titels van de drie stijlkeuzes stonden op verschillende
  hoogten. De keuzes lijnen nu bovenaan uit. De geselecteerde titel gebruikt
  dezelfde lichte accenttekst als de overige actieve bedieningselementen.

## Visueel bekeken in de native app

Home, Opnemen (klaar), Taken (leeg), Notulen (lijst en bestaand testtranscript),
Mensen (leeg). Alle zeven instellingentabs: Algemeen, Verwerking, Notulen,
Agenda, Obsidian, Account en Geavanceerd.

Geopende vensters/formulieren: Persoon toevoegen, Deelnemers kiezen (leeg),
Nieuw profiel, Feedback, Tags beheren, Notulen regenereren, Opgeslagen opnames
(geladen lijst), native audio-bestandsdialoog en Woord toevoegen.
Exportmenu van het testtranscript bekeken. Geen gegevens opgeslagen,
opnames gestart, bestanden geïmporteerd of documenten geregenereerd.

Standaard venster van circa 1200 x 830 pixels en gemaximaliseerde opnamepagina
bekeken. Instellingen ook op circa 880 pixels vensterbreedte bekeken:
tabs herschikken zich, bediening blijft bereikbaar via de eigen scrollzone.

## Controles

- `npm run build`: geslaagd.
- `npx vitest run`: 34 testbestanden, 88 tests geslaagd.
- Impeccable detector eenmaal uitgevoerd op de drie gewijzigde UI-bestanden.
  Vijf meldingen betreffen bestaande accentstrepen/gradienttekst buiten de
  gewijzigde regels. Niet onderdrukt en niet als nieuwe regressies aangemerkt.
- Broncommit: `2093ac31009c55607af595a53a2321d2413bf0fa`.
- Private Windows CI: https://github.com/michelknoop21/ThoughtVault/actions/runs/37921299654
  Publicatie naar download- en updaterfeeds staat uit.

## Grenzen

Actieve opname, pauze, zwevende widget, snelle notitie tijdens opname,
onboarding, bewerkte notule met exportformaten en gevulde personenlijst zijn
niet opnieuw live getest. Geen volledige functionele of macOS-parity signoff.
Native verificatie van de nieuwe MSI wordt hieronder afzonderlijk vastgelegd.

## Nieuwe MSI geïnstalleerd en visueel geverifieerd

- CI geslaagd, inclusief installatie, upgrade, twee starts en behoud van
  opgeslagen notulen. MSI SHA-256:
  `a21679bbf81ea4336a5e56a0e3de81ce0197a1e909d1d09ed24b6a78944df9e1`.
- Remote Windows via Royal TSX opgewaardeerd van 1.0.270 naar 1.0.271.
  Vooraf normale afsluiting bij inactieve opname en lokale notulenbackup.
  Installer exit 0. Bestandshash van notulen identiek na installatie en review.
  Draaiende executable meldt 1.0.271 en Responding=True.
- Native opnameprofiel-dropdown geopend: zeven namen leesbaar op donker
  oppervlak, geselecteerd Standaard leesbaar op Windows-selectiekleur.
  Bron-dropdown: Gecombineerd geselecteerd en Microfoon beide leesbaar.
  Beide via Escape gesloten zonder een andere opnamekeuze toe te passen.
- Notulenlijst opnieuw bekeken: geen smalle, lege detailkolom meer.
- Nieuw profiel opnieuw geopend: Zakelijk, Informeel en Technisch staan
  op dezelfde hoogte; geselecteerde titel is leesbaar. Zonder opslaan gesloten.
- Eerste start onderging de automatische Avast-scan; deze afgerond zonder
  beveiliging uit te schakelen of een uitzondering toe te voegen.
- Tijdelijke installer-HTTP-server na overdracht gestopt.

Windows forced-colors is niet live ingeschakeld. Bovenstaande verificatie
geldt voor het huidige donkere Windows-thema. Bronwijzigingen zijn gepusht
op de werkbranch; deze kandidaat is niet gemerged of naar updaterfeeds gepubliceerd.
