# Build the local/cloud AI installer. No upload, release tag or deployment.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$version = (Get-Content "$root/VERSION" -Raw).Trim()
foreach ($tool in @("node", "npm", "cargo", "cmake")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Ontbrekend bouwgereedschap: $tool" }
}
# whisper-rs bindgen requires LLVM libclang in addition to Visual Studio's C++ tools.
if (-not $env:LIBCLANG_PATH -and (Test-Path "C:/Program Files/LLVM/bin/libclang.dll")) {
    $env:LIBCLANG_PATH = "C:/Program Files/LLVM/bin"
}
Push-Location "$root/windows"
try {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm ci mislukt" }
    npx vitest run
    if ($LASTEXITCODE -ne 0) { throw "Frontendtests mislukt" }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "Frontendbuild mislukt" }
    cargo test --release --manifest-path src-tauri/Cargo.toml --lib
    if ($LASTEXITCODE -ne 0) { throw "Native tests mislukt" }
    $env:TAURI_CONFIG = '{"identifier":"nl.prezent.transcript-studio","productName":"ThoughtVault","bundle":{"targets":["msi"]}}'
    npm run tauri build
    if ($LASTEXITCODE -ne 0) { throw "Windows-build mislukt" }
    $msi = Get-ChildItem "src-tauri/target/release/bundle/msi" -Filter "ThoughtVault_${version}_*.msi" | Select-Object -First 1
    if (-not $msi) { throw "MSI niet gevonden" }
    New-Item -ItemType Directory -Force "$root/build/windows-local" | Out-Null
    Copy-Item $msi.FullName "$root/build/windows-local/ThoughtVault_${version}_x64.msi"
    Copy-Item "$($msi.FullName).sig" "$root/build/windows-local/ThoughtVault_${version}_x64.msi.sig"
    Copy-Item "$root/docs/WINDOWS-LOKAAL.md" "$root/build/windows-local/LEESMIJ.md"
    Get-FileHash "$root/build/windows-local/ThoughtVault_${version}_x64.msi" -Algorithm SHA256 |
        Format-List | Out-File "$root/build/windows-local/SHA256.txt"
    Write-Host "Installer en handleiding: $root/build/windows-local"
} finally {
    Remove-Item Env:TAURI_CONFIG -ErrorAction SilentlyContinue
    Pop-Location
}
