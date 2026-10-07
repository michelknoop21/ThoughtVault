# Sync VERSION file to all platform build configs
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$VersionFile = Join-Path $RootDir "VERSION"

if (-not (Test-Path $VersionFile)) {
    Write-Error "VERSION file not found at $VersionFile"
    exit 1
}

$Version = (Get-Content $VersionFile -Raw).Trim()
$Patch = $Version.Split('.')[2]

Write-Host "Syncing version $Version to all platform configs..."

# 1. Xcode project.pbxproj
$Pbxproj = Join-Path $RootDir "ThoughtVault.xcodeproj\project.pbxproj"
if (Test-Path $Pbxproj) {
    $content = Get-Content $Pbxproj -Raw
    $content = $content -replace 'MARKETING_VERSION = [^;]*', "MARKETING_VERSION = $Version"
    $content = $content -replace 'CURRENT_PROJECT_VERSION = [^;]*', "CURRENT_PROJECT_VERSION = $Patch"
    Set-Content -Path $Pbxproj -Value $content -NoNewline
    Write-Host "  Updated: project.pbxproj (MARKETING_VERSION=$Version, CURRENT_PROJECT_VERSION=$Patch)"
} else {
    Write-Host "  Skipped: project.pbxproj (not found)"
}

# 2. Tauri tauri.conf.json
$TauriConf = Join-Path $RootDir "windows\src-tauri\tauri.conf.json"
if (Test-Path $TauriConf) {
    $content = Get-Content $TauriConf -Raw
    $content = $content -replace '"version": "[^"]*"', "`"version`": `"$Version`""
    Set-Content -Path $TauriConf -Value $content -NoNewline
    Write-Host "  Updated: tauri.conf.json (version=$Version)"
} else {
    Write-Host "  Skipped: tauri.conf.json (not found)"
}

# 3. Cargo.toml — first version under [package] only
$CargoToml = Join-Path $RootDir "windows\src-tauri\Cargo.toml"
if (Test-Path $CargoToml) {
    $lines = Get-Content $CargoToml
    $done = $false
    $newLines = @()
    foreach ($line in $lines) {
        if (-not $done -and $line -match '^version = "') {
            $newLines += "version = `"$Version`""
            $done = $true
        } else {
            $newLines += $line
        }
    }
    Set-Content -Path $CargoToml -Value ($newLines -join "`n")
    Write-Host "  Updated: Cargo.toml (version=$Version)"
} else {
    Write-Host "  Skipped: Cargo.toml (not found)"
}

Write-Host "Version sync complete: $Version"
