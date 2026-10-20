# Build current source locally. Does not publish or change release metadata.
param(
    [ValidateSet("x86_64-pc-windows-msvc", "aarch64-pc-windows-msvc")]
    [string]$Target = "x86_64-pc-windows-msvc",
    [switch]$Portable
)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content (Join-Path $RootDir "VERSION") -Raw).Trim()
$BuildDir = Join-Path $RootDir "build"
foreach ($tool in @("node", "npm.cmd", "cargo", "rustc", "cmake")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool ontbreekt. Installeer Node, Rust (MSVC) en CMake; Visual Studio C++ Build Tools zijn ook vereist."
    }
}
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
# The C++ toolchain can replace PATH while configuring whisper.cpp.
$env:CMAKE = (Get-Command cmake).Source
Push-Location (Join-Path $RootDir "windows")
try {
    Write-Host "Building ThoughtVault $Version ($Target)..."
    # PowerShell 5 treats native stderr as errors when a caller captures logs.
    # Use the exit code as the build gate; warnings must not abort a valid build.
    $ErrorActionPreference = "Continue"
    & npm.cmd ci
    $ErrorActionPreference = "Stop"
    if ($LASTEXITCODE -ne 0) { throw "npm ci mislukt ($LASTEXITCODE)" }
    $BuildArgs = @("run", "tauri", "--", "build", "--target", $Target)
    if ($Portable) { $BuildArgs += "--no-bundle" } else { $BuildArgs += @("--bundles", "msi") }
    $ErrorActionPreference = "Continue"
    & npm.cmd @BuildArgs
    $ErrorActionPreference = "Stop"
    if ($LASTEXITCODE -ne 0) { throw "Tauri-build mislukt ($LASTEXITCODE)" }
    $TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { "src-tauri\target" }
    $ReleaseDir = Join-Path $TargetDir "$Target\release"
    $Arch = if ($Target.StartsWith("aarch64")) { "arm64" } else { "x64" }
    if ($Portable) {
        $Source = Join-Path $ReleaseDir "transcript-studio.exe"
        $Dest = Join-Path $BuildDir "ThoughtVault_${Version}_${Arch}.exe"
    } else {
        $Msi = Get-ChildItem (Join-Path $ReleaseDir "bundle\msi") -Filter "*.msi" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $Msi) { throw "MSI niet gevonden" }
        $Source = $Msi.FullName
        $Dest = Join-Path $BuildDir "ThoughtVault_${Version}_${Arch}.msi"
    }
    Copy-Item $Source $Dest -Force
    Get-FileHash $Dest -Algorithm SHA256 | Format-List
    Write-Host "Build complete: $Dest"
} finally { Pop-Location }
