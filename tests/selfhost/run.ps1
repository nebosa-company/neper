$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\neper.exe'
$testBuild = Join-Path $repo 'build\tests\selfhost'
& (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$compiler = Join-Path $testBuild 'neper-self.exe'
& $neper build (Join-Path $repo 'src\main.e') --output $compiler
if ($LASTEXITCODE -ne 0) { throw 'self-hosted compiler slice did not build' }
$lexer = & $compiler self-test
if ($LASTEXITCODE -ne 0 -or $lexer -ne 'selfhost lexer ok') { throw 'self-hosted lexer behavior failed' }
$scan = & $compiler scan 'fn main() -> err { ret ok }'
if ($LASTEXITCODE -ne 0 -or $scan -ne 'scan ok') { throw 'self-hosted compiler scan command failed' }
$parse = & $compiler parse 'fn main() -> err { ret ok }'
if ($LASTEXITCODE -ne 0 -or $parse -ne 'parse ok') { throw 'self-hosted compiler parse command failed' }
$invalid = & $compiler scan '#' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalid -join "`n") -notmatch 'lex.InvalidSource') {
    throw 'self-hosted compiler invalid-source result failed'
}
$invalidParse = & $compiler parse 'fn broken() -> err {' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidParse -join "`n") -notmatch 'parse.InvalidSyntax') {
    throw 'self-hosted compiler invalid-syntax result failed'
}

$moduleFixture = Join-Path $PSScriptRoot 'fixtures\modules\src\main.e'
$moduleOutput = & $neper run $moduleFixture --output (Join-Path $testBuild 'modules.exe')
if ($LASTEXITCODE -ne 0 -or $moduleOutput -ne 'module loading ok') {
    throw 'nested module path and alias resolution failed'
}

$diagnosticFixture = Join-Path $PSScriptRoot 'fixtures\diagnostics\src\main.e'
$diagnosticOutput = & $neper build $diagnosticFixture --output (Join-Path $testBuild 'diagnostics.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($diagnosticOutput -join "`n") -notmatch 'broken\.e:1:1: error\[E-NAME-9999\]') {
    throw 'imported-module diagnostic source failed'
}

$cycleFixture = Join-Path $PSScriptRoot 'fixtures\cycle\src\main.e'
$cycleOutput = & $neper build $cycleFixture --output (Join-Path $testBuild 'cycle.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($cycleOutput -join "`n") -notmatch
    'module import cycle: cycle\.a -> cycle\.b -> cycle\.a') {
    throw 'module import cycle rejection failed'
}

Write-Output 'selfhost tests passed'
