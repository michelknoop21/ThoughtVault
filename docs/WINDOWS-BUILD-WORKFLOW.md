# Windows bouwen en testen vanuit de Mac

Vastgelegd op 1 oktober 2026. Dit beschrijft de daadwerkelijk gebruikte werkwijze
voor versie **1.0.255**, inclusief de fouten en hun oplossing. De testresultaten
en grenzen staan in [het testverslag](windows-build-parity-2026-10-01.md).

## 1. Bouwomgeving en keuze

- Bron op Mac: `/Volumes/SSD/Projects/thoughtvault-native`, basiscommit `b5a3575`
  met ongecommitte wijzigingen. Niet uitsluitend een checkout van die commit
  gebruiken: die bevat deze wijzigingen niet.
- Eerst Parallels onderzocht: Windows 11 ARM64. `prlctl exec` was niet bruikbaar
  met de geïnstalleerde editie; daarvoor is Pro/Business nodig. Er is geen
  geslaagde ARM64-build gemaakt. Dit sluit bouwen via de interactieve VM niet uit.
- Vervolgens gebouwd op de bestaande **Windows-pc**, via Royal TSX en de bestaande
  RDP-verbinding **Dalf38 VPN**. Dit was een andere machine dan Parallels.
- Pc: Windows 11 Pro Education, Ryzen 7 5700X3D, 48 GB RAM.
- Afzonderlijke bronmap op die pc: `C:\tvb-20261001`. Niet bouwen vanuit een
  Mac-share, OneDrive-map of de Apple-werkmap.
- Windows-terminalcommando's zijn via de RDP-interface in PowerShell uitgevoerd.
  Er was geen SSH- of WinRM-buildverbinding.

Bij een volgende sessie: meld een verandering van bouwmachine expliciet. Lees
eerst `CLAUDE.md` en verifieer de vereiste gstack-installatie. Behoud wijzigingen
van andere sessies; deze Windows-opdracht heeft geen Apple-bronbestanden gewijzigd.

## 2. Vereiste tools

Op de Windows-pc zijn Node/npm, Rust met MSVC-target, Visual Studio C++ Build Tools
met Windows SDK, CMake en LLVM/libclang gebruikt. WiX maakt de MSI; de Tauri-config
gebruikt `useLocalToolsDir: true`. Installeer tools alleen uit officiële bronnen.

Exacte hostversies zijn niet volledig bewaard; verzin deze niet. Leg bij een
volgende build de versies vast vóór het bouwen:

```powershell
node --version
npm.cmd --version
rustc --version
cargo --version
rustup show
cmake --version
clang --version
Get-Command node,npm.cmd,cargo,rustc,cmake,clang
```

Gebruik de huidige `windows/package-lock.json` en `windows/src-tauri/Cargo.lock`.
De werkende target was `x86_64-pc-windows-msvc`. Whisper bouwt C++ vanuit bron;
de standaardconfiguratie gebruikt CPU-inference.

## 3. Bron overzetten

Tijdens deze sessie zijn bron-ZIP's en gerichte vervolgpatches vanuit de actuele
Mac-werkmap overgezet. Geen `node_modules`, `dist` of Rust `target` overzetten.
Ook geen credentials, settings met secrets, `.env` of meetingopnamen meenemen.
Voor herhaling verdient één complete, gecontroleerde bron-ZIP de voorkeur boven
de historische reeks patches.

Voor de overdracht draaide tijdelijk een Python HTTP-server op de Mac:

- Tijdelijke map: `/tmp/thoughtvault-windows-transfer`.
- Mac-adres tijdens deze sessie: `192.168.3.106`, poort `18743`.
- Windows-pc tijdens deze sessie: `192.168.3.104`.
- Downloads vanuit die map; uploads alleen van die pc, alleen naar
  `/incoming/<bestandsnaam>`, maximaal 200 MB, opgeslagen in `received/`.
- Dit waren lokale netwerkadressen, geen permanente configuratie.
- De server is na afloop gestopt. Hij draait dus niet meer.

De gebruikte Windows-downloadvorm was:

```powershell
Invoke-WebRequest 'http://192.168.3.106:18743/ThoughtVault-source.zip' -OutFile C:\tvb-20261001\source.zip
Expand-Archive C:\tvb-20261001\source.zip C:\tvb-20261001 -Force
```

Controleer vooraf de ZIP-structuur: `scripts`, `windows` en `VERSION` moeten direct
onder `C:\tvb-20261001` terechtkomen. `Expand-Archive -Force` verwijdert geen oude
bestanden die niet meer in de ZIP zitten; gebruik bij een nieuwe sessie een nieuwe
werkmap om verouderde bronbestanden te vermijden.

## 4. Testen en bouwen

Frontendcontroles zijn op de Mac uitgevoerd. Native Rust-tests en de MSI-build
zijn op de Windows-pc uitgevoerd. Commando's voor herhaling:

```powershell
Set-Location C:\tvb-20261001\windows
npm.cmd ci
npx.cmd vitest run
npm.cmd run build
npm.cmd audit --omit=dev

Set-Location C:\tvb-20261001\windows\src-tauri
$env:CMAKE = (Get-Command cmake).Source
cargo test --target x86_64-pc-windows-msvc

Set-Location C:\tvb-20261001
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 *> .\build-icons-final.log
$tvBuildExit = $LASTEXITCODE
Get-Content .\build-icons-final.log -Tail 20
if ($tvBuildExit -ne 0) { throw "Build mislukt: $tvBuildExit" }
```

De laatste regel is een herhaalbare foutcontrole; in de sessie is de exitcode
getoond en het log bekeken. De definitieve build slaagde, met Rust-releasecompilatie
in **1 minuut 9 seconden**, gevolgd door candle/light en de MSI.

`scripts/build.ps1` doet het volgende:

1. Leest `VERSION` en controleert Node/npm/Rust/CMake.
2. Zet `CMAKE` expliciet op het absolute executable-pad.
3. Voert `npm ci` uit.
4. Voert `npm run tauri -- build --target x86_64-pc-windows-msvc --bundles msi` uit.
5. Controleert de exitcodes en kopieert de MSI naar de rootmap `build`.
6. Print SHA256 en het resultaatpad.

Resultaatpaden:

```text
C:\tvb-20261001\build\ThoughtVault_1.0.255_x64.msi
C:\tvb-20261001\windows\src-tauri\target\x86_64-pc-windows-msvc\release\transcript-studio.exe
```

Het script ondersteunt ook `-Portable` en een ARM64-target; die routes zijn niet
in deze sessie native geverifieerd. De build wijzigt geen releaseversie en publiceert niets.

## 5. Problemen die daadwerkelijk opgelost zijn

### CMake en PowerShell

De C++-toolchain kan PATH veranderen. Daarom gebruikt het buildscript het absolute
`CMAKE`-pad. PowerShell 5 kan native stderr tijdens logopvang als fout behandelen,
ook bij waarschuwingen. Het script controleert daarom native exitcodes en zet
`ErrorActionPreference` rond die aanroepen tijdelijk op `Continue`.

### LLVM en Whisper

De eerdere `whisper-rs 0.14`-bindings liepen vast op een layout/alignment-controle
met LLVM 22. `whisper-rs 0.16` gebruikt bindgen 0.72 en bouwde wel. Dit staat in
`windows/src-tauri/Cargo.toml` en de lockfile. Niet terugdraaien zonder de native
build opnieuw te testen.

### Oude logo's ondanks nieuwe PNG's

De PNG's in de React-app waren vernieuwd, maar de executable bevatte nog het oude
roze icoon. Dit is bewezen door het icoon uit de geïnstalleerde executable te
extraheren. Alleen het zichtbare logo in de sidebar controleren was onvoldoende.

De nieuwe assets zijn overgenomen uit de actuele Apple-assets, inclusief een ICO
met meerdere Windows-resoluties. `windows/src-tauri/build.rs` volgt nu ook `icons`:

```rust
fn main() {
    println!("cargo:rerun-if-changed=icons");
    tauri_build::build()
}
```

Daarna opnieuw gebouwd en geïnstalleerd. Het nieuwe paarse icoon was zichtbaar in
de app, op de taakbalk, op het bureaublad en in het geëxtraheerde executable-icoon.

## 6. Installeren en controleren

Sluit ThoughtVault voordat je dezelfde testversie opnieuw installeert. Tijdens
deze sessie zijn meerdere builds met versienummer 1.0.255 gemaakt. Alleen
`REINSTALL=ALL` kon exitcode 0 geven terwijl features nog `Absent` waren en bestanden
niet werden vervangen. De werkende onderhoudsvolgorde was:

```powershell
$tvMsi = 'C:\tvb-20261001\build\ThoughtVault_1.0.255_x64.msi'
$tvInstall = Start-Process msiexec.exe -ArgumentList "/i $tvMsi ADDLOCAL=ALL /passive /L*v C:\tvb-20261001\install-icons-final.log" -PassThru -Wait
$tvInstall.ExitCode
$tvRepair = Start-Process msiexec.exe -ArgumentList "/fvamus $tvMsi /passive /L*v C:\tvb-20261001\repair-icons-final.log" -PassThru -Wait
$tvRepair.ExitCode
Start-Process 'C:\Program Files\ThoughtVault\transcript-studio.exe'
```

Beide exitcodes waren 0. Dit is de onderhoudsroute voor deze herhaalde testbuilds;
bij een normale release hoort een nieuw versienummer volgens de bestaande procedure.
Gebruik aanhalingstekens rond MSI- en logpaden als die spaties bevatten.

Voor verificatie is ook een MSI administratief uitgepakt en de executable daarin
met de geïnstalleerde executable vergeleken; die hashes waren gelijk. Vergelijk
met de MSI-payload: Tauri kan na compilatie bundle-informatie in de executable
patchen, waardoor een vergelijking met een ander buildstadium misleidend is.

```powershell
Start-Process msiexec.exe -ArgumentList '/a C:\tvb-20261001\build\ThoughtVault_1.0.255_x64.msi TARGETDIR=C:\tvb-20261001\msi-check /qn /L*v C:\tvb-20261001\extract-check.log' -Wait
Get-ChildItem C:\tvb-20261001\msi-check -Filter transcript-studio.exe -Recurse | ForEach-Object {
    (Get-FileHash $_.FullName).Hash -eq (Get-FileHash 'C:\Program Files\ThoughtVault\transcript-studio.exe').Hash
}
```

Deze hashcontrole vond plaats vóór de laatste iconen-rebuild. Die laatste rebuild
is apart geverifieerd met installatie-exitcodes, zichtbaar bureaubladicoon en
extractie van het geïnstalleerde icoon:

```powershell
Add-Type -AssemblyName System.Drawing
$tvIcon = [Drawing.Icon]::ExtractAssociatedIcon('C:\Program Files\ThoughtVault\transcript-studio.exe')
$tvIcon.ToBitmap().Save('C:\tvb-20261001\installed-icon-final.png', [Drawing.Imaging.ImageFormat]::Png)
ie4uinit.exe -show
```

Alleen `ie4uinit -show` loste het probleem niet op: de executable bevatte toen
nog het oude icoon. Een handmatige wijziging van de publieke bureaubladsnelkoppeling
faalde op toegangsrechten en is niet als oplossing gebruikt. De nieuwe MSI loste dit op.

## 7. Native functietest

Werkelijk uitgevoerd op de Windows-pc:

1. Algemene opname vanaf Home starten: bron **Gecombineerd**.
2. Nederlandse synthetische testaudio via Windows afspelen:
   `System.Media.SoundPlayer`, `PlayLooping()`; daarna expliciet `Stop()`.
3. Waveformreactie op WASAPI-systeemaudio controleren; pauzeren en vlakke waveform controleren.
4. **Bewaar zonder verwerken** gebruiken en controleren dat de WAV beschikbaar is.
5. Whisper Small via de app downloaden en synthetische Nederlandse audio lokaal transcriberen.
6. Ollama niet beschikbaar: expliciete fout in Taken en behouden transcript controleren.
7. Regenereren openen: alle zeven templates in de keuzedialoog controleren; annuleren.
8. Instellingen, echte hardwaregegevens, modeladvies, API-kostenlabels en logo's controleren.

Resultaten: 57 frontendtests en 20 native Rust-tests geslaagd. Echte betaalde API-calls,
live Obsidian REST-sync en ARM64 zijn niet getest. De opname is niet geüpload;
de lokaal bewaarde opname is niet verwijderd. Geen volledige functiepariteit claimen
op basis van alleen een geslaagde build.

## 8. Artifacts terughalen en opruimen

De upload gebruikte raw bytes, niet `UploadFile` (dat maakt multipart-data):

```powershell
$tvWeb = [Net.WebClient]::new()
$tvWeb.UploadData('http://192.168.3.106:18743/incoming/ThoughtVault_1.0.255_x64.msi', [IO.File]::ReadAllBytes('C:\tvb-20261001\build\ThoughtVault_1.0.255_x64.msi')) | Out-Null
```

MSI en logs zijn op de Mac opgeslagen in `build/windows-2026-10-01/` (gitignored).
Daar staan ook `SHA256SUMS.txt`, `source-manifest.json`, build-/installatielogs en het
geëxtraheerde icoon. Definitieve MSI SHA256:

```text
4113f1608939613f8dc59dd54f9cf54ae646c39cdbf8284a18927cf29947740e
```

Screenshots zijn uitgesneden tot het appvenster of icoon en staan in
`docs/qa/windows-2026-10-01/`; geen volledige privé-desktopscreenshots opslaan.
Tijdelijke HTTP-server en lokale devserver zijn gestopt. Geen commit, versie-bump,
tag, digitale ondertekening of publieke release gedaan.

## 9. Aandachtspunt bij RDP-bediening

Bij plakken via de Mac-RDP-interface kwam soms een clipboard-timeout, terwijl het
commando wel in PowerShell stond. Controleer het zichtbare commando en de uitvoer
voordat je opnieuw plakt. Screenshots konden één actie achterlopen. Selecteer de
juiste terminaltab, lees opnieuw de UI en voer een commando nooit blind dubbel uit.
