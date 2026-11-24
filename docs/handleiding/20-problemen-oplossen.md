groep: Hulp
samenvatting: Zoek de foutmelding op die de app toont en lees wat er aan de hand is en wat je zelf kunt doen.

# Problemen oplossen

Dit hoofdstuk is ingedeeld naar het moment waarop het misgaat: bij het opnemen, bij het transcriberen of bij het maken van de notulen. De meldingen staan er letterlijk bij, zodat je erop kunt zoeken. In bijna alle gevallen blijft je opname of je transcriptie bewaard en kun je na het oplossen opnieuw verwerken.

## Opnemen

### De microfoon wordt geweigerd

::: macos ios
De app meldt "Microfoontoestemming is geweigerd. Geef toegang via Instellingen."
:::

::: macos
Bovenaan het venster kan ook een balk **Ontbrekende rechten** staan met de namen van wat ontbreekt: Microfoon, Systeemaudio of Spraakherkenning.

1. Open **Instellingen** > **Geavanceerd**.
2. Klik onder **Permissies** op **Systeeminstellingen openen**.
3. Zet de toegang voor ThoughtVault aan.
4. Start de app opnieuw als de status daarna niet verandert.
:::

::: ios
1. Open **Instellingen** > **Rechten** in de app.
2. Tik op **Systeeminstellingen openen**.
3. Zet de microfoon aan voor ThoughtVault.
:::

::: windows
1. Open **Instellingen** > **Geavanceerd**.
2. Klik op **Systeeminstellingen openen**.
3. Sta in Windows bij **Privacy en beveiliging** > **Microfoon** toe dat apps de microfoon gebruiken.

Meldt de app "Geen standaard audio-invoerapparaat gevonden", dan is er geen microfoon aangesloten of geen standaardmicrofoon gekozen in Windows.
:::

### Het geluid van de videocall wordt niet opgenomen

::: macos
| Melding | Wat je doet |
|---------|-------------|
| "Systeemaudio kon niet worden gestart" met een code | Controleer **Systeemaudio** in de Systeeminstellingen van macOS onder **Privacy en beveiliging** en geef ThoughtVault toegang. |
| "Geen audio-uitvoer beschikbaar. Kies een uitvoerapparaat en probeer opnieuw." | Kies in macOS een luidspreker of koptelefoon als uitvoer en start de opname opnieuw. |

macOS vraagt de toegang tot systeemaudio bij de eerste opname waarin je die gebruikt.
:::

::: windows
Bij "Systeemaudio niet beschikbaar" met daarachter de oorzaak kan de app het geluid van je pc niet opnemen. Kies **Microfoon** als bron om alleen je eigen microfoon op te nemen.

Bij "Audio samenvoegen mislukt" zijn de microfoonopname en de opname van het systeemgeluid los van elkaar bewaard. Er is dan niets verloren.
:::

::: ios
Op iPhone en iPad neemt de app alleen de microfoon op. Het geluid van een videocall op hetzelfde toestel komt niet in de opname.
:::

### De opname is leeg of te kort

::: macos ios
Bij "De opname is leeg of te kort om te verwerken." is er te weinig audio vastgelegd. Controleer of de juiste microfoon is gekozen en neem opnieuw op. De melding "De opname werd onderbroken door een telefoongesprek." betekent dat een inkomend gesprek de opname heeft gestopt.
:::

::: windows
Bij "Microfoonverbinding onderbroken" is de microfoon tijdens de opname weggevallen, bijvoorbeeld een headset die is losgekoppeld. Sluit hem opnieuw aan en start een nieuwe opname.
:::

## Transcriberen

### Het transcriptiemodel ontbreekt

::: macos ios
De melding is "Het spraakmodel is nog niet gedownload. Download het in Instellingen; de opname blijft bewaard."
:::

::: macos
1. Open **Instellingen** > **Verwerking**.
2. Klik in de kaart **Aanbevolen model** op **Downloaden** en wacht tot de knop **In gebruik** of **Gebruik dit model** toont.
3. Ga naar **Opnemen**, open **Opgeslagen opnames** en verwerk de opname opnieuw.

Staat er "Downloaden mislukt" met een oorzaak onder de knop, controleer dan je internetverbinding en de vrije schijfruimte bij **Jouw Mac**, en klik opnieuw op **Downloaden**.
:::

::: windows
De melding is "Transcriptiemodel ontbreekt. Download het gekozen model bij Instellingen → Verwerking en verwerk daarna deze opname opnieuw. De opname wordt niet gewijzigd."

1. Open **Instellingen** > **Verwerking**.
2. Klik bij **Transcriptie** op **Model downloaden** en wacht op "Model gedownload en klaar voor gebruik".
3. Verwerk de opname opnieuw.
:::

### Er is geen tekst herkend

::: macos ios
"De transcriptie bevat geen tekst. Controleer of de opname audio bevat."
:::

::: windows
"Geen bruikbare spraak herkend. Controleer de opname en probeer opnieuw."
:::

Luister de opname terug. Hoor je niets of alleen ruis, dan stond de verkeerde bron of microfoon aan. Hoor je wel spraak, verwerk de opname dan opnieuw, eventueel met een groter transcriptiemodel.

::: macos ios
Staat er "Toestemming voor spraakherkenning is geweigerd. Geef toegang via Instellingen.", zet dan Spraakherkenning aan voor ThoughtVault, of kies bij **Verwerking** de engine WhisperKit.
:::

## Notulen maken

Mislukt deze stap, dan is de transcriptie al bewaard. Je hoeft niet opnieuw op te nemen: los de oorzaak op en laat de notulen opnieuw maken, zie [Notulen](notulen.html).

### Er ontbreekt een API-sleutel of de sleutel wordt geweigerd

| Melding | Oorzaak |
|---------|---------|
| "Vul je API-sleutel in bij Instellingen > Verwerking." of een melding die begint met "Geen API-sleutel voor" | Voor de gekozen aanbieder staat geen sleutel op dit apparaat. |
| Een melding met "API-sleutel geweigerd" | De aanbieder accepteert de sleutel niet: verkeerd geplakt, ingetrokken of van een ander account. |

1. Open **Instellingen** > **Verwerking** en kies de aanbieder.
2. Plak de sleutel opnieuw, zonder spaties ervoor of erachter.
3. Controleer bij de aanbieder of de sleutel nog geldig is en of er tegoed op je API-account staat.

Sleutels staan per apparaat opgeslagen. Op een tweede apparaat vul je ze opnieuw in.

### Ollama of LM Studio is niet bereikbaar

::: windows
De melding begint met "Kan de notule-generator niet bereiken op", gevolgd door het adres en het model, en eindigt met "Draait Ollama/LM Studio en klopt de URL in Instellingen?".
:::

::: macos ios
De melding is "De AI-provider is niet beschikbaar." Is er geen model gekozen, dan staat er "Kies een model bij Instellingen > Verwerking."
:::

1. Controleer of Ollama of LM Studio is gestart op de computer waar het adres naar wijst.
2. Open **Instellingen** > **Verwerking** en controleer het adres. De standaard is `http://localhost:11434` voor Ollama en `http://localhost:1234` voor LM Studio.
3. Test de verbinding en kies een model dat in de lijst staat.

Blijft de lijst met modellen leeg, dan is het adres fout of heeft de server nog geen model geladen.

### De aanbieder antwoordt niet, te laat of onvolledig

| Melding | Wat je doet |
|---------|-------------|
| Een melding met "gebruikslimiet bereikt (429)" of "API-limiet bereikt (429)" | Wacht en probeer het later opnieuw, verwerk minder opnames tegelijk, of controleer je limiet bij de aanbieder. |
| "Tijdslimiet bereikt: de AI-provider gaf niet op tijd een volledig antwoord. Probeer het opnieuw of kies een sneller model." | Probeer het opnieuw. Gebeurt het vaker bij lange gesprekken, kies dan een sneller model. |
| "Het antwoord van de AI-provider is afgebroken omdat het de maximale lengte bereikte." | Kies een model dat langere antwoorden kan geven, of een compacter profiel. |
| "De notule-generator gaf een leeg concept. De transcriptie is bewaard." | Probeer het opnieuw. Blijft het leeg, kies dan een ander model. |
| "De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw." | Het gesprek is te lang voor dit model. Kies een model dat meer tekst aankan. |

### Apple Intelligence werkt niet

::: macos ios
| Melding | Wat je doet |
|---------|-------------|
| "Schakel Apple Intelligence in via Systeeminstellingen." | Zet Apple Intelligence aan in de instellingen van je apparaat. |
| "Apple Intelligence-model wordt nog gedownload. Probeer later opnieuw." | Wacht tot je apparaat klaar is met downloaden. |
| "Dit apparaat ondersteunt Apple Intelligence niet." | Kies een andere aanbieder bij **Instellingen** > **Verwerking**. |
:::

::: windows
Apple Intelligence is op Windows niet beschikbaar. Kies een andere aanbieder.
:::

## Sleutels, Obsidian en agenda

### Een sleutel opslaan lukt niet

::: macos ios
Bij "De sleutel kon niet veilig worden opgeslagen" met een code kon de app niet in de sleutelhanger schrijven. Probeer het opnieuw en controleer of de sleutelhanger van je apparaat ontgrendeld is.
:::

::: windows
Bij "Sleutelopslag niet beschikbaar" of "Opslaan in Windows Credential Manager mislukt" kan de app niet bij Windows Credential Manager. Start de app opnieuw en sla de sleutel nogmaals op.
:::

### Exporteren naar Obsidian lukt niet

- "Deze notule is gewijzigd in Obsidian. Haal die versie eerst op voordat je exporteert." De notitie in je vault is aangepast nadat de app hem schreef. De app overschrijft die wijziging niet.
- Een melding die begint met "Vul eerst de Obsidian": de koppeling is niet volledig ingevuld. Ga naar **Instellingen** > **Obsidian**.
- "Niet bereikbaar" na **Test verbinding**: Obsidian staat niet open, de plugin Local REST API staat uit, of het adres of de sleutel klopt niet.

### De agenda koppelt niet

::: windows
Bij "Agenda-koppeling niet geconfigureerd. Neem contact op met de beheerder." is de koppeling met Microsoft 365 voor jouw omgeving niet ingericht. Dat los je niet zelf op in de app.
:::

::: macos ios
Staat er bij Apple Agenda "Geen toegang, vergaderingen worden niet gedetecteerd", kies dan **Agenda koppelen** bij **Instellingen** > **Agenda** en geef toestemming.
:::

## Werken in de modus Cloud

Deze meldingen krijg je alleen als je bij **Verwerking** voor **Cloud** hebt gekozen.

::: macos ios
| Melding | Wat je doet |
|---------|-------------|
| "Je sessie is verlopen. Log opnieuw in om door te gaan." | Log opnieuw in via **Instellingen** > **Account**. |
| "Kan geen verbinding maken met de server. Controleer je internetverbinding." | Controleer je verbinding. De opname is opgeslagen en wordt opnieuw geprobeerd. |
| "Het audiobestand is te groot (maximaal 500 MB). Maak kortere opnames." | Splits lange sessies in meerdere opnames, of verwerk lokaal. |
| **Update vereist** | Klik op **Update nu** en installeer de nieuwe versie. |
:::

::: windows
| Melding | Wat je doet |
|---------|-------------|
| "Sessie mogelijk verlopen. Log opnieuw in als er problemen zijn." | Log uit en opnieuw in als verwerken daarna niet lukt. |
| **Update vereist** met je huidige en de minimale versie | Klik op **Download update** en installeer de nieuwe versie. |
:::

Kun je niet inloggen of heb je geen account, zet **Verwerking** dan terug op **Lokaal**. Daarvoor is geen account nodig, zie [Account](account.html).

## Bijwerken

::: windows
Bij "Bijwerken mislukt. Probeer opnieuw." klik je opnieuw op **Nu bijwerken** in de balk bovenaan. Updates worden niet geïnstalleerd tijdens een opname of verwerking: wacht tot die klaar is.
:::

::: macos ios
Zie je geen melding over een nieuwe versie, controleer dan of **Controleer op updates** aan staat, zie [Instellingen](overige-instellingen.html#algemeen-en-geavanceerd).
:::

## Kom je er niet uit

Stuur een melding vanuit de app en zet de letterlijke foutmelding erin. Het logbestand gaat automatisch mee. Hoe dat werkt staat in [Support en meldingen](support-en-meldingen.html).
