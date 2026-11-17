# Notulen samenvoegen — implementatie en verificatie

Branch: `feat/notulen-samenvoegen-20261117`.
Basis: actuele `origin/main` bij aanvang, `791bf565`.
Worktree: `/Volumes/SSD/Projects/thoughtvault-samenvoegen`.
Bewijs: `/Volumes/SSD/Projects/task-evidence/thoughtvault-samenvoegen`.

## Gedrag

Op macOS, iPhone/iPad en Windows staat Samenvoegen bij de bestaande meervoudige selectie. Vanaf twee geselecteerde items toont een bevestiging titels, datums en de ingestelde profielkeuze. De actie valideert minstens twee verschillende, bruikbare notulen voordat een AI-aanvraag start. Ontbrekende serverdetails en gekoppelde notulen worden eerst opgehaald; een fout houdt de generatie tegen.

De actuele opgeslagen notulenteksten worden via de bestaande HTML-conversie leesbare brontekst. De bronmomentopname is chronologisch gesorteerd, met bron-ID als vaste tweede sorteersleutel, en bevat duidelijke bronbegrenzingen, titels en datums. Meer dan 1.000.000 tekens geeft een fout; er wordt niets afgeknipt. De bestaande provider, fallback, profieltemplates, lange-tekstverwerking, kostenregistratie en inhoudscontrole blijven in gebruik. Instructies vragen om thematische bundeling, behoud van unieke informatie, acties en besluiten, expliciete brondatums bij tegenspraken en geen verzonnen gezamenlijke vergaderdatum of aanwezigheid.

Een succesvolle generatie maakt één nieuw lokaal record en opent dat pas na geslaagde opslag. Originelen blijven behouden. Op Apple zijn audio en duur afwezig; Windows gebruikt de bestaande waarde 0 voor ontbrekende duur, die de interface niet als opnameduur toont. Er is geen audiobestand of audiopad. Dubbele starts zijn geblokkeerd. Annuleren vóór opslag verwerpt de uitvoer.

Het nieuwe record toont Bronnotulen en bewaart de vaste momentopname voor opnieuw genereren. Woordcorrecties wijzigen de notule, maar houden deze bronmomentopname intact. Optionele bronmetadata loopt mee in de bestaande Apple-opslag, Codable-weergave en iCloud-payload en in de Windows-opslag. Er is geen nieuw backend-endpoint of synchronisatie tussen Windows en Apple.

## Geautomatiseerd bevestigd

- Apple: 62 gerichte tests geslaagd, 0 mislukt. Bronvolgorde, twee/meerdere bronnen, dubbele selectie, bewerkte notulen, HTML-conversie, lege/te grote invoer, merge-instructies, inhoudscontrole, bronbehoud bij correcties, lokale opslag en hercodering. Ook een echte schijfmigratie vanaf het bevroren model zonder samenvoegmetadata en een roundtrip van de overdraagbare iCloud-payload. Bestaande generatie-, synchronisatie-, migratie- en lange-teksttests draaien mee.
- Windows: 835 tests geslaagd, 2 bestaande tests overgeslagen; 94 testbestanden geslaagd en 1 overgeslagen. Inclusief ophalen van ontbrekende gekoppelde notulen, ophaalfouten vóór generatie, generatie- en opslagfouten, annuleren, dubbele starts, hergeneratie met dezelfde bronmomentopname en bronbehoud bij woordcorrecties.
- Builds: signed macOS Debug, iOS/iPadOS Simulator en Windows TypeScript/Vite. De Windows-build betreft de frontend, geen Windows-MSI of native Rust-build.
- `git diff --check` zonder fouten.

Apple-testdetails: `apple-test-summary.json`, `apple-final-tests.log` en de xcresult-bundels op de SSD. Windows: `windows-regression.log`, `windows-final-build.log`. De laatste toegankelijkheidslabels zijn daarnaast met de platformbuilds en gerichte lijstregressietests gecontroleerd.

## Browserbewijs

Aside controleert de echte Windows-componenten in een tijdelijke browserproef met voorbeelddata en een gesimuleerde AI-aanbieder. Bevestigd: één selectie schakelt de actie uit, twee/drie bronnen, titels en datums in de bevestiging, standaardprofiel en gewijzigde profielkeuze, focus binnen de dialoog, Enter-bediening, voortgang, resultaat automatisch openen en Bronnotulen. Selectie krijgt een toegankelijke ingedrukte status; Apple-selectieknoppen krijgen een titel en geselecteerd-status.

Bewijs: `browser-flow.log`, `browser-keyboard.log`, `confirmation.jpg`, `result.jpg`, `sources.jpg`. De browserproef bewijst de bediening en het doorgeven van de invoer, niet de kwaliteit van echte modeluitvoer. De fictieve voorbeelden bevatten overlap, unieke acties, een expliciet gewijzigd opleverbesluit en tegenstrijdige budgetten. Providerintegratietests controleren de instructies en auditketen met gesimuleerde antwoorden; er is geen live modelkwaliteitsmeting uitgevoerd.

## Nog open voor acceptatie

- Handmatige bediening en toegankelijkheid in de native macOS-, iPhone/iPad- en Windows-apps; de Apple-code is gebouwd en getest, de Windows-bediening is in de browser gecontroleerd.
- iCloud-upload en -download tussen fysieke apparaten met dit samengestelde record. Payload-roundtrip en opslagtests zijn geen bewijs van fysieke synchronisatie.
- Een live beoordeling van de volledigheid bij het werkelijk gekozen AI-model. Die blijft mede modelafhankelijk.
- Windows-providerverzoeken hebben in de bestaande transportketen geen abort-signaal. Annuleren voorkomt het opslaan van het resultaat, maar de lopende aanvraag kan nog doorlopen en kosten maken.

Geen release gepubliceerd, niet gepusht of gemerged. Extra schrijfopdrachten en automatische vervanging van originelen zijn niet toegevoegd.

## Opslag en opruimen

Builds, package-checkouts, tijdelijke ontwikkelbestanden en bewijs staan op de externe SSD. De lokale browserserver is gestopt. De tijdelijke browserproef is naar de bewijsmap gekopieerd, met SHA-256 gecontroleerd en uit de worktree verwijderd. De tijdelijke browser-screenshotomgeving bestaat niet meer; de afbeeldingen zijn op de SSD bewaard. Kleine interne testhostmappen zijn wegens niet eenduidig vast te stellen eigenaarschap behouden; paden en omvang staan in `storage-audit.json`. Er zijn daarom geen interne bestanden op basis van alleen een tijdstempel verwijderd; gemeten vrijgemaakte interne ruimte: 0 bytes.
