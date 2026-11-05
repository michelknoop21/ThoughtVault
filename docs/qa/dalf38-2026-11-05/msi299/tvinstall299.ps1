param([ValidateSet('Install','Rollback')][string]$Action='Install')
$ErrorActionPreference='Stop'
$report='C:\Dalf38\incoming\acceptance299'
try {
 if($env:USERNAME -ne 'michel'){throw 'Run in the existing michel session'}
 if(Get-Process ThoughtVault -ErrorAction SilentlyContinue){throw 'Close ThoughtVault normally before installation'}
 $backup=Get-Content "$report\pre-upgrade.json" -Raw | ConvertFrom-Json
 if($backup.status -ne 'verified'){throw 'Verified pre-upgrade backup required'}
 $candidate=Get-Content "$report\candidate.json" -Raw | ConvertFrom-Json
 if($candidate.payloadVerified -ne $true){throw 'Verified payload required'}
 if($candidate.updaterVerified -ne $true){throw 'Updater signature verification required'}
 if((Get-FileHash -LiteralPath $candidate.path -Algorithm SHA256).Hash -ne $candidate.sha256){throw 'Candidate MSI hash mismatch'}
 $rollback=Join-Path $backup.backup 'ThoughtVault_1.0.295_x64.msi'
 if((Get-FileHash -LiteralPath $rollback -Algorithm SHA256).Hash -ne 'c212094768d98ffaa9b76e4fec48bf81e6033f1d2817ca0fe3e57ed4cb95ee8b'){throw 'Rollback MSI hash mismatch'}
 function Manifest([string]$root){
  @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
   [pscustomobject]@{path=$_.FullName.Substring($root.Length).TrimStart('\');length=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;created=$_.CreationTimeUtc.Ticks;modified=$_.LastWriteTimeUtc.Ticks}
  } | Sort-Object path)
 }
 $roots=@{Local=(Join-Path $env:LOCALAPPDATA 'nl.prezent.transcript-studio');Roaming=(Join-Path $env:APPDATA 'nl.prezent.transcript-studio')}
 $before=@{}
 foreach($kind in @('Local','Roaming')){
  $before[$kind]=Manifest $roots[$kind]
  if($Action -eq 'Install'){
   $expected=Get-Content (Join-Path $backup.backup "$kind-manifest.json") -Raw | ConvertFrom-Json
   if(($before[$kind]|ConvertTo-Json -Depth 4 -Compress) -cne ($expected|ConvertTo-Json -Depth 4 -Compress)){throw "Appdata changed since backup: $kind"}
  }
 }
 $codes=@()
 if($Action -eq 'Rollback'){
  $uninstall=Start-Process msiexec.exe -Verb RunAs -ArgumentList @('/x',('"'+$candidate.path+'"'),'/passive','/norestart','/l*v',('"'+$report+'\rollback-uninstall.log"')) -Wait -PassThru
  $codes+=$uninstall.ExitCode
  if($uninstall.ExitCode -notin @(0,3010)){throw "Candidate uninstall failed: $($uninstall.ExitCode)"}
 }
 $msi=if($Action -eq 'Install'){$candidate.path}else{$rollback}
 $process=Start-Process msiexec.exe -Verb RunAs -ArgumentList @('/i',('"'+$msi+'"'),'/passive','/norestart','/l*v',('"'+$report+'\'+$Action+'.log"')) -Wait -PassThru
 $codes+=$process.ExitCode
 if($process.ExitCode -notin @(0,3010)){throw "MSI installation failed: $($process.ExitCode)"}
 $exe='C:\Program Files\ThoughtVault\ThoughtVault.exe'
 $version=(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
 $expectedVersion=if($Action -eq 'Install'){'1.0.299'}else{'1.0.295'}
 if($version -ne $expectedVersion){throw "Installed version mismatch: $version"}
 if($Action -eq 'Install' -and (Test-Path 'C:\Program Files\ThoughtVault\read_token.exe')){throw 'Development token helper remains installed'}
 $counts=@{}
 foreach($kind in @('Local','Roaming')){
  $after=Manifest $roots[$kind]
  if(($before[$kind]|ConvertTo-Json -Depth 4 -Compress) -cne ($after|ConvertTo-Json -Depth 4 -Compress)){throw "Appdata changed during MSI operation: $kind"}
  $counts[$kind]=$after.Count
 }
 @{status='verified';action=$Action;version=$version;msiExitCodes=$codes;appdataHashesAndTimestampsUnchanged=$true;counts=$counts;exeSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;authenticode=(Get-AuthenticodeSignature -FilePath $exe).Status.ToString();timestamp=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 "$report\$Action-result.json"
 Write-Host "$Action VERIFIED" -ForegroundColor Green
}catch{
 @{status='failed';action=$Action;error=$_.Exception.Message} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\$Action-result.json"
 Write-Host $_ -ForegroundColor Red
}
Read-Host 'Press Enter to close'
