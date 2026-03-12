# Upload build artifact to server and update releases.json manifest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$Version = (Get-Content (Join-Path $RootDir "VERSION") -Raw).Trim()
$BuildDir = Join-Path $RootDir "build"

$Server = "michelk@3.69.205.209"
$RemoteDir = "/home/michelk/tstudio-releases"

$DmgArtifact = "TranscriptStudio-$Version.dmg"
$MsiArtifact = "TranscriptStudio-$Version.msi"
$DmgPath = Join-Path $BuildDir $DmgArtifact
$MsiPath = Join-Path $BuildDir $MsiArtifact

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# Auto-find MSI from Tauri build output if not already in build/
if (-not (Test-Path $MsiPath)) {
    $TauriMsi = Get-ChildItem -Path (Join-Path $RootDir "transcript-studio-windows\src-tauri\target\release\bundle") -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($TauriMsi) {
        Copy-Item $TauriMsi.FullName -Destination $MsiPath -Force
        Write-Host "  Found MSI in Tauri output, copied to build/"
    }
}

$HasDmg = Test-Path $DmgPath
$HasMsi = Test-Path $MsiPath

if (-not $HasDmg -and -not $HasMsi) {
    Write-Error "No artifacts found in $BuildDir. Expected $DmgArtifact and/or $MsiArtifact. Run scripts\build.ps1 first."
    exit 1
}

$DownloadPage = Join-Path $ScriptDir "download-page.html"
$FeaturesPage = Join-Path $ScriptDir "features-page.html"

Write-Host "Uploading artifacts to server..."

# Ensure remote directory exists
ssh $Server "mkdir -p $RemoteDir"

# Upload artifacts
$ManifestUpdates = @()
if ($HasDmg) {
    scp $DmgPath "${Server}:${RemoteDir}/${DmgArtifact}"
    Write-Host "  Uploaded: $DmgArtifact"
    $ManifestUpdates += "macos"
}
if ($HasMsi) {
    scp $MsiPath "${Server}:${RemoteDir}/${MsiArtifact}"
    Write-Host "  Uploaded: $MsiArtifact"
    $ManifestUpdates += "windows"
}

# Upload website pages
if (Test-Path $DownloadPage) {
    scp $DownloadPage "${Server}:${RemoteDir}/index.html"
    Write-Host "  Updated: download page"
}
if (Test-Path $FeaturesPage) {
    scp $FeaturesPage "${Server}:${RemoteDir}/features.html"
    Write-Host "  Updated: features page"
}

# Upload screenshots
$ScreenshotsDir = Join-Path $ScriptDir "screenshots"
if (Test-Path $ScreenshotsDir) {
    ssh $Server "mkdir -p $RemoteDir/screenshots"
    scp (Join-Path $ScreenshotsDir "*.png") "${Server}:${RemoteDir}/screenshots/"
    Write-Host "  Updated: screenshots"
}

# Update releases.json manifest on server
Write-Host "Updating releases.json..."
$PlatformsStr = $ManifestUpdates -join ","
$PythonScript = @"
import json

manifest_path = '$RemoteDir/releases.json'
try:
    with open(manifest_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data['latest_version'] = '$Version'

platforms = '$PlatformsStr'.split(',')
if 'macos' in platforms:
    data['macos'] = {
        'url': '/tstudio/download/$DmgArtifact',
        'version': '$Version',
        'filename': '$DmgArtifact'
    }
if 'windows' in platforms:
    data['windows'] = {
        'url': '/tstudio/download/$MsiArtifact',
        'version': '$Version',
        'filename': '$MsiArtifact'
    }

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)

print('  Updated releases.json')
"@

ssh $Server "python3 -c `"$($PythonScript -replace '"', '\"')`""

Write-Host ""
Write-Host "Upload complete."
if ($HasDmg) {
    Write-Host "  macOS:     https://n8n.prezent.nl/tstudio/download/$DmgArtifact"
}
if ($HasMsi) {
    Write-Host "  Windows:   https://n8n.prezent.nl/tstudio/download/$MsiArtifact"
}
Write-Host "  Manifest:  https://n8n.prezent.nl/tstudio/download/releases.json"
Write-Host "  Downloads: https://n8n.prezent.nl/tstudio/download/"
