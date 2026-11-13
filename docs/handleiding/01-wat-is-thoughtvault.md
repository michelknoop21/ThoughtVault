groep: Beginnen
samenvatting: Je weet wat ThoughtVault doet, op welke apparaten het draait en welke gegevens je apparaat verlaten.

# Wat is ThoughtVault?

ThoughtVault neemt een gesprek of vergadering op, zet de opname om naar tekst en schrijft er notulen van. Dat gaat in drie stappen:

1. Je neemt op, of je importeert een bestaand audiobestand.
2. De app maakt van de audio een transcriptie.
3. Een AI-model schrijft op basis van die transcriptie de notulen, in de vorm van het profiel dat je kiest.

De voortgang van stap 2 en 3 volg je op het scherm **Taken**. Het resultaat staat daarna bij **Notulen**.

## Op welke apparaten

| Apparaat | Wat je kunt opnemen |
|----------|---------------------|
| Mac | Je microfoon, of je microfoon samen met het geluid van je computer (voor videocalls) |
| Windows-pc | Je microfoon, of je microfoon samen met het geluid van je computer |
| iPhone en iPad | Je microfoon |

De schermen heten op alle apparaten hetzelfde: **Home**, **Opnemen**, **Taken**, **Notulen** en **Instellingen**. Op Mac en Windows staat **Mensen** als eigen onderdeel in de zijbalk.

## Wat blijft op je apparaat

Standaard staat de app op lokale verwerking. Je hebt daarvoor geen ThoughtVault-account nodig.

- De opname wordt op je apparaat bewaard en daar omgezet naar tekst.
- Transcripties en notulen worden op je apparaat opgeslagen.

## Wat naar buiten kan gaan

Voor het schrijven van de notulen stuurt de app de transcriptie (de tekst, niet de audio) naar het AI-model dat je bij **Instellingen** > **Verwerking** hebt gekozen. Wat dat betekent hangt af van je keuze:

| Keuze voor notulen | Waar gaat de transcriptie heen |
|--------------------|--------------------------------|
| Ollama of LM Studio op je eigen computer | Nergens: het model draait lokaal |
| Ollama of LM Studio op een andere server | Naar die server |
| Een cloudaanbieder met je eigen sleutel | Naar die aanbieder, die het gebruik apart in rekening brengt |

::: macos ios
Op Apple-apparaten die het ondersteunen kun je ook **Apple Intelligence** kiezen. Dat model draait op het apparaat zelf.
:::

Kies je bij **Transcriptie** voor **Cloud** in plaats van **Lokaal**, dan wordt de opname zelf naar de ThoughtVault-server geüpload en maakt die server ook de notulen. Meer hierover staat in [Lokaal of via de cloud verwerken](lokaal-of-cloud.html).

Gaat er iets mis bij opnemen, transcriberen of het maken van de notulen, dan stuurt de app automatisch een foutrapport naar de ontwikkelaar. Daarin staan de app-versie, je apparaat, je klikpad en een afgeschermd logbestand. Opnames, transcripties, notulen en titels gaan niet mee.
