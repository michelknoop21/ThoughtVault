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

## Inhoudsherstel in uitvoering

De echte providerresponses zijn nu vastgelegd, zonder headers of credentials.
- Baseline `b836c967aa074c4f85f7da53197073c5`: ontbrekende actie kreeg een
  ongeldig positief verdict zonder bewijs; veilig afgewezen maar QA-gate faalde.
- Prompt-only `de1cc8101f364282b3cc44a3863b32a2`: Opname10 onterecht geaccepteerd;
  deze variant is niet geschikt voor release.
- Afzonderlijke broncontrole `4e79a6a475084ea0a6bbce6c80267b1b`: vijf vaste
  gevallen PASS, 9 begrensde calls, geen retry; onbegrijpelijke bron stopt vóór notulenaudit.
- Volledige generator `4924f6491a3c490face6b220109b4f5c`: drie bruikbare
  concepten faalden op dubbel, inconsistent teruggeschreven bewijsverwijzingen.
- Canonieke bewijsrelaties `76e2088ae5fc42638084798a75e4b872`: vijf vaste
  gevallen opnieuw PASS. Alle bron-/notule-IDs, verplichte bronvoorwaarden,
  affirmative bewijs en negatieve verdicts blijven gevalideerd; omgekeerde
  relaties volgen mechanisch uit dezelfde links.
- Generator-v2 `fcab49af4b1b43319aa9841174b77ec2`: twee productieacceptaties
  maar scenarioasserties faalden op NBSP-datums. Derde concept terecht afgewezen
  wegens een ongenoemde uitvoeringsstatus. Historische job blijft FAILED.
- Generator-v3 `e3e1d472d8e84c068ffb1a56586c762a`: lopende nieuwe proef met
  generieke statusverduidelijking en alleen in QA genormaliseerde witruimte.

Dit is service-/providerbewijs; nog geen nieuwe geïnstalleerde MSI-acceptatie.

## Actuele beslissing na de volledige proeven

**Taak 1 afgerond; taak 2 open en inhoudelijk NO-GO. Taken 3–8 niet afgerond.**
De laatste zesvoudige echte auditproef `9acd06163a5b4c0fba8c2b0c0ae4a696`
keurt één onterechte actie goed. Generator-v4 `05a36312371c4fd480b6a368339ec55d`
levert slechts 1/3 productieacceptaties; de twee overige concepten bevatten
opnieuw niet genoemde uitvoeringsstatussen. Zie `CONTENT-REVIEW.md` voor
beoordeling, raw request-/responsehashes en precieze beperkingen.
De modelrichting is voorgelegd; geen nieuwe promptfixes of modelwissel zolang
die keuze openstaat. Er zijn geen eigen proeven meer op de achtergrond actief.

De geïnstalleerde 305-binary is nu ook bytegewijs herleid: de enige afwijking
tegenover native job `19ab8…` is de driebyte bundelmarkering `UNK`→`MSI` op offset
20987538, overeenkomstig het Tauri-verpakkingslog. Alle overige bytes zijn gelijk.
MSI-request `b46dd82726654eae9e1961045ca206dc` en het huidige pakket hebben hash
`cf85b2576ebb9869bd51703f28e66a601c227519dd92ff3a3c945f0dcf8118da`.
Zie `binary-lineage305.json`; een gewone hashvergelijking zonder deze
verpakkingsstap zou onterecht bronafwijking suggereren.

Interne opruimcontrole: 11 eigen npm-debuglogs naar de externe SSD verplaatst,
hashes gecontroleerd en originelen verwijderd; 45056 toegewezen bytes
vrijgemaakt. Gedeelde npm-cache ongemoeid gelaten wegens gedeeld eigenaarschap.
Bewijs: `build/colleague-rollout-20261109/internal-task-logs/migration.json`.
