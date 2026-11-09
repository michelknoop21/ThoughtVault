# Windows collega-uitrol — actuele status

Bijgewerkt 9 november 2026. Nog niet vrijgegeven voor collega's.
Dit bestand is de leidende blocker-lijst; oudere rapporten blijven historisch.

## Bronbasis

Native 1.0.305 job `19ab8be2adf747468acd886ca132f280` is opnieuw gecontroleerd.
Alle 285 bronmanifestregels zijn met Git-basis `4de88a4` vergeleken: 261 identiek,
21 gewijzigde/nieuwe productbestanden via SFTP opgehaald en SHA256 gecontroleerd;
3 hostspecifieke build/provenancebestanden blijven in SSD-bewijs. Zie
`source305-changes.json`; het volledige manifest staat onder
`build/colleague-rollout-20261109/source305/`.

Herstelde wijzigingen: native tekstexport met padkeuze, begrijpelijke
inhoudsafwijzingen met behouden negatieve verdicts, brononzekerheid expliciet
controleren, fictieve status in prompts behouden, beide audiokanalen mengen,
MP4-audiospoor selecteren, verouderde uninstall-shortcut opruimen.
Gegenereerde Tauri-schema's en Rust-versie zijn bij dezelfde bron hersteld.

## Gecontroleerde Dalf38-toestand

SSH developer heeft verhoogde rechten; UAC blijft aan. Geïnstalleerd: 1.0.305.
Geen operationsjobs queued/running bij deze controle. `gui-status` toont slechts
historische routeprobe (5 november), geen actuele ontgrendelde desktopacceptatie.

## Leidende blockers

1. **Inhoud:** korte opname `8667a70b30584695942917a48fde7c7e`, MP4
   `13e679efbf9247a0b92a1dd0af19c9c0` en uurproef
   `7fc986da68174dc2af71fda9c1efe862` stoppen alle bij inhoudscontrole.
   Korte/MP4 reden: `De inhoudscontrole onderbouwt niet alle beweringen`;
   uurproef: `De inhoudscontrole is onzeker; beoordeel het concept`.
   MP4-conversie en transcriptie zijn dus niet de aangetoonde fout. Concept,
   transcript en originele gegevens zijn bewaard. Zonder het ruwe auditantwoord
   is nog niet te onderscheiden tussen terechte afwijzing en foutieve modelcontrole.
   De cleanup-stage `select: Transcriptiemodel` is geen hoofdoorzaak.
2. **Volledige flow:** export/bewerken/heropenen en tien stabiele runs ontbreken
   op de gekozen route. De uurproef bevat herhaalde synthetische spraak en
   transcriptievarianten; geen acceptatie van gevarieerde vergadering/fysieke microfoon.
3. **Collega-start:** verse identiteit met eigen toegang en schone installatie
   nog niet bewezen; geen persoonlijke credentials delen.
4. **Release/herstel:** nieuwe vaste RC, pakket/signature, daadwerkelijke upgrade,
   rollback en updater nog te bewijzen; geen release gepubliceerd.
5. **Pilot:** doelgroep/toegang vastleggen en vijf werkdagen werkelijk gebruik
   volgen nadat bovenstaande gates slagen.

## Volgende stap

Leg het werkelijke auditantwoord vast via de bestaande gekozen modelroute;
reproduceer de oorzaak met een gerichte regressie vóór een minimale reparatie.

Bronherstelcommit: `57dde58c07cb2f8543de8959788f074778f2f09a`. Frontendbasis vóór herstel: 209 tests PASS;
na herstel: 216 tests PASS, 1 bestaande opt-in modelproef overgeslagen.
De print()-melding komt uit de bestaande jsdom-testomgeving; geen PDF-acceptatie.
