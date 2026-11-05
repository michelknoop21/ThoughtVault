$ErrorActionPreference='Stop'
$env:CARGO_HOME='C:\Dalf38\tools\cargo'
$env:RUSTUP_HOME='C:\Dalf38\tools\rustup'
New-Item -ItemType Directory -Force C:\Dalf38\tools | Out-Null
if ((Get-FileHash "$PSScriptRoot\rustup-init.exe" -Algorithm SHA256).Hash -ne '38027d51d69a5d05493627a0634dbea52d6cd793c8f072d2373d3f4163eec7db') { throw 'Installer hash mismatch' }
& "$PSScriptRoot\rustup-init.exe" -y --no-modify-path --profile minimal --default-host x86_64-pc-windows-msvc --default-toolchain stable
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$env:CARGO_HOME\bin\rustc.exe" --version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$env:CARGO_HOME\bin\cargo.exe" --version
exit $LASTEXITCODE
