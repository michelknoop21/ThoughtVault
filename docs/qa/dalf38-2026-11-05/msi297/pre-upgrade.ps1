$ErrorActionPreference='Stop'
$report='C:\Dalf38\incoming\acceptance297'
try {
 if($env:USERNAME -ne 'michel'){throw "Expected interactive michel, got $env:USERNAME"}
 if(Get-Process ThoughtVault -ErrorAction SilentlyContinue){throw 'ThoughtVault is running; close normally before backup'}
 $backup=Join-Path $env:TEMP ('ThoughtVault297-backup-'+(Get-Date -Format yyyyMMdd-HHmmss))
 New-Item -ItemType Directory $backup | Out-Null
 function Manifest([string]$root){
  @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
   [pscustomobject]@{path=$_.FullName.Substring($root.Length).TrimStart('\');length=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;created=$_.CreationTimeUtc.Ticks;modified=$_.LastWriteTimeUtc.Ticks}
  } | Sort-Object path)
 }
 $counts=@{}
 foreach($kind in @('Local','Roaming')){
  $base=if($kind -eq 'Local'){$env:LOCALAPPDATA}else{$env:APPDATA}
  $source=Join-Path $base 'nl.prezent.transcript-studio'
  if(!(Test-Path $source)){throw "Missing expected appdata $kind"}
  if(Get-ChildItem -LiteralPath $source -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }){throw "Reparse point in $kind; review before backup"}
  $before=Manifest $source
  $destination=Join-Path $backup $kind
  & robocopy.exe $source $destination /E /COPY:DAT /DCOPY:DAT /R:0 /W:0 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
  if($LASTEXITCODE -ge 8){throw "Backup copy failed: $LASTEXITCODE"}
  $after=Manifest $source; $copied=Manifest $destination
  $b=$before | ConvertTo-Json -Depth 4 -Compress
  if($b -cne ($after | ConvertTo-Json -Depth 4 -Compress)){throw "Source changed during backup: $kind"}
  if($b -cne ($copied | ConvertTo-Json -Depth 4 -Compress)){throw "Backup mismatch: $kind"}
  $before | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $backup "$kind-manifest.json")
  $counts[$kind]=@{files=$before.Count;bytes=($before|Measure-Object length -Sum).Sum;hashesAndTimestampsVerified=$true}
 }
 $installer=New-Object -ComObject WindowsInstaller.Installer
 $products=@($installer.Products)
 $rollback=@()
 foreach($product in $products){
  try {
   if($installer.ProductInfo($product,'ProductName') -eq 'ThoughtVault'){
    $version=$installer.ProductInfo($product,'VersionString');$cached=$installer.ProductInfo($product,'LocalPackage')
    if(Test-Path $cached){Copy-Item -LiteralPath $cached -Destination (Join-Path $backup 'rollback-cached.msi')}
    $rollback+=@{productCode=$product;version=$version;cachedMsiExists=(Test-Path $cached);cachedMsiIsNotFullPayload=$true}
   }
  } catch {Write-Output 'Could not inspect one product'}
 }
 $oldMsis=@(Get-ChildItem (Join-Path $env:TEMP 'ThoughtVault-Pilot295') -Recurse -Filter '*.msi' -File -ErrorAction SilentlyContinue | Select-Object FullName,Length)
 $result=@{status='verified';identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;backup=$backup;counts=$counts;installed=$rollback;oldMsis=$oldMsis;timestamp=(Get-Date).ToUniversalTime().ToString('o')}
 $result | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 "$report\pre-upgrade.json"
 Write-Host 'BACKUP VERIFIED' -ForegroundColor Green
} catch {
 @{status='failed';error=$_.Exception.Message} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\pre-upgrade.json"
 Write-Host $_ -ForegroundColor Red
}
Read-Host 'Press Enter to close'
