groep: Opnemen en verwerken
samenvatting: Je laat de app waarschuwen vlak voor een vergadering of bij een videocall, en start de opname vanuit die melding.

# Vergaderdetectie

ThoughtVault kan je eraan herinneren dat er iets op te nemen valt. Dat gebeurt op twee manieren: op basis van je agenda, vijf minuten voor een vergadering, en op basis van wat er op je computer draait. Opnemen begint nooit vanzelf: je start altijd zelf vanuit de melding.

Wat er werkt, verschilt per apparaat:

| | Mac | Windows | iPhone en iPad |
|---|-----|---------|----------------|
| Melding vijf minuten voor een vergadering uit je agenda | Ja | Ja, met een gekoppelde Microsoft 365-agenda | Nee |
| Melding als er een videocall actief is | Ja | Alleen op het scherm **Opnemen** | Nee |
| Vergaderingen van vandaag op **Home** | Ja | Ja | Ja, met de knop **Start opname** |

## Melding vlak voor een vergadering

::: macos
Is je agenda gekoppeld, dan kijkt de app elke minuut of er binnen vijf minuten een vergadering begint. Zo ja, dan verschijnt rechtsonder in het venster het kaartje **Vergadering begint straks** met de titel, de starttijd, de agenda en het platform. Je krijgt ook een melding van macOS, zodat je het ziet als ThoughtVault op de achtergrond staat.

| Knop | Wat er gebeurt |
|------|----------------|
| **Start opname** | De opname begint meteen. Heeft de vergadering een deelnamelink, dan neemt de app microfoon en systeemgeluid op, anders alleen de microfoon. |
| **Herinnering** | Het kaartje verdwijnt en komt bij de volgende controle terug, zolang de vergadering nog niet is begonnen. |
| **Negeer** | Het kaartje komt voor deze vergadering niet meer terug. |

De melding van macOS heeft de knoppen **Start opname** en **Negeren**.

De deelnemers uit de agenda-afspraak worden aan de opname gekoppeld. Staan er na het stoppen personen bij die je nog niet in **Mensen** hebt, dan vraagt de app of je ze wilt toevoegen.

:::

::: windows
Is je Microsoft 365-agenda gekoppeld, dan kijkt de app elke minuut of er binnen vijf minuten een vergadering begint. Zo ja, dan verschijnt rechtsonder in het venster een kaartje met de titel en **Begint om** met de starttijd. Je krijgt ook een melding van Windows.

| Knop | Wat er gebeurt |
|------|----------------|
| **Videocall opnemen** of **Meeting opnemen** | Het scherm **Opnemen** opent, de opname begint meteen en het hoofdvenster wordt geminimaliseerd. Heeft de vergadering een deelnamelink, dan is de bron **Gecombineerd**, anders **Microfoon**. |
| **Negeren** | Het kaartje komt voor deze vergadering niet meer terug. |

De agenda koppel je bij **Instellingen** > **Agenda** met **Verbinden met Microsoft 365**. Staat daar **Agenda-koppeling niet geconfigureerd. Neem contact op met de beheerder.**, dan is de koppeling voor jouw installatie niet ingericht en werkt de agendamelding niet.

:::

::: ios
iPhone en iPad geven geen melding vooraf. Op **Home** staan onder **Vandaag** de vergaderingen van vandaag, elk met de knop **Start opname**.
:::

## Melding bij een actieve videocall

::: macos
De app merkt het op als je camera wordt ingeschakeld terwijl er een vergader-app draait: Microsoft Teams, Zoom, FaceTime, Slack, Webex of Discord. Draait geen van die apps maar wel een browser (Safari, Chrome, Edge, Brave, Arc of Firefox), dan gaat de app uit van een videocall in de browser. Je krijgt dan hetzelfde kaartje als bij een agenda-afspraak, met als titel **Videogesprek** en de naam van de app. **Start opname** neemt microfoon en systeemgeluid op.

Er komt geen melding als je al aan het opnemen bent, of als er op dat moment een vergadering uit je agenda loopt: daarvoor heb je de agendamelding al gehad.

Omdat de detectie op je camera let, blijft de melding uit bij een gesprek waarin je camera uit staat. Start de opname dan zelf.
:::

::: windows
Windows heeft geen losse melding voor videocalls. Open je het scherm **Opnemen** terwijl Microsoft Teams, Zoom, Google Chrome, Cisco Webex, GoTo Meeting of Whereby draait, dan staat daar een balk met de naam van de app en **is actief**, de vraag **Wil je de vergadering opnemen?** en de knop **Opnemen**. Die knop start direct een opname met de bron **Gecombineerd**.

De app kijkt alleen of het programma draait, niet of je in een gesprek zit. Staat Chrome open, dan zie je de balk dus ook zonder vergadering.
:::

::: ios
Op iPhone en iPad is er geen detectie van videocalls.
:::

## Aan- en uitzetten

::: macos
1. Open **Instellingen**.
2. Ga naar **Agenda**.
3. Zet **Automatische vergaderdetectie** aan of uit.

Deze schakelaar regelt de melding bij een actieve videocall. De melding vlak voor een agenda-afspraak hangt aan de agendakoppeling: zonder gekoppelde agenda komt die niet.

Bij lokale verwerking gebruikt de Mac de agenda's van **Apple Agenda**. Een rechtstreekse koppeling met Microsoft 365 werkt alleen als de verwerking op **Cloud** staat. Staat je werkagenda in de Agenda-app van macOS, dan ziet ThoughtVault die afspraken via **Apple Agenda**.
:::

::: windows
Er is geen schakelaar voor de detectie. De agendamelding stopt als je bij **Instellingen** > **Agenda** de verbinding verbreekt met **Verbinding verbreken**.
:::
