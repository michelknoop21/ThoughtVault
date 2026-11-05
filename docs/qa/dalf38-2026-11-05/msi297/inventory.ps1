$ErrorActionPreference='Stop'
$report='C:\Dalf38\incoming\acceptance297'
try {
 $backup=Get-Content "$report\pre-upgrade.json" -Raw | ConvertFrom-Json
 if($backup.status -ne 'verified'){throw 'Backup is not verified'}
 $rollback=Join-Path $env:TEMP 'ThoughtVault-Pilot295\ThoughtVault_1.0.295_x64.msi'
 if(!(Test-Path $rollback)){throw 'Rollback installer unavailable'}
 $hash=(Get-FileHash -LiteralPath $rollback -Algorithm SHA256).Hash
 Copy-Item -LiteralPath $rollback -Destination (Join-Path $backup.backup 'ThoughtVault_1.0.295_x64.msi')
 if((Get-FileHash (Join-Path $backup.backup 'ThoughtVault_1.0.295_x64.msi') -Algorithm SHA256).Hash -ne $hash){throw 'Rollback copy mismatch'}
 $models=Join-Path $env:APPDATA 'nl.prezent.transcript-studio\whisper-models'
 $modelManifest=@(Get-ChildItem $models -Recurse -File | ForEach-Object {@{path=$_.FullName.Substring($models.Length).TrimStart('\');length=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
 $largeProcess=$null
 try{
  $p=Get-CimInstance Win32_Process -Filter 'ProcessId=31896'
  $scriptPath=if($p.CommandLine -match '(?i)-File\s+"?([^"\r\n]+?\.ps1)'){ $Matches[1] }else{'No -File path found'}
  $largeProcess=@{pid=$p.ProcessId;parentPid=$p.ParentProcessId;executable=$p.ExecutablePath;script=$scriptPath}
 }catch{$largeProcess=@{error='Process identity lookup denied'}}
 $result=@{rollback=@{path=$rollback;sha256=$hash;backupVerified=$true};models=$modelManifest;largeProcess=$largeProcess}
 $result | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 "$report\inventory.json"
 Write-Host 'INVENTORY COMPLETE' -ForegroundColor Green
}catch{ @{error=$_.Exception.Message} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\inventory.json"; Write-Host $_ -ForegroundColor Red }
Read-Host 'Press Enter to close'
