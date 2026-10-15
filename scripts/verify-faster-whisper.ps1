$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $PSScriptRoot '../windows/src-tauri/resources/faster-whisper-1.2.1/faster-whisper/faster-whisper.exe'
$Work = Join-Path $env:TEMP ('ThoughtVault-Faster-QA-' + [guid]::NewGuid())
$Model = Join-Path $Work 'model'
New-Item -ItemType Directory $Model | Out-Null
$Files = @{
    'config.json' = 'b55496ac7940a7ae47d2c01eab40edfd8701feec1229d9cce3b40014383fb828'
    'model.bin' = '3e305921506d8872816023e4c273e75d2419fb89b24da97b4fe7bce14170d671'
    'tokenizer.json' = 'fb7b63191e9bb045082c79fd742a3106a12c99513ab30df4a0d47fa6cb6fd0ab'
    'vocabulary.txt' = '34ce3fe1c5041027b3f8d42912270993f986dbc4bb34cf27f951e34a1e453913'
}
foreach ($File in $Files.Keys) {
    $Path = Join-Path $Model $File
    Invoke-WebRequest "https://huggingface.co/Systran/faster-whisper-small/resolve/536b0662742c02347bc0e980a01041f333bce120/$File" -OutFile $Path
    if ((Get-FileHash $Path).Hash.ToLower() -ne $Files[$File]) { throw 'Faster Whisper QA model checksum mismatch' }
}
$env:HF_HUB_OFFLINE = '1'
$Probe = (& $Runtime --probe | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $Probe.engine -ne 'faster-whisper' -or $Probe.version -ne '1.2.1' -or $Probe.device -ne 'cpu') { throw 'Faster Whisper runtime identity mismatch' }
$Clock = [Diagnostics.Stopwatch]::StartNew()
& $Runtime --model $Model --audio (Join-Path $PSScriptRoot '../windows/src-tauri/tests/fixtures/dutch-qa.wav') --output "$Work/result.txt" | Out-File "$Work/progress.jsonl"
if ($LASTEXITCODE -ne 0) { throw 'Packaged Faster Whisper inference failed' }
$Clock.Stop()
$Text = (Get-Content -Raw "$Work/result.txt").ToLowerInvariant()
$Alex = [regex]::Matches($Text,'alex').Count
$Monday = [regex]::Matches($Text,'maandag').Count
if ($Alex -ne 1 -or $Monday -ne 1) { throw 'Faster Whisper own Dutch markers failed' }
$Progress = @(Get-Content "$Work/progress.jsonl" | ForEach-Object { $_ | ConvertFrom-Json })
if ($Progress[-1].progress -ne 100) { throw 'Faster Whisper completion progress missing' }
Write-Host "QA_FASTER_WHISPER_CPU_SECONDS=$($Clock.Elapsed.TotalSeconds) ALEX=$Alex MONDAY=$Monday"
