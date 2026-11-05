$ErrorActionPreference='Stop'
$report='C:\Dalf38\incoming\acceptance299'
try {
 if($env:USERNAME -ne 'michel'){throw 'Expected existing michel desktop session'}
 $source='C:\Dalf38\workspaces\thoughtvault-msi299'
 $job='18916d4c4d5b4251bfeb9a9f7f8074ee'
 $result=Get-Content "C:\Dalf38\jobs\$job\job.json" -Raw | ConvertFrom-Json
 if($result.status -ne 'succeeded'){throw 'Successful central native build required'}
 $expected=Get-Content "C:\Dalf38\jobs\$job\source-manifest.json" -Raw | ConvertFrom-Json
 foreach($entry in $expected){
  if($entry.path -eq 'windows/src-tauri/gen/schemas/windows-schema.json'){continue}
  if((Get-FileHash -LiteralPath (Join-Path $source $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256){throw "Source changed: $($entry.path)"}
 }
 $bins=Get-Content "$source\package\binary-targets.json" -Raw | ConvertFrom-Json
 if(@($bins).Count -ne 1 -or $bins.name -ne 'thoughtvault'){throw 'Unexpected binary targets'}
 if(Test-Path "$source\windows\src-tauri\src\bin\read_token.rs"){throw 'Development helper source remains'}
 $env:CARGO_HOME='C:\Dalf38\tools\cargo'
 $env:RUSTUP_HOME='C:\Dalf38\tools\rustup'
 $env:CARGO_TARGET_DIR='C:\Dalf38\temp\thoughtvault-cargo-target'
 $env:PATH="$env:CARGO_HOME\bin;C:\Windows\System32;C:\Windows;C:\Program Files\nodejs;C:\Program Files\Git\cmd"
 $native="$env:CARGO_TARGET_DIR\release\ThoughtVault.exe"
 if((Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash -ne (Get-FileHash "$source\package\ThoughtVault.exe" -Algorithm SHA256).Hash){throw 'Native output differs from verified central artifact'}
 $resources=Get-Content "$source\resource-provenance.json" -Raw | ConvertFrom-Json
 foreach($entry in $resources){
  $file=Join-Path "$source\windows\src-tauri\resources" (Join-Path $entry.resource $entry.path)
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256){throw 'Runtime resource changed'}
 }
 $process=Start-Process 'C:\Program Files\nodejs\node.exe' -WorkingDirectory "$source\windows" -ArgumentList @('node_modules/@tauri-apps/cli/tauri.js','bundle','--bundles','msi','--ci','--verbose') -RedirectStandardOutput "$report\bundle-stdout.log" -RedirectStandardError "$report\bundle-stderr.log" -Wait -PassThru
 $code=$process.ExitCode
 $msis=@(Get-ChildItem "$env:CARGO_TARGET_DIR\release\bundle\msi\ThoughtVault_1.0.299_x64*.msi" -File -ErrorAction SilentlyContinue)
 if($msis.Count -ne 1){throw "No unique MSI; Tauri bundle exit $code"}
 $destination="$report\ThoughtVault_1.0.299_x64.msi"
 Copy-Item -LiteralPath $msis[0].FullName -Destination $destination
 @{status='built-updater-signing-pending';tauriBundleExitCode=$code;identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;sourceCommit='870c3f93f75620f4a932f6cacf595f7ce2850aea';nativeBuildJob=$job;path=$destination;length=(Get-Item $destination).Length;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash;bundledExecutableHash=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash;verifiedResources=$resources.Count;updaterVerified=$false} | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 "$report\package-result.json"
 Write-Host 'MSI CREATED; Mac updater signing and payload inspection still required' -ForegroundColor Green
}catch{@{status='failed';error=$_.Exception.Message} | ConvertTo-Json | Set-Content -Encoding UTF8 "$report\package-result.json";Write-Host $_ -ForegroundColor Red}
Read-Host 'Press Enter to close'
