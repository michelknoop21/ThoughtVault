# Inhoudsbeoordeling — serviceproef geslaagd, native acceptatie open

## Actueel besluit — 9 november 12:37 CET

**Taak 2 geslaagd binnen de serviceproef.** De gekozen route voor verdere native
acceptatie is **Ollama Cloud, Kimi K2.6**. Alle negen werkelijke generatieantwoorden
noemen `kimi-k2.6`. Dit is een expliciete keuze op basis van onderstaande vergelijking;
geen bestaande gebruikersvoorkeur, credential of provider-URL is overschreven.

- Volledige productie-LLMService, job `163c73591d5749c7bab6413320b2ea6c`:
  drie verschillende fictieve vergaderingen, elk eenmaal zonder retry. Onafhankelijk
  beoordeeld: Waddenspoor bewaart 12.450 incl. btw, beide controles en beperkingen;
  Noorderlicht bewaart annulering en voorwaarden vóór productie; Bibliotheek bewaart
  2.750 incl. btw, beide offerteacties, geen leverancier en schriftelijke toestemming
  zonder die toestemming tot een opdracht te maken. **3/3 PASS.**
- Vaste audit, job `bc58d19b05e3433791f1c86943aa4f1f`: echte antwoorden opnieuw door
  de productieparser en testpoort gehaald. **6/6 PASS**: correcte parafrase slagen;
  ontbrekende actie, tegengestelde toestemming, verkeerd budget, voorwaarde als
  opdracht en onbegrijpelijke bron gericht afgewezen. Geen transportfout als
  semantische afwijzing meegeteld. Maximaal elf werkelijke requests; geen retries.
- Beide centrale artifactmanifesten lokaal op lengte en SHA256 gecontroleerd.
  Bewijs staat onder `content/kimi-k26-single-draft` en `content/alternate-kimi-k26`.
- Frontend: 237 PASS / 1 opt-in live gate overgeslagen; die live gate is hierboven
  afzonderlijk werkelijk uitgevoerd. Windows Rust: 38 PASS / 3 ignored.

Dit bewijst geen native opname/import, lange vergadering, onboarding, export of
herstel van de nog te bouwen MSI. Een kleine modelproef garandeert geen foutloze
notulen; gebruikers moeten de inhoud blijven controleren. Historische mislukkingen
hieronder blijven behouden en tellen niet als acceptatie.

## Historische proeven

Scope: echte Windows `LLMService` in een geïsoleerde bronkopie, echte bestaande
Ollama Cloud `gpt-oss:120b`, uitsluitend fictieve teksten. Geen appdata of
persoonlijke credentials gekopieerd, geen providerinstellingen veranderd.
Service-/providerbewijs is geen native opname-, hardware- of MSI-acceptatie.

## Wat aantoonbaar is verbeterd

- Bronbegrijpelijkheid wordt afzonderlijk gecontroleerd zonder de vloeiende
  conceptnotule in die request. Onzekerheid bewaart het concept voor review.
- Eén canonieke notule→bron-bewijsrelatie voorkomt dubbele, tegenstrijdig
  overgeschreven indexen. Alle bron-/notuleverdicts en IDs blijven verplicht;
  ontbrekend bewijs, tegenspraken, onzekerheid en ontbrekende expliciete
  beperkingen blijven afwijzingen. Negatieve antwoorden worden niet gerepareerd.
- Generatie-instructies bewaren fictieve status en onderscheiden voorwaarden
  van opdrachten. De laatste instructie is nog niet betrouwbaar effectief.

## Laatste vaste auditproef

Centrale job `9acd06163a5b4c0fba8c2b0c0ae4a696` eindigde technisch met 0,
maar echte parserreplay op alle 11 bewaarde responses geeft **FAIL**.

| Geval | Beoogd | Werkelijk | Inhoudsoordeel |
|---|---|---|---|
| Correcte parafrase | Accepteren | Geaccepteerd | PASS |
| Tweede actie ontbreekt | Gericht afwijzen | Ontbrekende Iris-actie gevonden | PASS |
| Tegengestelde toestemming | Gericht afwijzen | Tegenspraak gevonden | PASS |
| Verkeerd budget | Gericht afwijzen | Bedrag/bronfeit ontbreekt gevonden | PASS |
| Voorwaarde wordt opdracht | Afwijzen | Onterecht geaccepteerd | **FAIL** |
| Onbegrijpelijke Opname10-bron | Afwijzen | Broncontrole onzeker | PASS |

De onterechte actie is: `Sara de Boer: schriftelijke goedkeuring geven voordat
bestellingen worden geplaatst.` De bron stelt alleen dat bestellen haar
schriftelijke goedkeuring vereist; zij zegt niet toe die goedkeuring te geven.
Alleen geldige JSON, dekking en referenties bewijzen dus geen semantische juistheid.

## Drie volledige generatieketens

Job v3 `e3e1d472d8e84c068ffb1a56586c762a`: 3 productieacceptaties, maar
onafhankelijke beoordeling vond bovengenoemde onterechte bibliotheekactie.
Deze job is **geen inhoudelijke PASS**, ondanks exitcode 0.

Job v4 `05a36312371c4fd480b6a368339ec55d`: 1/3 productieacceptaties.
- **Noorderlicht:** annulering 16 november, Mila 17 november 10:00, Oscar 18
  november, beide controles vóór productie, nog geen productieakkoord en geen
  echte klantgegevens zijn behouden. Fictieve status is expliciet. PASS binnen
  deze beperkte serviceproef.
- **Waddenspoor:** terecht afgewezen omdat `nog niet uitgevoerd` is toegevoegd;
  die status staat niet in de bron. Niet bruikbaar als geslaagde generatie.
- **Bibliotheek:** afgewezen met `Ontbrekend controlebewijs bij T2`; bovendien
  bevat het concept opnieuw de niet genoemde status `nog niet uitgevoerd`.

## Besluit

Taak 2 blijft open. Geen vierde onbewezen instructiepatch op dezelfde oorzaak;
architectuur/modelrichting is aan de gebruiker voorgelegd. Keuze: een andere
modelroute met dezelfde strenge proeven onderzoeken, of expliciet een pilot
met verplichte menselijke conceptgoedkeuring afspreken. Geen stille wijziging
van model/provider en geen kwaliteitspoort groen maken met mocks.

Normale frontendtests: 227 PASS / 1 opt-in live gate overgeslagen. De uitgevoerde
live gate staat hierboven apart en is rood. Geen nieuwe MSI geïnstalleerd of
release gepubliceerd in deze uitvoeringsronde.

## Vervolg: alternatieve route en één generatie (9 november 12:30 CET)

Mistral Large 4 doorstaat de zes vaste auditgevallen na strikte verwerking van
één volledig JSON-codeblok. GPT OSS 20b blijft de toestemmingsvoorwaarde verkeerd
accepteren. Een tweede generatieve herschrijving verminkte eerder een correcte
eerste notule; die onvoorwaardelijke herschrijving is daarom verwijderd. De
bestaande bron- en inhoudsaudit controleren nu het oorspronkelijke concept.

Job `6a1ccc67dbc04965846fb6b312a42d06` met Mistral Large 4 accepteerde automatisch
3/3 concepten, maar onafhankelijke beoordeling geeft **2/3 bruikbaar**. Waddenspoor
en Noorderlicht behouden de feiten. Bibliotheek bevat in het ruwe providerantwoord
`Einrichtung` en `Sara beoordeelt deettes maandag 16 november.` De audit accepteert
dit onterecht als volledig ondersteund; deze generatie telt niet als PASS. Alle
centrale artifacts zijn met hun manifesthash gecontroleerd en hier bewaard.

Taak 2 blijft open; geen gebruikersinstellingen aangepast. Een begrensde proef met
Kimi K2.6 via dezelfde Ollama Cloud-verbinding is gestart als job
`163c73591d5749c7bab6413320b2ea6c`, maximaal negen requests zonder retries. Dit
is een empirische vergelijking, geen reeds gekozen pilotmodel.
