# Lokale MCP in ThoughtVault

Optioneel inschakelen via Instellingen → Verwerking → AI-koppelingen. Geen ThoughtVault-account nodig. ThoughtVault moet geopend blijven. De verbinding is uitsluitend bereikbaar vanaf hetzelfde apparaat en vereist de willekeurige Bearer-sleutel uit de systeemkeyring. Gebruik de knop om verbindingsgegevens te kopiëren; behandel die als een wachtwoord.

| Platform | HTTP-endpoint |
| --- | --- |
| macOS | `http://127.0.0.1:11218/mcp` |
| Windows | `http://127.0.0.1:11219/mcp` |

De gekopieerde JSON bevat `url` en `headers.Authorization`. Dit zijn verbindingsgegevens; plaats ze in de HTTP-MCP-configuratie van je client. Cloudwebsites zoals ChatGPT-web kunnen jouw loopback-adres niet rechtstreeks bereiken. Een lokale MCP-client is vereist; ondersteuning hangt van de client af. Een publieke tunnel of nieuwe accountbackend is geen onderdeel van deze oplossing.

Voor de lokaal geïnstalleerde Codex CLI ondersteunt `codex mcp add --help` een HTTP-endpoint en een token uit een omgevingsvariabele. Voorbeeld voor macOS:

```sh
codex mcp add thoughtvault --url http://127.0.0.1:11218/mcp --bearer-token-env-var THOUGHTVAULT_MCP_TOKEN
```

Stel `THOUGHTVAULT_MCP_TOKEN` veilig in voor de client, met alleen de sleutel na `Bearer ` uit de gekopieerde gegevens. Zet de sleutel niet in broncode of gedeelde logs. De opdracht hierboven is documentatie; de audit heeft je Codex-configuratie niet gewijzigd.

## Rechten en tools

| Recht | Mogelijkheden |
| --- | --- |
| Lezen | `list_devices`, `get_app_state`, `list_transcripts`, `get_transcript`, `list_profiles`, `get_profile`, `export_minutes` |
| Wijzigen | `save_minutes`, `update_transcript`, `save_profile`, `open_view` |
| Opname bedienen | `start_recording`, `pause_recording`, `resume_recording`, `stop_recording` |

De toolcatalogus toont alleen de toegestane tools. Lees eerst een document/profiel met zijn revisie voordat je schrijft. Verouderde revisies worden geweigerd. Een ingebouwd profiel wordt bij wijzigen naar een eigen profiel gekopieerd. Geen algemene shell-/bestands-, verwijder-, personenbeheer- of credentialtools.

Windows ondersteunt microfoon of gecombineerde audio; macOS ook systeemgeluid. Opnameacties gebruiken de bestaande zichtbare opnameflow. Bij een onzekere uitkomst na een timeout: niet automatisch opnieuw starten/stoppen/schrijven. Controleer de appstatus.

Export ondersteunt HTML, Markdown en tekst. `format: pdf` levert opgemaakte, printklare HTML en documentstijl voor PDF-rendering door de client; het levert geen PDF-bestand of tijdelijke downloadlink.

Uitschakelen stopt de server en slaat intrekking op vóór het verwijderen van de sleutel. Al gestarte appacties kunnen nog afronden. De ingestelde cloudprovider voor notulengeneratie blijft beschikbaar: lokale MCP verandert die instelling niet.

## Controles

- Windows: frontendtests en productiebuild; native compile, PE-runtime en installer via private CI-kandidaat.
- macOS: ondertekende Debugbuild en AIConnectionTests.
- `python3 scripts/test-local-mcp.py`: daadwerkelijke macOS HTTP-server met synthetische handlers; protocol, toolcatalogus, rechten en ongeldige aanvragen. Geen privétranscript of opname nodig.

Een transporttest is geen bewijs van een live Claude/ChatGPT-sessie. Native Windows-VM-audio, popupstijl en macOS sandbox/gebruikerskeyring moeten afzonderlijk in de geïnstalleerde app worden gecontroleerd.

Transport: stateless Streamable HTTP, protocol `2025-06-18`, JSON-antwoorden en geen SSE-stream. GET/DELETE ontvangen 405. Referentie: [MCP transport-specificatie](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).
