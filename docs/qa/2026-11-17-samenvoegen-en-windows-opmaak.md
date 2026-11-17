# Samenvoegen en Windows-opmaak, 17 november 2026

Werkboom: `thoughtvault-samenvoegen-presentatie`, branch `fix/samenvoegen-presentatie-20261117`, gebaseerd op `8031b2c4`. Geen push, merge, installatie over productie of uitrol uitgevoerd.

## Wijzigingen

- Het samenvoegvenster op macOS, iOS/iPadOS en Windows toont documentkaarten die naar één kolom teruglopen. Datums staan los van titels; de interface voegt geen emdash-scheiding toe. Alleen het aantal bronnotulen en “Originelen blijven bewaard.” blijven als toelichting staan. De oorspronkelijke inhoud, sorteervolgorde, profielvalidatie en samenvoeglogica blijven behouden.
- Het venster gebruikt de bestaande Apple-tokens en Windows DesktopDialog, inclusief sluiten met Escape en focusterugkeer. Windows heeft één scrollbare inhoud, met vaste kop en acties. Lange titels mogen doorlopen.
- Windows blokkeerde de ingebedde documentfonts door `font-src 'self'`. De verpakte CSP staat nu ook lokale `data:`-fonts toe. De gedeelde editor stelt kop- en alineastijlen expliciet in, zodat de Tailwind-reset deze niet platmaakt.
- De instellingentabs lopen in rijen door; horizontale tabscroll is verwijderd. De gedeelde huisstijleditor schakelt op de eigen containerbreedte naar bewerken/voorbeeld, ook als het venster breed is maar het inhoudsvak smal.

## Gecontroleerd

Bewijs: `/Volumes/SSD/Projects/task-evidence/thoughtvault-samenvoegen-presentatie/`.

| Controle | Uitkomst |
|---|---|
| macOS, volledige app met geïsoleerde QA-host | BUILD SUCCEEDED, `mac-final-build.log` |
| iOS Simulator, volledige app met dezelfde sheet | BUILD SUCCEEDED, `ios-final-build.log` |
| Windows, native Tauri-release op fysieke Dalf38 | Geslaagd, inclusief TypeScript/Vite/Rust, `windows-native-build.log` |
| Windows-tests | 866 geslaagd, 2 bestaande skips, `windows-tests.log` |
| Gedeelde documenttests | 9 geslaagd, `shared-tests.log` |
| Nederlandse en Engelse strings | plutil: OK |
| Mac-weergave | Werkelijke sheet met drie synthetische documenten visueel bekeken: kaarten, losse datums, profielkeuze en korte toelichting. Laatste standaardknop-toetsmarkering daarna gecompileerd; geen laatste visuele aftekening. |

De Windows-QA-EXE is op hash gecontroleerd en naar de bewijsmap gekopieerd: `3756b59b2b39916d45bb6403e204b839c371b451ec191ef58e302a85b7125da1`. Remote: `C:\Dalf38\workspaces\thoughtvault-huisstijl-qa-20261117\output\ThoughtVault.exe`. Deze build heeft een eigen product- en gegevensidentiteit. De bestaande installatie is niet vervangen of gestopt. Voor Windows is broncommit `f2f135a1` gebruikt; de latere commit wijzigt uitsluitend de Apple-standaardknop.

## Open acceptatie

De eerdere melding dat Windows geen venster kon openen is achterhaald: de geïsoleerde app kon interactief via Verkenner worden gestart en Michel heeft de onboarding afgerond. De door Michel aangeleverde afbeelding maakte daarna de font-/editor- en tablayoutproblemen zichtbaar. De oplossingen zijn gebouwd; de uiteindelijke Windows-gebruikersroutes zijn nog niet afgetekend.

Tijdens de eindcontrole begon de schermbediening op alle apps te time-outen. Ook een expliciete reset en opnieuw selecteren van Royal TSX en de Mac-QA-app herstelden de bediening niet. SSH en builds bleven functioneren. Daarom ontbreken de uiteindelijke fysieke Windows-resize-, font-, import/export- en WebView2-afdrukcontrole en de visuele simulatorcontrole. De eigen iPhone-simulator is geïnstalleerd en gestart, maar dit geldt niet als visuele goedkeuring.

Volledige gesproken VoiceOver-acceptatie blijft open; de toegankelijkheidsboom alleen is daarvoor onvoldoende. Fysieke iPad op uitdrukkelijk verzoek overgeslagen. Het eerdere fysieke Mac/iPhone- en iCloud-bewijs voor huisstijlen blijft afzonderlijk beschreven in `docs/huisstijlen/IMPLEMENTATIE.md`.
