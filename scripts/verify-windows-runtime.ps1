param([Parameter(Mandatory=$true)][string]$Executable, [switch]$AppLocalRuntime)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$dumpbin = Get-ChildItem "$installation/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $dumpbin) { throw 'dumpbin niet gevonden; runtime-afhankelijkheden niet gecontroleerd.' }
$directory = Split-Path (Resolve-Path $Executable)
$binaries = @($Executable)
if ($AppLocalRuntime) { $binaries = @(Get-ChildItem $directory -File -Recurse | Where-Object { $_.Extension -in '.exe','.dll','.pyd' } | ForEach-Object FullName) }
foreach ($binary in $binaries) {
    $dependencies = & $dumpbin.FullName /dependents $binary
    if ($LASTEXITCODE -ne 0) { throw 'Runtime-controle mislukt.' }
    $dependencies
    foreach ($line in $dependencies) {
        if ($line -match '(?i)^\s*((?:MSVCP|VCRUNTIME|CONCRT|VCOMP)[\w]+\.dll)\s*$') {
            if (!$AppLocalRuntime) { throw 'De executable vereist nog een afzonderlijke Visual C++ runtime.' }
            $name = $Matches[1]
            $dependency = @((Join-Path (Split-Path $binary) $name), (Join-Path $directory $name), (Join-Path "$directory/_internal" $name)) | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
            if (!$dependency) { throw "App-local runtime ontbreekt: $dependency" }
            $signature = Get-AuthenticodeSignature $dependency
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "Ongeldige Microsoft runtime: $dependency" }
        }
    }
}
Write-Host 'Geen afzonderlijke Visual C++ runtime-installatie vereist.'
