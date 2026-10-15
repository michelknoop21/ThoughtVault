$ErrorActionPreference = 'Stop'
$env:RUNNER_TEMP = Join-Path $env:TEMP 'ThoughtVault-Audit290-build'
New-Item -ItemType Directory -Force $env:RUNNER_TEMP | Out-Null
Set-Location (Join-Path $PSScriptRoot '..')
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
$env:CARGO_BUILD_JOBS = '4'
cargo test --release --manifest-path src-tauri/Cargo.toml --lib
if ($LASTEXITCODE -ne 0) { throw 'Native regression tests failed' }
Set-Location ..
./scripts/verify-parakeet-cpu.ps1
./scripts/verify-faster-whisper.ps1
Write-Output 'QA_LOCAL_CANDIDATE_RUNTIME_AND_TESTS_PASS'
