$ErrorActionPreference='Stop'
$env:CARGO_HOME='C:\Dalf38\tools\cargo'
$env:RUSTUP_HOME='C:\Dalf38\tools\rustup'
$env:CARGO_TARGET_DIR='C:\Dalf38\temp\thoughtvault-cargo-target'
$env:CMAKE_POLICY_DEFAULT_CMP0091='NEW'
$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
$env:PATH="$env:CARGO_HOME\bin;C:\Windows\System32;C:\Windows;C:\Program Files\nodejs;C:\Program Files\Git\cmd;C:\Program Files\CMake\bin;C:\Program Files\LLVM\bin"
$vc = & cmd.exe /d /c vc-env.cmd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach($line in $vc) { if($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process') } }
& rustc.exe --version
& cargo.exe --version
'fn main() { println!("Dalf38 Rust MSVC smoke PASS"); }' | Set-Content -Encoding ASCII smoke.rs
& rustc.exe smoke.rs -o smoke.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\smoke.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
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
$artifactRoot='C:\Dalf38\artifacts\46a3d8c218a44b4f97a90b6e160ef4b1'
$manifest=Get-Content 'C:\Dalf38\jobs\46a3d8c218a44b4f97a90b6e160ef4b1\artifact-manifest.json' -Raw | ConvertFrom-Json
foreach($entry in $manifest){
 if(!$entry.path.StartsWith('windows/dist/')){throw 'Unexpected frontend artifact path'}
 $source=Join-Path $artifactRoot $entry.path
 if((Get-FileHash $source -Algorithm SHA256).Hash -ne $entry.sha256){throw 'Frontend artifact hash mismatch'}
 $destination=Join-Path $PSScriptRoot $entry.path
 New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
 Copy-Item -LiteralPath $source -Destination $destination
 if((Get-FileHash $destination -Algorithm SHA256).Hash -ne $entry.sha256){throw 'Copied frontend hash mismatch'}
}
Set-Location windows/src-tauri
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& cargo.exe clean --locked -p whisper-rs-sys
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& cargo.exe test --locked
exit $LASTEXITCODE
