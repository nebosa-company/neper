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

$struct = & $neper run (Join-Path $PSScriptRoot 'struct.e') --output (Join-Path $testBuild 'struct.exe')
if ($LASTEXITCODE -ne 0 -or $struct -ne 'struct ok') { throw 'struct and pointer behavior failed' }

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

$pointerConstError = & $neper build (Join-Path $PSScriptRoot 'pointer-const-error.e') --output (Join-Path $testBuild 'pointer-const-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($pointerConstError -join "`n") -notmatch '10:5: error\[E-TYPE-9999\]') {
    throw 'const pointer mutation rejection failed'
}

$recursiveStructError = & $neper build (Join-Path $PSScriptRoot 'recursive-struct-error.e') --output (Join-Path $testBuild 'recursive-struct-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($recursiveStructError -join "`n") -notmatch '3:1: error\[E-TYPE-9999\]') {
    throw 'recursive struct rejection failed'
}

$aggregateAbi = & $neper run (Join-Path $PSScriptRoot 'aggregate-abi.e') --output (Join-Path $testBuild 'aggregate-abi.exe')
if ($LASTEXITCODE -ne 0 -or $aggregateAbi -ne 'aggregate abi ok') { throw 'aggregate ABI behavior failed' }

$aggregateParamError = & $neper build (Join-Path $PSScriptRoot 'aggregate-param-mutation-error.e') --output (Join-Path $testBuild 'aggregate-param-mutation-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($aggregateParamError -join "`n") -notmatch '10:5: error\[E-TYPE-9999\]') {
    throw 'immutable aggregate parameter rejection failed'
}

$enumUnion = & $neper run (Join-Path $PSScriptRoot 'enum-union-switch.e') --output (Join-Path $testBuild 'enum-union-switch.exe')
if ($LASTEXITCODE -ne 0 -or $enumUnion -ne 'enum union switch ok') { throw 'enum, union, and switch behavior failed' }

& (Join-Path $PSScriptRoot 'check-codeview.ps1') -ObjectPath @(
    (Join-Path $testBuild 'aggregate-abi.obj'),
    (Join-Path $testBuild 'enum-union-switch.obj'),
    (Join-Path $testBuild 'array.obj')
)

$exhaustiveError = & $neper build (Join-Path $PSScriptRoot 'switch-exhaustive-error.e') --output (Join-Path $testBuild 'switch-exhaustive-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($exhaustiveError -join "`n") -notmatch 'non-exhaustive switch; missing member `Two`') {
    throw 'enum switch exhaustiveness rejection failed'
}

$enumValueError = & $neper build (Join-Path $PSScriptRoot 'enum-value-error.e') --output (Join-Path $testBuild 'enum-value-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($enumValueError -join "`n") -notmatch 'enum member value is outside its backing type' -or
    ($enumValueError -join "`n") -notmatch 'duplicate enum backing value') {
    throw 'invalid enum value rejection failed'
}

$tagTrap = & $neper run (Join-Path $PSScriptRoot 'tagged-payload-trap.e') --output (Join-Path $testBuild 'tagged-payload-trap.exe') 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagTrap -join "`n") -notmatch 'trap\[tag\]') {
    throw 'tagged-union payload trap failed'
}

$enumZeroError = & $neper build (Join-Path $PSScriptRoot 'enum-zero-error.e') --output (Join-Path $testBuild 'enum-zero-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($enumZeroError -join "`n") -notmatch 'has no zero value') {
    throw 'non-zeroable enum rejection failed'
}

$defer = & $neper run (Join-Path $PSScriptRoot 'defer.e') --output (Join-Path $testBuild 'defer.exe')
if ($LASTEXITCODE -ne 0 -or $defer -ne 'defer ok') { throw 'defer behavior failed' }

$deferTryError = & $neper build (Join-Path $PSScriptRoot 'defer-try-error.e') --output (Join-Path $testBuild 'defer-try-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($deferTryError -join "`n") -notmatch 'try is not legal inside defer') {
    throw 'try-inside-defer rejection failed'
}

$deferValueError = & $neper build (Join-Path $PSScriptRoot 'defer-value-error.e') --output (Join-Path $testBuild 'defer-value-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($deferValueError -join "`n") -notmatch 'deferred call returning a value') {
    throw 'undiscarded deferred value rejection failed'
}

$deferRetError = & $neper build (Join-Path $PSScriptRoot 'defer-ret-error.e') --output (Join-Path $testBuild 'defer-ret-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($deferRetError -join "`n") -notmatch 'ret is not legal inside defer') {
    throw 'ret-inside-defer rejection failed'
}

$protocol = & $neper run (Join-Path $PSScriptRoot 'protocol-iteration.e') --output (Join-Path $testBuild 'protocol-iteration.exe')
if ($LASTEXITCODE -ne 0 -or $protocol -ne 'protocol iteration ok') { throw 'protocol iteration behavior failed' }

$protocolImmutable = & $neper build (Join-Path $PSScriptRoot 'protocol-immutable-error.e') --output (Join-Path $testBuild 'protocol-immutable-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($protocolImmutable -join "`n") -notmatch 'iterator subject must be a mutable variable or a mutable pointer') {
    throw 'immutable iterator rejection failed'
}

$protocolSignature = & $neper build (Join-Path $PSScriptRoot 'protocol-signature-error.e') --output (Join-Path $testBuild 'protocol-signature-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($protocolSignature -join "`n") -notmatch 'iterator next function must have signature') {
    throw 'iterator signature rejection failed'
}

$protocolMissing = & $neper build (Join-Path $PSScriptRoot 'protocol-missing-error.e') --output (Join-Path $testBuild 'protocol-missing-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($protocolMissing -join "`n") -notmatch 'protocol iteration needs `fn counter_next') {
    throw 'missing iterator protocol rejection failed'
}

$multipleReturn = & $neper run (Join-Path $PSScriptRoot 'multiple-return.e') --output (Join-Path $testBuild 'multiple-return.exe')
if ($LASTEXITCODE -ne 0 -or $multipleReturn -ne 'multiple return ok') { throw 'multiple return behavior failed' }

$multipleReturnCount = & $neper build (Join-Path $PSScriptRoot 'multiple-return-count-error.e') --output (Join-Path $testBuild 'multiple-return-count-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($multipleReturnCount -join "`n") -notmatch 'multiple binding count does not match function results') {
    throw 'multiple return count rejection failed'
}

$multipleReturnMutable = & $neper build (Join-Path $PSScriptRoot 'multiple-return-mutable-error.e') --output (Join-Path $testBuild 'multiple-return-mutable-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($multipleReturnMutable -join "`n") -notmatch 'multiple assignment target is immutable') {
    throw 'immutable multiple assignment rejection failed'
}

$constantFolding = & $neper run (Join-Path $PSScriptRoot 'constant-folding.e') --output (Join-Path $testBuild 'constant-folding.exe')
if ($LASTEXITCODE -ne 0 -or $constantFolding -ne 'constant folding ok') { throw 'constant folding behavior failed' }

$constantCycle = & $neper build (Join-Path $PSScriptRoot 'constant-cycle-error.e') --output (Join-Path $testBuild 'constant-cycle-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($constantCycle -join "`n") -notmatch 'constant dependency cycle') {
    throw 'constant cycle rejection failed'
}

$arrayLengthType = & $neper build (Join-Path $PSScriptRoot 'array-length-type-error.e') --output (Join-Path $testBuild 'array-length-type-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($arrayLengthType -join "`n") -notmatch 'array length must have type usize') {
    throw 'array length type rejection failed'
}

$genericFunction = & $neper run (Join-Path $PSScriptRoot 'generic-function.e') --output (Join-Path $testBuild 'generic-function.exe')
if ($LASTEXITCODE -ne 0 -or $genericFunction -ne 'generic function ok') { throw 'generic function behavior failed' }

$genericInference = & $neper build (Join-Path $PSScriptRoot 'generic-inference-error.e') --output (Join-Path $testBuild 'generic-inference-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($genericInference -join "`n") -notmatch 'cannot infer compile-time parameter `T`') {
    throw 'generic inference rejection failed'
}

$genericAggregate = & $neper run (Join-Path $PSScriptRoot 'generic-aggregate.e') --output (Join-Path $testBuild 'generic-aggregate.exe')
if ($LASTEXITCODE -ne 0 -or $genericAggregate -ne 'generic aggregate ok') { throw 'generic aggregate behavior failed' }

$genericAggregateArity = & $neper build (Join-Path $PSScriptRoot 'generic-aggregate-arity-error.e') --output (Join-Path $testBuild 'generic-aggregate-arity-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($genericAggregateArity -join "`n") -notmatch 'compile-time argument count does not match generic type') {
    throw 'generic aggregate arity rejection failed'
}

$osHelper = Join-Path $testBuild 'os-spawn-helper.exe'
& $neper build (Join-Path $PSScriptRoot 'os-spawn-helper.e') --output $osHelper | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'OS spawn helper build failed' }
$osOutput = Join-Path $testBuild 'os-output.txt'
$osIntrinsic = & $neper run (Join-Path $PSScriptRoot 'os-intrinsics.e') --output (Join-Path $testBuild 'os-intrinsics.exe') -- $osOutput $PSScriptRoot $osHelper
if ($LASTEXITCODE -ne 0 -or $osIntrinsic -ne 'intrinsic ok') { throw 'fixed OS intrinsic behavior failed' }
if ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($osOutput)) -ne 'neper os!') { throw 'OS file round trip failed' }

$missingPath = Join-Path $testBuild 'does-not-exist.neper0'
$osError = & $neper run (Join-Path $PSScriptRoot 'os-error.e') --output (Join-Path $testBuild 'os-error.exe') -- $missingPath 2>&1
if ($LASTEXITCODE -ne 1 -or ($osError -join "`n") -notmatch 'error: os\.NotFound') { throw 'OS error mapping failed' }

& $neper run (Join-Path $PSScriptRoot 'os-exit.e') --output (Join-Path $testBuild 'os-exit.exe') | Out-Null
if ($LASTEXITCODE -ne 23) { throw 'OS exit intrinsic failed' }

'neper-0 Windows tests passed'
