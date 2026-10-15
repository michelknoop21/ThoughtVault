param([switch]$ResumeNative)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$cmakeDirectories = @("$env:ProgramFiles/CMake/bin", "$installation/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin")
foreach ($directory in $cmakeDirectories) { if (Test-Path "$directory/cmake.exe") { $env:PATH = "$directory;$env:PATH" } }
if (!(Get-Command cmake -ErrorAction SilentlyContinue)) { throw 'CMake is required for native regression tests' }

$env:RUNNER_TEMP = Join-Path $env:TEMP 'ThoughtVault-Audit290-build'
New-Item -ItemType Directory -Force $env:RUNNER_TEMP | Out-Null
Set-Location (Join-Path $PSScriptRoot '..')
if (!$ResumeNative) {
python -m unittest discover -s scripts/tests -p test_faster_whisper_worker.py
if ($LASTEXITCODE -ne 0) { throw 'Worker regression tests failed' }
./scripts/prepare-nvidia-runtime.ps1
./scripts/prepare-faster-whisper-runtime.ps1
Set-Location windows
npm ci
if ($LASTEXITCODE -ne 0) { throw 'Frontend dependencies failed' }
npx vitest run
if ($LASTEXITCODE -ne 0) { throw 'Frontend tests failed' }
npm run build
if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed' }
}
Set-Location (Join-Path $PSScriptRoot '../windows')
$env:CARGO_BUILD_JOBS = '4'
cargo test --release --manifest-path src-tauri/Cargo.toml --lib
if ($LASTEXITCODE -ne 0) { throw 'Native regression tests failed' }
Set-Location ..
./scripts/verify-parakeet-cpu.ps1
./scripts/verify-faster-whisper.ps1
Write-Output 'QA_LOCAL_CANDIDATE_RUNTIME_AND_TESTS_PASS'
