$ErrorActionPreference = 'Stop'
$Destination = Join-Path $PSScriptRoot '../windows/src-tauri/resources/faster-whisper-1.2.1'
$Stage = Join-Path $env:RUNNER_TEMP 'ThoughtVault-FasterWhisper'
python -m venv "$Stage/venv"
if ($LASTEXITCODE -ne 0) { throw 'Faster Whisper environment creation failed' }
$Python = Join-Path $Stage 'venv/Scripts/python.exe'
& $Python -m pip install 'faster-whisper==1.2.1' 'ctranslate2==4.6.0' 'pyinstaller==6.17.0'
if ($LASTEXITCODE -ne 0) { throw 'Faster Whisper dependencies failed' }
& $Python -m PyInstaller --noconfirm --clean --onedir --name faster-whisper --distpath $Destination --workpath "$Stage/build" --specpath $Stage --collect-all faster_whisper --collect-all ctranslate2 --collect-all av --collect-all tokenizers --collect-all onnxruntime "$PSScriptRoot/faster-whisper-worker.py"
if ($LASTEXITCODE -ne 0) { throw 'Faster Whisper packaging failed' }
& $Python -m pip freeze | Out-File "$Destination/dependencies.txt" -Encoding utf8
& "$Destination/faster-whisper/faster-whisper.exe" --probe
if ($LASTEXITCODE -ne 0) { throw 'Bundled Faster Whisper CPU runtime does not start' }
