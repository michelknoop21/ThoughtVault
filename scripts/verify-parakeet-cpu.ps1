param([string]$ModelPath)
$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $PSScriptRoot '../windows/src-tauri/resources/nemo-speech-0.2.0/bin/nemo-speech.exe'
$ExpectedHash = 'e3880d0aaaaf2c308ea2c35016b2b895c423eb3fda924c1b463d1c19b7f4d32e'
if (!$ModelPath) {
    $ModelPath = Join-Path $env:TEMP 'ThoughtVault-QA-parakeet-v3.q8_0.gguf'
    if (!(Test-Path $ModelPath)) {
        Invoke-WebRequest 'https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/resolve/541d1f99c6b0c3cd0b11a95167540bb8edefd82b/parakeet-tdt-0.6b-v3.q8_0.gguf' -OutFile $ModelPath
    }
}
if ((Get-Item $ModelPath).Length -ne 713975456 -or (Get-FileHash $ModelPath).Hash.ToLower() -ne $ExpectedHash) { throw 'Parakeet QA model checksum mismatch' }
$Work = Join-Path $env:TEMP ('ThoughtVault-Parakeet-QA-' + [guid]::NewGuid())
$InputDir = Join-Path $Work 'audio'
$OutputDir = Join-Path $Work 'text'
New-Item -ItemType Directory $InputDir,$OutputDir | Out-Null
@'
import sys,wave,array,pathlib
with wave.open(sys.argv[1],'rb') as source:
    assert source.getparams()[:3] == (1,2,16000)
    pcm = source.readframes(source.getnframes())
root=pathlib.Path(sys.argv[2])
def write(name,data):
    with wave.open(str(root/name),'wb') as out:
        out.setparams((1,2,16000,0,'NONE','not compressed'))
        out.writeframes(data)
for index in range(10): write(f'part-{index:02d}.wav',pcm*6)
quiet=array.array('h');quiet.frombytes(pcm)
quiet=array.array('h',(int(sample*0.04) for sample in quiet))
write('normal-quiet.wav',bytes(32*32000)+pcm+bytes(45*32000)+quiet.tobytes()+bytes(20*32000))
'@ | python - (Join-Path $PSScriptRoot '../windows/src-tauri/tests/fixtures/dutch-qa.wav') $InputDir
if ($LASTEXITCODE -ne 0) { throw 'Own Dutch fixture generation failed' }
$Clock = [Diagnostics.Stopwatch]::StartNew()
$Run = Start-Process $Runtime -ArgumentList @('--quiet','transcribe',$InputDir,'--model',$ModelPath,'--device','cpu','--format','text','--concurrency','1','--output-dir',$OutputDir) -RedirectStandardOutput (Join-Path $Work 'stdout.log') -RedirectStandardError (Join-Path $Work 'stderr.log') -NoNewWindow -Wait -PassThru
$Clock.Stop()
if ($Run.ExitCode -ne 0) { throw 'Parakeet CPU inference failed' }
$Files = @(Get-ChildItem $OutputDir -File -Filter '*.txt')
$Text = (($Files | ForEach-Object { Get-Content -Raw $_.FullName }) -join ' ').ToLowerInvariant()
$Alex = [regex]::Matches($Text,'alex').Count
$Monday = [regex]::Matches($Text,'maandag').Count
if ($Files.Count -ne 11 -or $Alex -ne 62 -or $Monday -ne 62 -or $Text.Contains('ik ben blij')) { throw 'Parakeet Dutch normal/quiet/continuous marker assertions failed' }
Write-Host "QA_PARAKEET_CPU_SECONDS=$($Clock.Elapsed.TotalSeconds) FILES=$($Files.Count) ALEX=$Alex MONDAY=$Monday"
