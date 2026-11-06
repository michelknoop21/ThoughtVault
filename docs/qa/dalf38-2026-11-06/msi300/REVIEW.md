# ThoughtVault 1.0.300 — kandidaatbewijs

**Geen vrijgave voor collega's.** Native build geslaagd; MSI-aanvraag wacht op
definitieve lokale snapshotgoedkeuring. Er is niets geïnstalleerd of gepubliceerd.

- Broncommit: `fef23dd1d8d5df093b1eb17bd7c511e34662b22d`.
- Native job: `6432b5df2af247978710b98664a5df68`, exit 0.
- Bronmanifest SHA-256: `184ab77858709c4d73445145d9fe6547ba585b35a9e64858469e81d2b27fe208`.
- Native executable: 27.411.456 bytes; SHA-256
  `b5f5389f7abe176822b3c515c6c289324a16b452c4ee5ad442693e737e90d4a3`.
- MSI-aanvraag: `2a1f78ee9b9d4e888094bc5982e7412b`.

## Verandering en controle

Zie de vastgelegde [templateherkomst en correcties](../../../../windows/src-tauri/installer/README.md).
Doel: ICE57/ICE61/ICE40 oplossen met correcte componentauthoring en upgradebeleid,
zonder waarschuwingen te onderdrukken. Product-ID en UpgradeCode blijven behouden.
De MIT-licentie van de upstreamtemplate wordt meegeleverd; verwacht één extra
payloadbestand ten opzichte van 1.0.299. De centrale payloadcontrole bepaalt het
daadwerkelijke aantal.

11 lokale scripttests PASS. De scope-regressietest faalt op de oorspronkelijke
template. Native build heeft de frontend opnieuw gebouwd; de 173 frontendinputs
zijn onveranderd tegenover de vastgelegde 209-PASS-baseline. Dit is geen nieuwe
uitvoering van de volledige frontend-/Rust-testsuite.

Werkelijke MSI-rendering, ICE-resultaat, payload, updaterondertekening en
installatie/rollback zijn nog niet gecontroleerd voor deze kandidaat. De bekende
inhoudskwaliteitsafwijzing en de overige native acceptatierijen blijven open.
De centrale MSI-taak verpakt en controleert uitsluitend; zij installeert niets.

## Voorbereide snapshot

Snapshot SHA-256: `2e6160c685b818275eea13fee935a107b13d57219be99674a7a3e2c880f9ba33`.
Het centrale manifest bevat 31.358 bestanden. De manifesthash is via de bestaande
centrale hashfunctie opnieuw berekend. EXE-hash vergeleken met het native artifact;
configuratie, installer-template en licentie vergeleken met de lokale bronhashes.
Dit is een gerichte broncontrole, geen onafhankelijke volledige kopie-audit.
De lokale beheerder moet deze exacte snapshot nog definitief goedkeuren.

## Inhoudsproef voorbereid

De vier vaste requests staan in `../model-baseline300/`, met het actuele
productie-auditpad en het bestaande model `gpt-oss:120b`. De prepare-run slaagt
(4 tests), maar doet **geen providerrequests**. `PREPARATION.json` is uitsluitend
voorbereidingsbewijs; er zijn nog geen echte modelantwoorden of semantische PASS.
Gebruik uitsluitend de reeds goedgekeurde beveiligde adapter; credentials blijven
in de bestaande gebruikerscontext. Daarna hetzelfde request/antwoordpaar replayen
volgens de [proefinstructie](../../../../windows/src/services/__tests__/qa-short-quality/README.md).
