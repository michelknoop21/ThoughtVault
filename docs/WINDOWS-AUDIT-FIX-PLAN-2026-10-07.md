# Windows audit herstelplan

Basis: officiële 1.0.260 (`3eb688b`), audit van 7 oktober. Werkmap: `/tmp/thoughtvault-brand-windows`. Geen oudere UI terugzetten.

1. Verwerking: Whisper-opmaak veilig naar tekst normaliseren bij opslag en lezen; dezelfde tekst in weergave/kopie/export/AI. Duur afronden. Nederlandse providerfouten met herstelroute. Oorspronkelijke importnaam bewaren. Mislukte taken bewaren en na herstart opnieuw proberen zonder hertranscriptie.
2. UI: Home grid binnen beschikbare breedte; opnamewidget alleen tonen als hoofdvenster geminimaliseerd is; consistente pagina-as en leesbreedte; grotere toolbar-acties; donkere selectopties en niveau-meter; onboarding scrollruimte; één merkfooter; één profielactie en lijniconen.
3. Branding: goedgekeurde kluisvariant in React-assets én executable-iconen, gegenereerd vanuit bestaande bron.
4. Setup: runtimeprobleem bij oorzaak oplossen (C++ runtime statisch linken waar ondersteund); optionele officiële runtime-installer voor bestaande installaties, zonder ongevraagde acceptatie van voorwaarden.
5. MCP: oorzaak 502 bevestigd: oude accountbackend bewust verwijderd. Michel kiest lokale MCP zonder account, ook op macOS. Loopback + willekeurige keyring-sleutel; expliciete lees/schrijf/opnamerechten; bestaande toolhandlers en revisiecontroles hergebruiken. Lokale HTTP-clients ondersteunen; ChatGPT-web kan deze loopback-URL niet rechtstreeks bereiken.
6. Controle: regressietests voor tekst/duur/fouten/herstart/herimport; bestaande frontendtests + productiebuild; Windows native build/installer via expliciete bronref; VM runtimecontrole. Niet bewezen punten blijven expliciet open.

Niet openbaar gepubliceerd: de private kandidaat is gebouwd en heeft de automatische gates doorlopen. De runtime-audit op de Parallels-guest blijft geblokkeerd door ontbrekende reactie op input.

Uitgevoerd: alle hierboven genoemde broncorrecties, 58 frontendtests en productiebuild, macOS signed build en 7 AIConnectionTests, MCP HTTP- en SDK-controle met synthetische handlers. Definitieve Windows MSI (bf331ae, CI 37683601634) heeft 22 native tests, runtimecontrole, upgrade, twee starts en behoud van notulen doorlopen. macOS export van legacy HTML is ook veilig gemaakt. Zichtbare runtimecontrole blijft open doordat de Mac vergrendeld is en de Windows-guest niet reageerde op input.
