# ThoughtVault voor Windows — lokaal gebruik

ThoughtVault wordt ontwikkeld door Yinga. Je hebt geen ThoughtVault-account nodig.
Opnames, transcripties en notulen worden lokaal opgeslagen. Transcriptie gebeurt lokaal met Whisper. Voor notulen kies je lokale AI of cloud-AI. Bij cloud-AI wordt alleen de transcriptie naar die provider verstuurd; audio blijft lokaal.

## Installeren

1. Installeer `ThoughtVault_<versie>_x64.msi` op een Windows x64-pc.
2. De installer controleert WebView2 en installeert dit zo nodig. Hiervoor kan internet nodig zijn.
3. Open ThoughtVault. De welkomstwizard helpt je met de lokale modellen en microfoon.
4. Download het Whisper-model. Standaard is dit Medium (circa 1,5 GB); Small is sneller en circa 466 MB.
5. Gebruik de knop **Ollama downloaden**, installeer Ollama en start het.
6. Open PowerShell en voer `ollama pull llama3.2` uit. Wacht tot de download klaar is.
7. Kies **Opnieuw controleren** in ThoughtVault. De modellen moeten als klaar voor gebruik worden getoond.
8. Geef de app microfoontoegang in Windows-instellingen en maak een korte testopname.

Na installatie van de modellen werkt opname → transcriptie → notulen ook zonder internet.
Ollama moet draaien. LM Studio is een alternatief: laad je model en start de lokale server.
Grotere modellen kosten meer schijfruimte, geheugen en verwerkingstijd; probeer eerst een korte opname op je eigen pc.

## Later inrichten of problemen oplossen

Je kunt de wizard overslaan en later via **Instellingen → Verwerking** afronden.
Bestaande notulen bekijken en opnemen blijven beschikbaar. Verwerken vereist de modellen.

- **AI-server niet bereikbaar:** start Ollama of de lokale server van LM Studio en kies Opnieuw controleren.
- **Notulemodel ontbreekt:** voer de getoonde `ollama pull`-opdracht uit, of laad het model in LM Studio.
- **Transcriptiemodel downloaden mislukt:** controleer internet en vrije schijfruimte, en probeer opnieuw.
- **Geen microfoon:** schakel microfoontoegang voor desktopapps in bij Windows → Instellingen → Privacy en beveiliging → Microfoon.
- **Alleen transcriptie beschikbaar:** de transcriptie is al lokaal opgeslagen; controleer het notulemodel en probeer opnieuw via Taken.

## Cloud-AI voor notulen

Kies **Ollama Cloud**, vul het cloudmodel in en sla de API-sleutel op. Het adres is `https://ollama.com`.
Kies **Cloudprovider** voor een OpenAI-compatibele aanbieder. Voeg een benoemde provider toe, stel HTTPS-adres en model in en sla de sleutel op. Een adres mag eindigen op `/v1`. Selecteer de opgeslagen configuratie en kies **Opnieuw controleren**. De controle haalt modellen op en doet voor cloud-AI een korte testgeneratie, zodat ook modeltoegang en authenticatie worden gecontroleerd.
Sleutels staan in de systeemkeyring en worden alleen via HTTPS verstuurd. Cloud-AI vereist internet. Een verkeerde sleutel, ontbrekend model of verbindingsfout blokkeert alleen de notulen; de transcriptie blijft lokaal bewaard en kan opnieuw worden verwerkt.
Microsoft 365 aanmelden en updates zijn beschikbaar via Instellingen. De ThoughtVault-serverroute en app-login worden niet gebruikt.
Verwijder de lokale appgegevens niet bij herinstallatie: die bevatten je notulen.

## Installer bouwen (ontwikkelaar)

Op een Windows x64-buildmachine: Node.js, Rust/MSVC, Visual Studio C++ buildtools, CMake en LLVM/libclang.
Als LLVM niet onder `C:/Program Files/LLVM` staat, stel `LIBCLANG_PATH` in op de map met `libclang.dll`.

Voer vanuit de repository uit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-local.ps1
```

De script voert frontend- en native tests uit en bouwt de MSI. De installer, handleiding en SHA256 staan in
`build/windows-local/`. Deze route uploadt of publiceert niets.

Alternatief: start handmatig een GitLab-pipeline met `LOCAL_WINDOWS_ONLY=1`.
Alleen de lokale Windows-build draait; download het artifact van `build-windows-local`.

## Vereiste praktijkcontrole vóór delen

Installeer op een echte Windows-pc, maak een opname met microfoon én systeemaudio, genereer notulen,
exporteer en herstart de app. Herhaal de verwerking met internet uitgeschakeld nadat de modellen zijn gedownload.
Controleer ook een upgrade van een bestaande installatie: oude notulen blijven zichtbaar, zonder login.
Een frontendbuild op macOS bewijst deze Windows-functies niet.

## Herstelcontrole op macOS — 7 oktober 2026

De Mac-versie is met Apple Development-identiteit en sandbox gebouwd en opnieuw geïnstalleerd op `/Applications/ThoughtVault.app`. De bestaande bundle-ID en Keychain-groep zijn behouden. Voor de upgrade zijn voorkeuren en de lokale opslag gekopieerd naar `/tmp/thoughtvault-upgrade-20261007-103550`.

- Mac-tests: 36 geslaagd; Windows-frontendtests: 37 geslaagd; native Rust-tests op macOS: 18 geslaagd. Frontendbuild, `cargo check`, ondertekende Mac-build en `codesign --verify --deep --strict` geslaagd.
- App opent zonder ThoughtVault-login. Bestaande notulen en de synthetische testtranscriptie bleven zichtbaar na herstart.
- Een korte microfoonopname startte en stopte. Stilte gaf een duidelijke melding; audio bleef lokaal bewaard.
- Een synthetisch WAV-bestand werd lokaal met WhisperKit getranscribeerd. Daarna genereerde lokale Ollama (`qwen3:8b`) notulen; de lokale server registreerde HTTP 200 op `/v1/chat/completions`. Markdown-export naar `/tmp/Testgesprek Dotvolt.md` gecontroleerd.
- Ollama Cloud leverde een modellenlijst. Generatie met de aanwezige configuratie gaf HTTP 401. De app meldde de sleutelfout en behield de transcriptie. De cloudverbindingstest doet daarom ook een korte generatie; een openbare modellenlijst wordt niet als bewijs voor geldige authenticatie gebruikt.
- Tests controleren afzonderlijke opgeslagen OpenAI-compatibele providers, geselecteerde adressen/modellen, aparte keyring-sleutels, SSE-voortgang, HTTPS voor sleutels en behoud van transcriptie bij fouten. Succesvolle externe generatie voor deze providers is nog niet live geverifieerd met een geldige sleutel.
- Apple-spraakherkenning mag in lokale modus niet uitwijken naar serverherkenning. Wanneer on-device herkenning ontbreekt, verwijst de melding naar WhisperKit.
- Volledig offline gebruik met uitgeschakelde netwerkverbinding en de Windows-installer/opnameflow zijn nog niet op echte Windows-hardware gecontroleerd.

De nieuwe migratie bewaart provider-, model-, onboarding-, update-, agenda- en Obsidian-instellingen. Waar versie 1 een adres door een standaardadres verving, wordt een eerdere iCloud-configuratie gebruikt als die beschikbaar is. Reeds gewiste instellingen zonder eerdere kopie zijn niet reconstrueerbaar; bestaande Mac-Keychain-items worden niet door de migratie verwijderd.

## Windows-buildcontrole — 7 oktober 2026

De x64-MSI voor 1.0.255 bevat de huidige Windows-wijzigingen, inclusief lokale en cloud-AI, AI-verbindingen, documentvormgeving en de opname-widget. De JavaScript- en Rust-versies van Tauri zijn gelijkgetrokken. API-sleutels gebruiken nu daadwerkelijk Windows Credential Manager; het ontwikkelhulpprogramma `read_token` wordt niet meegeleverd.

- Op een Windows x64-runner: 45 frontendtests en 19 native tests geslaagd, inclusief audio-import en opnieuw uitlezen van credentials.
- MSI gebouwd, stil geïnstalleerd met exitcode 0 en de geïnstalleerde `transcript-studio.exe` gestart. De app bleef draaien tijdens de startcontrole. Het installatielog bevestigt dat alleen de app wordt meegeleverd.
- Installer, handleiding, checksum, bronbestanden-hashes en build-/installatielogs staan in `build/windows-local/`. [Geslaagde Windows-build](https://github.com/michelknoop21/ThoughtVault/actions/runs/37610419654).
- Microfoon- en systeemaudio-opname, volledig offline verwerken en upgrade met bestaande gebruikersgegevens moeten nog op een Windows-pc worden gecontroleerd. De geslaagde build en startcontrole bewijzen die praktijkflows niet.

## Updates vanaf 1.0.256

De app controleert bij starten en vervolgens iedere zes uur op updates als
**Controleren op updates** aanstaat. Je krijgt een melding en kiest **Nu bijwerken**.
De app controleert de updatehandtekening, toont downloadvoortgang en laat Windows
de MSI installeren. Een Windows/UAC-bevestiging kan nodig zijn. Tijdens opnemen
of verwerken is bijwerken uitgeschakeld; ook na downloaden wordt dit gecontroleerd.
Bij een fout blijven opnames en notulen bewaard en kun je opnieuw proberen.

De installer staat op `https://thoughtvault.yinga.ai/releases/` en de website
leest de actuele downloadlink uit `/releases/releases.json`. Audio en transcriptie
blijven lokaal. Een cloudprovider ontvangt de transcriptie voor het maken van
notulen. Hiervoor is uitsluitend de sleutel van die gekozen provider nodig.

Voor releasebuilds moet `TAURI_SIGNING_PRIVATE_KEY` in de CI-secret store staan.
Deze releasesleutel is afzonderlijk van de AI-providersleutels. Bewaar een beveiligde
backup: een andere releasesleutel kan bestaande installaties niet bijwerken.

Vanaf 1.0.257 heet het geïnstalleerde programma `ThoughtVault.exe`. De bestaande app-identiteit en lokale opslag blijven behouden. Het hoofdvenster is ondoorzichtig; de opnamewidget blijft transparant.

## Release 1.0.257 — 7 oktober 2026

Gebouwd op Windows via run https://github.com/michelknoop21/ThoughtVault/actions/runs/37617125089
(source `ce1f322712765ac75819efdf1fc0e7bb088ed6aa`). 46 frontendtests en 19 native tests geslaagd.
De MSI is over 1.0.255 geïnstalleerd; `ThoughtVault.exe` startte tweemaal en het
opgeslagen notulenbestand bleef byte voor byte behouden. ProductName en
FileDescription zijn ThoughtVault, ProductVersion is 1.0.257. De oude executable
is bij de upgrade verwijderd. Deze controle bewijst geen microfoonopname of
visuele scherpte op een fysieke gebruikers-pc.

Publicatie door CI en HTTPS-download gecontroleerd:
https://thoughtvault.yinga.ai/releases/ThoughtVault_1.0.257_x64.msi
SHA-256: `148f34b36bf4270101921218ceeec2eb6471f0a0c817e7cb5b12cc2697e54f94`.
De publieke MSI en updater-signature komen overeen met het CI-artifact.
De updatefeed meldt 1.0.257. Lokale bewijsbestanden staan onder
`build/windows-local/1.0.257/` (MSI, signature, installatielogs, CI-log en metadata).
Een volledige update via de app en opname/export op de fysieke Windows-pc moeten
nog worden getest. Oudere installaties zonder de nieuwe updater vereisen deze
MSI eenmalig handmatig.
