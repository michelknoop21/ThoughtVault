# MSI 1.0.299: ondertekening en WiX-beoordeling

Status: DONE_WITH_CONCERNS voor deze onderteken-/beoordelingsronde.
**Geen vrijgave voor uitrol.** Er is niets geïnstalleerd of gepubliceerd.

## Exact pakket en herkomst

Centrale MSI-job `39b7f1a680c14372846bd1ca05e3cd4a` slaagde met exit 0;
ICE-validatie en 887 payloadhashes zijn door de centrale taak gecontroleerd.
Bronjob: `18916d4c4d5b4251bfeb9a9f7f8074ee`; broncommit
`870c3f93f75620f4a932f6cacf595f7ce2850aea`. Bronmanifesthash:
`36fb2f0b95dee20fe8dd2da7755d3835c6ef1e67040e18ba6551263a139a6244`.
Verpakkingssnapshot: `a09a6af6d12e60084a3308d7f287bded8cb441e484aff8d85b6d742e8fa72ab6`.

MSI: `ThoughtVault_1.0.299_x64_en-US.msi`, 110.751.664 bytes.
SHA-256: `b18758ab9ea2084d99f25b770a86cca3c333f5e235288f9022172a8f20647502`.
De naar de Mac overgebrachte MSI heeft exact deze lengte en hash. Het centrale
payloadmanifest bevat 887 entries en geen read_token. Dit is controle van het
centrale bewijs, geen tweede zelfstandige extractie van alle payloadbestanden.

## Updaterondertekening: PASS

Exact deze MSI is op de Mac met de bestaande Windows-updaterkey ondertekend.
De key bleef op de Mac; geen geheime sleutel of wachtwoord is gelogd/gekopieerd.
De publieke key komt overeen met de vastgelegde verpakkingsconfiguratie.
De cryptografische controle verifieert zowel de payload als het ondertekende
commentaar. Een gewijzigde payload en een gewijzigd commentaar worden afgewezen.

`.msi.sig`: 428 bytes, SHA-256
`c53d4f120da1a3d1831f7b3bf4379fd91539d876eef2c709aeb9a2aac0fa30e4`.
Het paar plus SIGNED-MANIFEST.json staat lokaal onder
`build/windows-pilot-20261105/central-1.0.299/output/artifacts/` en op Dalf38 onder
`C:/Dalf38/incoming/thoughtvault-1-0-299-signed/`.
Beide bestanden zijn na terugplaatsing op Dalf38 op hash en lengte gecontroleerd.
De teruggehaalde signature is bytegelijk en opnieuw cryptografisch geverifieerd.
Het oorspronkelijke centrale MSI-artifact is niet gewijzigd.

Dit is updaterondertekening. Windows rapporteert voor deze MSI Authenticode
`NotSigned`; er wordt geen Windows-uitgeverssignering geclaimd.

## ICE57: niet afgetekend voor brede uitrol

De waarschuwing is inhoudelijk bevestigd in twee componenten:

- `RegistryEntries`: HKCU InstallDir is het component-keypath, terwijl hetzelfde
  component de machinebrede HKLM protocolregistratie aanmaakt.
- `CMP_UninstallShortcut`: een HKCU-keypath wordt gecombineerd met een shortcut
  en mapverwijzing in de gedeelde installatiemap.

Hierdoor kan installatie voor verschillende Windows-gebruikers gedeeltelijk of
inconsistent uitpakken. Dit is een authoringprobleem, geen door hashcontrole
opgeloste onzekerheid. Microsoft adviseert gebruikers- en machinebronnen per
component te scheiden. Voor algemene distributie dit corrigeren: de HKLM
protocolregistratie van het gebruikerscomponent scheiden; de gedeelde
uninstallshortcut verwijderen of geheel machinebreed authoren. Daarna een
nieuwe kandidaat bouwen/valideren en installatie/verwijdering onder verschillende
gebruikers controleren. Er is in deze ronde geen template aangepast.
[Microsoft: ICE57](https://learn.microsoft.com/en-us/windows/win32/msi/ice57).

## ICE61: verklaard, upgradebeleid nog niet afgetekend

De oorspronkelijke WiX-authoring bevat `AllowDowngrades="yes"`; het onbeperkte
upgradebereik is dus verklaarbaar en geen onverwachte afwijking van de inputs.
De aanwezige Tauri-configuratieschema's bevestigen dat allowDowngrades standaard
true is. Dit pakket kan daarmee ook een nieuwere geïnstalleerde versie vervangen.
Dat bewijst geen veilige terugwaartse compatibiliteit van gebruikersgegevens.

Aanbevolen productiebeleid: `bundle.windows.allowDowngrades=false` en rollback
als afzonderlijke gecontroleerde herstelprocedure. Als directe downgrades bewust
gewenst zijn, eerst expliciet als beleid vastleggen en met de betrokken versies
gegevensbehoud, instellingen en herstel aantonen. Tot die keuze en acceptatie is
ICE61 geen afgetekende releasevoorwaarde. Geen downgrade/rollback uitgevoerd.
[Microsoft: ICE61](https://learn.microsoft.com/en-us/windows/win32/msi/ice61).

## Overige daadwerkelijk aanwezige waarschuwingen

Het ICE-log bevat ook ICE03 voor de lange WebView2-bootstrapperopdracht en ICE40
voor vooraf ingestelde REINSTALLMODE=amus. ICE03 meldt overschrijding van de
kolomdefinitie; volgens Microsoft begrenst Installer de werkelijke kolombreedte
niet intern tot die definitie. Dat is op zichzelf geen bewijs van een afgekapt
commando, maar de installatie zonder vooraf aanwezige WebView2 blijft ongetest.
ICE40 vraagt aandacht voor afwijkend herinstallatiegedrag. Schone installatie,
herinstallatie en upgrade moeten dit daadwerkelijk afdekken; niet stil negeren.
[Microsoft: ICE03](https://learn.microsoft.com/en-us/windows/win32/msi/ice03),
[Microsoft: ICE40](https://learn.microsoft.com/en-us/windows/win32/msi/ice40).

## Behoud en open acceptatie

Via SSH opnieuw vastgesteld: geïnstalleerd blijft 1.0.295. Het oorspronkelijke
native artifact heeft nog zijn geregistreerde hash b93fe7f4…2018e52.
De gedeelde cache-executable is de al eerder aanwezige MSI-markervariant
792396c2…2e95cfd, niet bytegelijk aan het native UNK-artifact; zijn laatste
schrijftijd 14:21:43 UTC ligt vóór de centrale verpakkingsjob. Er is geen
zelfstandige volledige cache-audit uitgevoerd. Deze ronde schreef uitsluitend
nieuwe lokale bewijsbestanden en de afzonderlijke ondertekende stagingmap.

Installatie/rollback, daadwerkelijk gegevensherstel, echte opnameketen en
inhoudskwaliteit blijven open. De centrale MSI-taak installeert nadrukkelijk
niets; deze ronde gebruikt uitsluitend SSH voor Dalf38. Geen Royal TSX,
computeruse, centrale codewijziging of nieuwe beheerinfrastructuur.
