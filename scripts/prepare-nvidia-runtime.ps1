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
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$crt = Get-ChildItem "$installation/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (!$crt) { throw 'Microsoft x64 CRT redistributable directory not found' }
# Use Microsoft's redistributable directory, never DLLs from the host System32.
Copy-Item (Join-Path $crt.FullName '*.dll') (Join-Path $Destination 'bin') -Force
& (Join-Path $Destination 'bin/nemo-speech.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'NVIDIA CPU runtime does not start' }
