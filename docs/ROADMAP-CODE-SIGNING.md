# Plan: Code Signing voor macOS en Windows builds

## Context

TranscriptStudio wordt gedistribueerd buiten de app stores via directe download. Momenteel zijn macOS builds ad-hoc gesigned en Windows builds unsigned, wat leidt tot:
- **macOS**: Gatekeeper waarschuwing "onbekende ontwikkelaar" — gebruikers moeten rechts-klikken → Open
- **Windows**: SmartScreen blokkeert met "Unknown publisher" melding

**Conclusie uit onderzoek: self-signed certificaten helpen NIET.**
- Windows: self-signed = zelfde als unsigned, SmartScreen blijft blokkeren
- macOS: Gatekeeper accepteert alleen Apple-uitgegeven Developer ID certificaten

## Wat is nodig

### Certificaten aanschaffen (eenmalig + jaarlijks)

| Item | Kosten/jaar | Doel |
|------|-------------|------|
| Apple Developer Program | $99 | Waarschijnlijk al actief (team XL9KN38ATX bestaat) |
| Developer ID Application certificaat | Gratis (bij Dev Program) | macOS code signing + notarization |
| SSL.com OV Code Signing + eSigner | ~$450 | Windows code signing via cloud HSM (nodig voor CI/CD) |
| **Totaal** | **~$550/jaar** | |

> **Belangrijk**: Sinds juni 2023 vereisen ALLE code signing certificaten hardware-backed key storage (USB token of cloud HSM). SSL.com eSigner biedt cloud HSM, nodig voor GitHub Actions.

> **SmartScreen realiteit**: EV certificaten geven sinds 2024 GEEN instant SmartScreen bypass meer. Zowel OV als EV bouwen reputatie op via downloads (2-8 weken). OV is de pragmatische keuze — toont bedrijfsnaam en kost minder.

## Implementatie

### Stap 1: GitHub Secrets configureren

**macOS secrets:**
| Secret | Inhoud |
|--------|--------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded .p12 met Developer ID Application cert + private key |
| `APPLE_CERTIFICATE_PASSWORD` | Wachtwoord van de .p12 export |
| `APPLE_ID` | Apple ID email voor notarization |
| `APPLE_ID_PASSWORD` | App-specific password (appleid.apple.com → App-Specific Passwords) |
| `APPLE_TEAM_ID` | `XL9KN38ATX` |

**Windows secrets:**
| Secret | Inhoud |
|--------|--------|
| `WINDOWS_SIGN_USER` | SSL.com eSigner username |
| `WINDOWS_SIGN_PASSWORD` | SSL.com eSigner password |
| `WINDOWS_SIGN_TOTP_SECRET` | TOTP secret voor eSigner 2FA (non-interactive signing) |
| `WINDOWS_SIGN_CREDENTIAL_ID` | SSL.com credential ID |

### Stap 2: `scripts/env.sh` — signing defaults toevoegen

Toevoegen aan het einde:
```bash
# Code signing (optional — defaults to ad-hoc for development)
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-XL9KN38ATX}"
```

### Stap 3: `scripts/build.sh` — conditionele macOS signing

Vervang de huidige ad-hoc signing flow door conditionele logica:

- Als `CODESIGN_IDENTITY` is ingesteld (niet `-`): bouw met `CODE_SIGNING_ALLOWED=YES`, sign met hardened runtime + entitlements, notariseer DMG
- Anders: huidige ad-hoc signing (ongewijzigd gedrag voor development)

Signing volgorde:
1. Archive met code signing enabled
2. Export .app
3. Sign geneste frameworks/dylibs individueel (niet `--deep`)
4. Sign .app met `--options runtime` + entitlements
5. Maak DMG
6. Sign DMG
7. Submit DMG naar `notarytool --wait`
8. Staple notarization ticket op DMG

### Stap 4: `.github/workflows/release.yml` — signing in CI

**macOS job - nieuwe stappen:**
1. **Import certificate**: Maak tijdelijke keychain, importeer .p12 uit secret
2. **Build**: `CODE_SIGNING_ALLOWED=YES` + `CODE_SIGN_IDENTITY` als cert aanwezig
3. **Sign**: Individuele components eerst, dan app bundle met hardened runtime
4. **Notarize**: `xcrun notarytool submit` + `xcrun stapler staple`
5. **Verify**: `codesign --verify` + `stapler validate`
6. **Cleanup**: Verwijder tijdelijke keychain

**Windows job - nieuwe stap:**
1. **Sign MSI**: Download SSL.com CodeSignTool, sign MSI na Tauri build
2. **Verify**: `Get-AuthenticodeSignature` check

Signing is conditioneel — als secrets niet geconfigureerd zijn, wordt unsigned gebouwd (backwards compatible).

**Geen wijzigingen aan `tauri.conf.json`** — Windows signing gebeurt als post-build stap met CodeSignTool, niet via Tauri's ingebouwde signtool integratie (die vereist een lokaal certificaat, niet compatible met cloud HSM).

### Stap 5: Verificatie

**macOS (na build):**
```bash
codesign --verify --deep --strict --verbose=2 "build/export/TranscriptStudio.app"
spctl --assess --type open --context context:primary-signature --verbose "build/TranscriptStudio-1.0.50.dmg"
xcrun stapler validate "build/TranscriptStudio-1.0.50.dmg"
```

**Windows (na build):**
```powershell
Get-AuthenticodeSignature "build\TranscriptStudio_1.0.50_x64.msi"
# Status = "Valid", Subject bevat "Prezent Internet B.V."
```

## Bestanden die gewijzigd worden

| Bestand | Wijziging |
|---------|-----------|
| `scripts/env.sh` | 2 regels: CODESIGN_IDENTITY + APPLE_TEAM_ID defaults |
| `scripts/build.sh` | Conditionele signing logica macOS sectie (~40 regels) |
| `.github/workflows/release.yml` | Certificate import + signing + notarization + verificatie stappen (~80 regels) |

## Aandachtspunten

1. **`temporary-exception.audio-unit-host` entitlement**: Kan notarization rejection veroorzaken. Als dat gebeurt: verwijderen als het niet meer nodig is, of Apple exception aanvragen.
2. **SmartScreen reputatie**: Eerste downloads tonen mogelijk nog waarschuwingen, ook met OV cert. Dit verbetert na ~500+ downloads. De melding toont dan wel "Prezent Internet B.V." in plaats van "Unknown publisher".
3. **Build tijd**: Notarization voegt 2-15 minuten toe aan macOS CI builds.
4. **Lokale builds**: Windows signing werkt alleen in CI (CodeSignTool + cloud HSM). Lokale Windows builds blijven unsigned — dat is OK want development gebeurt op macOS.

## Volgorde van uitvoering

1. ✅ Controleer Apple Developer Program membership (team XL9KN38ATX)
2. Genereer Developer ID Application certificaat + export als .p12
3. Maak app-specific password aan op appleid.apple.com
4. Koop SSL.com eSigner OV certificaat
5. Configureer alle GitHub secrets
6. Wijzig `env.sh`, `build.sh`, `release.yml`
7. Test met dev channel build (`deploy-dev.sh`)
8. Verifieer: DMG opent zonder Gatekeeper waarschuwing, MSI toont bedrijfsnaam
9. Productie deploy
