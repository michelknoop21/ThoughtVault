$ErrorActionPreference='Stop'
$env:CARGO_HOME='C:\Dalf38\tools\cargo'
$env:RUSTUP_HOME='C:\Dalf38\tools\rustup'
$env:CARGO_TARGET_DIR='C:\Dalf38\temp\thoughtvault-cargo-target'
$env:CMAKE_POLICY_DEFAULT_CMP0091='NEW'
$env:CARGO_BUILD_JOBS='2'
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
$env:PATH="$env:CARGO_HOME\bin;C:\Windows\System32;C:\Windows;C:\Program Files\nodejs;C:\Program Files\Git\cmd;C:\Program Files\CMake\bin;C:\Program Files\LLVM\bin"
$vc = & cmd.exe /d /c vc-env.cmd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach($line in $vc) { if($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process') } }
& rustc.exe --version
& cargo.exe --version
$donor='C:\Program Files\ThoughtVault\resources'
$provenance=@()
foreach($name in @('nemo-speech-0.2.0','faster-whisper-1.2.1')) {
 $source=Join-Path $donor $name
 $worker=if($name -like 'nemo*'){'bin\nemo-speech.exe'}else{'faster-whisper\faster-whisper.exe'}
 if(!(Test-Path (Join-Path $source $worker) -PathType Leaf)){throw "Installed worker unavailable: $name; do not restore quarantined files"}
 foreach($file in Get-ChildItem $source -File -Recurse) {
  $relative=$file.FullName.Substring($source.Length).TrimStart('\')
  $hash=(Get-FileHash $file.FullName -Algorithm SHA256).Hash
  $destination=Join-Path (Join-Path "$PSScriptRoot\windows\src-tauri\resources" $name) $relative
  New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
  if((Get-FileHash $destination -Algorithm SHA256).Hash -ne $hash){throw "Resource hash mismatch: $relative"}
  $provenance+=@{resource=$name;path=$relative;sha256=$hash;length=$file.Length}
 }
}
$provenance | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 resource-provenance.json
Write-Output "Installed resource files verified: $($provenance.Count)"

$wixSource='C:\tvb-20261001\windows\src-tauri\target\.tauri\WixTools314'
$wixTarget=Join-Path $env:CARGO_TARGET_DIR '.tauri\WixTools314'
if(!(Test-Path "$wixSource\candle.exe")){throw 'Existing WiX cache unavailable'}
$wixHashes=@()
foreach($file in Get-ChildItem $wixSource -File -Recurse){
 $relative=$file.FullName.Substring($wixSource.Length).TrimStart('\')
 $hash=(Get-FileHash $file.FullName -Algorithm SHA256).Hash
 $destination=Join-Path $wixTarget $relative
 New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
 Copy-Item -LiteralPath $file.FullName -Destination $destination
 if((Get-FileHash $destination -Algorithm SHA256).Hash -ne $hash){throw "WiX hash mismatch: $relative"}
 $wixHashes+=@{path=$relative;sha256=$hash;length=$file.Length}
}
$wixHashes | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 wix-provenance.json
Set-Location "$PSScriptRoot\windows"
& npm.cmd ci --offline --no-audit --no-fund --cache C:/Dalf38/temp/thoughtvault-npm-cache
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& node.exe node_modules/vitest/vitest.mjs run --maxWorkers=2
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
# The normal build preserves updater signing; an unsigned MSI is only an intermediate artifact.
& npm.cmd run tauri -- build --bundles msi --ci
$buildExit=$LASTEXITCODE
$output=Join-Path $PSScriptRoot 'package'
New-Item -ItemType Directory -Force $output | Out-Null
$msis=@(Get-ChildItem "$env:CARGO_TARGET_DIR\release\bundle\msi\ThoughtVault_1.0.297_x64*.msi" -File -ErrorAction SilentlyContinue)
@{tauriExitCode=$buildExit;msiCount=$msis.Count;updaterSignatureRequired=$true} | ConvertTo-Json | Set-Content -Encoding UTF8 "$output\build-result.json"
if($msis.Count -ne 1){throw "Expected one candidate MSI; found $($msis.Count); tauri exit $buildExit"}
Copy-Item -LiteralPath $msis[0].FullName -Destination $output
Get-FileHash "$output\*.msi" -Algorithm SHA256 | ConvertTo-Json | Set-Content -Encoding UTF8 "$output\msi-hash.json"
if($buildExit -ne 0){Write-Output "TAURI EXIT $buildExit; MSI retained for separate Mac signature verification, NOT delivery-ready"}
exit 0
