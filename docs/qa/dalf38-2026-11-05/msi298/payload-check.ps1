$ErrorActionPreference='Stop'
$report='C:\Dalf38\incoming\acceptance298'
try {
 $package=Get-Content "$report\package-result.json" -Raw | ConvertFrom-Json
 if((Get-FileHash -LiteralPath $package.path -Algorithm SHA256).Hash -ne $package.sha256){throw 'MSI hash changed'}
 $dark='C:\Dalf38\temp\thoughtvault-cargo-target\.tauri\WixTools314\dark.exe'
 $p=Start-Process $dark -ArgumentList @('-x',"$report\unpacked",'-o',"$report\package.wxs",$package.path) -RedirectStandardOutput "$report\dark-stdout.log" -RedirectStandardError "$report\dark-stderr.log" -Wait -PassThru -NoNewWindow
 if($p.ExitCode -ne 0){throw "MSI extraction failed: $($p.ExitCode)"}
 [xml]$xml=Get-Content "$report\package.wxs" -Raw
 $product=$xml.SelectSingleNode("/*[local-name()='Wix']/*[local-name()='Product']")
 if($product.GetAttribute('Version') -ne '1.0.298'){throw 'Wrong MSI version'}
 if($product.SelectSingleNode("*[local-name()='Package']").GetAttribute('Platform') -ne 'x64'){throw 'Wrong MSI architecture'}
 $resourceRoot='C:\Dalf38\workspaces\thoughtvault-msi298\windows\src-tauri\resources'
 $entries=Get-Content C:/Dalf38/workspaces/thoughtvault-msi298/resource-provenance.json -Raw | ConvertFrom-Json
 $expected=@{}
 foreach($e in $entries){$expected[('resources\'+$e.resource+'\'+$e.path)]=$e.sha256}
 $expected['resources\vad\LICENSE']=(Get-FileHash "$resourceRoot\vad\LICENSE" -Algorithm SHA256).Hash
 $native='C:\Dalf38\artifacts\2c17e207d4784332860a2c58362efd40\package\ThoughtVault.exe'
 if((Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash -ne 'CA08BB0E2D32E24C93E7C832F95AD74591303389D720E724F107A24C2F22813B'){throw 'Pinned native artifact changed'}
 $bytes=[IO.File]::ReadAllBytes($native)
 # shortcut: offset is pinned to the reviewed 1.0.298 binary; recheck Tauri marker on a new build.
 if([Text.Encoding]::ASCII.GetString($bytes,20995234,3) -ne 'UNK'){throw 'Unexpected native bundle marker'}
 [Array]::Copy([Text.Encoding]::ASCII.GetBytes('MSI'),0,$bytes,20995234,3)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$expected['ThoughtVault.exe']=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
 $payload="$report\payload"
 $verified=@()
 foreach($file in $xml.GetElementsByTagName('File')){
  $parts=@($file.GetAttribute('Name'))
  if($parts[0] -ieq 'read_token.exe'){throw 'Development credential helper is still bundled'}
  $parent=$file.ParentNode
  while($parent -and $parent.LocalName -ne 'Product'){
   if($parent.LocalName -eq 'Directory'){
    if($parent.GetAttribute('Id') -eq 'INSTALLDIR'){break}
    $parts=@($parent.GetAttribute('Name'))+$parts
   }
   $parent=$parent.ParentNode
  }
  $relative=$parts -join '\'
  if(!$expected.ContainsKey($relative)){throw "Unexpected MSI payload: $relative"}
  $source=[IO.Path]::GetFullPath($file.GetAttribute('Source'))
  if(!$source.StartsWith("$report\unpacked\",[StringComparison]::OrdinalIgnoreCase)){throw 'Extracted source outside expected directory'}
  $destination=[IO.Path]::GetFullPath((Join-Path $payload $relative))
  if(!$destination.StartsWith("$payload\",[StringComparison]::OrdinalIgnoreCase)){throw 'Payload path outside expected directory'}
  $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  if($hash -ne $expected[$relative]){throw "MSI payload differs: $relative"}
  New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination
  if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash){throw 'Reconstructed payload differs'}
  $verified+=@{path=$relative;sha256=$hash;length=(Get-Item $destination).Length}
 }
 if($verified.Count -ne $expected.Count){throw 'Missing or duplicate MSI payload files'}
 $verified | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 "$report\payload-manifest.json"
 @{status='verified';files=$verified.Count;resources=$entries.Count;version='1.0.298';architecture='x64';readTokenAbsent=$true;sha256=$package.sha256} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\payload-result.json"
 Write-Output 'PAYLOAD VERIFICATION PASS'
}catch{@{status='failed';error=$_.Exception.Message} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\payload-result.json";throw}
