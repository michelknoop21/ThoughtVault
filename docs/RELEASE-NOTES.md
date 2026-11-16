# ThoughtVault: releasenotes voor gebruikers

Wat er per versie verandert voor wie de app gebruikt, in gewone taal. De technische
wijzigingen staan in [CHANGELOG.md](CHANGELOG.md). Het helpcentrum bouwt de pagina
Releasenotes uit dit bestand (`scripts/build-helpcentrum.py`).

Elke release is een blok `## <versie> - <titel>` met direct daaronder een cursieve regel
met datum en platforms, bijvoorbeeld `*12 november 2026 · macOS · iOS · Windows*`.
De nieuwste release staat bovenaan.

## 1.0.327 - Taken met geschiedenis, modelkeuze bij de eerste start

*16 november 2026 · macOS · iOS · Windows*

- **Taken** bewaart nu elke verwerking, ook na een herstart. Open een taak voor de details: profiel, duur van de opname en van elke stap, welk model de notule schreef en eventuele foutmeldingen.
- Vanuit een taak kun je opnieuw verwerken met een ander profiel of model, de titel aanpassen, naar de notule springen, de opname verwijderen of de taak verwijderen. Een notule verdwijnt alleen als je daar zelf voor kiest.
- Bij de eerste start kies je in de nieuwe stap **Notulen** wie je notulen schrijft: OpenRouter met je eigen sleutel, een model op je apparaat of een andere aanbieder. De app test de sleutel voordat hij hem gebruikt. Overslaan kan; dan maakt de app pas notulen als je een model kiest.
- De modelkeuze toont alleen modellen tot een vaste prijs per notule. Staat er nog een duurder model ingesteld, dan gebruikt de app het aanbevolen model en meldt dat bij de taak.
- OpenRouter is de standaard voor nieuwe installaties. Bestaande installaties houden hun aanbieder.
- Bij elke notule zie je de werkelijke lengte, de kosten, het aantal verzoeken en de duur.
- Een correctie past notule en transcriptie tegelijk aan.
- Delen stuurt de notule; het transcript alleen als er geen notule is.
- Op de iPhone loopt de verwerking door als je naar een andere app gaat.
- Op de Mac groeit de zwevende opnamewidget mee met de timer, zodat een opname van meer dan een uur volledig in beeld blijft.

## 1.0.325 - Handleiding openen vanuit de app

*16 november 2026 · macOS · Windows*

- Met **Handleiding** open je deze handleiding in je browser, op de pagina's voor jouw apparaat.
- Op de Mac staat de knop bovenaan het menu Help en in Instellingen, Account, in het blok Support.
- Op Windows staat de knop in Instellingen, Account, onder Feedback, boven Probleem melden of suggestie.

## 1.0.322 - Conceptofferte in Prospect Flow vanuit een notule

*13 november 2026 · Windows*

- Onder Exporteren staat **Maak offerte in Prospect Flow**. Prospect Flow leidt uit de notule en het transcript offerteregels af en zet een conceptofferte klaar bij een bestaande of nieuwe klant. Naar de klant gaat niets.
- De conceptofferte komt in Prospect Flow op jouw naam in **Mijn inbox**. De app gebruikt daarvoor het e-mailadres bij Instellingen, Account.
- Adres en API-sleutel van Prospect Flow vul je in op het nieuwe tabblad Instellingen, Prospect Flow.
- Bij lokaal werken kun je een terugval kiezen: geeft de gekozen aanbieder een fout, dan probeert de app het één keer met een andere.
- **Test verbinding** bij Ollama meldt nu ook Verbonden bij een dienst die modellen op de OpenAI-manier aanbiedt, zoals OpenRouter. Eerder stond daar Niet bereikbaar terwijl de notule wel lukte.

## 1.0.321 - Nieuwe opmaak, een handleiding in de app en kleine fixes

*13 november 2026 · macOS · iOS · Windows*

- Support, Instellingen, Mensen, Persoon bewerken en het lege scherm Taken hebben een nieuwe opmaak die meeschaalt met een smal of breed venster. Op de Mac staan je meldingen links en het gesprek rechts.
- Bij een persoon op de Mac worden aliassen en expertise losse labels. Typ een waarde en druk op Enter of een komma.
- Op Windows zijn de keuzelijsten, knoppen en scrollbalken vernieuwd, en Mensen toont initialen, expertise en het label Intern of Extern.
- Op Windows vraagt de app nu ook om bevestiging als je een notule verwijdert via de rechtermuisknop of in de selectiemodus.
- Op de Mac heet de opdracht in het menubalkmenu nu **Stop en verwerk**, net als op het opnamescherm. Tijdens het verwerken staat er **Verwerken...**, en bij lokaal werken niet langer **Niet ingelogd**.
- Het voorbeeld bij Aliassen is nu "Voornaam, bijnaam, initialen", en de Cloud-instelling noemt de ThoughtVault-server.

## 1.0.320 - Titels van notulen breken niet meer midden in een woord af

*12 november 2026 · macOS · iOS · Windows*

- Een lange titel van een notule eindigt nu op een heel woord. Eerder kon de titel midden in een woord stoppen.
- Voor Windows is dit de eerste Windows-versie met de wijzigingen uit 1.0.318 en 1.0.319. Je krijgt dus ook de supportmeldingen, de stapnamen tijdens het maken van een notule en de knop **Toon logbestand**.

## 1.0.319 - Je ziet welke stap van de notule loopt

*12 november 2026 · macOS · iOS*

- Tijdens het maken van een notule staat bij de taak welke stap bezig is, bijvoorbeeld "Concept schrijven", "Broncontrole" of "Controle 12 van 61". Bij een lange opname zie je zo dat de app doorwerkt.
- De knop **Toon logbestand** bij Support. Op de Mac opent Finder met het logbestand geselecteerd, op iPhone en iPad het deelmenu. Handig als de ontwikkelaar om het logbestand vraagt.
- Het logbestand bevat per stap alleen technische gegevens zoals duur en uitkomst. De tekst van je opname, transcriptie of notule staat er niet in.

## 1.0.318 - Meldingen maken vanuit de app en een snellere controle

*12 november 2026 · macOS · iOS*

- Onder Support maak je met **Melding maken** een melding voor de ontwikkelaar en lees je het antwoord terug in de app. Bij de eerste start vraagt de app om je naam en e-mailadres, zodat je antwoord kunt krijgen.
- Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt de app automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand. Je opnames, transcripties, notules en titels gaan nooit mee. Uitzetten kan met de schakelaar **Foutrapporten automatisch versturen**.
- De controle van een notule op de bron en de inhoud loopt nu gedeeltelijk tegelijk met het schrijven. Een trage controlestap houdt de rest niet meer op.
- De titel van een notule noemt het doel van het gesprek.
- Een modelverzoek dat te lang duurt, stopt na 15 minuten met de melding "Tijdslimiet bereikt".
