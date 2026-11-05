$ErrorActionPreference='Stop'
$report='C:\Dalf38\incoming\acceptance297'
try {
 if($env:USERNAME -ne 'michel'){throw 'Expected existing michel desktop session'}
 $root='C:\Dalf38\temp\thoughtvault-cargo-target'
 $wix="$root\.tauri\WixTools314"
 $work="$root\release\wix\x64"
 $inputs=@("$work\main.wxs","$work\main.wixobj","$work\locale.wxl","$root\release\ThoughtVault.exe")
 $hashes=@($inputs | ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})
 $resources=Get-Content C:/Dalf38/workspaces/thoughtvault-msi1105/resource-provenance.json -Raw | ConvertFrom-Json
 foreach($entry in $resources){
  $file=Join-Path 'C:\Dalf38\workspaces\thoughtvault-msi1105\windows\src-tauri\resources' (Join-Path $entry.resource $entry.path)
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256){throw 'Runtime resource changed since native build'}
 }
 Set-Location $work
 & "$wix\light.exe" -ext "$wix\WixUIExtension.dll" -ext "$wix\WixUtilExtension.dll" -o "$work\output.msi" -cultures:en-us -loc "$work\locale.wxl" '*.wixobj' 1> "$report\light-stdout.log" 2> "$report\light-stderr.log"
 $code=$LASTEXITCODE
 if($code -ne 0){throw "WiX light failed: $code"}
 foreach($input in $hashes){if((Get-FileHash -LiteralPath $input.path -Algorithm SHA256).Hash -ne $input.sha256){throw 'Package input changed during light'}}
 $destination="$report\ThoughtVault_1.0.297_x64.msi"
 Copy-Item -LiteralPath "$work\output.msi" -Destination $destination
 $msi=Get-Item $destination
 @{status='built-validation-enabled';lightExitCode=$code;identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;sourceCommit='6ff05811314086abff94f1398dab973545725866';inputs=$hashes;verifiedResources=$resources.Count;path=$destination;length=$msi.Length;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash;updaterVerified=$false} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 "$report\package-result.json"
 Write-Host 'MSI BUILT WITH VALIDATION; updater signing still required' -ForegroundColor Green
}catch{@{status='failed';error=$_.Exception.Message} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\package-result.json";Write-Host $_ -ForegroundColor Red}
Read-Host 'Press Enter to close'
