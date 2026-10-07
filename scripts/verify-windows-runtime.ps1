param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$dumpbin = Get-ChildItem "$installation/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $dumpbin) { throw 'dumpbin niet gevonden; runtime-afhankelijkheden niet gecontroleerd.' }
$dependencies = & $dumpbin.FullName /dependents $Executable
if ($LASTEXITCODE -ne 0) { throw 'Runtime-controle mislukt.' }
$dependencies
if ($dependencies -match '(?i)(MSVCP\d+|VCRUNTIME\d+|CONCRT\d+)\.dll') { throw 'De executable vereist nog een afzonderlijke Visual C++ runtime.' }
Write-Host 'Geen afzonderlijke Visual C++ runtime vereist.'
