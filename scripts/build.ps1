# Build release artifacts for Windows (Tauri MSI)
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$Version = (Get-Content (Join-Path $RootDir "VERSION") -Raw).Trim()
$BuildDir = Join-Path $RootDir "build"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Write-Host "Building ThoughtVault $Version for Windows..."

$WindowsDir = Join-Path $RootDir "windows"
if (-not (Test-Path $WindowsDir)) {
    Write-Error "windows directory not found"
    exit 1
}

Push-Location $WindowsDir
try {
    Write-Host "Running Tauri build..."
    npm run tauri build

    # Find the MSI in the Tauri output
    $MsiSource = Get-ChildItem -Path "src-tauri\target\release\bundle" -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $MsiSource) {
        Write-Error "MSI not found in Tauri build output"
        exit 1
    }

    $MsiName = "ThoughtVault_$Version.msi"
    $MsiDest = Join-Path $BuildDir $MsiName
    Copy-Item $MsiSource.FullName -Destination $MsiDest -Force

    $Size = [math]::Round((Get-Item $MsiDest).Length / 1MB, 1)
    Write-Host ""
    Write-Host "Build complete: $MsiDest"
    Write-Host "Size: ${Size} MB"
} finally {
    Pop-Location
}
