# ThoughtVault: releasenotes voor gebruikers

Wat er per versie verandert voor wie de app gebruikt, in gewone taal. De technische
wijzigingen staan in [CHANGELOG.md](CHANGELOG.md). Het helpcentrum bouwt de pagina
Releasenotes uit dit bestand (`scripts/build-helpcentrum.py`).

Elke release is een blok `## <versie> - <titel>` met direct daaronder een cursieve regel
met datum en platforms, bijvoorbeeld `*12 november 2026 · macOS · iOS · Windows*`.
De nieuwste release staat bovenaan.

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
