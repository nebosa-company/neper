$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\neper.exe'
$testBuild = Join-Path $repo 'build\tests\neper0'
& (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$range = & $neper run (Join-Path $PSScriptRoot 'range.e') --output (Join-Path $testBuild 'range.exe')
if ($LASTEXITCODE -ne 0 -or $range -ne 'range ok') { throw 'range control flow failed' }

$array = & $neper run (Join-Path $PSScriptRoot 'array.e') --output (Join-Path $testBuild 'array.exe')
if ($LASTEXITCODE -ne 0 -or $array -ne 'array ok') { throw 'fixed array behavior failed' }

$slice = & $neper run (Join-Path $PSScriptRoot 'slice-mutate.e') --output (Join-Path $testBuild 'slice-mutate.exe') -- original
if ($LASTEXITCODE -ne 0 -or $slice -ne 'slice mutation ok') { throw 'slice mutation failed' }

$iteration = & $neper run (Join-Path $PSScriptRoot 'slice-iterate.e') --output (Join-Path $testBuild 'slice-iterate.exe') -- 'slice iteration ok'
if ($LASTEXITCODE -ne 0 -or $iteration -ne 'slice iteration ok') { throw 'slice iteration failed' }

$slicing = & $neper run (Join-Path $PSScriptRoot 'slice.e') --output (Join-Path $testBuild 'slice.exe')
if ($LASTEXITCODE -ne 0 -or $slicing -ne 'slice ok') { throw 'slice construction failed' }

$sliceBounds = & $neper run (Join-Path $PSScriptRoot 'slice-bounds.e') --output (Join-Path $testBuild 'slice-bounds.exe') 2>&1
if ($LASTEXITCODE -ne 134 -or ($sliceBounds -join "`n") -notmatch 'trap\[bounds\]') {
    throw 'slice bounds trap failed'
}

$bounds = & $neper run (Join-Path $PSScriptRoot 'array-bounds.e') --output (Join-Path $testBuild 'array-bounds.exe') 2>&1
if ($LASTEXITCODE -ne 134 -or ($bounds -join "`n") -notmatch 'trap\[bounds\]') {
    throw 'array bounds trap failed'
}

$countError = & $neper build (Join-Path $PSScriptRoot 'array-count-error.e') --output (Join-Path $testBuild 'array-count-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($countError -join "`n") -notmatch '4:18: error\[E-TYPE-9999\]') {
    throw 'array literal count rejection failed'
}

$mutationError = & $neper build (Join-Path $PSScriptRoot 'array-mutation-error.e') --output (Join-Path $testBuild 'array-mutation-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($mutationError -join "`n") -notmatch '5:5: error\[E-TYPE-9999\]') {
    throw 'immutable array mutation rejection failed'
}

$bindingError = & $neper build (Join-Path $PSScriptRoot 'for-binding-error.e') --output (Join-Path $testBuild 'for-binding-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($bindingError -join "`n") -notmatch '6:9: error\[E-TYPE-9999\]') {
    throw 'immutable for binding rejection failed'
}

$sliceMutationError = & $neper build (Join-Path $PSScriptRoot 'slice-mutation-error.e') --output (Join-Path $testBuild 'slice-mutation-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($sliceMutationError -join "`n") -notmatch '6:5: error\[E-TYPE-9999\]') {
    throw 'readonly slice mutation rejection failed'
}

$scopeError = & $neper build (Join-Path $PSScriptRoot 'scope-error.e') --output (Join-Path $testBuild 'scope-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($scopeError -join "`n") -notmatch '7:23: error\[E-NAME-9999\]') {
    throw 'block scope rejection failed'
}

$breakError = & $neper build (Join-Path $PSScriptRoot 'break-error.e') --output (Join-Path $testBuild 'break-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($breakError -join "`n") -notmatch '4:5: error\[E-TYPE-9999\]') {
    throw 'out-of-loop break rejection failed'
}

'neper-0 Windows tests passed'
