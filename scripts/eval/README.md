# Notule-evaluatie

Vergelijkt notules van kandidaatmodellen via OpenRouter. Het script draait de echte Windows-pijplijn (`windows/src/services/llm.ts`: concept, broncontrole, inhoudscontrole, "Even nalopen") met het standaardprofiel, onder het al geinstalleerde vitest. Kosten komen per verzoek uit `usage.cost` van OpenRouter.

Het detailniveau (`--detail kort|normaal|volledig`) bestaat in de pijplijn nog niet. De optie wordt geaccepteerd, genegeerd en als "n.v.t." vastgelegd.

## Invoer en uitvoer (privé, buiten de repo)

Invoer staat in `~/Documents/ThoughtVault-eval` (transcripties plus feitenlijsten). Resultaten gaan naar `~/Documents/ThoughtVault-eval/results/<tijdstempel>/` (map 700, bestanden 600): per run de notule als HTML, `runs.jsonl` en `summary.md`. Stdout toont alleen aantallen. Een resultatenmap binnen de git-worktree wordt geweigerd.

## Echte run

Vanuit `windows/` moet `node_modules` bestaan (`npm ci`).

```bash
vault-exec OPENROUTER_API -- \
  node scripts/eval/eval.mjs --models all --conversations schadebezoek,thuisserver --reps 2 --budget 6
```

Stuur eerst `/grant OPENROUTER_API`. Zonder `--env-var` leest het script `VAULT_VALUE`.

## Opties

| Optie | Standaard | Betekenis |
|---|---|---|
| `--models` | `all` | `all`, tiernamen uit `candidates.json` (Snel, Gebalanceerd, Grondig) of model-ids, komma-gescheiden |
| `--conversations` | `schadebezoek,thuisserver` | Naamvoorvoegsel van de bestanden in de datamap |
| `--reps` | 1 | Herhalingen per model en gesprek |
| `--budget` | 6 | USD. Geen nieuwe run als het gemeten totaal dit haalt, dus overschrijding hooguit één run |
| `--detail` | geen | `kort`, `normaal` of `volledig` (nog n.v.t.) |
| `--data-dir`, `--results-dir`, `--candidates` | zie boven | Andere locaties |
| `--dry-run` | uit | Nep-OpenRouter en fictieve fixture, geen netwerk, geen sleutel |
| `--dry-cost` | 0.01 | Nepkosten per verzoek in een dry-run |

Model-ids worden vooraf gecontroleerd tegen de openbare lijst op openrouter.ai; een onbekend id breekt af. Is de kostprijs van een verzoek onbekend, dan stopt het script om het budget te bewaken.

## Controle zonder kosten

```bash
node scripts/eval/eval.mjs --dry-run --reps 2
```
