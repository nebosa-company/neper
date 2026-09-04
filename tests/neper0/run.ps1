$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\neper.exe'
$testBuild = Join-Path $repo 'build\tests\neper0'
& (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$range = & $neper run (Join-Path $PSScriptRoot 'range.e') --output (Join-Path $testBuild 'range.exe')
if ($LASTEXITCODE -ne 0 -or $range -ne 'range ok') { throw 'range control flow failed' }

$scopeError = & $neper build (Join-Path $PSScriptRoot 'scope-error.e') --output (Join-Path $testBuild 'scope-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($scopeError -join "`n") -notmatch '7:23: error\[E-NAME-9999\]') {
    throw 'block scope rejection failed'
}

$breakError = & $neper build (Join-Path $PSScriptRoot 'break-error.e') --output (Join-Path $testBuild 'break-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($breakError -join "`n") -notmatch '4:5: error\[E-TYPE-9999\]') {
    throw 'out-of-loop break rejection failed'
}

'neper-0 Windows control-flow tests passed'
