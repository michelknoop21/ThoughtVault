# macOS GO-rapport, 9 november 2026

## Besluit

**NO-GO.** De broncode is groen en de TestFlight-build staat bij Apple, maar de praktijkpoorten M4 tot en met M13 zijn nog niet uitgevoerd (M3 is PASS). Een gedeeltelijk resultaat telt niet als PASS.

De macOS-route is TestFlight (App Store-target zonder Sparkle). Build 1.0.309 (309) is op 9 november 2026 geüpload: Delivery UUID `06185210-e1ee-4c08-934d-52d06341e80f`. Build 1.0.310 (310) volgde op 10 november 2026: Delivery UUID `ed4e6505-1d05-426a-84ab-d0938143cc6f`. Er is geen DMG gepubliceerd en niets naar Developer ID-notarisatie gestuurd.

## Kandidaat

- Branch `feat/macos-parity`, commit `6ed9bf44291d7a7a27ab97f01c96aa687cfe20c6`.
- Basis: pilotcommit `6d03290`, daarna `origin/main` tot `6f3ef3d` ingevoegd (notulekwaliteit, testhost-afscherming, release 1.0.309).
- TestFlight-pakket: `ThoughtVault.pkg` uit target `ThoughtVault AppStore`, commit `8ca507f`, SHA-256 `6518708efad8e1a7f06de100867d0466fc5a4f7ca0fa80978caaf139859fdb09`, ondertekend met `3rd Party Mac Developer Installer: Michel Knoop (XL9KN38ATX)`.
- TestFlight-pakket 1.0.310 (310): gebouwd vanaf tag `v1.0.310` (commit `1c77d72`, merge van `feat/macos-parity` in `main` plus versieophoging), SHA-256 `f2142c81a8e105ce744cd2bb781be5339db97d4bce01002e47c60506e5571d88`, zelfde installercertificaat. Een eerdere poging vanaf lokale `main` mislukte bij het archiveren omdat daar de nog niet gepushte merge van `feat/lerende-context` in stond, met bronbestanden die niet in `ThoughtVault AppStore` waren opgenomen; die poging uploadde niets.

## Poorten

| Poort | Status | Bewijs |
|---|---|---|
| M0 broncode | PASS | macOS XCTest: `TEST SUCCEEDED`, 245 geslaagd, 0 mislukt. iOS Debug, iOS Release en macOS Release compileren. `test_sparkle_platforms.py`, `test-publish-release.py`, `test_macos_release.py`: OK. Windows vitest 53 bestanden, 237 geslaagd, 1 overgeslagen; `tsc --noEmit` schoon. `cargo test` draait niet op deze Mac (Windows-resource `nemo-speech-0.2.0` ontbreekt), zie BASELINE.md. |
| M1 bundle-ID | PASS (bron) | `env.sh`, `.gitlab-ci.yml`, RELEASE.md en PRD gebruiken `com.buildmind.ThoughtVault` en `.dev`. Resterende treffer `SystemAudioCapture.swift:88` is de naam van een privé audio-aggregaat, geen bundle-ID. Controle op een getekende app volgt bij M2. |
| M2 ondertekening | PASS (TestFlight) | App Store-export met Apple Distribution slaagt; uploads geaccepteerd: 1.0.309 Delivery UUID `06185210-e1ee-4c08-934d-52d06341e80f`, 1.0.310 Delivery UUID `ed4e6505-1d05-426a-84ab-d0938143cc6f`. Eerste upload met Sparkle werd door Apple geweigerd (90296, niet-gesandboxte Sparkle-helpers); opgelost met target `ThoughtVault AppStore`. Het directe DMG-kanaal blijft BLOCKED, zie [M2.txt](M2.txt). |
| M3 inhoud | PASS | Live run op 10 november 2026, 10:41 tot 10:49 UTC: `M3LiveContentGateTests` op basis 1.0.311 (`d94a2fe` plus de gate), Ollama Cloud met `kimi-k2.6` (alle antwoorden noemen dat model), 20 van maximaal 21 verzoeken, geen herhalingen, geen transportfouten. Auditgevallen 6/6: de correcte parafrase is goedgekeurd; ontbrekende actie (Iris), tegenstrijdige toestemming, verkeerd budget (15.000 tegen 12.450 euro), voorwaarde als opdracht (Sara) en de onduidelijke Opname10-bron zijn elk op de geplante fout afgewezen. Vergaderingen 3/3, inhoudelijk naast de bron gelegd: Waddenspoor bewaart 12.450 euro inclusief btw, beide controles, alleen een interne proef en geen klantgegevens naar buiten; Noorderlicht bewaart de vervallen migratie op 16 november, Mila 17 november 10 uur, Oscar 18 november, productie pas na beide controles, geen productieakkoord en geen echte klantgegevens; Bibliotheek bewaart 2.750 euro inclusief btw, beide offerteacties, geen gekozen leverancier, en schriftelijke goedkeuring blijft een voorwaarde in plaats van een actie. Geen van de drie voegt feiten toe. Offline: de echte Windows-antwoorden geven op macOS dezelfde uitkomst en de prompts zijn byte voor byte gelijk. Bewijs zonder sleutel (gecontroleerd): [M3/M3-20261110T114128](M3/M3-20261110T114128/). Dat gold voor de broncontrole als poort. Sinds DEC-062 is de broncontrole een waarschuwing en is `auditNotule` de poort; Opname10 vraagt daardoor twee verzoeken (21 in totaal) en wordt door de inhoudscontrole afgewezen. Opnieuw gedraaid op 10 november 2026: run [M3/M3-20261110T120552](M3/M3-20261110T120552/) haalde 8 van 9, want bij `tegenstrijdige_toestemming` zette `kimi-k2.6` het hele antwoord in het SSE-veld `reasoning` en gaf lege `content`, wat terecht als onbruikbaar is afgewezen (geen terugval op `reasoning`, zie DEC-062). Run [M3/M3-20261110T122528](M3/M3-20261110T122528/) haalde 9 van 9: 21 van 21 verzoeken, alle antwoorden van `kimi-k2.6`, geen herhalingen of transportfouten; Opname10 afgewezen met "De inhoudscontrole is onzeker", de vijf andere auditgevallen en de drie vergaderingen zoals hierboven. Offline replay met de nieuwe Windows-opname van de Opname10-inhoudsaudit ([kimi-k26-bronwaarschuwing](../colleague-rollout-2026-11-09/content/kimi-k26-bronwaarschuwing/)): zelfde uitkomsten. Beide nieuwe runs zijn op de sleutel gecontroleerd (grep-exitcode 1). |
| M4 ASR vaste clip | GEDEELTELIJK | `WhisperSilenceTests` draaiden met het geïnstalleerde model: `dutch-qa.wav` correct op "dotfoulduurtest" na; 60 s stilte gaf alleen `*** *** ***`. Nog te doen: eerste transcriptie offline (tokenizer wordt nu nog bij eerste gebruik opgehaald) en losse sterretjes vóór spraak. |
| M5 korte opname | NOT TESTED | Microfoon en gecombineerd, 2 minuten; widget-annuleren tijdens transcriptie. |
| M6 importen | NOT TESTED | WAV, M4A, MP3, MP4 met en zonder geluid, stille WAV, hernoemd tekstbestand. Extractor en foutteksten zijn met tests gedekt. |
| M7 één uur | NOT TESTED | Notulen boven 64 000 tekens worden altijd als concept bewaard, net als op Windows. |
| M8 tien runs | NOT TESTED | Volgorde van de transcriptiewachtrij waarnemen. |
| M9 export/bewerken | NOT TESTED | TXT, MD, PDF, HTML, ⌘P. Bevestigingen: zie [M9-confirmations.md](M9-confirmations.md). Draftsectie op macOS gezien: [screens](screens/). iOS-screenshots ontbreken: geen iOS-simulatorruntime op deze Mac. |
| M10 force-quit | NOT TESTED | `kill -9` tijdens opname en `pmset sleepnow`; herstel van WAV-headers is met tests gedekt. |
| M11 nieuwe gebruiker | NOT TESTED | Vereist getekende DMG (M2). |
| M12 upgrade en terugrol | NOT TESTED | Vereist getekende DMG. Back-up `~/ThoughtVault-backup-1.0.270-20261109.app` staat klaar. |
| M13 publicatie | NOT TESTED | Alleen via `publish-release.py`, alleen na "publiceer". |
| M14 pilot | NOT TESTED | Volgt op GO. |

## Alleen nodig voor het DMG-kanaal

TestFlight heeft dit niet nodig. Voor een Developer ID-DMG met Sparkle kies je één van twee:

1. In App Store Connect onder Gebruikers en toegang, Integraties, de API-sleutel `NA27NHZ724` toegang geven tot cloud-beheerde distributiecertificaten (rol Admin of het vinkje voor cloud managed distribution). Daarna exporteert Xcode zelf met Developer ID.
2. Als Account Holder op developer.apple.com een certificaat "Developer ID Application" aanmaken en in de login-sleutelhanger van deze Mac zetten. Daarna draait `scripts/build-macos-release.sh` volledig, inclusief notarisatie met de API-sleutel uit `~/.appstoreconnect/config.json`.

## Bewuste keuzes in dit traject

- **Verwerkingsadvies (taak 16) niet geport.** Op macOS werkt het advies pas na "Toepassen" en blijft de gekozen provider staan zolang die werkt. Dat is de Windows-regel. De Windows-drempels gelden voor whisper.cpp op de processor; macOS gebruikt WhisperKit op de Neural Engine met de eigen aanbeveling per chip.
- **Zoeken volgt Windows letterlijk**: de hele zoekterm als één tekst, hoofdletterongevoelig, geen woorden los en geen accentvrij zoeken.
- **Apple Intelligence blijft beschikbaar** met de melding dat lange vergaderingen meestal als concept worden bewaard; de feitencontrole past niet in het contextvenster van het lokale model.
- **Geen cloud-terugval meer** bij een mislukte lokale notule: de cloud zou een ongecontroleerde notule opleveren.

## Bekende open punten

- Een recorder die zelf stopt door een fout: het bestand blijft in "Opgeslagen opnames", maar de taak toont "te kort".
- Gecombineerde modus: na een microfoonfout blijft de systeemaudio opnemen.
- `env.sh` neemt de versie uit `VERSION`, niet uit de CI-tag; houd ze gelijk.
- De deploy-job schrijft `releases.json` voor de andere platforms nog zelf, naast `publish-release.py`.
