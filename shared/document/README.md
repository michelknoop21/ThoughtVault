# Gedeelde documentmodule

`src/` bevat het versie-1 huisstijlformaat, importvalidatie, de huisstijleditor, A4-HTML-opbouw en de `docx`-exporter. De vooraf gebouwde bestanden in `dist/` worden door beide platformen gebruikt: Apple laadt de kopie onder `macos/Resources/Document` in WKWebView; Windows importeert `document.mjs`. Een normale Windows-build heeft daarom geen tweede npm-installatie nodig.

Wijzig bronbestanden en bouw beide bundels samen opnieuw:

```sh
npm ci --prefix shared/document
npm run build --prefix shared/document
npm test --prefix shared/document
npm run build --prefix windows
```

`build.mjs` gebruikt alleen lokale assets. Het genereert de twee JS-bundels, TypeScript-declaraties, Apple-hostpagina's, de Xcode-resourcefolder `macos/Resources/Document`, licenties en `docs/huisstijlen/Yinga.tvhuisstijl`. `src/bundled.json` is een genegeerd tussenbestand. Commit de gewijzigde bron én dist-bestanden samen. Lettertypen en originele Yinga-assets blijven onder `assets/`.

De editor slaat pas na succesvolle hostopslag een nieuwe bibliotheekstatus op. Windows gebruikt de bestaande Tauri Store; Apple gebruikt een atomisch lokaal JSON-bestand. Foutieve opslag wordt zichtbaar gemeld. `.tvhuisstijl` bevat één versie-1 stijl met ingebedde PNG/JPEG-afbeeldingen. Een afbeelding is maximaal 2 MB en 25 megapixels; een stijlbestand is maximaal 12 MB. Onbekende velden worden niet actief. Externe assets en SVG zijn uitgesloten.

Een toegepaste snapshot is JSON (`document_branding_json` in overdrachtsmodellen, `documentBrandingJSON` in SwiftData). Ontbrekende snapshots behouden bestaande gegevens en weergave. Nieuwe notulen en een bewuste keuze voor Standaard ThoughtVault bewaren eveneens een versie-1 snapshot van de meegeleverde standaardstijl. Stijlbeheer verwijst nooit terug vanuit een eerder opgeslagen snapshot naar wijzigbare bestanden.

Dezelfde DOM wordt na het laden van fonts en afbeeldingen over A4-pagina's verdeeld. Tabellen krijgen herhaalde kolomkoppen; lange alinea's behouden inline-opmaak tijdens het splitsen. Een tabelrij of lijstpunt dat afzonderlijk groter is dan een hele pagina wordt met een foutmelding afgewezen; de inhoud wordt niet stil afgekapt. HTML bevat de uiteindelijke pagina's en fonts. Apple maakt van elke pagina een afzonderlijke WebKit-PDF-rechthoek en voegt die samen op A4. Afdrukken op macOS gebruikt de geproduceerde PDF. Windows gebruikt de gepagineerde DOM in het native afdrukvenster.

De inhoudseditor kan alleen `.tv-content` aanpassen. Het documentkader, logo's en banners vallen daarbuiten. In bewerkmodus groeit de inhoudspagina mee; de volledige tekst blijft bereikbaar. Voor weergave en export wordt opnieuw gepagineerd.

Controles:

- `test/branding.test.mjs`: schema, ongeldige imports, snapshots, sanitatie, CSS en assets.
- `test/editor-fixture.html`: beheer, import/export, standaard, verwijdering en fout bij schrijven.
- `test/fixture.html`: korte en lange notulen uit `test/fixtures.json`, tekstbehoud, lijsten en 120 tabelrijen.
- `scripts/tests/document-webkit-smoke.sh <map-op-externe-SSD>`: dezelfde lange notule door de native WebKit-engine, DOCX en de productcode voor A4-PDF.
- `ThoughtVaultTests/DocumentBrandingTests.swift`: bibliotheek, snapshot, DTO, lokale bewerking en Apple-syncmodel.

Open browserfixtures via een lokale HTTP-server, nooit via `file://`. De Apple-webview laadt gebundelde productresources via `loadFileURL`; dat is geen browsermockup.
