# Yinga-huisstijl voor ThoughtVault

De kant-en-klare huisstijl staat in [Yinga.tvhuisstijl](Yinga.tvhuisstijl). Dit ene bestand bevat het originele logo, de geometrische voorbladbanner, de koplijn en de blauwe voetbanner. Er zijn geen losse afbeeldingen nodig.

Na installatie van een build met deze functie:

1. Open **Instellingen → Huisstijlen**.
2. Kies **Yinga toevoegen**. Of kies **Importeren** en selecteer `Yinga.tvhuisstijl`.
3. Kies desgewenst **Standaard maken** voor nieuwe notulen.
4. Open een bestaande notule en kies **Huisstijl → Yinga** om alleen die notule aan te passen.

Tekst, acties en controle-uitkomsten blijven behouden. Een notule bewaart de toegepaste huisstijlversie, inclusief afbeeldingen. Een wijziging of verwijdering in de bibliotheek verandert eerdere notulen niet. **Nieuwste versie toepassen** werkt alleen de geopende notule bij. Een herimport met dezelfde stijl-ID vervangt de bibliotheekversie na bevestiging; eerdere snapshots blijven bestaan.

Pas naam, bedrijfsgegevens, afbeeldingen, kleuren, typografie, marges en kop/voet aan en kies **Opslaan**. Met **Dupliceren** maak je een aparte stijl. Op een telefoon wissel je tussen **Instellingen** en **Voorbeeld**. Exporteer een stijl als `.tvhuisstijl` om hem op een ander apparaat te importeren.

De bibliotheek blijft lokaal. Apple-synchronisatie neemt de bij de notule opgeslagen versie en afbeeldingen mee. Kies **PDF**, **Word (.docx)** of **HTML** bij de notule voor documentexport. Word blijft bewerkbaar. De precieze paginaovergangen kunnen per documentengine verschillen.

De bronassets komen uit `ProspectFlow/deploy/instances/yinga/assets`, met de bijbehorende documentinstellingen. De documentlettertypen zijn Caladea en Carlito; de meegeleverde SIL OFL-licenties staan in `shared/document/assets` en in de applicatiebundel. Er worden geen externe scripts, afbeeldingen of lettertypen geladen.

Dit is een bronimplementatie in een eigen werkboom, nog geen gepubliceerde release.
