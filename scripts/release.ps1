# Full release pipeline: sync version -> build -> upload
param(
    [switch]$NoUpload
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$Version = (Get-Content (Join-Path $RootDir "VERSION") -Raw).Trim()

Write-Host "=== TranscriptStudio Release Pipeline v$Version ==="
Write-Host ""

# Step 1: Sync version
Write-Host "--- Step 1: Sync version ---"
& "$ScriptDir\sync-version.ps1"
Write-Host ""

# Step 2: Build
Write-Host "--- Step 2: Build ---"
& "$ScriptDir\build.ps1"
Write-Host ""

# Step 3: Upload (optional)
if (-not $NoUpload) {
    Write-Host "--- Step 3: Upload ---"
    & "$ScriptDir\upload.ps1"
} else {
    Write-Host "--- Step 3: Upload (skipped with -NoUpload) ---"
}

Write-Host ""
Write-Host "=== Release $Version complete ==="
