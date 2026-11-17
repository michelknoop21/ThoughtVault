# Opnametitel, kladblok en opnieuw verwerken

De opnamepagina biedt een automatisch bepaalde titel, een eigen titel of de titel van een lopende agenda-afspraak. De gekozen titel blijft behouden na generatie. De agenda-associatie bewaart het event-ID, de titel en het begintijdstip bij het oorspronkelijke audiobestand. Er wordt geen agenda-afspraak gewijzigd. Deze associatie is lokaal; het is geen nieuwe agendasynchronisatie.

Het kladblok bevat vrije tekst en een bewerkbare checklist. Beide gebruiken de bestaande notitieopslag bij de opname. Een checklistregel wordt opgeslagen als `- [ ] tekst` of `- [x] tekst`. Notities en actiepunten komen onder **Eigen notities** in een afzonderlijke, gemarkeerde sectie van de notulen. Ze worden niet als gesproken tekst of als opdrachten naar het notulenmodel gestuurd.

Het exportmenu bevat **Eigen notities meenemen**. PDF, tekst, Markdown, HTML (waar beschikbaar), kopiëren en Obsidian gebruiken dezelfde keuze. De keuze verandert het opgeslagen document niet. Aanpassingen aan de eigen-notitiessectie in de notuleneditor blijven bij export behouden. Een via iCloud ontvangen gemarkeerde sectie kan ook zonder lokale audio worden weggelaten.

Oude, ongemarkeerde secties met de naam ‘Notities’ blijven intact: de app kan niet betrouwbaar vaststellen welke daarvan eigen notities of gewone vergaderinhoud zijn.

## Opnieuw verwerken

Vanuit takenhistorie en opnieuw verwerken kan expliciet opnieuw worden getranscribeerd, met optioneel **Audio optimaliseren**. Gewoon opnieuw notulen genereren gebruikt de opgeslagen transcriptie wanneer die beschikbaar is. Een nieuwe transcriptie krijgt een eigen resultaat; de oorspronkelijke opname en bestaande notulen blijven behouden.

Optimalisatie maakt lokaal een tijdelijke kopie met één vaste versterking, maximaal +12 dB, begrensd op −1 dBFS. Duur en tijdcodes blijven gelijk. Stilte blijft stil. De bestaande standaardconversie krijgt geen tweede volumeversterking wanneer de expliciete optimalisatie is gelukt. Een fout in de voorbewerking valt terug op de oorspronkelijke audio; annuleren verwijdert de tijdelijke kopie.

Windows gebruikt hiervoor de bestaande interne audio-indeling (16 kHz mono PCM16). Andere indelingen vallen terug op het origineel. De optimalisatiekeuze is daar beschikbaar voor lokale transcriptie. Native macOS/iOS houdt de gekozen verwerkingsroute aan, ook bij opnieuw transcriberen met optimalisatie.

Dit is een expliciete keuze, geen automatisch geactiveerde kwaliteitsverbetering. Een betere woordfoutscore op echte opnames is hiermee niet aangetoond. Beschadigde audio kan niet betrouwbaar worden hersteld met volumebewerking.

## Platformen en weergave

- macOS en Windows: kladblok onder de opnamebediening; smalle vensters plaatsen de overige bediening onder de werkruimte.
- iOS: één scrollbare pagina, ombrekende actiepunten en ruimere aanraakvlakken.
- macOS `APP_STORE`: nieuwe titelvelden, kladblok en nieuwe verwerkings-/exportkeuzes verborgen, overeenkomstig de bevestigde TestFlight-keuze. Dit compileert ook voor de App Store-distributietarget; het is geen ontvangstbewijsdetectie.
- iOS en Windows tonen de nieuwe mogelijkheden.

## Verificatie

Gerichte Swift-tests: notitieopslag, checkliststatus, gescheiden exports, identiteit, behoud van bronbestanden, stilte, begrensde versterking, ontbrekende invoer en annulering. Gerichte React-tests: export met/zonder notities, geen wijziging van opgeslagen notulen, nieuwe transcriptie naast bestaand document, hergebruik van transcriptie, opnamehandler en takenhistorie. Rust test de daadwerkelijke normalisatiebron met 40.001 samples, stilte, zachte en luide signalen en opruimen bij annulering.

Bouw- en schermafbeeldingsbewijs staat op de externe SSD in `/Volumes/SSD/Projects/task-evidence/thoughtvault-hertranscriptie-20261117`. De browsercontrole gebruikt echte React-componenten met gesimuleerde native functies. De iPhone-controle gebruikt de native simulatorapp met een geïsoleerde debugseed, zonder microfoonopname.

Niet bewezen: fysieke Bluetooth-/duurtest, transcriptiekwaliteitswinst, Windows-installatie en afdrukopmaak op echte apparaten. Geen nieuwe distributie uitgevoerd voor deze functies.
