# CI smoke check: upgrade the existing MSI, preserve saved notes, and launch the renamed executable twice.
param([Parameter(Mandatory=$true)][string]$Installer, [string]$PreviousInstaller = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
function Install-Msi([string]$Path, [string]$Log) {
    $Process = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + (Resolve-Path $Path).Path + '"'), '/qn', '/norestart', '/l*v', ('"' + $Log + '"')) -Wait -PassThru
    if ($Process.ExitCode -notin @(0,3010)) { throw "MSI installation failed: $($Process.ExitCode). See $Log" }
}
if ($PreviousInstaller) { Install-Msi $PreviousInstaller "$Root/build/previous-install.log" }
$NotesDir = Join-Path $env:APPDATA 'nl.prezent.transcript-studio'
New-Item -ItemType Directory -Force $NotesDir | Out-Null
$NotesFile = Join-Path $NotesDir 'local-transcripts.json'
# The CI account is disposable. Never overwrite notes on a user's Windows installation.
if (Test-Path $NotesFile) { throw "Smoke check requires an empty CI account; existing notes found" }
$Notes = @{items=@(@{id='local-upgrade-check';title='Upgrade check';raw_transcription='Saved transcript';notule_html='<p>Saved minutes</p>';has_notes=$true;date='2026-10-07T10:00:00Z';created_at='2026-10-07T10:00:00Z'})} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($NotesFile,$Notes,(New-Object Text.UTF8Encoding $false))
$Before = (Get-FileHash $NotesFile).Hash
Install-Msi $Installer "$Root/build/install.log"
$Exe = Join-Path $env:ProgramFiles 'ThoughtVault/ThoughtVault.exe'
if (-not (Test-Path $Exe)) { throw "ThoughtVault.exe missing" }
if (Test-Path (Join-Path $env:ProgramFiles 'ThoughtVault/transcript-studio.exe')) { throw "Old executable was not removed by the upgrade" }
foreach ($Attempt in @(1,2)) {
    $App = Start-Process $Exe -PassThru
    Start-Sleep -Seconds 10
    if ($App.HasExited) { throw "ThoughtVault exited during startup: $($App.ExitCode)" }
    if ((Get-FileHash $NotesFile).Hash -ne $Before) { throw "Saved notes changed during upgrade/startup" }
    Stop-Process -Id $App.Id
}
(Get-Item $Exe).VersionInfo | Select-Object ProductName,FileDescription,ProductVersion | Format-List | Out-File "$Root/build/INSTALL-VERIFICATION.txt"
"MSI upgrade, renamed executable, two starts and saved-notes preservation passed" | Tee-Object -FilePath "$Root/build/INSTALL-VERIFICATION.txt" -Append
