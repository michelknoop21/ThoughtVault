$ErrorActionPreference='Stop'
Set-Location windows
& npm.cmd ci --offline --no-audit --no-fund --cache C:/Dalf38/temp/thoughtvault-npm-cache
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& node.exe node_modules/vitest/vitest.mjs run
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& npm.cmd run build
exit $LASTEXITCODE
