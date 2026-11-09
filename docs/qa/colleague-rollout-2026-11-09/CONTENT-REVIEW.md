# Inhoudsbeoordeling — geen vrijgave

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
