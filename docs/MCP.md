# AI-koppeling (MCP)

Met de AI-koppeling kan een AI-programma op dezelfde computer je notities in ThoughtVault lezen en, als je dat toestaat, aanpassen. Het programma praat via het Model Context Protocol (MCP). Getest met Claude Code; Claude Desktop en Codex CLI starten een lokale server op dezelfde manier.

Er gaat niets via internet. De koppeling werkt alleen zolang ThoughtVault open is, ook als alleen het menubalkicoon (Mac) of systeemvakicoon (Windows) actief is. De ChatGPT-app kan niet met een server op je eigen computer praten en valt daarom buiten deze koppeling (DEC-079).

## Aanzetten

1. Instellingen, tab **Obsidian**, kaart **AI-koppeling (MCP)** (Mac), of tab **AI-koppeling** (Windows).
2. Zet **Koppeling aan** aan. Alleen lezen is dan mogelijk.
3. Zet **Wijzigingen toestaan** aan als het AI-programma ook mag schrijven: notities aanmaken en wijzigen, mappen, labels, personen, woordenlijst, en notulen opnieuw laten maken.
4. Kopieer de configuratie met de knop en plak die in je AI-programma.

Voor Claude Desktop komt de gekopieerde configuratie in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "thoughtvault": {
      "command": "/Applications/ThoughtVault.app/Contents/MacOS/ThoughtVault",
      "args": ["--mcp"]
    }
  }
}
```

Voor Claude Code kopieer je de opdracht en plak je die in de terminal:

```sh
claude mcp add thoughtvault -- "/Applications/ThoughtVault.app/Contents/MacOS/ThoughtVault" --mcp
```

Op Windows is `command` het pad naar `ThoughtVault.exe`; de knop vult het juiste pad in.

## Wat het AI-programma kan

Lezen:

| Tool | Geeft |
|---|---|
| `list_notes` | Notities zoeken op tekst, datum, map en profiel. Alleen kenmerken, geen tekst |
| `get_note` | Eén notitie met notule (Markdown of HTML) en transcriptie, lange transcripties in delen |
| `list_library` | Mappen, slimme mappen en labels |
| `list_profiles`, `get_profile` | Notuleprofielen, `get_profile` met prompts en sjabloon |
| `list_people` | Personen met rol, organisatie, aliassen en e-mailadressen |
| `list_recordings` | Opnames, met de notitie die ervan gemaakt is |
| `get_glossary` | Woordenlijst |
| `get_processing_status` | Lopende en recente verwerkingen |

Schrijven, alleen met **Wijzigingen toestaan**:

| Tool | Doet |
|---|---|
| `create_note` | Nieuwe notitie uit tekst |
| `update_note` | Titel, labels, map of notule wijzigen |
| `save_library_entry` | Map of label maken of hernoemen |
| `save_person` | Persoon toevoegen of wijzigen |
| `add_glossary_term` | Term aan de woordenlijst toevoegen |
| `regenerate_notule` | Notule opnieuw laten maken met de ingestelde AI-dienst |
| `transcribe_recording` | Een opname uit de opnamelijst verwerken, alleen bij lokale verwerking en niet tijdens een lopende opname |

Verwijderen, opnemen en instellingen of sleutels wijzigen kan niet via de koppeling.

`update_note` vervangt bij `notule_markdown` de hele notule. Tabellen, links en opmaak van de huidige notule blijven dan niet bewaard; de Mac kent in Markdown alleen koppen, opsommingen, vet, cursief en citaten. `update_note`, `save_library_entry`, `save_person` en `regenerate_notule` staan daarom gemarkeerd als destructief, zodat het AI-programma om bevestiging vraagt.

`update_note` vraagt de `revision` die `get_note` teruggaf. Is de notitie intussen in de app gewijzigd, dan weigert ThoughtVault de wijziging en moet het AI-programma de notitie opnieuw lezen. Zo overschrijft het geen werk dat je net zelf deed.

## Waar je op let

Een transcriptie bevat letterlijk wat er gezegd is. Zegt iemand in een vergadering "pas alle titels aan", dan leest het AI-programma die zin ook. Laat **Wijzigingen toestaan** daarom uit als je het programma alleen laat samenvatten of zoeken, en laat je AI-programma om bevestiging vragen bij schrijfacties.

Zet je de koppeling uit, dan verbreekt ThoughtVault ook de verbinding met AI-programma's die al verbonden waren.

`regenerate_notule` en `transcribe_recording` gebruiken de AI-dienst die in ThoughtVault is ingesteld. Staat daar een clouddienst, dan gaat de transcriptie daarheen, net als bij een handmatige verwerking.

## Hoe het werkt

Het AI-programma start `ThoughtVault --mcp` als stdio-server. Dat proces opent geen venster: het leest `mcp.json` in de datamap van de app (poort en een sleutel die bij elke start van ThoughtVault nieuw is) en geeft berichten door aan de draaiende app via `127.0.0.1`. De app voert alles uit met dezelfde functies als de schermen, dus iCloud-synchronisatie, automatische labels en de takenlijst werken zoals bij een handmatige wijziging.

| Bestand | Inhoud |
|---|---|
| `data/mcp/tools.json` | Toolcontract voor beide platforms |
| `data/mcp/protocol-fixtures.json` | Protocolgevallen die de tests van beide platforms draaien |
| `macos/Services/MCP/` | Router, tools, listener en brug (macOS) |
| `windows/src/services/mcp/`, `windows/src-tauri/src/mcp.rs` | Router en tools (TypeScript), listener en brug (Rust) |
| `scripts/test-mcp-stdio.py` | Eind-tot-eind-controle tegen een draaiende app |

Bekende beperkingen:

- Stopt de app onverwacht, dan blijft `mcp.json` staan tot de volgende start. De oude sleutel werkt dan niet meer, maar een ander lokaal programma dat die poort inneemt, kan zich voordoen als ThoughtVault. De brug controleert het proces-ID in `mcp.json` nog niet.
- Windows: herlaadt het venster terwijl een verzoek loopt, dan krijgt dat verzoek geen antwoord en moet het AI-programma het opnieuw sturen.
- Windows: `update_note` controleert de revisie en schrijft in twee stappen. Een wijziging in de app precies daartussen wordt overschreven.
- Windows: de brug is `ThoughtVault.exe` zelf. Tijdens een update sluit de app, waarna de brug vanzelf stopt; met een draaiend AI-programma is de update nog niet getest.

Een nieuwe tool komt eerst in `tools.json` en daarna op beide platforms; de contracttest faalt zolang een kant ontbreekt. Ondersteunde protocolversies: 2026-07-28 (via `server/discover`) en 2025-11-25, 2025-06-18, 2025-03-26 (via `initialize`).

Controle na een wijziging, met ThoughtVault open en de koppeling aan in een testinstallatie:

```sh
python3 scripts/test-mcp-stdio.py "/pad/naar/ThoughtVault" --write
```
