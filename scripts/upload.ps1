# Upload build artifact to server and update releases.json manifest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$Version = (Get-Content (Join-Path $RootDir "VERSION") -Raw).Trim()
$BuildDir = Join-Path $RootDir "build"

$Server = "michelk@3.69.205.209"
$RemoteDir = "/home/michelk/tstudio-releases"

$Artifact = "TranscriptStudio-$Version.msi"
$Platform = "windows"
$ArtifactPath = Join-Path $BuildDir $Artifact

if (-not (Test-Path $ArtifactPath)) {
    Write-Error "Artifact not found at $ArtifactPath. Run scripts\build.ps1 first."
    exit 1
}

$DownloadPage = Join-Path $ScriptDir "download-page.html"

Write-Host "Uploading $Artifact to server..."

# Ensure remote directory exists
ssh $Server "mkdir -p $RemoteDir"

# Upload artifact
scp $ArtifactPath "${Server}:${RemoteDir}/${Artifact}"
Write-Host "  Uploaded: $Artifact"

# Upload download page
if (Test-Path $DownloadPage) {
    scp $DownloadPage "${Server}:${RemoteDir}/index.html"
    Write-Host "  Updated: download page"
}

# Update releases.json manifest on server
Write-Host "Updating releases.json..."
$PythonScript = @"
import json, os

manifest_path = '$RemoteDir/releases.json'
try:
    with open(manifest_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data['latest_version'] = '$Version'
data['$Platform'] = {
    'url': '/tstudio/download/$Artifact',
    'version': '$Version',
    'filename': '$Artifact'
}

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)

print('  Updated releases.json')
"@

ssh $Server "python3 -c `"$($PythonScript -replace '"', '\"')`""

Write-Host ""
Write-Host "Upload complete."
Write-Host "  Artifact:  https://n8n.prezent.nl/tstudio/download/$Artifact"
Write-Host "  Manifest:  https://n8n.prezent.nl/tstudio/download/releases.json"
Write-Host "  Downloads: https://n8n.prezent.nl/tstudio/download/"
