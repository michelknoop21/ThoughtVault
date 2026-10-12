$ErrorActionPreference = 'Stop'
$Version = '0.2.0'
$Archive = "nemo-speech-$Version-windows-x86_64-cpu"
$ExpectedHash = '82c80451086e86194aba9af19f800da77cd66d1c28d993d0efceffd6cdb49bb8'
$Stage = Join-Path $env:TEMP "ThoughtVault-Nvidia-$Version"
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
$Zip = Join-Path $Stage "$Archive.zip"
if (!(Test-Path $Zip)) {
    Invoke-WebRequest "https://github.com/NVIDIA/NeMo-Speech.cpp/releases/download/v$Version/$Archive.zip" -OutFile $Zip
}
if ((Get-FileHash $Zip).Hash.ToLower() -ne $ExpectedHash) { throw 'NVIDIA CPU runtime checksum mismatch' }
Expand-Archive $Zip -DestinationPath $Stage -Force
$Destination = Join-Path $PSScriptRoot "../windows/src-tauri/resources/nemo-speech-$Version"
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Copy-Item (Join-Path $Stage "$Archive/bin") $Destination -Recurse -Force
Copy-Item (Join-Path $Stage "$Archive/share") $Destination -Recurse -Force
& (Join-Path $Destination 'bin/nemo-speech.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'NVIDIA CPU runtime does not start' }
