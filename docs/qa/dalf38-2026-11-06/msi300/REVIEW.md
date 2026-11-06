# ThoughtVault 1.0.300 — gecontroleerde MSI

**Nog geen vrijgave voor collega's.** Native build, MSI/ICE/payload en
updaterondertekening zijn geslaagd. Installatie/rollback en echte opname-/
inhoudsacceptatie blijven open. Er is niets geïnstalleerd of gepubliceerd.

## Exact pakket

- Broncommit: `fef23dd1d8d5df093b1eb17bd7c511e34662b22d`.
- Native job: `6432b5df2af247978710b98664a5df68`, exit 0.
- Bronmanifest: `184ab77858709c4d73445145d9fe6547ba585b35a9e64858469e81d2b27fe208`.
- Native EXE: 27.411.456 bytes; SHA-256
  `b5f5389f7abe176822b3c515c6c289324a16b452c4ee5ad442693e737e90d4a3`.
- MSI-job: `2a1f78ee9b9d4e888094bc5982e7412b`, exit 0.
- Snapshot: `2e6160c685b818275eea13fee935a107b13d57219be99674a7a3e2c880f9ba33`.
- `ThoughtVault_1.0.300_x64_en-US.msi`: 110.772.409 bytes; SHA-256
  `a1ac99e94ba06f1f5a062068ae95df099884ffe910c3e8cb579a37c034a40912`.
- `.msi.sig`: 428 bytes; SHA-256
  `7481ee994b1c9adba7a2f08400510b9974b09b7ae848d18f3bfc0a8394125616`.

Ondertekend paar op Mac: `build/windows-pilot-20261105/central-1.0.300/output/artifacts/`.
Op Dalf38: `C:/Dalf38/incoming/thoughtvault-1-0-300-signed/`.
Beide transferhashes en lengtes na terugplaatsing gecontroleerd; zie
`ssh-handoff-verification.json`. Signingkey bleef op Mac. De publieke productiekey,
payload en trusted comment zijn cryptografisch geverifieerd. Gewijzigde payload
en gewijzigd commentaar worden afgewezen. Dit is updaterondertekening;
Windows-uitgeverssignering wordt niet geclaimd.

## Installerfix en controles

De [vastgelegde upstreamtemplate](../../../../windows/src-tauri/installer/README.md)
bevat minimale scope-/upgradecorrecties. De echte bundelbouw en afzonderlijke
ICE-validatie zijn geslaagd. **ICE57, ICE61 en ICE40 zijn niet meer aanwezig**.
Alleen ICE03 voor de standaard WebView2-downloadbootstrapper blijft in het log;
installatie zonder vooraf aanwezige WebView2 is nog niet getest.

De centrale taak controleerde alle **888 payloadbestanden**, inclusief de nieuwe
MIT-licentie. Geen `read_token` in het payloadmanifest. Dit is controle van het
centrale extractie-/hashbewijs, geen tweede zelfstandige extractie op de Mac.
Het native artifact behoudt de oorspronkelijke hash. Via SSH vastgesteld:
geïnstalleerd blijft **1.0.295**.

11 lokale scripttests PASS; de scope-regressietest faalt op de oorspronkelijke
template. Native build heeft de frontend opnieuw gebouwd. De 173 frontendinputs
zijn onveranderd tegenover de vastgelegde 209-PASS-baseline; frontend-/Rust-tests
zijn in deze ronde niet volledig herhaald.

## Voorbereide inhoudsproef

De vier vaste requests in `../model-baseline300/` gebruiken het actuele
productie-auditpad en het bestaande model `gpt-oss:120b`. De prepare-run slaagt
(4 tests), maar doet **geen providerrequests**. PREPARATION.json is uitsluitend
voorbereidingsbewijs. Er zijn nog geen echte modelantwoorden of semantische PASS.
De bekende Opname10-afwijzing blijft open. Gebruik uitsluitend de reeds
geautoriseerde beveiligde adapter en volg de bestaande
[prepare/replay-instructie](../../../../windows/src/services/__tests__/qa-short-quality/README.md).

## Centrale uitvoergrens

Uitsluitend SSH gebruikt. De huidige centrale MSI-taak verpakt en controleert;
zij installeert niets en voert geen algemene app-/microfoontests uit.
De automatische snapshotvoorbereiding is na Windows-tests en onafhankelijke
review eenmalig door de beheerder geactiveerd (centrale commit a442929). De nieuwe
aanvraag c79cf1d550bd4212a03597182d1ae588 is zonder handmatige snapshotopdrachten
voorbereid/goedgekeurd en de beperkte verpakkingstaak draait. Eindresultaat volgt.
Dit geeft geen toestemming voor installatie/publicatie. Appdata bleef onaangeroerd.
