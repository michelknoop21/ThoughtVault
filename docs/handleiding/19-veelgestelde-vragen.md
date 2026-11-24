groep: Hulp
samenvatting: Vind korte antwoorden over accounts, privacy, kosten, modellen en meldingen, met een verwijzing naar het hoofdstuk met de stappen.

# Veelgestelde vragen

## Account en privacy

### Heb ik een account nodig?

Nee. De app werkt standaard lokaal en vraagt dan geen login. Een ThoughtVault-account heb je alleen nodig als je bij **Instellingen** > **Verwerking** voor **Cloud** kiest. Zie [Account](account.html).

### Waarom vraagt de app bij de eerste start om mijn naam en e-mailadres?

Daarmee kan de ontwikkelaar je meldingen en foutrapporten beantwoorden. Het is geen account en je logt er niet mee in. Zie [Support en meldingen](support-en-meldingen.html#je-naam-en-e-mailadres).

### Blijft mijn opname op mijn apparaat?

Met lokale transcriptie wel: de audio wordt op je apparaat omgezet naar tekst en niet verstuurd. Voor het transcript hangt het af van de aanbieder die de notulen schrijft.

| Aanbieder voor notulen | Waar het transcript heen gaat |
|------------------------|-------------------------------|
| Ollama of LM Studio op je eigen computer | Nergens: het blijft op je computer |
| Apple Intelligence | Nergens: het blijft op je apparaat |
| Ollama of LM Studio op een andere server | Naar die server |
| Een cloudaanbieder met je eigen sleutel, of Ollama Cloud | Naar die aanbieder |

Kies je bij Transcriptie voor **Cloud**, dan wordt de audio zelf geüpload naar de ThoughtVault-server.

### Wat stuurt de app zelf naar de ontwikkelaar?

Alleen foutrapporten, en alleen als **Foutrapporten automatisch versturen** aan staat. Daarin zitten de app-versie, het apparaat, je klikpad en een afgeschermd logbestand. Opnames, transcripties, notulen en titels gaan nooit mee. Zie [Support en meldingen](support-en-meldingen.html#automatische-foutrapporten).

## Verwerking en modellen

### Werkt de app zonder internet?

Ja, als beide stappen lokaal draaien: lokale transcriptie met een model dat al is gedownload, en voor de notulen Ollama of LM Studio op je eigen computer of Apple Intelligence. Internet is wel nodig om een transcriptiemodel te downloaden en voor elke cloudaanbieder.

### Welk transcriptiemodel moet ik kiezen?

Begin met het model dat de app aanbeveelt.

::: macos
Dat is het model in het blok **Snelle setup** en de kaart **Aanbevolen model**. De app kiest het op basis van je chip en geheugen.
:::

::: windows
Dat is Whisper Medium bij minstens 16 GB geheugen en 8 processorthreads, en anders Whisper Small. Dat advies is gebaseerd op je hardware en niet op een gemeten snelheid, dus probeer een kleiner model als verwerken lang duurt.
:::

::: ios
Op iPhone en iPad kies je bij **Verwerking** zelf tussen WhisperKit en Apple Spraakherkenning. Apple Spraakherkenning werkt zonder download.
:::

### Wat kost een cloudaanbieder?

De app zelf rekent daar niets voor. De aanbieder brengt het gebruik in rekening op je eigen API-account, per verwerkte notule. Een abonnement op de chatdienst van dezelfde aanbieder dekt dit niet: je hebt een aparte API-sleutel nodig.

### Mijn notulen missen feiten. Ligt dat aan het profiel?

Het profiel bepaalt de opbouw en de toon. Hoeveel het model uit een lang transcript haalt, verschilt per model. Probeer bij ontbrekende feiten een ander of groter model bij **Instellingen** > **Verwerking** en laat de notulen opnieuw maken.

### Een naam wordt steeds verkeerd gespeld. Hoe los ik dat op?

Zet de naam in de woordenlijst, met de verkeerde spellingen erbij. De app vervangt die dan in volgende notulen. Zie [Woordenlijst](woordenlijst.html).

### Kan ik Apple Intelligence op Windows gebruiken?

Nee. De tegel staat in de lijst, maar is op Windows uitgeschakeld.

## Opnemen en notulen

### Moet ik opnieuw opnemen als het verwerken mislukt?

Nee. De opname blijft bewaard bij **Opgeslagen opnames** op het scherm **Opnemen**. Los de oorzaak op, bijvoorbeeld een ontbrekend model of een geweigerde sleutel, en verwerk de opname opnieuw. Zie [Problemen oplossen](problemen-oplossen.html).

### Kan ik notulen opnieuw laten maken met een ander profiel of model?

Ja. Open de notule en kies **Regenereer**. De transcriptie blijft dezelfde, alleen de notulen worden opnieuw geschreven. Zie [Notulen](notulen.html).

### Wordt het geluid van de andere deelnemers in een videocall opgenomen?

::: macos windows
Ja, met de bron **Gecombineerd**. Die neemt je microfoon en het geluid van je computer samen op. Met **Microfoon** neem je alleen jezelf en de ruimte op. Zie [Opnemen](opnemen.html).
:::

::: ios
Nee. Op iPhone en iPad neemt de app alleen de microfoon op.
:::

## Updates en hulp

### Hoe zie ik welke versie ik heb?

::: macos windows
Open **Instellingen** > **Algemeen**. Het versienummer staat onder **Over**.
:::

::: ios
Open **Instellingen** > **Over ThoughtVault**. Het versienummer staat onder **Over**.
:::

### Werkt de app zichzelf bij?

::: windows
Ja, als **Automatisch bijwerken** aan staat bij **Instellingen** > **Algemeen**. De nieuwe versie wordt op de achtergrond gedownload en geïnstalleerd wanneer je de app afsluit, nooit tijdens een opname of verwerking.
:::

::: macos ios
Staat **Controleer op updates** aan, dan toont de app een melding zodra er een nieuwe versie is.
:::

### Hoe meld ik een fout of stel ik een vraag?

Vanuit de app, bij de instellingen. Je krijgt antwoord in de app en per e-mail. De stappen staan in [Support en meldingen](support-en-meldingen.html#een-melding-maken).

### Waar staat het getal bij Instellingen voor?

Dat is het aantal antwoorden op je meldingen dat je nog niet hebt gelezen. Open **Mijn meldingen** om ze te lezen.
