# Optional repair for existing installations. The Microsoft installer owns consent.
$ErrorActionPreference = 'Stop'
$runtime = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
if ($runtime.Installed -eq 1) { Write-Host 'Visual C++ x64 runtime is aanwezig.'; exit 0 }
$installer = Join-Path $env:TEMP 'ThoughtVault-vc_redist.x64.exe'
Invoke-WebRequest 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $installer
$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Microsoft handtekening niet geldig.' }
Write-Host 'De Microsoft installer opent. Lees en accepteer de voorwaarden alleen als je de runtime wilt installeren.'
$result = Start-Process $installer -Wait -PassThru
if ($result.ExitCode -notin 0,3010) { throw "Runtime niet geïnstalleerd (exitcode $($result.ExitCode))." }
