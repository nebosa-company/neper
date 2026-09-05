$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\neper.exe'
$testBuild = Join-Path $repo 'build\tests'
if (-not (Test-Path -LiteralPath $neper)) {
    & (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
}
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$hello = & $neper run (Join-Path $repo 'examples\hello.e') --output (Join-Path $testBuild 'hello.exe')
if ($LASTEXITCODE -ne 0 -or $hello -ne 'hello, neper') { throw 'hello.e failed' }

Push-Location ([IO.Path]::GetTempPath())
try {
    $cwdHello = & $neper run (Join-Path $repo 'examples\hello.e') --output (Join-Path $testBuild 'hello-cwd.exe')
    if ($LASTEXITCODE -ne 0 -or $cwdHello -ne 'hello, neper') { throw 'cross-directory run failed' }
} finally {
    Pop-Location
}

$control = & $neper run (Join-Path $repo 'tests\m0\control.e') --output (Join-Path $testBuild 'control.exe')
if ($LASTEXITCODE -ne 0 -or $control -ne 'control ok') { throw 'control.e failed' }

$argsOutput = & $neper run (Join-Path $repo 'tests\m0\args.e') --output (Join-Path $testBuild 'args.exe') -- 'héllo 😀'
if ($LASTEXITCODE -ne 0 -or $argsOutput -ne 'héllo 😀') { throw 'UTF-8 startup args failed' }

$abiOutput = & $neper run (Join-Path $repo 'tests\m0\abi.e') --output (Join-Path $testBuild 'abi.exe')
if ($LASTEXITCODE -ne 0 -or $abiOutput -ne 'abi ok') { throw 'x64 argument ABI failed' }

$largeStackOutput = & $neper run (Join-Path $repo 'tests\m0\large-stack.e') --output (Join-Path $testBuild 'large-stack.exe')
if ($LASTEXITCODE -ne 0 -or $largeStackOutput -ne 'large stack ok') { throw 'large stack frame failed' }
$largeStackAssembly = Get-Content -Raw (Join-Path $testBuild 'large-stack.asm')
if ($largeStackAssembly -notmatch 'call np_stack_probe') { throw 'large stack frame was not probed' }

$boundsOutput = & $neper run (Join-Path $repo 'tests\m0\bounds.e') --output (Join-Path $testBuild 'bounds.exe') 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsOutput -join "`n") -notmatch 'trap\[bounds\]') {
    throw 'bounds trap failed'
}

$divideOutput = & $neper run (Join-Path $repo 'tests\m0\divide.e') --output (Join-Path $testBuild 'divide.exe') 2>&1
if ($LASTEXITCODE -ne 134 -or ($divideOutput -join "`n") -notmatch 'trap\[divide\]') {
    throw 'divide trap failed'
}

$errorOutput = & $neper run (Join-Path $repo 'tests\m0\errors.e') --output (Join-Path $testBuild 'errors.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($errorOutput -join "`n") -ne 'error: errors.Boom') {
    throw 'named error propagation failed'
}

$badOutput = & $neper build (Join-Path $repo 'tests\m0\bad-main.e') --output (Join-Path $testBuild 'bad-main.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($badOutput -join "`n") -notmatch 'E-TYPE-9999') {
    throw 'bad-main.e did not produce the expected diagnostic'
}

$missingOutput = & $neper build (Join-Path $repo 'tests\m0\missing-module.e') --output (Join-Path $testBuild 'missing.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($missingOutput -join "`n") -notmatch '1:1: error\[E-MODULE-0001\]') {
    throw 'missing module diagnostic failed'
}

$typeOutput = & $neper build (Join-Path $repo 'tests\m0\type-error.e') --output (Join-Path $testBuild 'type-error.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($typeOutput -join "`n") -notmatch '4:5: error\[E-TYPE-0002\]') {
    throw 'type diagnostic span failed'
}

$tabSource = Join-Path $testBuild 'tab.e'
[IO.File]::WriteAllText($tabSource, "use e.mem`n`nfn main(a: *mem.Arena, args: []str) -> err {`n`tret ok`n}`n", [Text.UTF8Encoding]::new($false))
$tabOutput = & $neper build $tabSource --output (Join-Path $testBuild 'tab.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($tabOutput -join "`n") -notmatch '4:1: error\[E-LEX-0002\]') {
    throw 'tab diagnostic span failed'
}

$utf8Source = Join-Path $testBuild 'invalid-utf8.e'
$prefix = [Text.Encoding]::ASCII.GetBytes("use e.mem`n")
$invalid = [byte[]]($prefix + 0xC3 + [Text.Encoding]::ASCII.GetBytes("`n"))
[IO.File]::WriteAllBytes($utf8Source, $invalid)
$utf8Output = & $neper build $utf8Source --output (Join-Path $testBuild 'invalid-utf8.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($utf8Output -join "`n") -notmatch '2:1: error\[E-LEX-0001\]') {
    throw 'UTF-8 diagnostic span failed'
}

'M0 Windows tests passed'
