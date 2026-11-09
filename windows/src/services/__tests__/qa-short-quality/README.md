# Opname10: vaste auditproef

De oorspronkelijke vier fixtures komen uit de Windows-overdracht van 30 oktober; de vijfde bewaakt een verkeerd budget en de zesde het onterecht veranderen van een toestemmingsvoorwaarde in een opdracht. De gate gebruikt de echte `auditSource` en `auditNotule`; de zes bronnen/notulen zijn vooraf vastgelegd. Het is geen audio-, generator-, Tauri-proxy- of MSI-proef.

De gewone tests controleren uitsluitend het QA-hulpmiddel met synthetische antwoorden. Zij bewijzen geen modelkwaliteit. De optionele prepare/replay-test blijft standaard overgeslagen.

Vanuit `windows`, met een nieuwe lege bewijslocatie:

```sh
TV_AUDIT_MODE=prepare TV_AUDIT_DIR=/absolute/path/new-baseline \
  npx --no-install vitest run src/services/__tests__/qa-short-quality/modelcontrole.test.js
```

Dit schrijft maximaal twaalf `*.request.json` (per geval eerst `.source.request.json`, daarna de inhoudsaudit) met uitsluitend het model en de exacte messages/stream-inhoud uit de productie-auditprompt. Er worden **geen providerrequests** gedaan. `PREPARATION.json` bevat dus geen semantische PASS; de verwachte interne voorbereidingsfouten zijn geen modelafwijzingen.

Een reeds goedgekeurde beveiligde adapter moet eerst de broncontrole eenmaal uitvoeren. Bij een onduidelijke bron wordt de inhoudsaudit overgeslagen. Voor een duidelijke bron moet de adapter het inhoudsrequest eenmaal naar de bestaande Ollama Cloud `gpt-oss:120b` sturen. De requestbody komt overeen met het compatibele productiepad; deze QA-route vervangt niet de Windows Tauri-proxy. Behoud het ongewijzigde `choices[0].message.content` als `<geval>.response.txt`, UTF-8. Geen headers, keys, audio of andere gebruikersinhoud opslaan. Geen nieuwe sleutelroute, download, retry of providerwissel. Een HTTP-/transportfout apart bewaren en niet presenteren als modelantwoord.

Daarna, met dezelfde bron/promptversie en dezelfde bewijslocatie:

```sh
TV_AUDIT_MODE=replay TV_AUDIT_DIR=/absolute/path/new-baseline \
  npx --no-install vitest run src/services/__tests__/qa-short-quality/modelcontrole.test.js
```

Replay vergelijkt de effectieve requestbody exact met de eerder bewaarde versie, voert de echte parser/validatie uit en schrijft `REPLAY.json`. Een ontbrekend antwoord, ongeldige JSON of ongerichte afwijzing is geen negatieve PASS. Bewijsbestanden worden niet overschreven. Iedere promptwijziging krijgt een eigen locatie en maximaal twaalf nieuwe begrensde calls; behoud eerdere fouten.

De oorspronkelijke auditresponse van de app-proef is niet bewaard. Een nieuwe baseline is een nieuwe waarneming en reconstrueert die historische response niet. De geobserveerde onterechte appacceptatie blijft staan, ook bij een later gunstig antwoord. Zonder echte modelantwoorden is een gerichte productfix nog niet onderbouwd.
