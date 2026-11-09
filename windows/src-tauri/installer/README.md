# ThoughtVault MSI-template

`main.wxs` is gebaseerd op de lokaal aanwezige, bij CLI 2.10.1 gebruikte
`tauri-bundler 2.8.1/src/bundle/windows/msi/main.wxs` (MIT OR Apache-2.0).
Originele SHA-256: `57741539ea0f67eafd86c7d50247f79c0da1ec2e094bad0e8bf0f27ae8990402`.
De MIT-licentie is opgenomen in LICENSE-MIT.md.

Gerichte afwijkingen:

- Machinebrede InstallDir en protocolregistratie hebben een HKLM-keypath.
  De bestaande HKCU-zoekpaden blijven voor upgrades beschikbaar; de nieuwe
  HKLM-zoekopdracht heeft voorrang. De bestaande UpgradeCode blijft behouden.
- De extra uninstall-snelkoppeling in Program Files is verwijderd. Verwijderen
  blijft beschikbaar via Windows Geïnstalleerde apps. Desktop/startmenu blijven.
  Bij installatie wordt ook de achtergebleven `Uninstall ThoughtVault.lnk`
  uit de installatiemap verwijderd; deze verwees na upgrades nog naar het
  ProductCode van de voorganger. Alleen deze exacte productbestandsnaam wordt
  geraakt. Upgradegedrag moet met de nieuwe MSI op Windows worden bewezen.
- Alleen oudere versies mogen automatisch worden vervangen. Ook vervanging van
  dezelfde versie door een anders gebouwde installer wordt niet toegestaan.
  Rollback vereist een afzonderlijke, gecontroleerde herstelprocedure.
- REINSTALLMODE wordt niet overschreven; Windows Installer gebruikt zijn normale
  herinstallatiegedrag. Er wordt geen ICE-validatie onderdrukt.

Bij een Tauri CLI/bundler-update deze afwijkingen met de nieuwe upstream-template
vergelijken en de werkelijk gebouwde MSI opnieuw met ICE en payloadhashes toetsen.
De standaardtests controleren het componentbereik, de upgrade-identiteit en het
upgradebeleid; dit vervangt geen Windows-installatie-/herstelacceptatie.

De bestaande WebView2-downloadbootstrapper blijft behouden. Zijn ICE03-melding
betekent volgens de eerdere beoordeling niet dat Installer de opdracht afkapt;
een schone Windows-installatie zonder WebView2 blijft een aparte acceptatiestap.
