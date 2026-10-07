# Publish signed Windows artifacts through the same locked server publisher.
param([string]$Channel = "production", [string]$KeyPath = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
python (Join-Path $Root "scripts/check-windows-design.py")
if ($LASTEXITCODE -ne 0) { throw "Windows visual release review failed" }
$Version = (Get-Content (Join-Path $Root VERSION) -Raw).Trim()
$Prefix = if ($Channel -eq "production") { "ThoughtVault" } else { "ThoughtVault-Dev" }
$Server = "michelk@3.69.205.209"
$Remote = "/home/michelk/tstudio-releases"
$Options = @()
if ($KeyPath) { $Options += @("-i", $KeyPath) }
$Stage = & ssh @Options $Server "mktemp -d $Remote/.upload.XXXXXXXX"
if ($LASTEXITCODE -ne 0) { throw "Cannot create release staging directory" }
try {
    $Found = $false
    foreach ($Arch in @("x64", "arm64")) {
        $Name = "${Prefix}_${Version}_${Arch}.msi"
        $File = Join-Path $Root "build/$Name"
        if (-not (Test-Path $File)) { continue }
        if (-not (Test-Path "$File.sig")) { throw "Missing updater signature: $File.sig" }
        & scp @Options $File "$File.sig" "${Server}:${Stage}/"
        if ($LASTEXITCODE -ne 0) { throw "Artifact upload failed" }
        $Found = $true
    }
    if (-not $Found) { throw "No current-version MSI found" }
    & scp @Options (Join-Path $PSScriptRoot "publish-release.py") "${Server}:${Stage}/publish-release.py"
    if ($LASTEXITCODE -ne 0) { throw "Publisher upload failed" }
    & ssh @Options $Server "python3 $Stage/publish-release.py --directory $Remote --staging $Stage --version $Version --channel $Channel"
    if ($LASTEXITCODE -ne 0) { throw "Release publication failed" }
} finally {
    & ssh @Options $Server "rm -rf $Stage"
}
