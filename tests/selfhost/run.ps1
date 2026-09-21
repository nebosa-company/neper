$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\windows\neper.exe'
$testBuild = Join-Path $repo 'build\windows\tests\selfhost'
& (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$compiler = Join-Path $testBuild 'neper-self.exe'
$compilerAsm = Join-Path $testBuild 'neper-self.asm'
# The arena is reserved and committed as it is used (D133), so its size is a ceiling rather
# than a cost -- what a run charges is what it allocates. Measured against the heaviest
# workload there is, the compiler compiling itself: 384m exhausts, 400m succeeds, and the
# peak is 388m. A gigabyte is the largest program worth compiling, not the largest the
# commit limit will bear.
& $neper build (Join-Path $repo 'src\main.e') --arena 1g --output $compiler --emit-asm $compilerAsm
if ($LASTEXITCODE -ne 0) { throw 'self-hosted compiler slice did not build' }
& python (Join-Path $repo 'scripts\check_module_surfaces.py') --compiler $compiler --arch x64 --os windows
if ($LASTEXITCODE -ne 0) { throw 'compiler-resolved module surface validation failed' }
# The bootstrap's rules for `src/` (D794), before the next ten-minute build finds one.
& python (Join-Path $repo 'scripts\lint_bootstrap.py') (Join-Path $repo 'src')
if ($LASTEXITCODE -ne 0) { throw 'src/ breaks a bootstrap rule (scripts/lint_bootstrap.py)' }
# Every bootstrap frame has to cover the temporaries its statements allocate. A
# frame sized by guess rather than by measurement lets a deep statement address
# below rsp, into the outgoing argument area and past the stack pointer.
$frameProc = ''
$frameSize = 0
$frameDeepest = 0
$frameProbe = -1
$frameOverruns = @()
function Test-Frame {
    if ($script:frameProc -and $script:frameSize -gt 0 -and $script:frameDeepest -gt $script:frameSize) {
        $script:frameOverruns += "$($script:frameProc) reaches [rbp-$($script:frameDeepest)] in a $($script:frameSize)-byte frame"
    }
}
foreach ($line in [IO.File]::ReadLines($compilerAsm)) {
    if ($line -match '^(\S+) PROC FRAME') {
        Test-Frame
        $frameProc = $Matches[1]; $frameSize = 0; $frameDeepest = 0; $frameProbe = -1
        continue
    }
    if (-not $frameProc) { continue }
    if ($frameSize -eq 0) {
        if ($line -match '^\s+sub rsp, (\d+)$') { $frameSize = [int]$Matches[1]; continue }
        if ($line -match '^\s+mov eax, (\d+)$') { $frameProbe = [int]$Matches[1]; continue }
        if ($frameProbe -ge 0 -and $line.Contains('call np_stack_probe')) { $frameSize = $frameProbe; $frameProbe = -1 }
        continue
    }
    if (-not $line.Contains('[rbp-')) { continue }
    foreach ($hit in [regex]::Matches($line, '\[rbp-(\d+)')) {
        $depth = [int]$hit.Groups[1].Value
        if ($depth -gt $frameDeepest) { $frameDeepest = $depth }
    }
}
Test-Frame
if ($frameOverruns.Count -ne 0) { throw "bootstrap frames do not cover their temporaries: $($frameOverruns -join '; ')" }
$lexer = & $compiler self-test
# A bootstrap code-generation regression: `.len` on a call result is read out of a
# register, not an address, because a call result has no address. Built and run with
# the bootstrap, since that is the back end that had it wrong.
$callLenPath = Join-Path $testBuild 'call-result-len-bootstrap.exe'
& $neper build (Join-Path $repo 'tests\neper0\call-result-len.e') --output $callLenPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the bootstrap did not build the call-result length fixture' }
& $callLenPath
if ($LASTEXITCODE -ne 0) { throw 'the bootstrap reads the length of a call result from the wrong place' }
if ($LASTEXITCODE -ne 0 -or $lexer -ne 'selfhost lexer ok') { throw 'self-hosted lexer behavior failed' }
$scan = & $compiler scan 'fn main() -> err { ret ok }'
if ($LASTEXITCODE -ne 0 -or $scan -ne 'scan ok') { throw 'self-hosted compiler scan command failed' }
$parse = & $compiler parse 'fn main() -> err { ret ok }'
if ($LASTEXITCODE -ne 0 -or $parse -ne 'parse ok') { throw 'self-hosted compiler parse command failed' }
$scanFile = & $compiler scan-file (Join-Path $repo 'src\main.e')
if ($LASTEXITCODE -ne 0 -or $scanFile -ne 'scan file ok') { throw 'arena-backed source scan failed' }
$parseFile = & $compiler parse-file (Join-Path $PSScriptRoot 'fixtures\source-load.e')
if ($LASTEXITCODE -ne 0 -or $parseFile -ne 'parse file ok') { throw 'arena-backed source parse failed' }
$missingFile = & $compiler scan-file (Join-Path $testBuild 'missing-source.e') 2>&1
if ($LASTEXITCODE -ne 1 -or ($missingFile -join "`n") -notmatch 'error: os\.NotFound') {
    throw 'source loader missing-file propagation failed'
}
$projectRoot = & $compiler project-file (Join-Path $repo 'src\main.e') $repo 'main'
if ($LASTEXITCODE -ne 0 -or $projectRoot -ne 'project file ok') { throw 'project src module discovery failed' }
$libraryModule = & $compiler project-file (Join-Path $repo 'lib\e\mem.e') $repo 'e.mem'
if ($LASTEXITCODE -ne 0 -or $libraryModule -ne 'project file ok') { throw 'project lib module discovery failed' }
$nestedRoot = Join-Path $PSScriptRoot 'fixtures\modules'
$nestedModule = & $compiler project-file (Join-Path $nestedRoot 'src\util\math.e') $nestedRoot 'util.math'
if ($LASTEXITCODE -ne 0 -or $nestedModule -ne 'project file ok') { throw 'nested project module discovery failed' }
$outsideRoot = & $compiler project-file (Join-Path $repo 'examples\hello.e') $repo 'hello'
if ($LASTEXITCODE -ne 0 -or $outsideRoot -ne 'project file ok') { throw 'named file module discovery failed' }
Push-Location $repo
try {
    $relativeRoot = & $compiler project-file 'src\main.e' '.' 'main'
    if ($LASTEXITCODE -ne 0 -or $relativeRoot -ne 'project file ok') { throw 'relative project discovery failed' }
} finally {
    Pop-Location
}
$invalidModule = & $compiler project-file (Join-Path $repo 'src\main.txt') $repo 'main' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidModule -join "`n") -notmatch 'error: project\.InvalidPath') {
    throw 'non-source module path rejection failed'
}
$variantRoot = Join-Path $PSScriptRoot 'fixtures\variants'
$variantModule = & $compiler project-file (Join-Path $variantRoot 'src\system.windows.e') $variantRoot 'system'
if ($LASTEXITCODE -ne 0 -or $variantModule -ne 'project file ok') { throw 'OS variant module naming failed' }
$nestedVariantModule = & $compiler project-file (Join-Path $variantRoot 'src\nested\codec.aarch64.e') $variantRoot 'nested.codec'
if ($LASTEXITCODE -ne 0 -or $nestedVariantModule -ne 'project file ok') { throw 'architecture variant module naming failed' }
$windowsVariant = & $compiler select-file $variantRoot 'src' 'system' 'x64' 'windows' (Join-Path $variantRoot 'src\system.windows.e')
if ($LASTEXITCODE -ne 0 -or $windowsVariant -ne 'source variant ok') { throw 'OS source variant selection failed' }
$linuxVariant = & $compiler select-file $variantRoot 'src' 'system' 'x86' 'linux' (Join-Path $variantRoot 'src\system.linux.e')
if ($LASTEXITCODE -ne 0 -or $linuxVariant -ne 'source variant ok') { throw 'second OS source variant selection failed' }
$plainFallback = & $compiler select-file $variantRoot 'src' 'system' 'x64' 'macos' (Join-Path $variantRoot 'src\system.e')
if ($LASTEXITCODE -ne 0 -or $plainFallback -ne 'source variant ok') { throw 'plain source fallback failed' }
$archVariant = & $compiler select-file $variantRoot 'src' 'architecture' 'x64' 'linux' (Join-Path $variantRoot 'src\architecture.x64.e')
if ($LASTEXITCODE -ne 0 -or $archVariant -ne 'source variant ok') { throw 'architecture source variant selection failed' }
$nestedVariant = & $compiler select-file $variantRoot 'src' 'nested.codec' 'aarch64' 'macos' (Join-Path $variantRoot 'src\nested\codec.aarch64.e')
if ($LASTEXITCODE -ne 0 -or $nestedVariant -ne 'source variant ok') { throw 'nested source variant selection failed' }
$deviceVariant = & $compiler select-file $variantRoot 'src' 'device' 'spv' 'none' (Join-Path $variantRoot 'src\device.none.e')
if ($LASTEXITCODE -ne 0 -or $deviceVariant -ne 'source variant ok') { throw 'device OS source variant selection failed' }
$ambiguousVariant = & $compiler select-file $variantRoot 'src' 'ambiguous' 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($ambiguousVariant -join "`n") -notmatch 'error: project\.AmbiguousVariant') {
    throw 'ambiguous target source variants were not rejected'
}
$missingVariant = & $compiler select-file $variantRoot 'src' 'missing' 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($missingVariant -join "`n") -notmatch 'error: project\.ModuleNotFound') {
    throw 'missing target source module returned the wrong error'
}
$invalidTarget = & $compiler select-file $variantRoot 'src' 'system' 'riscv64' 'linux' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidTarget -join "`n") -notmatch 'error: project\.InvalidTarget') {
    throw 'invalid source target returned the wrong error'
}
$invalidTargetPair = & $compiler select-file $variantRoot 'src' 'system' 'x86' 'macos' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidTargetPair -join "`n") -notmatch 'error: project\.InvalidTarget') {
    throw 'invalid architecture/OS pair returned the wrong error'
}
$invalidSourceRoot = & $compiler select-file $variantRoot 'source' 'system' 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidSourceRoot -join "`n") -notmatch 'error: project\.InvalidPath') {
    throw 'invalid source-root name returned the wrong error'
}
$reservedModule = & $compiler project-file (Join-Path $variantRoot 'src\windows.e') $variantRoot '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedModule -join "`n") -notmatch 'error: project\.InvalidPath') {
    throw 'reserved target module name was not rejected'
}
$compoundVariant = & $compiler project-file (Join-Path $variantRoot 'src\system.x64.windows.e') $variantRoot '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($compoundVariant -join "`n") -notmatch 'error: project\.InvalidPath') {
    throw 'compound target source suffix was not rejected'
}
$graphRoot = Join-Path $PSScriptRoot 'fixtures\graph'
$transitiveGraph = & $compiler graph-file (Join-Path $graphRoot 'transitive\src\main.e') $repo 'x64' 'windows' 'main' 'branch' 'leaf'
if ($LASTEXITCODE -ne 0 -or $transitiveGraph -ne 'module graph ok') { throw 'transitive module graph loading failed' }
$reusedGraph = & $compiler graph-file (Join-Path $graphRoot 'reuse\src\main.e') $repo 'x64' 'windows' 'main' 'common'
if ($LASTEXITCODE -ne 0 -or $reusedGraph -ne 'module graph ok') { throw 'multiply aliased module was not reused' }
$toolchainGraph = & $compiler graph-file (Join-Path $nestedRoot 'src\main.e') $repo 'x64' 'windows' 'main' 'e.io' 'e.mem' 'e.os' 'e.str' 'util.math'
if ($LASTEXITCODE -ne 0 -or $toolchainGraph -ne 'module graph ok') { throw 'toolchain fallback module graph loading failed' }
$variantGraph = & $compiler graph-file (Join-Path $variantRoot 'src\root.e') $repo 'x64' 'windows' 'root' 'system'
if ($LASTEXITCODE -ne 0 -or $variantGraph -ne 'module graph ok') { throw 'target-variant module graph loading failed' }
$cycleGraph = & $compiler graph-file (Join-Path $graphRoot 'cycle\src\a.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($cycleGraph -join "`n") -notmatch 'b\.e:1:1: error\[E-MODULE-0002\]: `use a` closes an import cycle') {
    throw 'module import cycle was not rejected'
}
$duplicateGraph = & $compiler graph-file (Join-Path $graphRoot 'duplicate\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($duplicateGraph -join "`n") -notmatch 'main\.e:1:1: error\[E-MODULE-0001\]: `use thing` is defined by both source roots') {
    throw 'duplicate source-root module was not rejected'
}
$aliasGraph = & $compiler graph-file (Join-Path $graphRoot 'alias\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($aliasGraph -join "`n") -notmatch 'error: graph\.DuplicateQualifier') {
    throw 'duplicate import qualifier was not rejected'
}
$missingGraph = & $compiler graph-file (Join-Path $graphRoot 'missing\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($missingGraph -join "`n") -notmatch 'main\.e:1:1: error\[E-MODULE-0001\]: `use absent` names no module') {
    throw 'missing graph module returned the wrong error'
}
$invalidGraph = & $compiler graph-file (Join-Path $graphRoot 'invalid\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidGraph -join "`n") -notmatch 'broken\.e:1:12: error\[E-SYNTAX-9999\]: unexpected `\{`') {
    throw 'invalid imported source did not name the offending module, position and token'
}
$invalidGraphTarget = & $compiler graph-file (Join-Path $graphRoot 'transitive\src\leaf.e') $repo 'x86' 'macos' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidGraphTarget -join "`n") -notmatch 'error: project\.InvalidTarget') {
    throw 'module graph accepted an invalid target without imports'
}
$resolveRoot = Join-Path $PSScriptRoot 'fixtures\resolve'
$resolved = & $compiler resolve-file (Join-Path $resolveRoot 'valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $resolved -ne 'module resolve ok') { throw 'qualified module resolution failed' }
$compilerResolved = & $compiler resolve-file (Join-Path $repo 'src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $compilerResolved -ne 'module resolve ok') { throw 'self-hosted compiler module resolution failed' }
$builtinQualifier = & $compiler resolve-file (Join-Path $resolveRoot 'builtin_qualifier\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $builtinQualifier -ne 'module resolve ok') { throw 'type-namespace qualifier reuse failed' }
$duplicateValue = & $compiler resolve-file (Join-Path $resolveRoot 'duplicate_value\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($duplicateValue -join "`n") -notmatch 'error: resolve\.DuplicateName') { throw 'duplicate value declaration was not rejected' }
$duplicateType = & $compiler resolve-file (Join-Path $resolveRoot 'duplicate_type\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($duplicateType -join "`n") -notmatch 'error: resolve\.DuplicateName') { throw 'duplicate type declaration was not rejected' }
$qualifierCollision = & $compiler resolve-file (Join-Path $resolveRoot 'qualifier_collision\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($qualifierCollision -join "`n") -notmatch 'error: resolve\.QualifierCollision') { throw 'qualifier/value collision was not rejected' }
$reservedValue = & $compiler resolve-file (Join-Path $resolveRoot 'reserved_value\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedValue -join "`n") -notmatch 'error: resolve\.ReservedName') { throw 'reserved value declaration was not rejected' }
$reservedType = & $compiler resolve-file (Join-Path $resolveRoot 'reserved_type\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedType -join "`n") -notmatch 'error: resolve\.ReservedName') { throw 'reserved type declaration was not rejected' }
$reservedModule = & $compiler resolve-file (Join-Path $resolveRoot 'reserved_module\src\u8.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedModule -join "`n") -notmatch 'error: resolve\.ReservedName') { throw 'reserved module name was not rejected' }
$reservedQualifier = & $compiler resolve-file (Join-Path $resolveRoot 'reserved_qualifier\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedQualifier -join "`n") -notmatch 'error: resolve\.ReservedName') { throw 'reserved target qualifier was not rejected' }
$unknownValue = & $compiler resolve-file (Join-Path $resolveRoot 'unknown_value\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($unknownValue -join "`n") -notmatch 'error: resolve\.UnknownMember') { throw 'unknown qualified value was not rejected' }
$unknownType = & $compiler resolve-file (Join-Path $resolveRoot 'unknown_type\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($unknownType -join "`n") -notmatch 'error: resolve\.UnknownMember') { throw 'unknown qualified type was not rejected' }
$unqualifiedValid = & $compiler resolve-file (Join-Path $resolveRoot 'unqualified_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $unqualifiedValid -ne 'module resolve ok') { throw 'valid unqualified references did not resolve' }
$unknownName = & $compiler resolve-file (Join-Path $resolveRoot 'unknown_name\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($unknownName -join "`n") -notmatch 'error: resolve\.UnknownName') { throw 'unknown unqualified name was not rejected' }
$unknownBareType = & $compiler resolve-file (Join-Path $resolveRoot 'unknown_bare_type\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($unknownBareType -join "`n") -notmatch 'error: resolve\.UnknownType') { throw 'unknown unqualified type was not rejected' }
$namespaceAsType = & $compiler resolve-file (Join-Path $resolveRoot 'namespace_as_type\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($namespaceAsType -join "`n") -notmatch 'error: resolve\.UnknownType') { throw 'builtin namespace was accepted as a type' }
$useBeforeBinding = & $compiler resolve-file (Join-Path $resolveRoot 'use_before_binding\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($useBeforeBinding -join "`n") -notmatch 'error: resolve\.UnknownName') { throw 'binding was visible in its initializer' }
$siblingOutOfScope = & $compiler resolve-file (Join-Path $resolveRoot 'sibling_out_of_scope\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($siblingOutOfScope -join "`n") -notmatch 'error: resolve\.UnknownName') { throw 'sibling local remained visible after its scope' }
$captureNotInCase = & $compiler resolve-file (Join-Path $resolveRoot 'capture_not_in_case\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($captureNotInCase -join "`n") -notmatch 'error: resolve\.UnknownName') { throw 'switch capture was visible in its case expression' }
$unknownTopLevel = & $compiler resolve-file (Join-Path $resolveRoot 'unknown_top_level\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($unknownTopLevel -join "`n") -notmatch 'error: resolve\.UnknownName') { throw 'unknown top-level initializer name was not rejected' }
$deferBindingScope = & $compiler resolve-file (Join-Path $resolveRoot 'defer_binding_scope\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($deferBindingScope -join "`n") -notmatch 'error: resolve\.UnknownName') { throw 'deferred single-statement binding escaped its implicit scope' }
$checkRoot = Join-Path $PSScriptRoot 'fixtures\check'
$checked = & $compiler check-file (Join-Path $checkRoot 'valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $checked -ne 'module check ok') { throw 'valid scalar program did not type-check' }
$lowered = & $compiler nir-file (Join-Path $repo 'lib\e\io.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $lowered -ne 'module nir ok') { throw 'checked module did not lower to canonical NIR' }
$helloLowered = & $compiler nir-file (Join-Path $repo 'examples\hello.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $helloLowered -ne 'module nir ok') { throw 'qualified call and try propagation did not lower to canonical NIR' }
$expressionsLowered = & $compiler nir-file (Join-Path $PSScriptRoot 'fixtures\nir\expressions\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $expressionsLowered -ne 'module nir ok') { throw 'scalar expressions did not lower to canonical NIR' }
$expressionsGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\expressions\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $expressionsGenerated -ne 'module codegen ok') { throw 'scalar NIR did not allocate and select x64 machine code' }
$parametersGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\parameters\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $parametersGenerated -ne 'module codegen ok') { throw 'Windows x64 parameter ingress did not reach allocated NIR values' }
$callsGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\calls\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $callsGenerated -ne 'module codegen ok') { throw 'Windows x64 calls did not emit ABI moves and relocations' }
$objectGenerated = & $compiler object-file (Join-Path $PSScriptRoot 'fixtures\nir\calls\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $objectGenerated -ne 'module object ok') { throw 'source-to-COFF object pipeline failed' }
$coffPath = Join-Path $testBuild 'calls.obj'
$objectWritten = & $compiler emit-object (Join-Path $PSScriptRoot 'fixtures\nir\calls\src\main.e') $repo 'x64' 'windows' $coffPath
if ($LASTEXITCODE -ne 0 -or $objectWritten -ne 'object written' -or -not (Test-Path -LiteralPath $coffPath) -or (Get-Item -LiteralPath $coffPath).Length -le 60) { throw 'COFF object file emission failed' }
$executablePath = Join-Path $testBuild 'basic-selfhost.exe'
$executableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\basic\src\main.e') $repo 'x64' 'windows' $executablePath
if ($LASTEXITCODE -ne 0 -or $executableWritten -ne 'executable written' -or -not (Test-Path -LiteralPath $executablePath) -or (Get-Item -LiteralPath $executablePath).Length -le 512) { throw 'PE executable emission failed' }
& $executablePath
if ($LASTEXITCODE -ne 0) { throw 'self-hosted PE executable did not run successfully' }
$executableBytes = [IO.File]::ReadAllBytes($executablePath)
$executableText = [Text.Encoding]::ASCII.GetString($executableBytes)
if ([BitConverter]::ToUInt16($executableBytes, 134) -ne 2 -or [BitConverter]::ToUInt32($executableBytes, 272) -eq 0 -or [BitConverter]::ToUInt32($executableBytes, 360) -eq 0) { throw 'PE executable omitted its import directory or IAT' }
if ($executableText -notmatch 'KERNEL32\.dll' -or $executableText -notmatch 'ExitProcess') { throw 'PE executable omitted its fixed kernel32 import' }
$scalarExecutablePath = Join-Path $testBuild 'scalar-selfhost.exe'
$scalarExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\scalar\src\main.e') $repo 'x64' 'windows' $scalarExecutablePath
if ($LASTEXITCODE -ne 0 -or $scalarExecutableWritten -ne 'executable written') { throw 'scalar PE executable emission failed' }
& $scalarExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'integer cast semantics failed in the self-hosted PE executable' }
$genericExecutablePath = Join-Path $testBuild 'generic-selfhost.exe'
$genericExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\generic\src\main.e') $repo 'x64' 'windows' $genericExecutablePath
if ($LASTEXITCODE -ne 0 -or $genericExecutableWritten -ne 'executable written') { throw 'generic function instance did not lower into a PE executable' }
& $genericExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'generic function instance failed in the self-hosted PE executable' }
$genericArtifactPath = Join-Path $testBuild 'generic.x64-windows.em'
$genericArtifactWritten = & $compiler emit-em (Join-Path $PSScriptRoot 'fixtures\link\generic\src\main.e') $repo 'x64' 'windows' $genericArtifactPath
if ($LASTEXITCODE -ne 0 -or $genericArtifactWritten -ne 'compiled module written') { throw 'generic function instance was not serialized into a compiled module' }
$genericArtifactExecutablePath = Join-Path $testBuild 'generic-from-artifact.exe'
$genericArtifactExecutableWritten = & $compiler link-em $genericArtifactExecutablePath $genericArtifactPath
if ($LASTEXITCODE -ne 0 -or $genericArtifactExecutableWritten -ne 'artifact executable written') { throw 'generic compiled module did not link' }
& $genericArtifactExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'generic compiled-module executable failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $genericArtifactExecutablePath).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $genericExecutablePath).Hash) { throw 'generic compiled-module and source links differ' }
# Walk a compiled module's code section. The section directory is fixed, so the
# code section offset is at byte 112 (D320: no NIR section); each record is a 24-byte header followed by
# its machine code and its relocations of 28 bytes each (format 5, D319).
function Get-EmCodeRecords([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $code = [int][BitConverter]::ToUInt64($bytes, 112)
    $count = [int][BitConverter]::ToUInt32($bytes, $code)
    $records = @()
    $cursor = $code + 4
    for ($i = 0; $i -lt $count; $i++) {
        $length = [int][BitConverter]::ToUInt32($bytes, $cursor + 16)
        $relocations = [int][BitConverter]::ToUInt32($bytes, $cursor + 20)
        $records += [pscustomobject]@{
            Instance = [BitConverter]::ToUInt32($bytes, $cursor + 4)
            ContentHash = [BitConverter]::ToUInt64($bytes, $cursor + 8)
        }
        $cursor += 24 + $length + $relocations * 28
    }
    return ,$records
}
$functionValueExecutable = Join-Path $testBuild 'function-values-selfhost.exe'
$functionValueWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\function_values\src\main.e') $repo 'x64' 'windows' $functionValueExecutable
if ($LASTEXITCODE -ne 0 -or $functionValueWritten -ne 'executable written') { throw 'function value executable emission failed' }
& $functionValueExecutable
if ($LASTEXITCODE -ne 0) { throw 'function values as arguments, bindings or struct fields behaved wrongly' }
$functionValueArtifacts = Join-Path $testBuild 'function-values'
New-Item -ItemType Directory -Force -Path $functionValueArtifacts | Out-Null
$functionValueArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\function_values\src\main.e') $repo 'x64' 'windows' $functionValueArtifacts
if ($LASTEXITCODE -ne 0 -or $functionValueArtifactsWritten -ne 'compiled modules written') { throw 'function value artifact emission failed' }
$functionValueLinked = Join-Path $testBuild 'function-values-from-artifacts.exe'
$functionValueLinkWritten = & $compiler link-em $functionValueLinked (Join-Path $functionValueArtifacts 'main.x64-windows.em') (Join-Path $functionValueArtifacts 'ops.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $functionValueLinkWritten -ne 'artifact executable written') { throw 'function value compiled modules did not link' }
& $functionValueLinked
if ($LASTEXITCODE -ne 0) { throw 'executable linked from function value compiled modules failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $functionValueLinked).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $functionValueExecutable).Hash) { throw 'function value compiled-module and source links differ' }
$protocolExecutablePath = Join-Path $testBuild 'protocol-cmp-selfhost.exe'
$protocolWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\protocol_cmp\src\main.e') $repo 'x64' 'windows' $protocolExecutablePath
if ($LASTEXITCODE -ne 0 -or $protocolWritten -ne 'executable written') { throw 'protocol call executable emission failed' }
& $protocolExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'T.cmp did not resolve to each receiver type own protocol function' }
# An enum orders by its backing integer. Codegen sees only the named type, so a
# `u64` enum whose top member sets the sign bit orders backwards unless lowering
# resolves the backing type first.
$enumOrderingPath = Join-Path $testBuild 'enum-ordering-selfhost.exe'
$enumOrderingWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\enum_ordering\src\main.e') $repo 'x64' 'windows' $enumOrderingPath
if ($LASTEXITCODE -ne 0 -or $enumOrderingWritten -ne 'executable written') { throw 'enum ordering executable emission failed' }
& $enumOrderingPath
if ($LASTEXITCODE -ne 0) { throw 'enum ordering or the supplied enum cmp is wrong' }
# A negative member is the backing integer's two's complement at the backing
# width, so it has to compare, match and order like that integer.
$enumNegativePath = Join-Path $testBuild 'enum-negative-selfhost.exe'
$enumNegativeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\enum_negative\src\main.e') $repo 'x64' 'windows' $enumNegativePath
if ($LASTEXITCODE -ne 0 -or $enumNegativeWritten -ne 'executable written') { throw 'negative enum member executable emission failed' }
& $enumNegativePath
if ($LASTEXITCODE -ne 0) { throw 'a negative enum member compares, matches or orders wrongly' }
# Spec section 9 rule 4 recurses into arrays, slices and `str` in index order, and
# orders a matching prefix before the sequence that extends it.
$sequenceCmpPath = Join-Path $testBuild 'sequence-cmp-selfhost.exe'
$sequenceCmpWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\sequence_cmp\src\main.e') $repo 'x64' 'windows' $sequenceCmpPath
if ($LASTEXITCODE -ne 0 -or $sequenceCmpWritten -ne 'executable written') { throw 'sequence cmp executable emission failed' }
& $sequenceCmpPath
if ($LASTEXITCODE -ne 0) { throw 'the supplied cmp for an array, slice or str is wrong' }
# An element whose own module declares `fn <t>_cmp` is compared by calling it. The
# fixture's `tag_cmp` reverses deliberately, so any comparison that did not reach the
# declaration would order the other way, and the call has to carry a dependency edge.
$elementCmpPath = Join-Path $testBuild 'element-cmp-selfhost.exe'
$elementCmpWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\element_cmp\src\main.e') $repo 'x64' 'windows' $elementCmpPath
if ($LASTEXITCODE -ne 0 -or $elementCmpWritten -ne 'executable written') { throw 'declared element cmp executable emission failed' }
& $elementCmpPath
if ($LASTEXITCODE -ne 0) { throw 'a sequence did not compare its elements through their declared cmp' }
$elementCmpArtifacts = Join-Path $testBuild 'element-cmp-artifacts'
New-Item -ItemType Directory -Force -Path $elementCmpArtifacts | Out-Null
$elementCmpArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\element_cmp\src\main.e') $repo 'x64' 'windows' $elementCmpArtifacts
if ($LASTEXITCODE -ne 0 -or $elementCmpArtifactsWritten -ne 'compiled modules written') { throw 'declared element cmp artifact emission failed' }
$elementCmpEdge = & $compiler check-em-edge (Join-Path $elementCmpArtifacts 'main.x64-windows.em') (Join-Path $elementCmpArtifacts 'shapes.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $elementCmpEdge -ne 'dependency current') { throw 'the synthesized element cmp call recorded no dependency edge' }
$elementCmpLinked = Join-Path $testBuild 'element-cmp-from-artifacts.exe'
$elementCmpLinkWritten = & $compiler link-em $elementCmpLinked (Join-Path $elementCmpArtifacts 'main.x64-windows.em') (Join-Path $elementCmpArtifacts 'shapes.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $elementCmpLinkWritten -ne 'artifact executable written') { throw 'declared element cmp compiled modules did not link' }
& $elementCmpLinked
if ($LASTEXITCODE -ne 0) { throw 'executable linked from declared element cmp compiled modules failed' }
# Rule 4 orders a tagged union by its tag before the live payload, and a void arm is
# equal to itself once the tags match.
$taggedUnionCmpPath = Join-Path $testBuild 'tagged-union-cmp-selfhost.exe'
$taggedUnionCmpWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\tagged_union_cmp\src\main.e') $repo 'x64' 'windows' $taggedUnionCmpPath
if ($LASTEXITCODE -ne 0 -or $taggedUnionCmpWritten -ne 'executable written') { throw 'tagged union cmp executable emission failed' }
& $taggedUnionCmpPath
if ($LASTEXITCODE -ne 0) { throw 'a tagged union ordered its tag or its live payload wrongly' }
# The supplied `hash` is xxHash64 seed 0 over a value's canonical little-endian
# bytes, computed by the host runtime, and the fixture checks it against
# e.algo.hash.xxhash64 over those same bytes. The artifact link matters here as well:
# the call is the first host runtime symbol to reach the compiled-module linker.
$suppliedHashPath = Join-Path $testBuild 'supplied-hash-selfhost.exe'
$suppliedHashWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\supplied_hash\src\main.e') $repo 'x64' 'windows' $suppliedHashPath
if ($LASTEXITCODE -ne 0 -or $suppliedHashWritten -ne 'executable written') { throw 'supplied hash executable emission failed' }
& $suppliedHashPath
if ($LASTEXITCODE -ne 0) { throw 'the supplied hash disagrees with e.algo.hash.xxhash64' }
$suppliedHashArtifacts = Join-Path $testBuild 'supplied-hash-artifacts'
New-Item -ItemType Directory -Force -Path $suppliedHashArtifacts | Out-Null
$suppliedHashArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\supplied_hash\src\main.e') $repo 'x64' 'windows' $suppliedHashArtifacts
if ($LASTEXITCODE -ne 0 -or $suppliedHashArtifactsWritten -ne 'compiled modules written') { throw 'supplied hash artifact emission failed' }
$suppliedHashLinked = Join-Path $testBuild 'supplied-hash-from-artifacts.exe'
$suppliedHashLinkWritten = & $compiler link-em $suppliedHashLinked (Join-Path $suppliedHashArtifacts 'main.x64-windows.em') (Join-Path $suppliedHashArtifacts 'e.algo.hash.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $suppliedHashLinkWritten -ne 'artifact executable written') { throw 'supplied hash compiled modules did not link' }
& $suppliedHashLinked
if ($LASTEXITCODE -ne 0) { throw 'executable linked from supplied hash compiled modules failed' }
# Rule 4 supplies `eq` for the same shapes as `cmp` and adds pointers. The fixture's
# `pair_eq` compares one field of two deliberately, so a comparison that did not reach
# the declaration would call unequal pairs equal.
$suppliedEqPath = Join-Path $testBuild 'supplied-eq-selfhost.exe'
$suppliedEqWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\supplied_eq\src\main.e') $repo 'x64' 'windows' $suppliedEqPath
if ($LASTEXITCODE -ne 0 -or $suppliedEqWritten -ne 'executable written') { throw 'supplied eq executable emission failed' }
& $suppliedEqPath
if ($LASTEXITCODE -ne 0) { throw 'the supplied eq is wrong for a scalar, pointer, sequence, tagged union or declared component' }
# H06's semantic-law properties: supplied equality is reflexive, symmetric and
# transitive over a finite domain, and equal values always have equal hashes.
$protocolLawSuppliedPath = Join-Path $testBuild 'protocol-law-supplied-selfhost.exe'
$protocolLawSuppliedWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\protocol_law_supplied\src\main.e') $repo 'x64' 'windows' $protocolLawSuppliedPath
if ($LASTEXITCODE -ne 0 -or $protocolLawSuppliedWritten -ne 'executable written') { throw 'supplied protocol-law executable emission failed' }
& $protocolLawSuppliedPath
if ($LASTEXITCODE -ne 0) { throw 'a supplied equality or hash law failed' }
# The same harness accepts a coherent declared pair and detects an intentionally
# incoherent one, proving the property check is not vacuous.
$protocolLawDeclaredPath = Join-Path $testBuild 'protocol-law-declared-selfhost.exe'
$protocolLawDeclaredWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\protocol_law_declared\src\main.e') $repo 'x64' 'windows' $protocolLawDeclaredPath
if ($LASTEXITCODE -ne 0 -or $protocolLawDeclaredWritten -ne 'executable written') { throw 'declared protocol-law executable emission failed' }
& $protocolLawDeclaredPath
if ($LASTEXITCODE -ne 0) { throw 'the declared protocol-law harness failed' }
# Implicit dispatch and an explicit function strategy agree over the same task;
# a reverse strategy remains observably distinct across the module boundary.
$protocolStrategyPath = Join-Path $testBuild 'protocol-strategy-equivalence-selfhost.exe'
$protocolStrategyWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\protocol_strategy_equivalence\src\main.e') $repo 'x64' 'windows' $protocolStrategyPath
if ($LASTEXITCODE -ne 0 -or $protocolStrategyWritten -ne 'executable written') { throw 'protocol strategy equivalence executable emission failed' }
& $protocolStrategyPath
if ($LASTEXITCODE -ne 0) { throw 'implicit and explicit protocol strategies disagree' }
# A recursively forwarded strategy produces exactly 66 instances. One fewer is a
# structured budget refusal; the exact budget builds and executes.
$protocolRecursivePath = Join-Path $testBuild 'protocol-strategy-recursive-selfhost.exe'
$protocolRecursiveRejected = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\protocol_strategy_recursive\src\main.e') $repo 'x64' 'windows' $protocolRecursivePath --json --instances 65
$protocolRecursiveStatus = $LASTEXITCODE
if ($protocolRecursiveStatus -ne 1 -or ($protocolRecursiveRejected -join "`n") -notmatch '"code":"E-COMPTIME-0001"' -or ($protocolRecursiveRejected -join "`n") -notmatch '66 instances.*budget of 65') { throw 'recursive strategy specialization did not honor its instance budget' }
$protocolRecursiveWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\protocol_strategy_recursive\src\main.e') $repo 'x64' 'windows' $protocolRecursivePath --instances 66
if ($LASTEXITCODE -ne 0 -or $protocolRecursiveWritten -ne 'executable written') { throw 'recursive strategy executable emission failed at its exact budget' }
& $protocolRecursivePath
if ($LASTEXITCODE -ne 0) { throw 'recursive strategy specialization computed the wrong result' }
# A value whose bytes are not contiguous folds one hash per component instead of
# hashing one run. The fixture pins that the contiguous path is unchanged, that equal
# contents through different storage agree, and that regrouping the same flat bytes
# does not collide.
$foldedHashPath = Join-Path $testBuild 'folded-hash-selfhost.exe'
$foldedHashWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\folded_hash\src\main.e') $repo 'x64' 'windows' $foldedHashPath
if ($LASTEXITCODE -ne 0 -or $foldedHashWritten -ne 'executable written') { throw 'folded hash executable emission failed' }
& $foldedHashPath
if ($LASTEXITCODE -ne 0) { throw 'the folded hash is wrong for a nested slice or a tagged union' }
# `mem.view` is the one arena intrinsic emitted where it is called rather than
# through a runtime symbol. It must alias storage the caller already owns.
$memViewPath = Join-Path $testBuild 'mem-view-selfhost.exe'
$memViewWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\mem_view\src\main.e') $repo 'x64' 'windows' $memViewPath
if ($LASTEXITCODE -ne 0 -or $memViewWritten -ne 'executable written') { throw 'mem.view executable emission failed' }
& $memViewPath
if ($LASTEXITCODE -ne 0) { throw 'mem.view did not alias the arena storage it was given' }
# `mem.cast` is the only route between pointer types, and the only route to `*void`
# at all. It must retype without moving: the address in is the address out.
$memCastPath = Join-Path $testBuild 'mem-cast-selfhost.exe'
$memCastWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\mem_cast\src\main.e') $repo 'x64' 'windows' $memCastPath
if ($LASTEXITCODE -ne 0 -or $memCastWritten -ne 'executable written') { throw 'mem.cast executable emission failed' }
& $memCastPath
if ($LASTEXITCODE -ne 0) { throw 'mem.cast did not give back the pointer it was handed' }
# The builder owns the top of an arena and grows in place. The fixture pins that the
# initial reservation is not a limit, that a foreign allocation turns the next push
# into `str.NotOnTop` rather than an overwrite, that `done` gives the unwritten tail
# back, that every integer form writes what its verb writes, and that a builder with
# a sink drains through it instead of reporting `mem.Exhausted`.
$strBuilderPath = Join-Path $testBuild 'str-builder-selfhost.exe'
$strBuilderWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_builder\src\main.e') $repo 'x64' 'windows' $strBuilderPath
if ($LASTEXITCODE -ne 0 -or $strBuilderWritten -ne 'executable written') { throw 'str builder executable emission failed' }
& $strBuilderPath
if ($LASTEXITCODE -ne 0) { throw 'the string builder or one of its pushes is wrong' }
# Each generator in `e.algo.rand` is a named published algorithm, so the fixture
# checks its stream against a separate implementation of the reference rather than
# against a property. A near miss is the failure worth catching here.
$randPath = Join-Path $testBuild 'algo-rand-selfhost.exe'
$randWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_rand\src\main.e') $repo 'x64' 'windows' $randPath
if ($LASTEXITCODE -ne 0 -or $randWritten -ne 'executable written') { throw 'rand executable emission failed' }
& $randPath
if ($LASTEXITCODE -ne 0) { throw 'a generator does not match its reference stream' }
# Section 4's formatter is checked against its format string: a call whose arity or
# argument types do not match is a compile error, not a runtime one. The expansion
# is not written yet, so these are check fixtures rather than link ones.
$formatAccepted = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\format_accept\src\main.e") $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $formatAccepted -ne 'module check ok') { throw 'a well-formed formatter call was rejected' }
foreach ($formatCase in @('format_too_few', 'format_too_many', 'format_no_arena', 'format_printf_arena', 'format_hex_float', 'format_binary_str', 'format_precision_integer', 'format_unknown_verb', 'format_unterminated', 'format_precision_wide', 'format_not_literal', 'format_untyped')) {
    & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$formatCase\src\main.e") $repo 'x64' 'windows' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 1) { throw "formatter fixture $formatCase was accepted" }
}
# `os.seek` is the first `e.os` intrinsic added since the runtime blobs were
# frozen, so this also exercises a twenty-second kernel32 import and the offsets
# that shift with it. The file it works in is passed as an argument.
$seekPath = Join-Path $testBuild 'os-seek-selfhost.exe'
$seekWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_seek\src\main.e') $repo 'x64' 'windows' $seekPath
if ($LASTEXITCODE -ne 0 -or $seekWritten -ne 'executable written') { throw 'os.seek executable emission failed' }
$seekFile = Join-Path $testBuild 'os-seek-output.txt'
Remove-Item -LiteralPath $seekFile -ErrorAction SilentlyContinue
& $seekPath $seekFile
if ($LASTEXITCODE -ne 0) { throw 'os.seek did not move the cursor where it said it did' }
if ((Get-Item -LiteralPath $seekFile).Length -ne 11) { throw 'seeking past the end extended the file' }
# `os.dup` (D349): a second identity for an open file, sharing its offset, closed on
# its own.
$dupPath = Join-Path $testBuild 'os-dup-selfhost.exe'
$dupWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_dup\src\main.e') $repo 'x64' 'windows' $dupPath
if ($LASTEXITCODE -ne 0 -or $dupWritten -ne 'executable written') { throw 'os.dup executable emission failed' }
$dupFile = Join-Path $testBuild 'os-dup-output.txt'
Remove-Item -LiteralPath $dupFile -ErrorAction SilentlyContinue
& $dupPath $dupFile
if ($LASTEXITCODE -ne 0) { throw 'os.dup did not hand back a second handle over the same file' }
# A comptime `str` parameter binds a string literal where the call is written, so
# each distinct literal is its own instance and the body reads it as an ordinary
# `str`.
$comptimeStrPath = Join-Path $testBuild 'comptime-str-selfhost.exe'
$comptimeStrWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\comptime_str\src\main.e') $repo 'x64' 'windows' $comptimeStrPath
if ($LASTEXITCODE -ne 0 -or $comptimeStrWritten -ne 'executable written') { throw 'comptime str executable emission failed' }
& $comptimeStrPath
if ($LASTEXITCODE -ne 0) { throw 'a comptime string was bound or instantiated wrongly' }
# Only a string literal can bind one, and it binds nothing else.
foreach ($comptimeStrCase in @('comptime_str_runtime', 'comptime_str_integer', 'comptime_str_type', 'comptime_str_for_usize')) {
    $comptimeStrOutput = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$comptimeStrCase\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1) { throw "comptime string fixture $comptimeStrCase was accepted" }
}
# `type` is a compile-time parameter kind, not something a struct field can hold. The
# report has to name the field, because a location-less failure is what this was.
& $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\field_type_keyword\src\main.e') $repo 'x64' 'windows' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 1) { throw 'a field typed `type` was accepted' }
# `@cc(CONV)` names a calling convention. Its argument parses as an expression but is
# not a value, and resolving it as one reported `unknown value name` at every `@cc`.
$ccAccepted = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\cc_accepted\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $ccAccepted -ne 'module check ok') { throw 'a named calling convention was rejected' }
& $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\cc_unknown\src\main.e') $repo 'x64' 'windows' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 1) { throw 'an unknown calling convention was accepted' }
# `os.thread_create` / `join` / `detach`. Windows runs a real thread; Linux answers
# `Unsupported` for now, the ELF output being static with no libc to get one from.
$osThreadPath = Join-Path $testBuild 'os-thread-selfhost.exe'
$osThreadWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_thread\src\main.e') $repo 'x64' 'windows' $osThreadPath
if ($LASTEXITCODE -ne 0 -or $osThreadWritten -ne 'executable written') { throw 'os thread emission failed' }
& $osThreadPath
if ($LASTEXITCODE -ne 0) { throw 'a thread did not run, join, or detach correctly' }
# `e.meta`'s scalar reflection. Section 9 keeps all of it at compile time, so each
# call is a constant by the time lowering sees it and the binary carries no type
# information at all.
$metaPath = Join-Path $testBuild 'meta-scalar-selfhost.exe'
$metaWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\meta_scalar\src\main.e') $repo 'x64' 'windows' $metaPath
if ($LASTEXITCODE -ne 0 -or $metaWritten -ne 'executable written') { throw 'meta reflection emission failed' }
& $metaPath
if ($LASTEXITCODE -ne 0) { throw 'a reflected type answer was wrong' }
# `e.io`'s streams: a reader and a writer are a context and a callback, so every
# adapter is a value the caller owns. The callbacks the constructors install are
# ordinary declarations (D94), which is what let the module be written at all.
$ioStreamsPath = Join-Path $testBuild 'io-streams-selfhost.exe'
$ioStreamsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\io_streams\src\main.e') $repo 'x64' 'windows' $ioStreamsPath
if ($LASTEXITCODE -ne 0 -or $ioStreamsWritten -ne 'executable written') { throw 'io streams emission failed' }
& $ioStreamsPath
if ($LASTEXITCODE -ne 0) { throw 'an e.io stream adapter behaved wrongly' }
# `io.printf[FMT]` is `format` over a buffer of its own, drained through a generated
# sink. Its output is compared byte for byte against a file written from the format
# strings, so the line that outgrows the 4 KiB buffer pins that the drains and the
# final write agree about where they are.
$printfPath = Join-Path $testBuild 'io-printf-selfhost.exe'
$printfWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\io_printf\src\main.e') $repo 'x64' 'windows' $printfPath
if ($LASTEXITCODE -ne 0 -or $printfWritten -ne 'executable written') { throw 'printf executable emission failed' }
$printfOutput = Join-Path $testBuild 'io-printf-output.txt'
$printfRun = Start-Process -FilePath $printfPath -RedirectStandardOutput $printfOutput -NoNewWindow -Wait -PassThru
if ($printfRun.ExitCode -ne 0) { throw 'printf returned an error' }
$printfActual = [System.IO.File]::ReadAllBytes($printfOutput)
$printfExpected = [System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'fixtures\link\io_printf\expected.txt'))
if (-not [System.Linq.Enumerable]::SequenceEqual($printfActual, $printfExpected)) { throw 'printf wrote the wrong bytes' }
# `push_err` writes an error's qualified name. It is the one `e.str` declaration a
# library cannot write: the answer is the merged error table, which is a property of
# the whole program rather than of any one module.
$pushErrPath = Join-Path $testBuild 'str-push-err-selfhost.exe'
$pushErrWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_push_err\src\main.e') $repo 'x64' 'windows' $pushErrPath
if ($LASTEXITCODE -ne 0 -or $pushErrWritten -ne 'executable written') { throw 'push_err executable emission failed' }
& $pushErrPath
if ($LASTEXITCODE -ne 0) { throw 'an error name was written wrongly' }
# A flushing builder over a stack arena: the shape `printf` expands to, and the only
# thing that exercises `builder_to`'s drain. Pushing several times the arena's size
# through it proves the drain happens during the pushes, not once at the end.
$flushPath = Join-Path $testBuild 'str-flush-selfhost.exe'
$flushWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_flush\src\main.e') $repo 'x64' 'windows' $flushPath
if ($LASTEXITCODE -ne 0 -or $flushWritten -ne 'executable written') { throw 'flushing builder emission failed' }
& $flushPath
if ($LASTEXITCODE -ne 0) { throw 'a flushing builder dropped or duplicated bytes' }
# `str.format[FMT]` expands to a generated function: a builder, a push per piece of
# the format string, and `done`. The fixture compares its output against the same
# pushes written by hand.
$formatPath = Join-Path $testBuild 'str-format-selfhost.exe'
$formatWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_format\src\main.e') $repo 'x64' 'windows' $formatPath
if ($LASTEXITCODE -ne 0 -or $formatWritten -ne 'executable written') { throw 'format executable emission failed' }
& $formatPath
if ($LASTEXITCODE -ne 0) { throw 'a format string expanded to the wrong pushes' }
# A struct whose module declares no format has nothing rule 4 supplies and nothing to
# call, so the build stops rather than quietly formatting nothing (D189-D191 cover
# what is formattable).
$formatRejectPath = Join-Path $testBuild 'format-compound-argument.exe'
& $compiler emit-executable (Join-Path $repo 'tests\selfhost\fixtures\check\format_compound_argument\src\main.e') $repo 'x64' 'windows' $formatRejectPath 2>&1 | Out-Null
if ($LASTEXITCODE -ne 1) { throw 'a format verb with no push was lowered' }
# `e.algo.uuid` reads no clock and no random source, so a UUID is a pure function of
# its inputs and the fixture can pin the exact text of one.
$uuidPath = Join-Path $testBuild 'algo-uuid-selfhost.exe'
$uuidWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_uuid\src\main.e') $repo 'x64' 'windows' $uuidPath
if ($LASTEXITCODE -ne 0 -or $uuidWritten -ne 'executable written') { throw 'uuid executable emission failed' }
& $uuidPath
if ($LASTEXITCODE -ne 0) { throw 'a UUID was built, parsed or formatted wrongly' }
# The float pushes: `{}` writes the shortest string that reads back as the same value,
# `{.N}` exactly N digits after the point. The fixture checks the text against an
# independent implementation and reads every shortest case back through the parser.
$pushFloatPath = Join-Path $testBuild 'str-push-float-selfhost.exe'
$pushFloatWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_push_float\src\main.e') $repo 'x64' 'windows' $pushFloatPath
if ($LASTEXITCODE -ne 0 -or $pushFloatWritten -ne 'executable written') { throw 'float push executable emission failed' }
& $pushFloatPath
if ($LASTEXITCODE -ne 0) { throw 'a float push wrote the wrong digits, notation or precision' }
# `parse_f64` and `parse_f32` are the inverse of the float pushes and accept nothing
# else. The fixture pins the grammar, the non-finite tokens, both range ends and the
# exact ties, against bit patterns produced by rounding an exact rational.
$parseFloatPath = Join-Path $testBuild 'str-parse-float-selfhost.exe'
$parseFloatWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_parse_float\src\main.e') $repo 'x64' 'windows' $parseFloatPath
if ($LASTEXITCODE -ne 0 -or $parseFloatWritten -ne 'executable written') { throw 'float parse executable emission failed' }
& $parseFloatPath
if ($LASTEXITCODE -ne 0) { throw 'a float parse rounded, rejected or accepted the wrong way' }
# `mem.bitcast` reads a value's bytes as another type of the same size, which is what
# lets a pun avoid a `union`. A scalar lives in a register and an aggregate is an
# address, so the fixture covers all four shapes as well as the bit patterns.
$bitcastPath = Join-Path $testBuild 'mem-bitcast-selfhost.exe'
$bitcastWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\mem_bitcast\src\main.e') $repo 'x64' 'windows' $bitcastPath
if ($LASTEXITCODE -ne 0 -or $bitcastWritten -ne 'executable written') { throw 'mem.bitcast executable emission failed' }
& $bitcastPath
if ($LASTEXITCODE -ne 0) { throw 'mem.bitcast changed a value''s bytes or lost a shape' }
# `mem.address_of` is the one way a pointer becomes a number. Where the arena lands is
# not knowable from inside the program, so the fixture checks what an address has to
# satisfy whatever it is: distances that follow the element size, field offsets,
# alignment, and the same answer for one place reached two ways.
$addressPath = Join-Path $testBuild 'mem-address-selfhost.exe'
$addressWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\mem_address\src\main.e') $repo 'x64' 'windows' $addressPath
if ($LASTEXITCODE -ne 0 -or $addressWritten -ne 'executable written') { throw 'mem.address_of executable emission failed' }
& $addressPath
if ($LASTEXITCODE -ne 0) { throw "mem.address_of gave an address that is not the place's: exit $LASTEXITCODE" }
# `e.os`'s filesystem primitives and `e.fs` over them, on a real filesystem. The
# primitives are the per-target half -- `os.syscall` on Linux, `kernel32` through
# `@import` on Windows -- so the same two fixtures run on both hosts and what they
# assert is that the two spellings answer alike. Both use relative paths, so they run
# with the build directory as the working directory and write nothing outside it.
$fsScratch = Join-Path $testBuild 'fs-scratch'
New-Item -ItemType Directory -Force -Path $fsScratch | Out-Null
$osFsPath = Join-Path $testBuild 'os-fs-selfhost.exe'
$osFsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/os_fs/src/main.e') $repo 'x64' 'windows' $osFsPath
if ($LASTEXITCODE -ne 0 -or $osFsWritten -ne 'executable written') { throw 'e.os filesystem primitive emission failed' }
Push-Location $fsScratch
& $osFsPath
$osFsExit = $LASTEXITCODE
Pop-Location
if ($osFsExit -ne 0) { throw "an e.os filesystem primitive answered wrongly: exit $osFsExit" }
$fsBasicsPath = Join-Path $testBuild 'fs-basics-selfhost.exe'
$fsBasicsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/fs_basics/src/main.e') $repo 'x64' 'windows' $fsBasicsPath
if ($LASTEXITCODE -ne 0 -or $fsBasicsWritten -ne 'executable written') { throw 'e.fs executable emission failed' }
$crossVolumeDir = $null
$crossVolumeCandidates = @([IO.Path]::GetTempPath(), (Join-Path $env:LOCALAPPDATA 'Temp'))
foreach ($candidate in $crossVolumeCandidates) {
    if ((Test-Path $candidate) -and ([IO.Path]::GetPathRoot($candidate) -ne [IO.Path]::GetPathRoot($fsScratch))) {
        $crossVolumeDir = $candidate
        break
    }
}
$previousCrossVolumeDir = $env:NEPER_CROSS_VOLUME_DIR
if ($null -ne $crossVolumeDir) {
    $env:NEPER_CROSS_VOLUME_DIR = $crossVolumeDir
} else {
    Remove-Item Env:NEPER_CROSS_VOLUME_DIR -ErrorAction SilentlyContinue
}
Push-Location $fsScratch
& $fsBasicsPath
$fsBasicsExit = $LASTEXITCODE
Pop-Location
if ($null -eq $previousCrossVolumeDir) {
    Remove-Item Env:NEPER_CROSS_VOLUME_DIR -ErrorAction SilentlyContinue
} else {
    $env:NEPER_CROSS_VOLUME_DIR = $previousCrossVolumeDir
}
if ($fsBasicsExit -ne 0) { throw "e.fs answered wrongly: exit $fsBasicsExit" }
# `e.proc` against a real child, which is the fixture's own image. Besides the legacy output
# path, `run` checks independent limits, pre-start cancellation, a live contained deadline,
# explicit outcomes, invalid grace, retained writers and the complete forced-shutdown grace.
$procPath = Join-Path $testBuild 'proc-output-selfhost.exe'
$procWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\proc_output\src\main.e') $repo 'x64' 'windows' $procPath
if ($LASTEXITCODE -ne 0 -or $procWritten -ne 'executable written') { throw 'e.proc emission failed' }
& $procPath
if ($LASTEXITCODE -ne 0) { throw "an e.proc child answered wrongly: exit $LASTEXITCODE" }
# `e.thread` over `e.os`'s three intrinsics: spawned and joined, the work in the context it
# was given, a zero stack meaning the default, and `Thread` being `os.Thread` in every respect.
$threadSpawnPath = Join-Path $testBuild 'thread-spawn-selfhost.exe'
$threadSpawnWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\thread_spawn\src\main.e') $repo 'x64' 'windows' $threadSpawnPath
if ($LASTEXITCODE -ne 0 -or $threadSpawnWritten -ne 'executable written') { throw 'e.thread emission failed' }
& $threadSpawnPath
if ($LASTEXITCODE -ne 0) { throw "an e.thread answer is wrong: exit $LASTEXITCODE" }
# `e.test`'s four assertions, each in both directions, and `eq` across every kind rule 4
# supplies equality for -- the floats now among them, under the container rule.
$testAssertPath = Join-Path $testBuild 'test-assert-selfhost.exe'
$testAssertWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\test_assert\src\main.e') $repo 'x64' 'windows' $testAssertPath
if ($LASTEXITCODE -ne 0 -or $testAssertWritten -ne 'executable written') { throw 'e.test emission failed' }
& $testAssertPath
if ($LASTEXITCODE -ne 0) { throw "an e.test assertion answered wrongly: exit $LASTEXITCODE" }
# `e.data.map`: open addressing with linear probing, keyed by anything with a `hash` and an
# `eq`. The fixture fills past several doublings, removes from the middle so that keys placed
# past a hole must still be reached through the dead slot, reinserts into it, and iterates.
$dataMapPath = Join-Path $testBuild 'data-map-selfhost.exe'
$dataMapWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_map\src\main.e') $repo 'x64' 'windows' $dataMapPath
if ($LASTEXITCODE -ne 0 -or $dataMapWritten -ne 'executable written') { throw 'e.data.map emission failed' }
& $dataMapPath
if ($LASTEXITCODE -ne 0) { throw "an e.data.map answer is wrong: exit $LASTEXITCODE" }
# A function selected in brackets is a compile-time strategy and part of the
# specialization identity: two choices make two direct-call bodies.
$comptimeFunctionPath = Join-Path $testBuild 'comptime-function-strategy-selfhost.exe'
$comptimeFunctionWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\comptime_function_strategy\src\main.e') $repo 'x64' 'windows' $comptimeFunctionPath
if ($LASTEXITCODE -ne 0 -or $comptimeFunctionWritten -ne 'executable written') { throw 'comptime function strategy emission failed' }
& $comptimeFunctionPath
if ($LASTEXITCODE -ne 0) { throw "a comptime function strategy answered wrongly: exit $LASTEXITCODE" }
# `e.bytes`: numbers through bytes in both orders and every width, the bit operations, and
# base64, base32 and base85 against the vectors their RFCs print, then every byte value round
# tripped through each. One generic `load` serves every width because `size_of` folds for a
# scalar, so the arm for the other width is gone rather than merely not taken.
$bytesPath = Join-Path $testBuild 'bytes-codec-selfhost.exe'
$bytesWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\bytes_codec\src\main.e') $repo 'x64' 'windows' $bytesPath
if ($LASTEXITCODE -ne 0 -or $bytesWritten -ne 'executable written') { throw 'e.bytes emission failed' }
& $bytesPath
if ($LASTEXITCODE -ne 0) { throw "an e.bytes answer is wrong: exit $LASTEXITCODE" }
# `e.data.iter`: every adapter over a list's iterator, stacked two and three deep, every fold
# to its end or its first answer, and the `try_` family over a source that fails where it is
# told to. It also pins the nested-instance annotation that misread its arguments (D145).
$dataIterPath = Join-Path $testBuild 'data-iter-selfhost.exe'
$dataIterWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_iter\src\main.e') $repo 'x64' 'windows' $dataIterPath
if ($LASTEXITCODE -ne 0 -or $dataIterWritten -ne 'executable written') { throw 'e.data.iter emission failed' }
& $dataIterPath
if ($LASTEXITCODE -ne 0) { throw "an e.data.iter answer is wrong: exit $LASTEXITCODE" }
# `e.math`'s exact set: `sqrt` as the instruction, correctly rounded on both widths and checked
# by its bits, and the rounders, `abs`, `copysign`, `min` and `max` as source. Exact means
# bit-for-bit, so `-0` and `+0` are told apart wherever a sign could hide.
$mathPath = Join-Path $testBuild 'math-exact-selfhost.exe'
$mathWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\math_exact\src\main.e') $repo 'x64' 'windows' $mathPath
if ($LASTEXITCODE -ne 0 -or $mathWritten -ne 'executable written') { throw 'e.math emission failed' }
& $mathPath
if ($LASTEXITCODE -ne 0) { throw "an e.math answer is wrong: exit $LASTEXITCODE" }
# `exp`, `exp2`, `log`, `log2` and `log10` against mpmath at 200 bits: within 1 ULP of the correctly rounded answer at every input, the reductions and the subnormal results included.
$mathExpLogPath = Join-Path $testBuild 'math-exp-log-selfhost.exe'
$mathExpLogWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\math_exp_log\src\main.e') $repo 'x64' 'windows' $mathExpLogPath
if ($LASTEXITCODE -ne 0 -or $mathExpLogWritten -ne 'executable written') { throw 'math_exp_log emission failed' }
& $mathExpLogPath
if ($LASTEXITCODE -ne 0) { throw "an e.math answer is outside its bound: exit $LASTEXITCODE" }
# `atan`, `atan2`, `asin` and `acos` against the same reference, on every fold point and every signed zero and infinity IEEE assigns a quadrant to.
$mathInversePath = Join-Path $testBuild 'math-inverse-selfhost.exe'
$mathInverseWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\math_inverse\src\main.e') $repo 'x64' 'windows' $mathInversePath
if ($LASTEXITCODE -ne 0 -or $mathInverseWritten -ne 'executable written') { throw 'math_inverse emission failed' }
& $mathInversePath
if ($LASTEXITCODE -ne 0) { throw "an e.math answer is outside its bound: exit $LASTEXITCODE" }
# `sin`, `cos` and `tan` against the same reference, through the direct kernel, the Cody-Waite reduction and the Payne-Hanek one, on the double that cancels the most bits of any.
$mathTrigPath = Join-Path $testBuild 'math-trig-selfhost.exe'
$mathTrigWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\math_trig\src\main.e') $repo 'x64' 'windows' $mathTrigPath
if ($LASTEXITCODE -ne 0 -or $mathTrigWritten -ne 'executable written') { throw 'math_trig emission failed' }
& $mathTrigPath
if ($LASTEXITCODE -ne 0) { throw "an e.math answer is outside its bound: exit $LASTEXITCODE" }
# `pow` against the same reference and the whole of section 11's special-value table, plus one value through each single-precision wrapper.
$mathPowPath = Join-Path $testBuild 'math-pow-selfhost.exe'
$mathPowWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\math_pow\src\main.e') $repo 'x64' 'windows' $mathPowPath
if ($LASTEXITCODE -ne 0 -or $mathPowWritten -ne 'executable written') { throw 'math_pow emission failed' }
& $mathPowPath
if ($LASTEXITCODE -ne 0) { throw "an e.math answer is outside its bound: exit $LASTEXITCODE" }
# `e.simd` over the two builtins: the closed table's layout, every intrinsic but `shuffle` on
# integer and float lanes, the pairwise reduction order, masked loads at a slice's tail, and
# `pdep`/`pext` against their definitions.
$simdLanesPath = Join-Path $testBuild 'simd-lanes-selfhost.exe'
$simdLanesWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\simd_lanes\src\main.e') $repo 'x64' 'windows' $simdLanesPath
if ($LASTEXITCODE -ne 0 -or $simdLanesWritten -ne 'executable written') { throw 'simd_lanes emission failed' }
& $simdLanesPath
if ($LASTEXITCODE -ne 0) { throw "an e.simd check failed: exit $LASTEXITCODE" }
# The same fixture under `--cpu x64-v3` (D765): every thirty-two-byte vector is one
# AVX2 instruction over a ymm register, the VEX forms of the same selection, in debug
# and in release; the suite's hosts have AVX2. The manifest names the level.
foreach ($avxMode in @(@('debug', @()), @('release', @('--release')))) {
    $avxPath = Join-Path $testBuild "simd-lanes-v3-$($avxMode[0]).exe"
    $avxWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\simd_lanes\src\main.e') $repo 'x64' 'windows' $avxPath --cpu x64-v3 @($avxMode[1])
    if ($LASTEXITCODE -ne 0 -or $avxWritten -ne 'executable written') { throw "simd_lanes emission under --cpu x64-v3 failed ($($avxMode[0]))" }
    & $avxPath
    if ($LASTEXITCODE -ne 0) { throw "an e.simd check failed under --cpu x64-v3 ($($avxMode[0])): exit $LASTEXITCODE" }
}
& $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\simd_lanes\src\main.e') $repo 'x64' 'windows' (Join-Path $testBuild 'simd-lanes-v9.exe') --cpu x64-v9 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { throw 'a level the build does not have was accepted' }
# A module-scope `var` is storage: a function that writes and another that reads agree, and each
# global keeps its own width. Never wired when it was written (849fa5b), and on Windows it did not
# link until D150 -- a global's index was bounded against the function references.
$moduleVarPath = Join-Path $testBuild 'module-var-selfhost.exe'
$moduleVarWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\module_var\src\main.e') $repo 'x64' 'windows' $moduleVarPath
if ($LASTEXITCODE -ne 0 -or $moduleVarWritten -ne 'executable written') { throw 'module_var emission failed' }
& $moduleVarPath
if ($LASTEXITCODE -ne 0) { throw "a module-scope var answer is wrong: exit $LASTEXITCODE" }
# And from `.em` artifacts: `module_var` reaches `e.os`, whose per-target variants hold the
# module-scope `var`s the format learned to carry (D154), and the link stays quick because the
# reach walk reads each module once rather than re-validating it per function (D155).
$moduleVarArtifacts = Join-Path $testBuild 'module-var-artifacts'
New-Item -ItemType Directory -Force -Path $moduleVarArtifacts | Out-Null
$moduleVarArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\module_var\src\main.e') $repo 'x64' 'windows' $moduleVarArtifacts
if ($LASTEXITCODE -ne 0 -or $moduleVarArtifactsWritten -ne 'compiled modules written') { throw 'module_var artifact emission failed' }
$moduleVarLinked = Join-Path $testBuild 'module-var-from-artifacts.exe'
$moduleVarLinkWritten = & $compiler link-em $moduleVarLinked (Join-Path $moduleVarArtifacts 'main.x64-windows.em') (Join-Path $moduleVarArtifacts 'e.mem.x64-windows.em') (Join-Path $moduleVarArtifacts 'e.os.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $moduleVarLinkWritten -ne 'artifact executable written') { throw 'module_var compiled modules did not link' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $moduleVarLinked).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $moduleVarPath).Hash) { throw 'module_var links differently from artifacts than from source' }
& $moduleVarLinked
if ($LASTEXITCODE -ne 0) { throw "a module-scope var answer is wrong from artifacts: exit $LASTEXITCODE" }
# `main` declaring `args` receives the command line whether the image was linked from source or
# from `.em` artifacts, and a quoted argument arrives whole. The root artifact goes first: the
# linker finds `main` in module 0, which is whichever artifact is named first.
$mainArgsPath = Join-Path $testBuild 'main-args-selfhost.exe'
$mainArgsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\main_args\src\main.e') $repo 'x64' 'windows' $mainArgsPath
if ($LASTEXITCODE -ne 0 -or $mainArgsWritten -ne 'executable written') { throw 'main_args emission failed' }
& $mainArgsPath one 'two words'
if ($LASTEXITCODE -ne 0) { throw 'main did not receive its arguments from source' }
$mainArgsArtifacts = Join-Path $testBuild 'main-args-artifacts'
New-Item -ItemType Directory -Force -Path $mainArgsArtifacts | Out-Null
$mainArgsArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\main_args\src\main.e') $repo 'x64' 'windows' $mainArgsArtifacts
if ($LASTEXITCODE -ne 0 -or $mainArgsArtifactsWritten -ne 'compiled modules written') { throw 'main_args artifact emission failed' }
$mainArgsLinked = Join-Path $testBuild 'main-args-from-artifacts.exe'
$mainArgsLinkWritten = & $compiler link-em $mainArgsLinked (Join-Path $mainArgsArtifacts 'main.x64-windows.em') (Join-Path $mainArgsArtifacts 'e.mem.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $mainArgsLinkWritten -ne 'artifact executable written') { throw 'main_args compiled modules did not link' }
& $mainArgsLinked one 'two words'
if ($LASTEXITCODE -ne 0) { throw 'main did not receive its arguments from artifacts' }
# A module-scope `var` links the same from source and from `.em` artifacts (D154): the format
# carries a section for it and a code relocation says which of a function or a var it names.
# This one imports nothing, so its single artifact links at once.
$globalArtifactPath = Join-Path $testBuild 'global-artifact-selfhost.exe'
$globalArtifactWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\global_artifact\src\main.e') $repo 'x64' 'windows' $globalArtifactPath
if ($LASTEXITCODE -ne 0 -or $globalArtifactWritten -ne 'executable written') { throw 'global_artifact emission failed' }
& $globalArtifactPath
if ($LASTEXITCODE -ne 0) { throw 'a module-scope var answer is wrong from source' }
$globalArtifacts = Join-Path $testBuild 'global-artifact'
New-Item -ItemType Directory -Force -Path $globalArtifacts | Out-Null
$globalArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\global_artifact\src\main.e') $repo 'x64' 'windows' $globalArtifacts
if ($LASTEXITCODE -ne 0 -or $globalArtifactsWritten -ne 'compiled modules written') { throw 'global_artifact artifact emission failed' }
$globalArtifactLinked = Join-Path $testBuild 'global-artifact-from-artifacts.exe'
$globalArtifactLinkWritten = & $compiler link-em $globalArtifactLinked (Join-Path $globalArtifacts 'main.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $globalArtifactLinkWritten -ne 'artifact executable written') { throw 'global_artifact compiled module did not link' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $globalArtifactLinked).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $globalArtifactPath).Hash) { throw 'a module-scope var links differently from artifacts than from source' }
& $globalArtifactLinked
if ($LASTEXITCODE -ne 0) { throw 'a module-scope var answer is wrong from artifacts' }
# `e.data.stack` and `e.data.queue` over their storage modules, and `e.algo.disjoint_set`
# on caller storage: order, peek, non-mutating iteration, growth, and union-find with path
# compression and union by rank.
$dataAdaptersPath = Join-Path $testBuild 'data-adapters-selfhost.exe'
$dataAdaptersWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_adapters\src\main.e') $repo 'x64' 'windows' $dataAdaptersPath
if ($LASTEXITCODE -ne 0 -or $dataAdaptersWritten -ne 'executable written') { throw 'data_adapters emission failed' }
& $dataAdaptersPath
if ($LASTEXITCODE -ne 0) { throw "a data adapter check failed: exit $LASTEXITCODE" }
# `e.algo.stat` against closed-form moments and a least-squares line, and `e.data.slot_map`'s
# generational keys: stale after removal, reused with the next generation, retired at the last.
$statSlotsPath = Join-Path $testBuild 'stat-slots-selfhost.exe'
$statSlotsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\stat_slots\src\main.e') $repo 'x64' 'windows' $statSlotsPath
if ($LASTEXITCODE -ne 0 -or $statSlotsWritten -ne 'executable written') { throw 'stat_slots emission failed' }
& $statSlotsPath
if ($LASTEXITCODE -ne 0) { throw "a stat or slot_map check failed: exit $LASTEXITCODE" }
# `e.data.linked`: stable node identifiers through insertion at both ends and beside a node,
# removal that never reuses one, and `clear` invalidating every identifier.
$dataLinkedPath = Join-Path $testBuild 'data-linked-selfhost.exe'
$dataLinkedWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_linked\src\main.e') $repo 'x64' 'windows' $dataLinkedPath
if ($LASTEXITCODE -ne 0 -or $dataLinkedWritten -ne 'executable written') { throw 'data_linked emission failed' }
& $dataLinkedPath
if ($LASTEXITCODE -ne 0) { throw "a linked-list check failed: exit $LASTEXITCODE" }
# `e.data.graph`: CSR adjacency from a builder, insertion order kept, undirected edges as two.
$dataGraphPath = Join-Path $testBuild 'data-graph-selfhost.exe'
$dataGraphWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_graph\src\main.e') $repo 'x64' 'windows' $dataGraphPath
if ($LASTEXITCODE -ne 0 -or $dataGraphWritten -ne 'executable written') { throw 'data_graph emission failed' }
& $dataGraphPath
if ($LASTEXITCODE -ne 0) { throw "a data_graph check failed: exit $LASTEXITCODE" }
# `e.algo.graph`: BFS, DFS, topological order and its Cycle, weak and strong components, Dijkstra.
$algoGraphPath = Join-Path $testBuild 'algo-graph-selfhost.exe'
$algoGraphWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_graph\src\main.e') $repo 'x64' 'windows' $algoGraphPath
if ($LASTEXITCODE -ne 0 -or $algoGraphWritten -ne 'executable written') { throw 'algo_graph emission failed' }
& $algoGraphPath
if ($LASTEXITCODE -ne 0) { throw "a algo_graph check failed: exit $LASTEXITCODE" }
# `e.data.tree`: an ordered map as a treap keyed by hash priority: ascending iteration, bounds,
# removal with reuse, clear, a set of strings, and two thousand keys.
$dataTreePath = Join-Path $testBuild 'data-tree-selfhost.exe'
$dataTreeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_tree\src\main.e') $repo 'x64' 'windows' $dataTreePath
if ($LASTEXITCODE -ne 0 -or $dataTreeWritten -ne 'executable written') { throw 'data_tree emission failed' }
& $dataTreePath
if ($LASTEXITCODE -ne 0) { throw "a tree check failed: exit $LASTEXITCODE" }
# `e.algo.complex` against closed forms: Smith's division, the scaled modulus, both sides of the cut.
$algoComplexPath = Join-Path $testBuild 'algo-complex-selfhost.exe'
$algoComplexWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_complex\src\main.e') $repo 'x64' 'windows' $algoComplexPath
if ($LASTEXITCODE -ne 0 -or $algoComplexWritten -ne 'executable written') { throw 'algo_complex emission failed' }
& $algoComplexPath
if ($LASTEXITCODE -ne 0) { throw "a algo_complex check failed: exit $LASTEXITCODE" }
# `e.algo.linalg.matrix` and `.tensor`: strided views, multiply, determinant, inverse, reshape.
$algoLinalgPath = Join-Path $testBuild 'algo-linalg-selfhost.exe'
$algoLinalgWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_linalg\src\main.e') $repo 'x64' 'windows' $algoLinalgPath
if ($LASTEXITCODE -ne 0 -or $algoLinalgWritten -ne 'executable written') { throw 'algo_linalg emission failed' }
& $algoLinalgPath
if ($LASTEXITCODE -ne 0) { throw "a algo_linalg check failed: exit $LASTEXITCODE" }
# `e.text.encoding`: UTF-16 and UTF-32 both ways, BOMs, rejection and replacement, streaming.
$textEncodingPath = Join-Path $testBuild 'text-encoding-selfhost.exe'
$textEncodingWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\text_encoding\src\main.e') $repo 'x64' 'windows' $textEncodingPath
if ($LASTEXITCODE -ne 0 -or $textEncodingWritten -ne 'executable written') { throw 'text_encoding emission failed' }
& $textEncodingPath
if ($LASTEXITCODE -ne 0) { throw "a text_encoding check failed: exit $LASTEXITCODE" }
# `e.algo.bignum`: three radices, the four operations, truncating division, gcd, rationals.
$algoBignumPath = Join-Path $testBuild 'algo-bignum-selfhost.exe'
$algoBignumWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_bignum\src\main.e') $repo 'x64' 'windows' $algoBignumPath
if ($LASTEXITCODE -ne 0 -or $algoBignumWritten -ne 'executable written') { throw 'algo_bignum emission failed' }
& $algoBignumPath
if ($LASTEXITCODE -ne 0) { throw "a algo_bignum check failed: exit $LASTEXITCODE" }
# `e.fmt.uri`: RFC 3986 parsing, the section 5.4 resolution examples, normalisation, escapes.
$fmtUriPath = Join-Path $testBuild 'fmt-uri-selfhost.exe'
$fmtUriWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_uri\src\main.e') $repo 'x64' 'windows' $fmtUriPath
if ($LASTEXITCODE -ne 0 -or $fmtUriWritten -ne 'executable written') { throw 'fmt_uri emission failed' }
& $fmtUriPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_uri check failed: exit $LASTEXITCODE" }
# `e.algo.decimal`: exact arithmetic over a 128-bit coefficient, every rounding mode, the edges.
$algoDecimalPath = Join-Path $testBuild 'algo-decimal-selfhost.exe'
$algoDecimalWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_decimal\src\main.e') $repo 'x64' 'windows' $algoDecimalPath
if ($LASTEXITCODE -ne 0 -or $algoDecimalWritten -ne 'executable written') { throw 'algo_decimal emission failed' }
& $algoDecimalPath
if ($LASTEXITCODE -ne 0) { throw "a algo_decimal check failed: exit $LASTEXITCODE" }
# `e.time.calendar`: weekdays, ISO weeks, month arithmetic with the clamped day, comptime patterns.
$timeCalendarPath = Join-Path $testBuild 'time-calendar-selfhost.exe'
$timeCalendarWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\time_calendar\src\main.e') $repo 'x64' 'windows' $timeCalendarPath
if ($LASTEXITCODE -ne 0 -or $timeCalendarWritten -ne 'executable written') { throw 'time_calendar emission failed' }
& $timeCalendarPath
if ($LASTEXITCODE -ne 0) { throw "a time_calendar check failed: exit $LASTEXITCODE" }
# `e.fmt.quoted_printable`: escapes, soft breaks at the limit, strict decoding, one-byte reads.
$fmtQuotedPrintablePath = Join-Path $testBuild 'fmt-quoted-printable-selfhost.exe'
$fmtQuotedPrintableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_quoted_printable\src\main.e') $repo 'x64' 'windows' $fmtQuotedPrintablePath
if ($LASTEXITCODE -ne 0 -or $fmtQuotedPrintableWritten -ne 'executable written') { throw 'fmt_quoted_printable emission failed' }
& $fmtQuotedPrintablePath
if ($LASTEXITCODE -ne 0) { throw "a fmt_quoted_printable check failed: exit $LASTEXITCODE" }
# `e.fmt.mime`: media types both ways, the extension table, header blocks with case-folded lookup.
$fmtMimePath = Join-Path $testBuild 'fmt-mime-selfhost.exe'
$fmtMimeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_mime\src\main.e') $repo 'x64' 'windows' $fmtMimePath
if ($LASTEXITCODE -ne 0 -or $fmtMimeWritten -ne 'executable written') { throw 'fmt_mime emission failed' }
& $fmtMimePath
if ($LASTEXITCODE -ne 0) { throw "a fmt_mime check failed: exit $LASTEXITCODE" }
# `e.fmt.tar`: ustar and PAX archives from Python's tarfile, partial reads, skips, limits, `..` refused.
$fmtTarPath = Join-Path $testBuild 'fmt-tar-selfhost.exe'
$fmtTarWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_tar\src\main.e') $repo 'x64' 'windows' $fmtTarPath
if ($LASTEXITCODE -ne 0 -or $fmtTarWritten -ne 'executable written') { throw 'fmt_tar emission failed' }
& $fmtTarPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_tar check failed: exit $LASTEXITCODE" }
# `e.metrics`: a counter, a gauge, cumulative histogram buckets and the sum under a CAS loop.
$metricsPath = Join-Path $testBuild 'metrics-selfhost.exe'
$metricsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\metrics\src\main.e') $repo 'x64' 'windows' $metricsPath
if ($LASTEXITCODE -ne 0 -or $metricsWritten -ne 'executable written') { throw 'metrics emission failed' }
& $metricsPath
if ($LASTEXITCODE -ne 0) { throw "a metrics check failed: exit $LASTEXITCODE" }
# `e.fmt.lzw`: both bit orders, two literal widths, table clears, and bytes matched to a reference.
$fmtLzwPath = Join-Path $testBuild 'fmt-lzw-selfhost.exe'
$fmtLzwWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_lzw\src\main.e') $repo 'x64' 'windows' $fmtLzwPath
if ($LASTEXITCODE -ne 0 -or $fmtLzwWritten -ne 'executable written') { throw 'fmt_lzw emission failed' }
& $fmtLzwPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_lzw check failed: exit $LASTEXITCODE" }
# `e.fs.mmap` and `e.fs.watch`: a file mapped by path both ways, and a directory watch seeing a file added.
$fsMmapWatchPath = Join-Path $testBuild 'fs-mmap-watch-selfhost.exe'
$fsMmapWatchWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fs_mmap_watch\src\main.e') $repo 'x64' 'windows' $fsMmapWatchPath
if ($LASTEXITCODE -ne 0 -or $fsMmapWatchWritten -ne 'executable written') { throw 'fs_mmap_watch emission failed' }
$fsWatchScratch = Join-Path $testBuild 'fs-watch-scratch'
if (Test-Path -LiteralPath $fsWatchScratch) { Remove-Item -LiteralPath $fsWatchScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path $fsWatchScratch | Out-Null
Push-Location $fsWatchScratch
try {
    & $fsMmapWatchPath
    if ($LASTEXITCODE -ne 0) { throw "a fs_mmap_watch check failed: exit $LASTEXITCODE" }
} finally {
    Pop-Location
}
# `e.fmt.msgpack`: every family byte-exact against the specification, the tree reader, the typed codec.
$fmtMsgpackPath = Join-Path $testBuild 'fmt-msgpack-selfhost.exe'
$fmtMsgpackWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_msgpack\src\main.e') $repo 'x64' 'windows' $fmtMsgpackPath
if ($LASTEXITCODE -ne 0 -or $fmtMsgpackWritten -ne 'executable written') { throw 'fmt_msgpack emission failed' }
& $fmtMsgpackPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_msgpack check failed: exit $LASTEXITCODE" }
# `e.crypto.hash`: six digests on four inputs against hashlib, streaming across block edges.
$cryptoHashPath = Join-Path $testBuild 'crypto-hash-selfhost.exe'
$cryptoHashWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\crypto_hash\src\main.e') $repo 'x64' 'windows' $cryptoHashPath
if ($LASTEXITCODE -ne 0 -or $cryptoHashWritten -ne 'executable written') { throw 'crypto_hash emission failed' }
& $cryptoHashPath
if ($LASTEXITCODE -ne 0) { throw "a crypto_hash check failed: exit $LASTEXITCODE" }
# `e.crypto.mac`, `.kdf`, `.random`: RFC 4231, RFC 5869 and RFC 8439 vectors, exhaustion, bounded draws.
$cryptoMacKdfRandomPath = Join-Path $testBuild 'crypto-mac-kdf-random-selfhost.exe'
$cryptoMacKdfRandomWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\crypto_mac_kdf_random\src\main.e') $repo 'x64' 'windows' $cryptoMacKdfRandomPath
if ($LASTEXITCODE -ne 0 -or $cryptoMacKdfRandomWritten -ne 'executable written') { throw 'crypto_mac_kdf_random emission failed' }
& $cryptoMacKdfRandomPath
if ($LASTEXITCODE -ne 0) { throw "a crypto_mac_kdf_random check failed: exit $LASTEXITCODE" }
# `e.crypto.aead`: NIST GCM cases 4 and 16 and RFC 8439's ChaCha20-Poly1305, tampering refused.
$cryptoAeadPath = Join-Path $testBuild 'crypto-aead-selfhost.exe'
$cryptoAeadWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\crypto_aead\src\main.e') $repo 'x64' 'windows' $cryptoAeadPath
if ($LASTEXITCODE -ne 0 -or $cryptoAeadWritten -ne 'executable written') { throw 'crypto_aead emission failed' }
& $cryptoAeadPath
if ($LASTEXITCODE -ne 0) { throw "a crypto_aead check failed: exit $LASTEXITCODE" }
# `e.crypto.kx`: X25519 against RFC 7748's exchange and 5.2 vector, the zero peer refused.
$cryptoKxPath = Join-Path $testBuild 'crypto-kx-selfhost.exe'
$cryptoKxWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\crypto_kx\src\main.e') $repo 'x64' 'windows' $cryptoKxPath
if ($LASTEXITCODE -ne 0 -or $cryptoKxWritten -ne 'executable written') { throw 'crypto_kx emission failed' }
& $cryptoKxPath
if ($LASTEXITCODE -ne 0) { throw "a crypto_kx check failed: exit $LASTEXITCODE" }
# `e.crypto.sign`: Ed25519 against RFC 8032 7.1 tests 1-3, five refusals.
$cryptoSignPath = Join-Path $testBuild 'crypto-sign-selfhost.exe'
$cryptoSignWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\crypto_sign\src\main.e') $repo 'x64' 'windows' $cryptoSignPath
if ($LASTEXITCODE -ne 0 -or $cryptoSignWritten -ne 'executable written') { throw 'crypto_sign emission failed' }
& $cryptoSignPath
if ($LASTEXITCODE -ne 0) { throw "a crypto_sign check failed: exit $LASTEXITCODE" }
# `e.fmt.pem`: blocks with a suffix and with headers, encode in 64 columns, five refusals.
$fmtPemPath = Join-Path $testBuild 'fmt-pem-selfhost.exe'
$fmtPemWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_pem\src\main.e') $repo 'x64' 'windows' $fmtPemPath
if ($LASTEXITCODE -ne 0 -or $fmtPemWritten -ne 'executable written') { throw 'fmt_pem emission failed' }
& $fmtPemPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_pem check failed: exit $LASTEXITCODE" }
# `e.fmt.asn1`: a DER SEQUENCE walked, decoded and re-encoded, the long length form, six refusals.
$fmtAsn1Path = Join-Path $testBuild 'fmt-asn1-selfhost.exe'
$fmtAsn1Written = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_asn1\src\main.e') $repo 'x64' 'windows' $fmtAsn1Path
if ($LASTEXITCODE -ne 0 -or $fmtAsn1Written -ne 'executable written') { throw 'fmt_asn1 emission failed' }
& $fmtAsn1Path
if ($LASTEXITCODE -ne 0) { throw "a fmt_asn1 check failed: exit $LASTEXITCODE" }
# `e.fmt.bson`: every carried tag parsed, sized and written back, the typed codec, five refusals.
$fmtBsonPath = Join-Path $testBuild 'fmt-bson-selfhost.exe'
$fmtBsonWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_bson\src\main.e') $repo 'x64' 'windows' $fmtBsonPath
if ($LASTEXITCODE -ne 0 -or $fmtBsonWritten -ne 'executable written') { throw 'fmt_bson emission failed' }
& $fmtBsonPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_bson check failed: exit $LASTEXITCODE" }
# `e.fmt.protobuf`: every wire type read and written back byte for byte, sizes, four refusals.
$fmtProtobufPath = Join-Path $testBuild 'fmt-protobuf-selfhost.exe'
$fmtProtobufWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_protobuf\src\main.e') $repo 'x64' 'windows' $fmtProtobufPath
if ($LASTEXITCODE -ne 0 -or $fmtProtobufWritten -ne 'executable written') { throw 'fmt_protobuf emission failed' }
& $fmtProtobufPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_protobuf check failed: exit $LASTEXITCODE" }
# `e.algo.deflate`: zlib's dynamic stream inflated whole and in steps, every level round-tripped, three blocks, six refusals.
$algoDeflatePath = Join-Path $testBuild 'algo-deflate-selfhost.exe'
$algoDeflateWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_deflate\src\main.e') $repo 'x64' 'windows' $algoDeflatePath
if ($LASTEXITCODE -ne 0 -or $algoDeflateWritten -ne 'executable written') { throw 'algo_deflate emission failed' }
& $algoDeflatePath
if ($LASTEXITCODE -ne 0) { throw "a algo_deflate check failed: exit $LASTEXITCODE" }
# `e.fmt.zlib`: Python's stream read back, the writer read back, five refusals.
$fmtZlibPath = Join-Path $testBuild 'fmt-zlib-selfhost.exe'
$fmtZlibWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_zlib\src\main.e') $repo 'x64' 'windows' $fmtZlibPath
if ($LASTEXITCODE -ne 0 -or $fmtZlibWritten -ne 'executable written') { throw 'fmt_zlib emission failed' }
& $fmtZlibPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_zlib check failed: exit $LASTEXITCODE" }
# `e.fmt.gzip`: Python's member with FNAME read back, the writer read back, seven refusals.
$fmtGzipPath = Join-Path $testBuild 'fmt-gzip-selfhost.exe'
$fmtGzipWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_gzip\src\main.e') $repo 'x64' 'windows' $fmtGzipPath
if ($LASTEXITCODE -ne 0 -or $fmtGzipWritten -ne 'executable written') { throw 'fmt_gzip emission failed' }
& $fmtGzipPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_gzip check failed: exit $LASTEXITCODE" }
# `e.fmt.zip`: Python's archive and a hand-built ZIP64 one read, seven refusals.
$fmtZipPath = Join-Path $testBuild 'fmt-zip-selfhost.exe'
$fmtZipWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_zip\src\main.e') $repo 'x64' 'windows' $fmtZipPath
if ($LASTEXITCODE -ne 0 -or $fmtZipWritten -ne 'executable written') { throw 'fmt_zip emission failed' }
& $fmtZipPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_zip check failed: exit $LASTEXITCODE" }
# `e.test.support`: the clock, the scripted reader and writer, the schedule.
$testSupportPath = Join-Path $testBuild 'test-support-selfhost.exe'
$testSupportWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\test_support\src\main.e') $repo 'x64' 'windows' $testSupportPath
if ($LASTEXITCODE -ne 0 -or $testSupportWritten -ne 'executable written') { throw 'test_support emission failed' }
& $testSupportPath
if ($LASTEXITCODE -ne 0) { throw "a test_support check failed: exit $LASTEXITCODE" }
# `e.cli`: a command tree parsed, validated, refused and rendered; parse_into over a struct.
$cliPath = Join-Path $testBuild 'cli-selfhost.exe'
$cliWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\cli\src\main.e') $repo 'x64' 'windows' $cliPath
if ($LASTEXITCODE -ne 0 -or $cliWritten -ne 'executable written') { throw 'cli emission failed' }
& $cliPath
if ($LASTEXITCODE -ne 0) { throw "a cli check failed: exit $LASTEXITCODE" }
# `e.text.template`: interpolation, if/else, repeat with index, seven refusals, the typed path.
$textTemplatePath = Join-Path $testBuild 'text-template-selfhost.exe'
$textTemplateWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\text_template\src\main.e') $repo 'x64' 'windows' $textTemplatePath
if ($LASTEXITCODE -ne 0 -or $textTemplateWritten -ne 'executable written') { throw 'text_template emission failed' }
& $textTemplatePath
if ($LASTEXITCODE -ne 0) { throw "a text_template check failed: exit $LASTEXITCODE" }
# `e.fmt.multipart`: three parts read in 5-byte chunks, the writer read back, six refusals.
$fmtMultipartPath = Join-Path $testBuild 'fmt-multipart-selfhost.exe'
$fmtMultipartWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_multipart\src\main.e') $repo 'x64' 'windows' $fmtMultipartPath
if ($LASTEXITCODE -ne 0 -or $fmtMultipartWritten -ne 'executable written') { throw 'fmt_multipart emission failed' }
& $fmtMultipartPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_multipart check failed: exit $LASTEXITCODE" }
# `e.db`: the contract over an in-memory driver, every handle Closed after its close.
$dbPath = Join-Path $testBuild 'db-selfhost.exe'
$dbWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\db\src\main.e') $repo 'x64' 'windows' $dbPath
if ($LASTEXITCODE -ne 0 -or $dbWritten -ne 'executable written') { throw 'db emission failed' }
& $dbPath
if ($LASTEXITCODE -ne 0) { throw "a db check failed: exit $LASTEXITCODE" }
# `e.fmt.xml`: a document walked as events, the writer read back, seven refusals.
$fmtXmlPath = Join-Path $testBuild 'fmt-xml-selfhost.exe'
$fmtXmlWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_xml\src\main.e') $repo 'x64' 'windows' $fmtXmlPath
if ($LASTEXITCODE -ne 0 -or $fmtXmlWritten -ne 'executable written') { throw 'fmt_xml emission failed' }
& $fmtXmlPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_xml check failed: exit $LASTEXITCODE" }
# `e.tz`: the builtin database against zoneinfo, transitions and footer rules, resolve three ways.
$tzPath = Join-Path $testBuild 'tz-selfhost.exe'
$tzWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\tz\src\main.e') $repo 'x64' 'windows' $tzPath
if ($LASTEXITCODE -ne 0 -or $tzWritten -ne 'executable written') { throw 'tz emission failed' }
& $tzPath
if ($LASTEXITCODE -ne 0) { throw "a tz check failed: exit $LASTEXITCODE" }
# `e.concurrent.queue` and `e.concurrent.map`: try, blocking, timed and closed forms; threads through both.
$concurrentQueueMapPath = Join-Path $testBuild 'concurrent-queue-map-selfhost.exe'
$concurrentQueueMapWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\concurrent_queue_map\src\main.e') $repo 'x64' 'windows' $concurrentQueueMapPath
if ($LASTEXITCODE -ne 0 -or $concurrentQueueMapWritten -ne 'executable written') { throw 'concurrent_queue_map emission failed' }
& $concurrentQueueMapPath
if ($LASTEXITCODE -ne 0) { throw "a concurrent_queue_map check failed: exit $LASTEXITCODE" }
# `e.fmt.bzip2`: Python's three-block stream read back in pulls, six refusals.
$fmtBzip2Path = Join-Path $testBuild 'fmt-bzip2-selfhost.exe'
$fmtBzip2Written = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_bzip2\src\main.e') $repo 'x64' 'windows' $fmtBzip2Path
if ($LASTEXITCODE -ne 0 -or $fmtBzip2Written -ne 'executable written') { throw 'fmt_bzip2 emission failed' }
& $fmtBzip2Path
if ($LASTEXITCODE -ne 0) { throw "a fmt_bzip2 check failed: exit $LASTEXITCODE" }
# `e.text.io`: lines across LF, CRLF and a bare CR, BOM sniffing, limits, both writers.
$textIoPath = Join-Path $testBuild 'text-io-selfhost.exe'
$textIoWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\text_io\src\main.e') $repo 'x64' 'windows' $textIoPath
if ($LASTEXITCODE -ne 0 -or $textIoWritten -ne 'executable written') { throw 'text_io emission failed' }
& $textIoPath
if ($LASTEXITCODE -ne 0) { throw "a text_io check failed: exit $LASTEXITCODE" }
# `e.log` and `e.debug`: the level gate, both sinks, a file read back, the empty backtrace.
$logDebugPath = Join-Path $testBuild 'log-debug-selfhost.exe'
$logDebugWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\log_debug\src\main.e') $repo 'x64' 'windows' $logDebugPath
if ($LASTEXITCODE -ne 0 -or $logDebugWritten -ne 'executable written') { throw 'log_debug emission failed' }
& $logDebugPath
if ($LASTEXITCODE -ne 0) { throw "a log_debug check failed: exit $LASTEXITCODE" }
# `e.fmt.yaml`: every scalar and collection form, the writer read back, the typed codec, eight refusals.
$fmtYamlPath = Join-Path $testBuild 'fmt-yaml-selfhost.exe'
$fmtYamlWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_yaml\src\main.e') $repo 'x64' 'windows' $fmtYamlPath
if ($LASTEXITCODE -ne 0 -or $fmtYamlWritten -ne 'executable written') { throw 'fmt_yaml emission failed' }
& $fmtYamlPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_yaml check failed: exit $LASTEXITCODE" }
# `e.crypto.x509`: an Ed25519 chain from Python parsed, signatures checked, chains built and refused.
$cryptoX509Path = Join-Path $testBuild 'crypto-x509-selfhost.exe'
$cryptoX509Written = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\crypto_x509\src\main.e') $repo 'x64' 'windows' $cryptoX509Path
if ($LASTEXITCODE -ne 0 -or $cryptoX509Written -ne 'executable written') { throw 'crypto_x509 emission failed' }
& $cryptoX509Path
if ($LASTEXITCODE -ne 0) { throw "a crypto_x509 check failed: exit $LASTEXITCODE" }
# `e.text.unicode`: properties and case mappings against unicodedata, grapheme clusters.
$textUnicodePath = Join-Path $testBuild 'text-unicode-selfhost.exe'
$textUnicodeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\text_unicode\src\main.e') $repo 'x64' 'windows' $textUnicodePath
if ($LASTEXITCODE -ne 0 -or $textUnicodeWritten -ne 'executable written') { throw 'text_unicode emission failed' }
& $textUnicodePath
if ($LASTEXITCODE -ne 0) { throw "a text_unicode check failed: exit $LASTEXITCODE" }
# `e.text.utf8` (D299): strict decode at every malformed shape, encode at every width boundary, count, byte_offset, lossy and strict iteration.
$textUtf8Path = Join-Path $testBuild 'text-utf8-selfhost.exe'
$textUtf8Written = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/text_utf8/src/main.e') $repo 'x64' 'windows' $textUtf8Path
if ($LASTEXITCODE -ne 0 -or $textUtf8Written -ne 'executable written') { throw 'text_utf8 emission failed' }
& $textUtf8Path
if ($LASTEXITCODE -ne 0) { throw "a text_utf8 check failed: exit $LASTEXITCODE" }
# `e.text.normalize` (D301): four forms, ordering, exclusions, Hangul, compatibility mappings, is_normalized in a stack window.
$textNormalizePath = Join-Path $testBuild 'text-normalize-selfhost.exe'
$textNormalizeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/text_normalize/src/main.e') $repo 'x64' 'windows' $textNormalizePath
if ($LASTEXITCODE -ne 0 -or $textNormalizeWritten -ne 'executable written') { throw 'text_normalize emission failed' }
& $textNormalizePath
if ($LASTEXITCODE -ne 0) { throw "a text_normalize check failed: exit $LASTEXITCODE" }
# `e.text.regex` (D768): Pike-VM matching, leftmost-first preference, captures, the three options and `$n` replacement.
$textRegexPath = Join-Path $testBuild 'text-regex-selfhost.exe'
$textRegexWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/text_regex/src/main.e') $repo 'x64' 'windows' $textRegexPath
if ($LASTEXITCODE -ne 0 -or $textRegexWritten -ne 'executable written') { throw 'text_regex emission failed' }
$textRegexOutput = & $textRegexPath
if ($LASTEXITCODE -ne 0 -or $textRegexOutput -ne 'text regex ok') { throw "a text_regex check failed: exit $LASTEXITCODE" }
# `e.text.shape` (D769): cmap, GSUB single and ligature lookups, feature ranges, GPOS pair kerning and legacy `kern` over a synthetic font.
$textShapePath = Join-Path $testBuild 'text-shape-selfhost.exe'
$textShapeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/text_shape/src/main.e') $repo 'x64' 'windows' $textShapePath
if ($LASTEXITCODE -ne 0 -or $textShapeWritten -ne 'executable written') { throw 'text_shape emission failed' }
$textShapeOutput = & $textShapePath
if ($LASTEXITCODE -ne 0 -or $textShapeOutput -ne 'text shape ok') { throw "a text_shape check failed: exit $LASTEXITCODE" }
# `e.text.locale` (D771): tags, grouped numbers, currency layout, LDML dates, natural comparison and Turkic case over the built-in CLDR subset and a loaded database.
$textLocalePath = Join-Path $testBuild 'text-locale-selfhost.exe'
$textLocaleWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/text_locale/src/main.e') $repo 'x64' 'windows' $textLocalePath
if ($LASTEXITCODE -ne 0 -or $textLocaleWritten -ne 'executable written') { throw 'text_locale emission failed' }
$textLocaleOutput = & $textLocalePath
if ($LASTEXITCODE -ne 0 -or $textLocaleOutput -ne 'text locale ok') { throw "a text_locale check failed: exit $LASTEXITCODE" }
# One function of 3000 checks (D302): wider than the old small NIR tier and than codegen's old per-function block table.
$capacityWidePath = Join-Path $testBuild 'capacity-wide-selfhost.exe'
$capacityWideWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/capacity_wide/src/main.e') $repo 'x64' 'windows' $capacityWidePath
if ($LASTEXITCODE -ne 0 -or $capacityWideWritten -ne 'executable written') { throw 'capacity_wide emission failed' }
& $capacityWidePath
if ($LASTEXITCODE -ne 0) { throw "a capacity_wide check failed: exit $LASTEXITCODE" }
# `e.fmt.zstd`: libzstd's frames at three levels read back, the writer's frame read back, six refusals.
$fmtZstdPath = Join-Path $testBuild 'fmt-zstd-selfhost.exe'
$fmtZstdWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_zstd\src\main.e') $repo 'x64' 'windows' $fmtZstdPath
if ($LASTEXITCODE -ne 0 -or $fmtZstdWritten -ne 'executable written') { throw 'fmt_zstd emission failed' }
& $fmtZstdPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_zstd check failed: exit $LASTEXITCODE" }
# `e.fmt.html`: a document tokenized and built, serialized and read back, a bare fragment, four refusals.
$fmtHtmlPath = Join-Path $testBuild 'fmt-html-selfhost.exe'
$fmtHtmlWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_html\src\main.e') $repo 'x64' 'windows' $fmtHtmlPath
if ($LASTEXITCODE -ne 0 -or $fmtHtmlWritten -ne 'executable written') { throw 'fmt_html emission failed' }
& $fmtHtmlPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_html check failed: exit $LASTEXITCODE" }
# `e.async`: the loop over two loopback datagram sockets, the os_poller shape.
$asyncPath = Join-Path $testBuild 'async-selfhost.exe'
$asyncWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\async\src\main.e') $repo 'x64' 'windows' $asyncPath
if ($LASTEXITCODE -ne 0 -or $asyncWritten -ne 'executable written') { throw 'async emission failed' }
& $asyncPath
if ($LASTEXITCODE -ne 0) { throw "a async check failed: exit $LASTEXITCODE" }
# `generic_value` (D772): a generic function instantiated by name stands as a value, a typed trampoline behind a `*void` callback.
$genericValuePath = Join-Path $testBuild 'generic-value-selfhost.exe'
$genericValueWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/generic_value/src/main.e') $repo 'x64' 'windows' $genericValuePath
if ($LASTEXITCODE -ne 0 -or $genericValueWritten -ne 'executable written') { throw 'generic_value emission failed' }
$genericValueOutput = & $genericValuePath
if ($LASTEXITCODE -ne 0 -or $genericValueOutput -ne 'generic value ok') { throw "a generic_value check failed: exit $LASTEXITCODE" }
# `e.task` (D772): a bounded pool over the trampoline instances -- tasks, futures, failure, cancellation, bounded waits, wait_any, a full ring, parallel_for, close.
$taskPoolPath = Join-Path $testBuild 'task-pool-selfhost.exe'
$taskPoolWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/task_pool/src/main.e') $repo 'x64' 'windows' $taskPoolPath
if ($LASTEXITCODE -ne 0 -or $taskPoolWritten -ne 'executable written') { throw 'task_pool emission failed' }
$taskPoolOutput = & $taskPoolPath
if ($LASTEXITCODE -ne 0 -or $taskPoolOutput -ne 'task pool ok') { throw "a task_pool check failed: exit $LASTEXITCODE" }
# `e.async.io` (D773): connect and accept through the loop, callback read and write, progress, wait_any, cancellation, an expired deadline, take's refusals.
$asyncIoPath = Join-Path $testBuild 'async-io-selfhost.exe'
$asyncIoWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/async_io/src/main.e') $repo 'x64' 'windows' $asyncIoPath
if ($LASTEXITCODE -ne 0 -or $asyncIoWritten -ne 'executable written') { throw 'async_io emission failed' }
$asyncIoOutput = & $asyncIoPath
if ($LASTEXITCODE -ne 0 -or $asyncIoOutput -ne 'async io ok') { throw "a async_io check failed: exit $LASTEXITCODE" }
# `e.fmt.mail`: addresses, lists, dates against email.utils, a message with a folded header, encoded words.
$fmtMailPath = Join-Path $testBuild 'fmt-mail-selfhost.exe'
$fmtMailWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_mail\src\main.e') $repo 'x64' 'windows' $fmtMailPath
if ($LASTEXITCODE -ne 0 -or $fmtMailWritten -ne 'executable written') { throw 'fmt_mail emission failed' }
& $fmtMailPath
if ($LASTEXITCODE -ne 0) { throw "a fmt_mail check failed: exit $LASTEXITCODE" }
# `e.fmt.html.template`: every context escaped, an unsafe scheme replaced, the typed path, six refusals.
$fmtHtmlTemplatePath = Join-Path $testBuild 'fmt-html-template-selfhost.exe'
$fmtHtmlTemplateWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_html_template\src\main.e') $repo 'x64' 'windows' $fmtHtmlTemplatePath
if ($LASTEXITCODE -ne 0 -or $fmtHtmlTemplateWritten -ne 'executable written') { throw 'fmt_html_template emission failed' }
& $fmtHtmlTemplatePath
if ($LASTEXITCODE -ne 0) { throw "a fmt_html_template check failed: exit $LASTEXITCODE" }
# `e.os`'s sockets over the loopback interface: a real TCP connection and a real UDP
# datagram inside one process, so nothing waits on a peer that has not already acted.
$socketPath = Join-Path $testBuild 'os-socket-selfhost.exe'
$socketWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_socket\src\main.e') $repo 'x64' 'windows' $socketPath
if ($LASTEXITCODE -ne 0 -or $socketWritten -ne 'executable written') { throw 'e.os socket emission failed' }
& $socketPath
if ($LASTEXITCODE -ne 0) { throw "an e.os socket call answered wrongly: exit $LASTEXITCODE" }
# `e.os`'s poller. `WSAPoll` retains nothing between calls, so the registration set lives in
# the arena and goes in whole on every wait; the wake is a datagram the wake socket sends to
# its own address. Two sockets are made readable at once so the array stride is exercised,
# and the wake is timed against the clock.
$pollerPath = Join-Path $testBuild 'os-poller-selfhost.exe'
$pollerWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_poller\src\main.e') $repo 'x64' 'windows' $pollerPath
if ($LASTEXITCODE -ne 0 -or $pollerWritten -ne 'executable written') { throw 'e.os poller emission failed' }
& $pollerPath
if ($LASTEXITCODE -ne 0) { throw "the e.os poller answered wrongly: exit $LASTEXITCODE" }
# `e.os`'s file mapping: a file read through memory, written through memory, and the change
# then seen by an ordinary read -- which is what says a mapping is the file and not a copy.
$mappingScratch = Join-Path $testBuild 'map-scratch'
New-Item -ItemType Directory -Force -Path $mappingScratch | Out-Null
$mappingPath = Join-Path $testBuild 'os-mapping-selfhost.exe'
$mappingWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_mapping\src\main.e') $repo 'x64' 'windows' $mappingPath
if ($LASTEXITCODE -ne 0 -or $mappingWritten -ne 'executable written') { throw 'e.os mapping emission failed' }
Push-Location $mappingScratch
& $mappingPath
$mappingExit = $LASTEXITCODE
Pop-Location
if ($mappingExit -ne 0) { throw "an e.os mapping call answered wrongly: exit $mappingExit" }
# `e.os`'s directory watch. The change is made before the read, which is the case that says
# watching begins when the watch opens: this host records only from the first read unless the
# read is armed at open, so an unarmed version misses the file it was watching for.
$watchScratch = Join-Path $testBuild 'watch-scratch'
New-Item -ItemType Directory -Force -Path $watchScratch | Out-Null
$watchPath = Join-Path $testBuild 'os-watch-selfhost.exe'
$watchWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_watch\src\main.e') $repo 'x64' 'windows' $watchPath
if ($LASTEXITCODE -ne 0 -or $watchWritten -ne 'executable written') { throw 'e.os watch emission failed' }
Push-Location $watchScratch
& $watchPath
$watchExit = $LASTEXITCODE
Pop-Location
if ($watchExit -ne 0) { throw "an e.os watch call answered wrongly: exit $watchExit" }
# `e.os`'s pipe, page size, reservation release and `kill`. The child `kill` needs is this
# fixture's own image spawned again, which is the only program it can be sure exists.
$processPath = Join-Path $testBuild 'os-process-selfhost.exe'
$processWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_process\src\main.e') $repo 'x64' 'windows' $processPath
if ($LASTEXITCODE -ne 0 -or $processWritten -ne 'executable written') { throw 'e.os process primitive emission failed' }
& $processPath
if ($LASTEXITCODE -ne 0) { throw "an e.os process primitive answered wrongly: exit $LASTEXITCODE" }
# `e.os`'s file locks. Two separate opens of one path are two separate claims, so one process
# is enough to make a lock actually block -- and the timed case is checked against the clock,
# since neither host has a timeout and the wait is polled.
$lockScratch = Join-Path $testBuild 'lock-scratch'
New-Item -ItemType Directory -Force -Path $lockScratch | Out-Null
$lockPath = Join-Path $testBuild 'os-lock-selfhost.exe'
$lockWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_lock\src\main.e') $repo 'x64' 'windows' $lockPath
if ($LASTEXITCODE -ne 0 -or $lockWritten -ne 'executable written') { throw 'e.os file lock emission failed' }
Push-Location $lockScratch
& $lockPath
$lockExit = $LASTEXITCODE
Pop-Location
if ($lockExit -ne 0) { throw "an e.os file lock answered wrongly: exit $lockExit" }
# `e.os`'s `spawn_with_options` and its process groups. Every check needs a second program and
# the only one the fixture can be sure exists is itself, so it spawns its own image with a
# marker argument and each mode answers by its exit code.
$groupScratch = Join-Path $testBuild 'group-scratch'
New-Item -ItemType Directory -Force -Path $groupScratch | Out-Null
$groupPath = Join-Path $testBuild 'os-group-selfhost.exe'
$groupWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_group\src\main.e') $repo 'x64' 'windows' $groupPath
if ($LASTEXITCODE -ne 0 -or $groupWritten -ne 'executable written') { throw 'e.os process group emission failed' }
Push-Location $groupScratch
& $groupPath
$groupExit = $LASTEXITCODE
Pop-Location
if ($groupExit -ne 0) { throw "an e.os spawn or process group answered wrongly: exit $groupExit" }
# `e.os`'s `socket_resolve`. Nothing here needs a network: a literal is parsed and the loopback
# name comes from the hosts file on one host and its own resolver on the other. The one case that
# does leave the machine only has to fail, which it does either way.
$resolvePath = Join-Path $testBuild 'os-resolve-selfhost.exe'
$resolveWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_resolve\src\main.e') $repo 'x64' 'windows' $resolvePath
if ($LASTEXITCODE -ne 0 -or $resolveWritten -ne 'executable written') { throw 'e.os resolver emission failed' }
& $resolvePath
if ($LASTEXITCODE -ne 0) { throw "an e.os socket_resolve answered wrongly: exit $LASTEXITCODE" }
# `e.time`'s civil calendar and ISO 8601. The nanosecond counts the fixture checks against were
# computed independently of this code, so a wrong shift or leap rule fails rather than agreeing
# with itself -- truncating instead of flooring fails at 22, and dropping the century rule at 34.
$calendarPath = Join-Path $testBuild 'time-calendar-selfhost.exe'
$calendarWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\time_calendar\src\main.e') $repo 'x64' 'windows' $calendarPath
if ($LASTEXITCODE -ne 0 -or $calendarWritten -ne 'executable written') { throw 'e.time calendar emission failed' }
& $calendarPath
if ($LASTEXITCODE -ne 0) { throw "an e.time calendar answer is wrong: exit $LASTEXITCODE" }
# `e.path`'s globs, which are pure matching and touch no filesystem. The boundary between `*`
# and a whole `**` component is what the fixture spends most of itself on -- making `**` consume a
# component instead of matching zero fails at 40.
$globPath = Join-Path $testBuild 'path-glob-selfhost.exe'
$globWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\path_glob\src\main.e') $repo 'x64' 'windows' $globPath
if ($LASTEXITCODE -ne 0 -or $globWritten -ne 'executable written') { throw 'e.path glob emission failed' }
& $globPath
if ($LASTEXITCODE -ne 0) { throw "an e.path glob answer is wrong: exit $LASTEXITCODE" }
# `e.mem`'s last four. `copy` and `eq` are ordinary generic code -- the first of `e.mem` that is
# not an intrinsic -- while `size_of` and `align_of` cannot be written at all and answer with a
# constant, which the fixture pins by standing one in an array length.
$memPath = Join-Path $testBuild 'mem-slices-selfhost.exe'
$memWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\mem_slices\src\main.e') $repo 'x64' 'windows' $memPath
if ($LASTEXITCODE -ne 0 -or $memWritten -ne 'executable written') { throw 'e.mem slice emission failed' }
& $memPath
if ($LASTEXITCODE -ne 0) { throw "an e.mem answer is wrong: exit $LASTEXITCODE" }
# `e.meta`'s two type-valued questions. What is checked is that the answer is a type in every
# respect -- a comptime argument to anything taking one, including the other question and a generic
# of the caller's own -- since a function that merely returned something would pass a weaker test.
$metaTypePath = Join-Path $testBuild 'meta-types-selfhost.exe'
$metaTypeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\meta_types\src\main.e') $repo 'x64' 'windows' $metaTypePath
if ($LASTEXITCODE -ne 0 -or $metaTypeWritten -ne 'executable written') { throw 'e.meta type emission failed' }
& $metaTypePath
if ($LASTEXITCODE -ne 0) { throw "an e.meta type answer is wrong: exit $LASTEXITCODE" }
# Reflection inside a generic function, where the type is a parameter rather than a name. A
# generic body is checked once as a template with nothing bound and again per instance, and a
# `meta` question has no answer in the first pass -- so it stands there and the instance settles
# it, which is the deferral `mem.size_of` always had (D136). Every answer here is the instance's
# own: a placeholder that survived would make them all agree.
$metaGenericPath = Join-Path $testBuild 'meta-generic-selfhost.exe'
$metaGenericWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\meta_generic\src\main.e') $repo 'x64' 'windows' $metaGenericPath
if ($LASTEXITCODE -ne 0 -or $metaGenericWritten -ne 'executable written') { throw 'e.meta generic emission failed' }
& $metaGenericPath
if ($LASTEXITCODE -ne 0) { throw "an e.meta answer inside a generic is wrong: exit $LASTEXITCODE" }
# A branch whose condition is settled at compile time has one arm, and the other is not code:
# not checked, not emitted. Only a `meta` question settles one (D138). The two things that
# could not be written before are both here -- a walk over `meta.fields` whose arms do not type
# check for each other's field types, and a generic recursing on `meta.element_type` whose base
# case is the arm that disappears. An ordinary runtime `if` is here too, to say what is not
# folded.
$foldPath = Join-Path $testBuild 'comptime-branch-selfhost.exe'
$foldWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\comptime_branch\src\main.e') $repo 'x64' 'windows' $foldPath
if ($LASTEXITCODE -ne 0 -or $foldWritten -ne 'executable written') { throw 'comptime branch emission failed' }
& $foldPath
if ($LASTEXITCODE -ne 0) { throw "a folded branch chose wrongly: exit $LASTEXITCODE" }
# Section 9's `Field` and `Member` as declared names: a comptime value crossing a call, so the
# callee is instantiated per field and its own return type depends on which one it was given.
# Without the guard that stops inference rebinding such a parameter, this fails at 88.
$fieldParamPath = Join-Path $testBuild 'meta-field-param-selfhost.exe'
$fieldParamWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\meta_field_param\src\main.e') $repo 'x64' 'windows' $fieldParamPath
if ($LASTEXITCODE -ne 0 -or $fieldParamWritten -ne 'executable written') { throw 'e.meta field parameter emission failed' }
& $fieldParamPath
if ($LASTEXITCODE -ne 0) { throw "an e.meta comptime value crossing a call is wrong: exit $LASTEXITCODE" }
# `e.os`'s loader. Each host opens the library it already depends on, so nothing needs installing.
# `dlsym` answers with a value of the caller's own `extern fn` type, which is why the fixture calls
# what it gets: a result passed the wrong way would be rubbish rather than a wrong number.
$dlPath = Join-Path $testBuild 'os-dl-selfhost.exe'
$dlWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_dl\src\main.e') $repo 'x64' 'windows' $dlPath
if ($LASTEXITCODE -ne 0 -or $dlWritten -ne 'executable written') { throw 'e.os loader emission failed' }
& $dlPath
if ($LASTEXITCODE -ne 0) { throw "an e.os loader call answered wrongly: exit $LASTEXITCODE" }
# D131's property: a program that uses `e.os` and opens no library needs no loader. It checks
# itself -- it reads its own image and walks its own program headers -- so nothing here has to
# have a dumper, and what is asserted is the file that was produced rather than what the compiler
# says about it. Windows has no freestanding form, since every image names `kernel32.dll`, so
# there the fixture asserts only that the self-read the other half depends on worked.
$freestandingPath = Join-Path $testBuild 'freestanding-selfhost.exe'
$freestandingWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\freestanding\src\main.e') $repo 'x64' 'windows' $freestandingPath
if ($LASTEXITCODE -ne 0 -or $freestandingWritten -ne 'executable written') { throw 'freestanding emission failed' }
& $freestandingPath
if ($LASTEXITCODE -ne 0) { throw "the freestanding image is not the shape it claims: exit $LASTEXITCODE" }
# `e.fmt.json`'s value tree. The module keeps a number as the lexeme it arrived with, which
# only a round trip can show: a parser that rounded through an `f64` would agree with itself
# everywhere except on what came back out. Escapes, surrogate pairs, duplicate keys, the depth
# limit and RFC 6901 pointers are checked here too.
$jsonPath = Join-Path $testBuild 'fmt-json-selfhost.exe'
$jsonWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_json\src\main.e') $repo 'x64' 'windows' $jsonPath
if ($LASTEXITCODE -ne 0 -or $jsonWritten -ne 'executable written') { throw 'e.fmt.json emission failed' }
& $jsonPath
if ($LASTEXITCODE -ne 0) { throw "an e.fmt.json parse, write or pointer answered wrongly: exit $LASTEXITCODE" }
# `e.fmt.csv` reads a bounded stream and writes a row at a time. The reader is a state
# machine with two bits of memory, so the fixture pins every byte that changes one: the
# quote that opens a field and the quote that is data, the doubled quote, the CRLF that
# terminates and the bare CR that does not. It runs over a real file as well as a slice,
# because a file reports its end by taking nothing rather than by saying so.
$csvPath = Join-Path $testBuild 'fmt-csv-selfhost.exe'
$csvWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_csv\src\main.e') $repo 'x64' 'windows' $csvPath
if ($LASTEXITCODE -ne 0 -or $csvWritten -ne 'executable written') { throw 'e.fmt.csv emission failed' }
Push-Location $fsScratch
& $csvPath
$csvExit = $LASTEXITCODE
Pop-Location
if ($csvExit -ne 0) { throw "an e.fmt.csv read or write answered wrongly: exit $csvExit" }
# `e.net` covers strict IP values, real TCP/UDP, stream adapters, portable native-error
# mapping and honest poll-based control; synchronous controlled DNS refuses unsupported bounds.
$netPath = Join-Path $testBuild 'net-selfhost.exe'
$netWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\net\src\main.e') $repo 'x64' 'windows' $netPath
if ($LASTEXITCODE -ne 0 -or $netWritten -ne 'executable written') { throw 'e.net emission failed' }
& $netPath
if ($LASTEXITCODE -ne 0) { throw "an e.net address codec answered wrongly: exit $LASTEXITCODE" }
# The delivered `e.net.http` codecs run over a one-byte source, and real loopback clients
# pin bounded GET/HEAD plus chunked streaming and cancellation. SSE pins split UTF-8/CRLF,
# retained state, the EOF rule and flat memory over ten thousand events.
$httpPath = Join-Path $testBuild 'net-http-selfhost.exe'
$httpWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\net_http\src\main.e') $repo 'x64' 'windows' $httpPath
if ($LASTEXITCODE -ne 0 -or $httpWritten -ne 'executable written') { throw 'e.net.http emission failed' }
& $httpPath
if ($LASTEXITCODE -ne 0) { throw "an e.net.http message, request or SSE read answered wrongly: exit $LASTEXITCODE" }
# `e.net.ws` pins both RFC handshakes plus bounded inbound and outbound frames.
$wsPath = Join-Path $testBuild 'net-ws-selfhost.exe'
$wsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\net_ws\src\main.e') $repo 'x64' 'windows' $wsPath
if ($LASTEXITCODE -ne 0 -or $wsWritten -ne 'executable written') { throw 'e.net.ws emission failed' }
& $wsPath
if ($LASTEXITCODE -ne 0) { throw "an e.net.ws handshake or frame answered wrongly: exit $LASTEXITCODE" }
# `e.net.tls` constructors are inert until handshake and expose pinned metadata.
$tlsPath = Join-Path $testBuild 'net-tls-selfhost.exe'
$tlsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\net_tls\src\main.e') $repo 'x64' 'windows' $tlsPath
if ($LASTEXITCODE -ne 0 -or $tlsWritten -ne 'executable written') { throw 'e.net.tls emission failed' }
& $tlsPath
if ($LASTEXITCODE -ne 0) { throw "an e.net.tls constructor or metadata query answered wrongly: exit $LASTEXITCODE" }
# `e.text.collate` pins code-point and overflow-free natural ordering.
$collatePath = Join-Path $testBuild 'text-collate-selfhost.exe'
$collateWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\text_collate\src\main.e') $repo 'x64' 'windows' $collatePath
if ($LASTEXITCODE -ne 0 -or $collateWritten -ne 'executable written') { throw 'e.text.collate emission failed' }
& $collatePath
if ($LASTEXITCODE -ne 0) { throw "an e.text.collate comparison answered wrongly: exit $LASTEXITCODE" }
# `e.time.cron` pins six-field parsing, day rules, offsets and next-time search.
$cronPath = Join-Path $testBuild 'time-cron-selfhost.exe'
$cronWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\time_cron\src\main.e') $repo 'x64' 'windows' $cronPath
if ($LASTEXITCODE -ne 0 -or $cronWritten -ne 'executable written') { throw 'e.time.cron emission failed' }
& $cronPath
if ($LASTEXITCODE -ne 0) { throw "an e.time.cron parse or match answered wrongly: exit $LASTEXITCODE" }
# `e.grep` pins recursive literal matches and its stateless index contract.
$grepPath = Join-Path $testBuild 'grep-selfhost.exe'
$grepWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\grep\src\main.e') $repo 'x64' 'windows' $grepPath
if ($LASTEXITCODE -ne 0 -or $grepWritten -ne 'executable written') { throw 'e.grep emission failed' }
Push-Location $fsScratch
& $grepPath
$grepExit = $LASTEXITCODE
Pop-Location
if ($grepExit -ne 0) { throw "an e.grep index or search answered wrongly: exit $grepExit" }
# `e.audio` pins interleaved PCM views and host-independent sample conversion.
$audioPath = Join-Path $testBuild 'audio-selfhost.exe'
$audioWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\audio\src\main.e') $repo 'x64' 'windows' $audioPath
if ($LASTEXITCODE -ne 0 -or $audioWritten -ne 'executable written') { throw 'e.audio emission failed' }
& $audioPath
if ($LASTEXITCODE -ne 0) { throw "an e.audio view or conversion answered wrongly: exit $LASTEXITCODE" }
# `e.audio.mixer` pins lifecycle, deterministic clipped mixing and integer resampling.
$audioMixerPath = Join-Path $testBuild 'audio-mixer-selfhost.exe'
$audioMixerWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\audio_mixer\src\main.e') $repo 'x64' 'windows' $audioMixerPath
if ($LASTEXITCODE -ne 0 -or $audioMixerWritten -ne 'executable written') { throw 'e.audio.mixer emission failed' }
& $audioMixerPath
if ($LASTEXITCODE -ne 0) { throw "an e.audio.mixer lifecycle, mix or resample answered wrongly: exit $LASTEXITCODE" }
# `e.audio.spatial` (D767) pins integer pan at the four bearings, linear attenuation over a
# source's range, gain-only placement on a live voice, and cues that draw a variant from the
# caller's generator and respect their cooldown.
$audioSpatialSurface = Get-Content (Join-Path $repo 'lib\e\audio\spatial.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.audio.spatial contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedAudioSpatialSurface = @('Listener', 'Source', 'Cue', 'Unknown', 'pan', 'attenuate', 'place', 'trigger', 'step_cues')
if (($audioSpatialSurface -join "`n") -ne ($expectedAudioSpatialSurface -join "`n")) { throw 'e.audio.spatial public declarations differ from module-apis.md' }
$audioSpatialParsed = & $compiler parse-file (Join-Path $repo 'lib\e\audio\spatial.e')
if ($LASTEXITCODE -ne 0 -or $audioSpatialParsed -ne 'parse file ok') { throw 'e.audio.spatial failed CLI parsing' }
$audioSpatialPath = Join-Path $testBuild 'audio-spatial-selfhost.exe'
$audioSpatialWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\audio_spatial\src\main.e') $repo 'x64' 'windows' $audioSpatialPath
if ($LASTEXITCODE -ne 0 -or $audioSpatialWritten -ne 'executable written') { throw 'e.audio.spatial emission failed' }
$audioSpatialOutput = & $audioSpatialPath
if ($LASTEXITCODE -ne 0 -or $audioSpatialOutput -ne 'audio spatial ok') { throw "an e.audio.spatial pan, attenuation, placement or cue answered wrongly: exit $LASTEXITCODE" }
# `e.fmt.wav` pins bounded PCM RIFF parsing, streaming decode, seek and exact encoding.
$wavPath = Join-Path $testBuild 'fmt-wav-selfhost.exe'
$wavWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_wav\src\main.e') $repo 'x64' 'windows' $wavPath
if ($LASTEXITCODE -ne 0 -or $wavWritten -ne 'executable written') { throw 'e.fmt.wav emission failed' }
& $wavPath
if ($LASTEXITCODE -ne 0) { throw "an e.fmt.wav open, decode, seek or encode answered wrongly: exit $LASTEXITCODE" }
# `e.fmt.mp3` (D770): Layer III against minimp3 -- three LAME streams whole, chunked and after a seek, within two LSB.
$mp3Path = Join-Path $testBuild 'fmt-mp3-selfhost.exe'
$mp3Written = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/fmt_mp3/src/main.e') $repo 'x64' 'windows' $mp3Path
if ($LASTEXITCODE -ne 0 -or $mp3Written -ne 'executable written') { throw 'e.fmt.mp3 emission failed' }
$mp3Output = & $mp3Path
if ($LASTEXITCODE -ne 0 -or $mp3Output -ne 'fmt mp3 ok') { throw "an e.fmt.mp3 decode, seek or refusal answered wrongly: exit $LASTEXITCODE" }
# `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.image` (D774): rectangles, transforms and a bounded path
# builder; sRGB, premultiplication and brush validation; images sized, cleared, blitted with clipping.
$gfxCorePath = Join-Path $testBuild 'gfx-core-selfhost.exe'
$gfxCoreWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gfx_core\src\main.e') $repo 'x64' 'windows' $gfxCorePath
if ($LASTEXITCODE -ne 0 -or $gfxCoreWritten -ne 'executable written') { throw 'gfx_core emission failed' }
$gfxCoreOutput = & $gfxCorePath
if ($LASTEXITCODE -ne 0 -or $gfxCoreOutput -ne 'gfx core ok') { throw "an e.gfx.geometry, e.gfx.paint or e.gfx.image answer was wrong: exit $LASTEXITCODE" }
# `e.fmt.png` (D774): every colour type and depth, tRNS and Adam7 decoded identically to libpng
# through Pillow; an exact encode read back by both decoders; refusals for APNG and bounds.
$fmtPngPath = Join-Path $testBuild 'fmt-png-selfhost.exe'
$fmtPngWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_png\src\main.e') $repo 'x64' 'windows' $fmtPngPath
if ($LASTEXITCODE -ne 0 -or $fmtPngWritten -ne 'executable written') { throw 'fmt_png emission failed' }
$fmtPngOutput = & $fmtPngPath
if ($LASTEXITCODE -ne 0 -or $fmtPngOutput -ne 'fmt png ok') { throw "an e.fmt.png decode, encode or refusal answered wrongly: exit $LASTEXITCODE" }
# `e.fmt.jpeg` (D774): baseline 4:4:4 and 4:2:0, progressive, greyscale and restart intervals within
# a few steps of libjpeg; a baseline encode decoded back within libjpeg's own error.
$fmtJpegPath = Join-Path $testBuild 'fmt-jpeg-selfhost.exe'
$fmtJpegWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_jpeg\src\main.e') $repo 'x64' 'windows' $fmtJpegPath
if ($LASTEXITCODE -ne 0 -or $fmtJpegWritten -ne 'executable written') { throw 'fmt_jpeg emission failed' }
$fmtJpegOutput = & $fmtJpegPath
if ($LASTEXITCODE -ne 0 -or $fmtJpegOutput -ne 'fmt jpeg ok') { throw "an e.fmt.jpeg decode, encode or refusal answered wrongly: exit $LASTEXITCODE" }
# `e.fmt.webp` (D774): VP8L decoded exactly and VP8 with ALPH within a few steps of libwebp, an
# animation inspected and decoded first-frame-only, an exact lossless encode libwebp reads back.
$fmtWebpPath = Join-Path $testBuild 'fmt-webp-selfhost.exe'
$fmtWebpWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_webp\src\main.e') $repo 'x64' 'windows' $fmtWebpPath
if ($LASTEXITCODE -ne 0 -or $fmtWebpWritten -ne 'executable written') { throw 'fmt_webp emission failed' }
$fmtWebpOutput = & $fmtWebpPath
if ($LASTEXITCODE -ne 0 -or $fmtWebpOutput -ne 'fmt webp ok') { throw "an e.fmt.webp inspect, decode, encode or refusal answered wrongly: exit $LASTEXITCODE" }
# `e.text.layout` (D775): paragraphs over two synthetic fonts -- wrapping, alignment, justification,
# fallback and two-level bidi, a line budget with an ellipsis, hit testing, carets and selections.
$textLayoutPath = Join-Path $testBuild 'text-layout-selfhost.exe'
$textLayoutWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\text_layout\src\main.e') $repo 'x64' 'windows' $textLayoutPath
if ($LASTEXITCODE -ne 0 -or $textLayoutWritten -ne 'executable written') { throw 'text_layout emission failed' }
$textLayoutOutput = & $textLayoutPath
if ($LASTEXITCODE -ne 0 -or $textLayoutOutput -ne 'text layout ok') { throw "an e.text.layout line, caret, hit test or refusal answered wrongly: exit $LASTEXITCODE" }
# `e.ui.style`, `e.ui.layout` (D775): style defaults and validation; flex growth, shrinking, every
# alignment, unbounded limits; grid tracks fixed, auto and flexible with gaps; Invalid and Overflow.
$uiCorePath = Join-Path $testBuild 'ui-core-selfhost.exe'
$uiCoreWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_core\src\main.e') $repo 'x64' 'windows' $uiCorePath
if ($LASTEXITCODE -ne 0 -or $uiCoreWritten -ne 'executable written') { throw 'ui_core emission failed' }
$uiCoreOutput = & $uiCorePath
if ($LASTEXITCODE -ne 0 -or $uiCoreOutput -ne 'ui core ok') { throw "an e.ui.style or e.ui.layout answer was wrong: exit $LASTEXITCODE" }
# `e.test.fuzz` (D776): deterministic mutation from the seed finds a two-byte failure twice alike,
# minimization lands on those two bytes, budgets and deadlines stop, corpus and bound refusals.
$testFuzzPath = Join-Path $testBuild 'test-fuzz-selfhost.exe'
$testFuzzWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\test_fuzz\src\main.e') $repo 'x64' 'windows' $testFuzzPath
if ($LASTEXITCODE -ne 0 -or $testFuzzWritten -ne 'executable written') { throw 'test_fuzz emission failed' }
$testFuzzOutput = & $testFuzzPath
if ($LASTEXITCODE -ne 0 -or $testFuzzOutput -ne 'test fuzz ok') { throw "an e.test.fuzz run, minimization or refusal answered wrongly: exit $LASTEXITCODE" }
# `e.test.coverage` (D776): hits through the instrumentation entry, snapshot, reset, merge sorted
# by file and region with a duplicate refused, and the JSON shape.
$testCoveragePath = Join-Path $testBuild 'test-coverage-selfhost.exe'
$testCoverageWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\test_coverage\src\main.e') $repo 'x64' 'windows' $testCoveragePath
if ($LASTEXITCODE -ne 0 -or $testCoverageWritten -ne 'executable written') { throw 'test_coverage emission failed' }
$testCoverageOutput = & $testCoveragePath
if ($LASTEXITCODE -ne 0 -or $testCoverageOutput -ne 'test coverage ok') { throw "an e.test.coverage snapshot, merge or JSON answered wrongly: exit $LASTEXITCODE" }
# `e.asset` (D777): the fixture project's `project.yaml` assets become the registry --
# sorted, hashed, typed, attributed -- through the compiler-generated overlay; a project
# without a manifest has the empty registry; a manifest entry the loader does not accept
# is reported at the manifest under E-MODULE-9999.
$assetPath = Join-Path $testBuild 'asset-selfhost.exe'
$assetWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\asset\src\main.e') $repo 'x64' 'windows' $assetPath
if ($LASTEXITCODE -ne 0 -or $assetWritten -ne 'executable written') { throw 'asset emission failed' }
$assetOutput = & $assetPath
if ($LASTEXITCODE -ne 0 -or $assetOutput -ne 'asset ok') { throw "an e.asset registry lookup answered wrongly: exit $LASTEXITCODE" }
# The build manifest lists every declared asset (D792): sorted by name, with the
# project-relative path, media type, attributes, size and SHA-256.
$assetManifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\link\asset\.neper\debug\build-manifest.json'))
if ($assetManifest -notmatch '"assets":\[\{"name":"bytes/all@1x","source":\{"root":"project","path":"assets/all.bin"\},"media_type":"application/octet-stream","attributes":\[\{"name":"base","value":"bytes/all"\},\{"name":"scale","value":"1"\}\],"size":256,"sha256":"40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880"\},\{"name":"bytes/empty",.*\{"name":"text/hello","source":\{"root":"project","path":"assets/hello.txt"\},"media_type":"text/plain","attributes":\[\{"name":"base","value":"text/hello"\},\{"name":"locale","value":""\},\{"name":"theme","value":"any"\}\],"size":18,"sha256":"30d428be3e8f02a9e56e7d2363a421eb0f883382216df0c6c9c34e639d7ac9b0"\}\]') { throw "the build manifest does not list the declared assets: $assetManifest" }
$assetEmptyPath = Join-Path $testBuild 'asset-empty-selfhost.exe'
$assetEmptyWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\asset_empty\src\main.e') $repo 'x64' 'windows' $assetEmptyPath
if ($LASTEXITCODE -ne 0 -or $assetEmptyWritten -ne 'executable written') { throw 'asset_empty emission failed' }
$assetEmptyOutput = & $assetEmptyPath
if ($LASTEXITCODE -ne 0 -or $assetEmptyOutput -ne 'asset empty ok') { throw "the empty e.asset registry answered wrongly: exit $LASTEXITCODE" }
$assetInvalidOutput = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\asset_invalid\src\main.e') $repo 'x64' 'windows' (Join-Path $testBuild 'asset-invalid-selfhost.exe') 2>&1
if ($LASTEXITCODE -ne 1 -or ($assetInvalidOutput -join "`n") -notmatch 'project\.yaml:1:1: error\[E-MODULE-9999\]: `project\.yaml` has an `assets:` entry the loader does not accept') {
    throw 'an asset manifest entry with an unknown key was not rejected at the manifest'
}
# `e.gpu` on the CPU backend (D778): the device, queues, buffers, `gpu.launch[K]` over
# a 1-D and a 2-D kernel with the ids, tokens and every refusal; `examples/saxpy.e`
# prints the CPU checksum; a kernel called directly, a bare `@gpu` and a host slice
# in a launch pack are refused at the call.
$gpuCpuPath = Join-Path $testBuild 'gpu-cpu-selfhost.exe'
$gpuCpuWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gpu_cpu\src\main.e') $repo 'x64' 'windows' $gpuCpuPath
if ($LASTEXITCODE -ne 0 -or $gpuCpuWritten -ne 'executable written') { throw 'gpu_cpu emission failed' }
$gpuCpuOutput = & $gpuCpuPath
if ($LASTEXITCODE -ne 0 -or $gpuCpuOutput -ne 'gpu cpu ok') { throw "an e.gpu device, buffer, launch or refusal answered wrongly: exit $LASTEXITCODE" }
$saxpyPath = Join-Path $testBuild 'saxpy-selfhost.exe'
$saxpyWritten = & $compiler emit-executable (Join-Path $repo 'examples\saxpy.e') $repo 'x64' 'windows' $saxpyPath
if ($LASTEXITCODE -ne 0 -or $saxpyWritten -ne 'executable written') { throw 'examples/saxpy.e emission failed' }
$saxpyOutput = & $saxpyPath
if ($LASTEXITCODE -ne 0 -or ($saxpyOutput -join "`n") -ne 'cpu    checksum 16777216') { throw "examples/saxpy.e answered wrongly: $($saxpyOutput -join "`n")" }
$gpuDirect = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\gpu_direct_call\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($gpuDirect -join "`n") -notmatch 'main\.e:9:5: error\[E-TYPE-9999\]: `fill` is a kernel and can only be run through `gpu\.launch`') { throw "a direct kernel call was not refused: $($gpuDirect -join "`n")" }
$gpuBare = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\gpu_bare_attribute\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($gpuBare -join "`n") -notmatch 'main\.e:4:1: error\[E-TYPE-9999\]: `fill` carries `@gpu` without a usable workgroup size') { throw "a bare @gpu was not refused: $($gpuBare -join "`n")" }
$gpuArgument = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\gpu_launch_argument\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($gpuArgument -join "`n") -notmatch 'main\.e:9:9: error\[E-TYPE-9999\]: `fill` takes a device slice at this position') { throw "a host slice in a launch pack was not refused: $($gpuArgument -join "`n")" }
# `e.gpu.tensor` (D779): a strided host view uploaded contiguous, `add` and `matmul` as
# launches agreeing with the host tensor module and the plain formula, an i64 kernel,
# every `Shape` refusal, a released tensor stale.
$gpuTensorPath = Join-Path $testBuild 'gpu-tensor-selfhost.exe'
$gpuTensorWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gpu_tensor\src\main.e') $repo 'x64' 'windows' $gpuTensorPath
if ($LASTEXITCODE -ne 0 -or $gpuTensorWritten -ne 'executable written') { throw 'gpu_tensor emission failed' }
$gpuTensorOutput = & $gpuTensorPath
if ($LASTEXITCODE -ne 0 -or $gpuTensorOutput -ne 'gpu tensor ok') { throw "an e.gpu.tensor upload, launch, download or refusal answered wrongly: exit $LASTEXITCODE" }
# `gpu.barrier()` on the CPU backend (D780): the barrier loop-fission machine over device
# memory, a barrier in a loop, two workgroups apart, a barrier-free kernel under the same
# frames; an invocation returning before a barrier its peers reach traps as `barrier`;
# a barrier outside a kernel is refused.
$gpuBarrierPath = Join-Path $testBuild 'gpu-barrier-selfhost.exe'
$gpuBarrierWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gpu_barrier\src\main.e') $repo 'x64' 'windows' $gpuBarrierPath
if ($LASTEXITCODE -ne 0 -or $gpuBarrierWritten -ne 'executable written') { throw 'gpu_barrier emission failed' }
$gpuBarrierOutput = & $gpuBarrierPath
if ($LASTEXITCODE -ne 0 -or $gpuBarrierOutput -ne 'gpu barrier ok') { throw "a kernel with barriers answered wrongly: exit $LASTEXITCODE" }
$gpuDivergencePath = Join-Path $testBuild 'gpu-divergence-selfhost.exe'
$gpuDivergenceWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gpu_divergence\src\main.e') $repo 'x64' 'windows' $gpuDivergencePath
if ($LASTEXITCODE -ne 0 -or $gpuDivergenceWritten -ne 'executable written') { throw 'gpu_divergence emission failed' }
$gpuDivergenceOutput = & $gpuDivergencePath 2>&1
if ($LASTEXITCODE -ne 134 -or ($gpuDivergenceOutput -join "`n") -notmatch 'trap\[barrier\]: invocation \(2, 0, 0\) of workgroup \(0, 0, 0\) returned before barrier 1 that invocation \(0, 0, 0\)') { throw "a divergent workgroup did not trap as barrier: exit $LASTEXITCODE, $($gpuDivergenceOutput -join "`n")" }
$gpuOutside = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\gpu_barrier_outside\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($gpuOutside -join "`n") -notmatch 'main\.e:4:5: error\[E-TYPE-9999\]: `gpu\.barrier\(\)` is written outside a kernel') { throw "a barrier outside a kernel was not refused: $($gpuOutside -join "`n")" }
# `shared var` on the CPU backend (D781): the spec's block sum through workgroup memory
# over three workgroups, a struct-typed shared var, the 0xCD fill before the publishing
# barrier; a shared var outside a kernel and one with an initialiser are refused.
$gpuSharedPath = Join-Path $testBuild 'gpu-shared-selfhost.exe'
$gpuSharedWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gpu_shared\src\main.e') $repo 'x64' 'windows' $gpuSharedPath
if ($LASTEXITCODE -ne 0 -or $gpuSharedWritten -ne 'executable written') { throw 'gpu_shared emission failed' }
$gpuSharedOutput = & $gpuSharedPath
if ($LASTEXITCODE -ne 0 -or $gpuSharedOutput -ne 'gpu shared ok') { throw "a kernel with shared memory answered wrongly: exit $LASTEXITCODE" }
$gpuSharedOutside = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\gpu_shared_outside\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($gpuSharedOutside -join "`n") -notmatch 'main\.e:4:5: error\[E-TYPE-9999\]: `shared var` is legal only directly in a kernel') { throw "a shared var outside a kernel was not refused: $($gpuSharedOutside -join "`n")" }
$gpuSharedInit = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\gpu_shared_initializer\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($gpuSharedInit -join "`n") -notmatch 'main\.e:5:5: error\[E-TYPE-9999\]: `tile` is a `shared var` with an initialiser') { throw "a shared var with an initialiser was not refused: $($gpuSharedInit -join "`n")" }
# `meta.signed[T]()` (D782): folded like `meta.kind`, a bare or negated bool question
# settles an `if`; `link/gpu_tensor` reaches the unsigned kernels through it.
$metaSignedPath = Join-Path $testBuild 'meta-signed-selfhost.exe'
$metaSignedWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\meta_signed\src\main.e') $repo 'x64' 'windows' $metaSignedPath
if ($LASTEXITCODE -ne 0 -or $metaSignedWritten -ne 'executable written') { throw 'meta_signed emission failed' }
$metaSignedOutput = & $metaSignedPath
if ($LASTEXITCODE -ne 0 -or $metaSignedOutput -ne 'meta signed ok') { throw "meta.signed answered wrongly: exit $LASTEXITCODE" }
# `printf` and `format` inside a generic of another module (D784): the template body
# accepts a `T` it cannot format yet, and each instance's expansion is the caller's.
$formatGenericPath = Join-Path $testBuild 'format-generic-selfhost.exe'
$formatGenericWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\format_generic\src\main.e') $repo 'x64' 'windows' $formatGenericPath
if ($LASTEXITCODE -ne 0 -or $formatGenericWritten -ne 'executable written') { throw 'format_generic emission failed' }
$formatGenericOutput = & $formatGenericPath
if ($LASTEXITCODE -ne 0 -or ($formatGenericOutput -join "`n") -ne 'n=42;m=-7;x=2.5;format generic ok') { throw "a formatter in a cross-module generic answered wrongly: $($formatGenericOutput -join "`n")" }
# The fault buffer (D785): a kernel's failed bounds check is a record `sync` and
# `download` answer as `Fault` once, the invocation gone and the others finished;
# a `@nocheck` block carries no check and no record.
foreach ($faultCase in @(@('gpu_fault_bounds', 'gpu fault ok'), @('gpu_fault_nocheck', 'gpu nocheck ok'))) {
    $faultPath = Join-Path $testBuild ($faultCase[0] + '-selfhost.exe')
    $faultWritten = & $compiler emit-executable (Join-Path $PSScriptRoot ('fixtures\link\' + $faultCase[0] + '\src\main.e')) $repo 'x64' 'windows' $faultPath
    if ($LASTEXITCODE -ne 0 -or $faultWritten -ne 'executable written') { throw "$($faultCase[0]) emission failed" }
    $faultOutput = & $faultPath
    if ($LASTEXITCODE -ne 0 -or $faultOutput -ne $faultCase[1]) { throw "$($faultCase[0]) answered wrongly: exit $LASTEXITCODE" }
}
# Presentation (D791): images a kernel writes, an offscreen target's frames acquired,
# presented and read back as the snapshot, resize, and the refusals.
$gpuPresentPath = Join-Path $testBuild 'gpu-present-selfhost.exe'
$gpuPresentWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gpu_present\src\main.e') $repo 'x64' 'windows' $gpuPresentPath
if ($LASTEXITCODE -ne 0 -or $gpuPresentWritten -ne 'executable written') { throw 'gpu_present emission failed' }
$gpuPresentOutput = & $gpuPresentPath
if ($LASTEXITCODE -ne 0 -or $gpuPresentOutput -ne 'gpu present ok') { throw "presentation answered wrongly: exit $LASTEXITCODE" }
# The native window primitives (D795): a hidden window's metrics, title, cursor,
# present, a second shown for its first events, capture, the primary monitor, the
# clipboard's text, and a closed handle stale.
$osWindowPath = Join-Path $testBuild 'os-window-selfhost.exe'
$osWindowWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_window\src\main.e') $repo 'x64' 'windows' $osWindowPath
if ($LASTEXITCODE -ne 0 -or $osWindowWritten -ne 'executable written') { throw 'os_window emission failed' }
$osWindowOutput = & $osWindowPath
if ($LASTEXITCODE -ne 0 -or $osWindowOutput -ne 'os window ok') { throw "the window primitives answered wrongly: exit $LASTEXITCODE" }
# `e.gfx.scene` (D796): the CPU reference renderer over an offscreen target -- fills,
# an anti-aliased edge, clips, a gradient, a stroke, an image, a glyph, a layer, a
# rotation -- checked pixel by pixel, and the refusals.
$gfxScenePath = Join-Path $testBuild 'gfx-scene-selfhost.exe'
$gfxSceneWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\gfx_scene\src\main.e') $repo 'x64' 'windows' $gfxScenePath
if ($LASTEXITCODE -ne 0 -or $gfxSceneWritten -ne 'executable written') { throw 'gfx_scene emission failed' }
$gfxSceneOutput = & $gfxScenePath
if ($LASTEXITCODE -ne 0 -or $gfxSceneOutput -ne 'gfx scene ok') { throw "the scene renderer answered wrongly: exit $LASTEXITCODE" }
# `e.ui.window` and `e.ui.input` (D797): a window with a scene target, a frame shown
# through request_frame and its Frame event first, the host's events by window id.
$uiWindowPath = Join-Path $testBuild 'ui-window-selfhost.exe'
$uiWindowWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_window\src\main.e') $repo 'x64' 'windows' $uiWindowPath
if ($LASTEXITCODE -ne 0 -or $uiWindowWritten -ne 'executable written') { throw 'ui_window emission failed' }
$uiWindowOutput = & $uiWindowPath
if ($LASTEXITCODE -ne 0 -or $uiWindowOutput -ne 'ui window ok') { throw "the ui window answered wrongly: exit $LASTEXITCODE" }
# `e.ui.asset` (D798): variants chosen by locale, theme and scale from the fixture
# project's registry, a font from it, and the texture cache over a renderer.
$uiAssetPath = Join-Path $testBuild 'ui-asset-selfhost.exe'
$uiAssetWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_asset\src\main.e') $repo 'x64' 'windows' $uiAssetPath
if ($LASTEXITCODE -ne 0 -or $uiAssetWritten -ne 'executable written') { throw 'ui_asset emission failed' }
$uiAssetOutput = & $uiAssetPath
if ($LASTEXITCODE -ne 0 -or $uiAssetOutput -ne 'ui asset ok') { throw "ui asset selection answered wrongly: exit $LASTEXITCODE" }
# `e.ui.widget` (D799): a tree reconciled, laid out, painted and read back; state by
# key across frames and a keyed reorder; a press dispatched; retirement; refusals.
$uiWidgetPath = Join-Path $testBuild 'ui-widget-selfhost.exe'
$uiWidgetWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_widget\src\main.e') $repo 'x64' 'windows' $uiWidgetPath
if ($LASTEXITCODE -ne 0 -or $uiWidgetWritten -ne 'executable written') { throw 'ui_widget emission failed' }
$uiWidgetOutput = & $uiWidgetPath
if ($LASTEXITCODE -ne 0 -or $uiWidgetOutput -ne 'ui widget ok') { throw "the widget runtime answered wrongly: exit $LASTEXITCODE" }
# `e.ui.testing` and `e.ui.animation` (D801): a harness pumping frames without a
# window, elements by key, a press sent, a snapshot compared; curves and controllers.
$uiTestingPath = Join-Path $testBuild 'ui-testing-selfhost.exe'
$uiTestingWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_testing\src\main.e') $repo 'x64' 'windows' $uiTestingPath
if ($LASTEXITCODE -ne 0 -or $uiTestingWritten -ne 'executable written') { throw 'ui_testing emission failed' }
$uiTestingOutput = & $uiTestingPath
if ($LASTEXITCODE -ne 0 -or $uiTestingOutput -ne 'ui testing ok') { throw "the ui harness answered wrongly: exit $LASTEXITCODE" }
# `e.ui.accessibility` and `e.ui.app` (D802): the semantic tree, a press performed
# through it, publication refused for a stale window; the app's init, step, stop, close.
$uiAccessibilityPath = Join-Path $testBuild 'ui-accessibility-selfhost.exe'
$uiAccessibilityWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_accessibility\src\main.e') $repo 'x64' 'windows' $uiAccessibilityPath
if ($LASTEXITCODE -ne 0 -or $uiAccessibilityWritten -ne 'executable written') { throw 'ui_accessibility emission failed' }
$uiAccessibilityOutput = & $uiAccessibilityPath
if ($LASTEXITCODE -ne 0 -or $uiAccessibilityOutput -ne 'ui accessibility ok') { throw "the accessibility tree answered wrongly: exit $LASTEXITCODE" }
$uiAppPath = Join-Path $testBuild 'ui-app-selfhost.exe'
$uiAppWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_app\src\main.e') $repo 'x64' 'windows' $uiAppPath
if ($LASTEXITCODE -ne 0 -or $uiAppWritten -ne 'executable written') { throw 'ui_app emission failed' }
$uiAppOutput = & $uiAppPath
if ($LASTEXITCODE -ne 0 -or $uiAppOutput -ne 'ui app ok') { throw "the ui app answered wrongly: exit $LASTEXITCODE" }
# Theme tokens (D805, widget plan P0-01): the reference palettes, role lookups, control
# state resolution, size classes and host adaptation.
$uiThemePath = Join-Path $testBuild 'ui-theme-selfhost.exe'
$uiThemeWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_theme\src\main.e') $repo 'x64' 'windows' $uiThemePath
if ($LASTEXITCODE -ne 0 -or $uiThemeWritten -ne 'executable written') { throw 'ui_theme emission failed' }
$uiThemeOutput = & $uiThemePath
if ($LASTEXITCODE -ne 0 -or $uiThemeOutput -ne 'ui theme ok') { throw "the theme tokens answered wrongly: exit $LASTEXITCODE" }
# Typed actions, gesture regions and scopes (D806, widget plan P0-02/P0-03): the
# arena settling taps, drags and hovers; Tab within a trapping scope; shortcuts.
$uiGesturePath = Join-Path $testBuild 'ui-gesture-selfhost.exe'
$uiGestureWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_gesture\src\main.e') $repo 'x64' 'windows' $uiGesturePath
if ($LASTEXITCODE -ne 0 -or $uiGestureWritten -ne 'executable written') { throw 'ui_gesture emission failed' }
$uiGestureOutput = & $uiGesturePath
if ($LASTEXITCODE -ne 0 -or $uiGestureOutput -ne 'ui gesture ok') { throw "the gesture arena answered wrongly: exit $LASTEXITCODE" }
# Editable text (D807, widget plan P0-04): caret and selection by hit test, typed
# text, clipboard, undo and redo, a multiline editor and a composition.
$uiEditPath = Join-Path $testBuild 'ui-edit-selfhost.exe'
$uiEditWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_edit\src\main.e') $repo 'x64' 'windows' $uiEditPath
if ($LASTEXITCODE -ne 0 -or $uiEditWritten -ne 'executable written') { throw 'ui_edit emission failed' }
$uiEditOutput = & $uiEditPath
if ($LASTEXITCODE -ne 0 -or $uiEditOutput -ne 'ui edit ok') { throw "the editable text answered wrongly: exit $LASTEXITCODE" }
# Viewports (D808, widget plan P0-05): the wheel, a drag with momentum, a bounce
# springing back, a scrollbar thumb, and a lazy viewport recycling its items.
$uiScrollPath = Join-Path $testBuild 'ui-scroll-selfhost.exe'
$uiScrollWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_scroll\src\main.e') $repo 'x64' 'windows' $uiScrollPath
if ($LASTEXITCODE -ne 0 -or $uiScrollWritten -ne 'executable written') { throw 'ui_scroll emission failed' }
$uiScrollOutput = & $uiScrollPath
if ($LASTEXITCODE -ne 0 -or $uiScrollOutput -ne 'ui scroll ok') { throw "the viewports answered wrongly: exit $LASTEXITCODE" }
# Semantics (D809, widget plan P0-06): roles, states, relationships, live regions,
# collection places, hidden subtrees, an editor's value and platform actions.
$uiSemanticsPath = Join-Path $testBuild 'ui-semantics-selfhost.exe'
$uiSemanticsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_semantics\src\main.e') $repo 'x64' 'windows' $uiSemanticsPath
if ($LASTEXITCODE -ne 0 -or $uiSemanticsWritten -ne 'executable written') { throw 'ui_semantics emission failed' }
$uiSemanticsOutput = & $uiSemanticsPath
if ($LASTEXITCODE -ne 0 -or $uiSemanticsOutput -ne 'ui semantics ok') { throw "the semantics answered wrongly: exit $LASTEXITCODE" }
# Overlays (D810, widget plan P0-07): root-level paint against an anchor, kept in the
# window, presses routed by the topmost, a modal taking and returning the focus.
$uiOverlayPath = Join-Path $testBuild 'ui-overlay-selfhost.exe'
$uiOverlayWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_overlay\src\main.e') $repo 'x64' 'windows' $uiOverlayPath
if ($LASTEXITCODE -ne 0 -or $uiOverlayWritten -ne 'executable written') { throw 'ui_overlay emission failed' }
$uiOverlayOutput = & $uiOverlayPath
if ($LASTEXITCODE -ne 0 -or $uiOverlayOutput -ne 'ui overlay ok') { throw "the overlays answered wrongly: exit $LASTEXITCODE" }
# The host capability model (D811, widget plan P0-08): capabilities, insets,
# orientation, screens, lifecycle, and the lifecycle, insets and back events.
$uiHostPath = Join-Path $testBuild 'ui-host-selfhost.exe'
$uiHostWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_host\src\main.e') $repo 'x64' 'windows' $uiHostPath
if ($LASTEXITCODE -ne 0 -or $uiHostWritten -ne 'executable written') { throw 'ui_host emission failed' }
$uiHostOutput = & $uiHostPath
if ($LASTEXITCODE -ne 0 -or $uiHostOutput -ne 'ui host ok') { throw "the host capabilities answered wrongly: exit $LASTEXITCODE" }
# The widget harness and the gallery (D812, widget plan P0-09): semantic queries,
# gestures, focus traversal, the fake IME, viewport visibility, overlays, a faked host.
$uiGalleryPath = Join-Path $testBuild 'ui-gallery-selfhost.exe'
$uiGalleryWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_gallery\src\main.e') $repo 'x64' 'windows' $uiGalleryPath
if ($LASTEXITCODE -ne 0 -or $uiGalleryWritten -ne 'executable written') { throw 'ui_gallery emission failed' }
$uiGalleryOutput = & $uiGalleryPath
if ($LASTEXITCODE -ne 0 -or $uiGalleryOutput -ne 'ui gallery ok') { throw "the gallery answered wrongly: exit $LASTEXITCODE" }
# Content controls (D813, widget plan P1-01): text under roles with a line budget,
# selectable text, rich text with links, icon, image and canvas under a theme.
$uiContentPath = Join-Path $testBuild 'ui-content-selfhost.exe'
$uiContentWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\ui_content\src\main.e') $repo 'x64' 'windows' $uiContentPath
if ($LASTEXITCODE -ne 0 -or $uiContentWritten -ne 'executable written') { throw 'ui_content emission failed' }
$uiContentOutput = & $uiContentPath
if ($LASTEXITCODE -ne 0 -or $uiContentOutput -ne 'ui content ok') { throw "the content controls answered wrongly: exit $LASTEXITCODE" }
# `e.fmt.ini` both ways over the same text: the document `parse` builds and the stream
# `reader` yields have to agree about what the format says. The format has no standard, so
# what the fixture pins is the choices -- a comment starts a line and nothing else, a
# case-insensitive parse folds the name it stores rather than the comparison it makes later,
# and a value is quoted on the way out only when leaving it bare would not read back as itself.
$iniPath = Join-Path $testBuild 'fmt-ini-selfhost.exe'
$iniWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\fmt_ini\src\main.e') $repo 'x64' 'windows' $iniPath
if ($LASTEXITCODE -ne 0 -or $iniWritten -ne 'executable written') { throw 'e.fmt.ini emission failed' }
Push-Location $fsScratch
& $iniPath
$iniExit = $LASTEXITCODE
Pop-Location
if ($iniExit -ne 0) { throw "an e.fmt.ini read or write answered wrongly: exit $iniExit" }
# Scalar f32 and f64 end to end. Float values live in general registers as raw bits
# and move into xmm only for the operation itself, so the fixture pins the literals,
# the four operators, IEEE comparison against a NaN, both conversion directions
# including the unsigned 64-bit edge, and float arguments across the convention.
$floatPath = Join-Path $testBuild 'float-scalar-selfhost.exe'
$floatWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\float_scalar\src\main.e') $repo 'x64' 'windows' $floatPath
if ($LASTEXITCODE -ne 0 -or $floatWritten -ne 'executable written') { throw 'float executable emission failed' }
& $floatPath
if ($LASTEXITCODE -ne 0) { throw 'a float literal, operator, comparison or conversion is wrong' }
# The read-only half of `e.str`: comparison, search, trim, split, the integer parsers
# and the forms that allocate. The fixture pins what an empty needle matches, where a
# non-overlapping count stops, that `lines` takes CRLF without inventing a final empty
# line, and that a parser rejects the value one past each end of its range.
$strPurePath = Join-Path $testBuild 'str-pure-selfhost.exe'
$strPureWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\str_pure\src\main.e') $repo 'x64' 'windows' $strPurePath
if ($LASTEXITCODE -ne 0 -or $strPureWritten -ne 'executable written') { throw 'str pure executable emission failed' }
& $strPurePath
if ($LASTEXITCODE -ne 0) { throw 'a string search, trim, split, join or integer parse is wrong' }
# Spec section 9 rules 3 and 5: a missing protocol names what to declare, and a
# protocol whose first parameter is not the type by value is rejected outright.
# A rejection test asserts only that the compiler failed, and a path that does not
# exist fails too -- so a fixture whose path is wrong passes for the wrong reason.
# Twice today a mangled path here did exactly that.
function Require-Fixture($name) {
    $fixturePath = Join-Path $repo ("tests\selfhost\fixtures\" + ($name -replace '/', '\\') + "\src\main.e")
    if (-not (Test-Path -LiteralPath $fixturePath)) { throw "fixture $name is missing" }
}

$protocolDiagnostics = @(
    @('protocol_missing', 'main\.e:4:9: error\[E-NAME-9999\]: no `cmp` protocol for `Point`; declare `fn point_cmp` in the module that declares the type'),
    @('protocol_signature', 'main\.e:6:9: error\[E-TYPE-0003\]: protocol `point_cmp` requires `fn\(main\.Point, main\.Point\) -> i32`, found `fn\(\*main\.Point, main\.Point\) -> i32`'),
    @('protocol_no_fallback', 'main\.e:6:9: error\[E-NAME-9999\]: no `cmp` protocol for `Pair`; declare `fn pair_cmp` in the module that declares the type')
)
foreach ($case in $protocolDiagnostics) {
    Require-Fixture ("check/" + $case[0])
    $protocolOutput = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($protocolOutput -join "`n") -notmatch $case[1]) {
        throw "protocol diagnostic for $($case[0]) is wrong: $($protocolOutput -join "`n")"
    }
}
# `ret` and `try` each reported one message for four different mistakes, so a returned
# value of the wrong type said "ret is not legal inside defer" in a file with no defer.
# Each situation now has its own text, and each is pinned to the message and not merely
# to the rejection.
$returnDiagnostics = @(
    @('return_type', 'main\.e:5:9: error\[E-TYPE-0002\]: the returned value does not have the declared return type'),
    @('return_count', 'main\.e:4:5: error\[E-TYPE-0003\]: ret gives a different number of values than this function returns'),
    @('return_values_unexpected', 'main\.e:4:5: error\[E-TYPE-0003\]: this function returns nothing, so ret takes no value'),
    @('return_inside_defer', 'main\.e:5:9: error\[E-TYPE-9999\]: ret is not legal inside defer'),
    @('try_cast', 'main\.e:4:5: error\[E-ERROR-9999\]: try needs a call that can fail; a conversion cannot'),
    @('try_not_fallible', 'main\.e:8:5: error\[E-ERROR-9999\]: try needs a call whose last result is an err'),
    @('try_no_propagate', 'main\.e:8:5: error\[E-ERROR-9999\]: try propagates an err, so the enclosing function must return one'),
    @('try_inside_defer', 'main\.e:9:9: error\[E-ERROR-9999\]: try is not legal inside defer'),
    @('aggregate_field_count', 'main\.e:12:17: error\[E-TYPE-9999\]: this literal gives a different number of fields than `Bad` declares'),
    @('break_outside_loop', 'main\.e:5:5: error\[E-TYPE-9999\]: break requires an enclosing loop or switch'),
    @('thread_create_context', 'main\.e:16:5: error\[E-TYPE-0002\]: type mismatch: expected `\*main\.Other`, found `\*main\.Ctx`')
)
foreach ($case in $returnDiagnostics) {
    Require-Fixture ("check/" + $case[0])
    $returnOutput = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($returnOutput -join "`n") -notmatch $case[1]) {
        throw "ret/try diagnostic for $($case[0]) is wrong: $($returnOutput -join "`n")"
    }
}
# `os.thread_create[Ctx]` binds a context type at the call and checks the entry point
# against it. The checker half only -- the runtime has no `neper_os_thread_create` yet.
$threadAccepted = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\thread_create_accepted\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $threadAccepted -ne 'module check ok') { throw 'a valid thread_create was rejected' }
# An aggregate's fields are one contiguous run, and resolving a field's type can
# instantiate a generic, which appends the instance's own fields. That split the run
# being collected, so `Holder` exposed `Box`'s `v` and hid its own `slot` -- the shape
# every `e.sync` lock is written in. Both halves are pinned: the read that has to work,
# and the leaked name that has to stop working.
Require-Fixture 'check/generic_instance_field'
$genericFieldAccepted = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\generic_instance_field\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $genericFieldAccepted -ne 'module check ok') { throw 'a field whose type is a generic instance was rejected' }
Require-Fixture 'check/generic_instance_field_leak'
$genericFieldLeak = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\generic_instance_field_leak\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($genericFieldLeak -join "`n") -notmatch 'main\.e:8:20: error\[E-TYPE-9999\]: `Holder` has no field `v`') {
    throw "a generic instance's own field leaked into the enclosing struct: $($genericFieldLeak -join "`n")"
}
# `e.channel`, over `e.sync`. The threaded half runs four producers through a channel
# that holds four, so every one of them blocks, and the close is what releases the
# consumers waiting on empty -- a close that failed to wake would hang here.
# Section 9's reflection, run rather than only checked: the offsets and sizes are
# asserted by hand, so a field read at the wrong offset is a wrong value here.
# `extern fn` bound by `@import`, reached through the image's import table. Two
# libraries and a repeated symbol, with effects that are observable -- a call that
# reached the wrong slot is a wrong answer, not a link error. Windows only until
# the ELF linker emits a dynamic image.
Require-Fixture 'check/extern_without_import'
$externUnbound = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\extern_without_import\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($externUnbound -join "`n") -notmatch 'main\.e:7:13: error\[E-TYPE-9999\]: `mystery` is an extern fn with no') { throw "an extern with no @import was not reported: $($externUnbound -join "`n")" }
# A `...` parameter outside the three intrinsic packs (D787): refused at the
# parameter, naming the function.
Require-Fixture 'check/argument_pack'
$packRefused = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\argument_pack\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($packRefused -join "`n") -notmatch 'main\.e:6:10: error\[E-TYPE-9999\]: `total` declares a `\.\.\.` parameter: an argument pack belongs to the three intrinsics') { throw "a user-declared argument pack was not refused: $($packRefused -join "`n")" }
$externPath = Join-Path $testBuild 'extern-import-selfhost.exe'
$externWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\extern_import\src\main.e') $repo 'x64' 'windows' $externPath
if ($LASTEXITCODE -ne 0 -or $externWritten -ne 'executable written') { throw 'imported extern executable emission failed' }
& $externPath
if ($LASTEXITCODE -ne 0) { throw 'an imported extern call reached the wrong symbol' }
# A C variadic through the same import table: `_snprintf` with an `f64` in a `...`
# position, which Win64 wants in the integer register of its slot as well.
$variadicPath = Join-Path $testBuild 'extern-variadic-selfhost.exe'
$variadicWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\extern_variadic\src\main.e') $repo 'x64' 'windows' $variadicPath
if ($LASTEXITCODE -ne 0 -or $variadicWritten -ne 'executable written') { throw 'variadic extern executable emission failed' }
& $variadicPath
if ($LASTEXITCODE -ne 0) { throw 'a variadic extern call printed the wrong text' }
# Section 11's trap protocol: a failed bounds check writes `file:line:col: trap[bounds]:
# <values>` to stderr and exits 134; the same program with no check tripped exits 0.
$trapPath = Join-Path $testBuild 'trap-bounds-selfhost.exe'
$trapWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_bounds\src\main.e') $repo 'x64' 'windows' $trapPath
if ($LASTEXITCODE -ne 0 -or $trapWritten -ne 'executable written') { throw 'trap fixture executable emission failed' }
$trapIndex = & $trapPath index 2>&1
if ($LASTEXITCODE -ne 134 -or ($trapIndex -join "`n") -notmatch 'main\.e:10:50: trap\[bounds\]: index 7 out of bounds for len 5') { throw "an index past the end did not trap as section 11 says: exit $LASTEXITCODE, $($trapIndex -join "`n")" }
$trapSlice = & $trapPath slice 2>&1
if ($LASTEXITCODE -ne 134 -or ($trapSlice -join "`n") -notmatch 'main\.e:13:16: trap\[bounds\]: slice end 7 out of bounds for len 5') { throw "a slice past the end did not trap as section 11 says: exit $LASTEXITCODE, $($trapSlice -join "`n")" }
& $trapPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the trap fixture tripped a check it should not have' }
# `unreachable()`: the literal form and the bare form each trap with kind `unreachable`,
# and a function may end in one instead of a `ret`.
$unreachablePath = Join-Path $testBuild 'trap-unreachable-selfhost.exe'
$unreachableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_unreachable\src\main.e') $repo 'x64' 'windows' $unreachablePath
if ($LASTEXITCODE -ne 0 -or $unreachableWritten -ne 'executable written') { throw 'unreachable fixture executable emission failed' }
$unreachableMessage = & $unreachablePath message 2>&1
if ($LASTEXITCODE -ne 134 -or ($unreachableMessage -join "`n") -notmatch 'main\.e:11:5: trap\[unreachable\]: n past the table') { throw "unreachable(...) did not trap as section 11 says: exit $LASTEXITCODE, $($unreachableMessage -join "`n")" }
$unreachableBare = & $unreachablePath bare 2>&1
if ($LASTEXITCODE -ne 134 -or ($unreachableBare -join "`n") -notmatch 'main\.e:21:9: trap\[unreachable\]: unreachable\(\) reached') { throw "unreachable() did not trap as section 11 says: exit $LASTEXITCODE, $($unreachableBare -join "`n")" }
& $unreachablePath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the unreachable fixture trapped on its ordinary path' }
# The arithmetic rows that trap in every mode: division by zero, the remainder by zero,
# the minimum divided by -1, and a shift count past the width -- scalar and over a
# vector's lanes, which is the same check -- each with its record.
$arithmeticPath = Join-Path $testBuild 'trap-arithmetic-selfhost.exe'
$arithmeticWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_arithmetic\src\main.e') $repo 'x64' 'windows' $arithmeticPath
if ($LASTEXITCODE -ne 0 -or $arithmeticWritten -ne 'executable written') { throw 'arithmetic trap fixture executable emission failed' }
$arithmeticOutput = & $arithmeticPath zero 2>&1
if ($LASTEXITCODE -ne 134 -or ($arithmeticOutput -join "`n") -notmatch 'main\.e:14:17: trap\[divide\]: 7 / 0 divides by zero') { throw "the zero case did not trap as section 11 says: exit $LASTEXITCODE, $($arithmeticOutput -join "`n")" }
$arithmeticOutput = & $arithmeticPath rem 2>&1
if ($LASTEXITCODE -ne 134 -or ($arithmeticOutput -join "`n") -notmatch 'main\.e:18:17: trap\[divide\]: 7 % 0 divides by zero') { throw "the rem case did not trap as section 11 says: exit $LASTEXITCODE, $($arithmeticOutput -join "`n")" }
$arithmeticOutput = & $arithmeticPath min 2>&1
if ($LASTEXITCODE -ne 134 -or ($arithmeticOutput -join "`n") -notmatch 'main\.e:23:17: trap\[divide\]: -2147483648 / -1 overflows') { throw "the min case did not trap as section 11 says: exit $LASTEXITCODE, $($arithmeticOutput -join "`n")" }
$arithmeticOutput = & $arithmeticPath shift 2>&1
if ($LASTEXITCODE -ne 134 -or ($arithmeticOutput -join "`n") -notmatch 'main\.e:27:17: trap\[shift\]: shift by 40 on a width of 32') { throw "the shift case did not trap as section 11 says: exit $LASTEXITCODE, $($arithmeticOutput -join "`n")" }
$arithmeticOutput = & $arithmeticPath vshift 2>&1
if ($LASTEXITCODE -ne 134 -or ($arithmeticOutput -join "`n") -notmatch 'main\.e:32:18: trap\[shift\]: shift by 40 on a width of 32') { throw "the vector shift case did not trap as section 11 says: exit $LASTEXITCODE, $($arithmeticOutput -join "`n")" }
& $arithmeticPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the arithmetic trap fixture trapped on its in-range path' }
# The `enum` row, which traps in every mode: `Kind(x)` naming no member, unsigned and
# signed, and the same casts naming members untouched.
$enumTrapPath = Join-Path $testBuild 'trap-enum-selfhost.exe'
$enumTrapWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_enum\src\main.e') $repo 'x64' 'windows' $enumTrapPath
if ($LASTEXITCODE -ne 0 -or $enumTrapWritten -ne 'executable written') { throw 'enum trap fixture executable emission failed' }
$enumTrapOutput = & $enumTrapPath color 2>&1
if ($LASTEXITCODE -ne 134 -or ($enumTrapOutput -join "`n") -notmatch 'main\.e:16:17: trap\[enum\]: no member of Color has value 7') { throw "the color case did not trap as section 11 says: exit $LASTEXITCODE, $($enumTrapOutput -join "`n")" }
$enumTrapOutput = & $enumTrapPath level 2>&1
if ($LASTEXITCODE -ne 134 -or ($enumTrapOutput -join "`n") -notmatch 'main\.e:20:17: trap\[enum\]: no member of Level has value -6') { throw "the level case did not trap as section 11 says: exit $LASTEXITCODE, $($enumTrapOutput -join "`n")" }
& $enumTrapPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'an enum cast naming a member trapped' }
# The `invalid` row for a representation (D548, D554, H03): bytes read as a `bool`,
# an enum or a tagged union through `mem.bitcast` trap in debug and in release, and
# not under `--unchecked`.
$invalidTrapSource = Join-Path $PSScriptRoot 'fixtures\link\trap_invalid\src\main.e'
foreach ($invalidMode in @(@('debug', @()), @('release', @('--release')), @('unchecked', @('--release', '--unchecked')))) {
    $invalidTrapPath = Join-Path $testBuild "trap-invalid-$($invalidMode[0]).exe"
    $invalidTrapWritten = & $compiler emit-executable $invalidTrapSource $repo 'x64' 'windows' $invalidTrapPath @($invalidMode[1])
    if ($LASTEXITCODE -ne 0 -or $invalidTrapWritten -ne 'executable written') { throw "invalid trap fixture executable emission failed ($($invalidMode[0]))" }
    $invalidTrapOutput = & $invalidTrapPath bool 2>&1
    if ($invalidMode[0] -eq 'unchecked') {
        if ($LASTEXITCODE -ne 0) { throw "an unchecked pun to bool trapped (exit $LASTEXITCODE)" }
        foreach ($uncheckedRepresentation in @('color', 'bool-bytes', 'color-bytes', 'union')) {
            & $invalidTrapPath $uncheckedRepresentation 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "an unchecked pun to $uncheckedRepresentation trapped (exit $LASTEXITCODE)" }
        }
    } else {
        if ($LASTEXITCODE -ne 134 -or ($invalidTrapOutput -join "`n") -notmatch 'main\.e:16:17: trap\[invalid\]: no bool has value 7') { throw "the bool case did not trap as section 11 says ($($invalidMode[0])): exit $LASTEXITCODE, $($invalidTrapOutput -join ' ')" }
        $invalidTrapOutput = & $invalidTrapPath color 2>&1
        if ($LASTEXITCODE -ne 134 -or ($invalidTrapOutput -join "`n") -notmatch 'main\.e:20:17: trap\[invalid\]: no member of Color has value 7') { throw "the color case did not trap as section 11 says ($($invalidMode[0])): exit $LASTEXITCODE, $($invalidTrapOutput -join ' ')" }
        $invalidTrapOutput = & $invalidTrapPath bool-bytes 2>&1
        if ($LASTEXITCODE -ne 134 -or ($invalidTrapOutput -join "`n") -notmatch 'main\.e:25:17: trap\[invalid\]: no bool has value 7') { throw "the bool byte-array case did not trap as section 11 says ($($invalidMode[0])): exit $LASTEXITCODE, $($invalidTrapOutput -join ' ')" }
        $invalidTrapOutput = & $invalidTrapPath color-bytes 2>&1
        if ($LASTEXITCODE -ne 134 -or ($invalidTrapOutput -join "`n") -notmatch 'main\.e:30:17: trap\[invalid\]: no member of Color has value 7') { throw "the enum byte-array case did not trap as section 11 says ($($invalidMode[0])): exit $LASTEXITCODE, $($invalidTrapOutput -join ' ')" }
        $invalidTrapOutput = & $invalidTrapPath union 2>&1
        if ($LASTEXITCODE -ne 134 -or ($invalidTrapOutput -join "`n") -notmatch 'main\.e:35:21: trap\[invalid\]: no member of Maybe has value 7') { throw "the tagged-union case did not trap as section 11 says ($($invalidMode[0])): exit $LASTEXITCODE, $($invalidTrapOutput -join ' ')" }
    }
    & $invalidTrapPath none 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "a pun to a valid representation trapped ($($invalidMode[0]))" }
}
# The `narrow` row: a checked integer cast whose value does not fit, by width, by sign
# and by both, and the meant truncation `T.trunc(x)` that never checks.
$narrowPath = Join-Path $testBuild 'trap-narrow-selfhost.exe'
$narrowWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_narrow\src\main.e') $repo 'x64' 'windows' $narrowPath
if ($LASTEXITCODE -ne 0 -or $narrowWritten -ne 'executable written') { throw 'narrow trap fixture executable emission failed' }
$narrowOutput = & $narrowPath wide 2>&1
if ($LASTEXITCODE -ne 134 -or ($narrowOutput -join "`n") -notmatch 'main\.e:15:17: trap\[narrow\]: 300 does not fit u8') { throw "the wide case did not trap as section 11 says: exit $LASTEXITCODE, $($narrowOutput -join "`n")" }
$narrowOutput = & $narrowPath negative 2>&1
if ($LASTEXITCODE -ne 134 -or ($narrowOutput -join "`n") -notmatch 'main\.e:20:17: trap\[narrow\]: -300 does not fit u16') { throw "the negative case did not trap as section 11 says: exit $LASTEXITCODE, $($narrowOutput -join "`n")" }
$narrowOutput = & $narrowPath sign 2>&1
if ($LASTEXITCODE -ne 134 -or ($narrowOutput -join "`n") -notmatch 'main\.e:24:17: trap\[narrow\]: 200 does not fit i8') { throw "the sign case did not trap as section 11 says: exit $LASTEXITCODE, $($narrowOutput -join "`n")" }
$narrowOutput = & $narrowPath unsigned 2>&1
if ($LASTEXITCODE -ne 134 -or ($narrowOutput -join "`n") -notmatch 'main\.e:28:17: trap\[narrow\]: -298 does not fit usize') { throw "the unsigned case did not trap as section 11 says: exit $LASTEXITCODE, $($narrowOutput -join "`n")" }
$narrowOutput = & $narrowPath same 2>&1
if ($LASTEXITCODE -ne 134 -or ($narrowOutput -join "`n") -notmatch 'main\.e:32:17: trap\[narrow\]: 4294967000 does not fit i32') { throw "the same case did not trap as section 11 says: exit $LASTEXITCODE, $($narrowOutput -join "`n")" }
& $narrowPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'a cast that fits, or a meant truncation, trapped' }
# Section 13's failure line: `main` returning an error writes `error: <qualified name>`
# to stderr, for this module's error and for one of `e.os`'s, and exits 1.
$failurePath = Join-Path $testBuild 'failure-line-selfhost.exe'
$failureWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\failure_line\src\main.e') $repo 'x64' 'windows' $failurePath
if ($LASTEXITCODE -ne 0 -or $failureWritten -ne 'executable written') { throw 'failure line fixture executable emission failed' }
$failureOwn = & $failurePath own 2>&1
if ($LASTEXITCODE -ne 1 -or ($failureOwn -join "`n") -ne 'error: main.Boom') { throw "main returning its own error did not write the failure line: exit $LASTEXITCODE, $($failureOwn -join "`n")" }
$failureOs = & $failurePath os 2>&1
if ($LASTEXITCODE -ne 1 -or ($failureOs -join "`n") -ne 'error: e.os.NotFound') { throw "main returning e.os's error did not write the failure line: exit $LASTEXITCODE, $($failureOs -join "`n")" }
$failureTry = & $failurePath try 2>&1
if ($LASTEXITCODE -ne 1 -or ($failureTry -join "`n") -ne 'error: main.Tried') { throw "a failing try in main did not write the failure line: exit $LASTEXITCODE, $($failureTry -join "`n")" }
$failureNone = & $failurePath none 2>&1
if ($LASTEXITCODE -ne 0 -or ($failureNone -join "`n") -ne '') { throw 'main returning ok wrote a failure line' }
# The `tag` row -- a payload read or written under another member's tag -- and the
# float side of `narrow`: NaN and values past the target's range refused.
$tagPath = Join-Path $testBuild 'trap-tag-selfhost.exe'
$tagWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_tag\src\main.e') $repo 'x64' 'windows' $tagPath
if ($LASTEXITCODE -ne 0 -or $tagWritten -ne 'executable written') { throw 'tag trap fixture executable emission failed' }
$tagOutput = & $tagPath tag 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagOutput -join "`n") -notmatch 'main\.e:17:17: trap\[tag\]: Node\.Pair read while the tag is 1') { throw "the tag case did not trap as section 11 says: exit $LASTEXITCODE, $($tagOutput -join "`n")" }
$tagOutput = & $tagPath write 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagOutput -join "`n") -notmatch 'main\.e:22:9: trap\[tag\]: Node\.Lit read while the tag is 0') { throw "the write case did not trap as section 11 says: exit $LASTEXITCODE, $($tagOutput -join "`n")" }
$tagOutput = & $tagPath nan 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagOutput -join "`n") -notmatch 'main\.e:26:17: trap\[narrow\]: a float outside i32') { throw "the nan case did not trap as section 11 says: exit $LASTEXITCODE, $($tagOutput -join "`n")" }
$tagOutput = & $tagPath big 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagOutput -join "`n") -notmatch 'main\.e:31:17: trap\[narrow\]: a float outside i32') { throw "the big case did not trap as section 11 says: exit $LASTEXITCODE, $($tagOutput -join "`n")" }
$tagOutput = & $tagPath negative 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagOutput -join "`n") -notmatch 'main\.e:36:17: trap\[narrow\]: a float outside u16') { throw "the negative case did not trap as section 11 says: exit $LASTEXITCODE, $($tagOutput -join "`n")" }
$tagOutput = & $tagPath wide 2>&1
if ($LASTEXITCODE -ne 134 -or ($tagOutput -join "`n") -notmatch 'main\.e:41:17: trap\[narrow\]: a float outside i64') { throw "the wide case did not trap as section 11 says: exit $LASTEXITCODE, $($tagOutput -join "`n")" }
& $tagPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'a live payload read, or a float cast that fits, trapped' }
# The `null` row: a field read or written through a nil pointer, and `*p` read or
# written, each refused; the same through live pointers untouched.
$nullPath = Join-Path $testBuild 'trap-null-selfhost.exe'
$nullWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_null\src\main.e') $repo 'x64' 'windows' $nullPath
if ($LASTEXITCODE -ne 0 -or $nullWritten -ne 'executable written') { throw 'null trap fixture executable emission failed' }
$nullOutput = & $nullPath field 2>&1
if ($LASTEXITCODE -ne 134 -or ($nullOutput -join "`n") -notmatch 'main\.e:11:35: trap\[null\]: nil dereferenced as \*Point') { throw "the field case did not trap as section 11 says: exit $LASTEXITCODE, $($nullOutput -join "`n")" }
$nullOutput = & $nullPath write 2>&1
if ($LASTEXITCODE -ne 134 -or ($nullOutput -join "`n") -notmatch 'main\.e:12:33: trap\[null\]: nil dereferenced as \*Point') { throw "the write case did not trap as section 11 says: exit $LASTEXITCODE, $($nullOutput -join "`n")" }
$nullOutput = & $nullPath deref 2>&1
if ($LASTEXITCODE -ne 134 -or ($nullOutput -join "`n") -notmatch 'main\.e:13:31: trap\[null\]: nil dereferenced as \*i32') { throw "the deref case did not trap as section 11 says: exit $LASTEXITCODE, $($nullOutput -join "`n")" }
$nullOutput = & $nullPath store 2>&1
if ($LASTEXITCODE -ne 134 -or ($nullOutput -join "`n") -notmatch 'main\.e:34:9: trap\[null\]: nil dereferenced as \*i32') { throw "the store case did not trap as section 11 says: exit $LASTEXITCODE, $($nullOutput -join "`n")" }
& $nullPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'a dereference of a live pointer trapped' }
# The `align` row: `simd.load_aligned` and `store_aligned` at an address that is not a
# multiple of the vector's width, each refused with the width named; aligned untouched.
$alignPath = Join-Path $testBuild 'trap-align-selfhost.exe'
$alignWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_align\src\main.e') $repo 'x64' 'windows' $alignPath
if ($LASTEXITCODE -ne 0 -or $alignWritten -ne 'executable written') { throw 'align trap fixture executable emission failed' }
$alignOutput = & $alignPath load 2>&1
if ($LASTEXITCODE -ne 134 -or ($alignOutput -join "`n") -notmatch 'main\.e:28:13: trap\[align\]: address not a multiple of 16: \d+') { throw "the load case did not trap as section 11 says: exit $LASTEXITCODE, $($alignOutput -join "`n")" }
$alignOutput = & $alignPath store 2>&1
if ($LASTEXITCODE -ne 134 -or ($alignOutput -join "`n") -notmatch 'main\.e:31:5: trap\[align\]: address not a multiple of 16: \d+') { throw "the store case did not trap as section 11 says: exit $LASTEXITCODE, $($alignOutput -join "`n")" }
& $alignPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'an aligned vector access trapped' }
# The `overflow` row: `+ - *` and unary `-` on every width, signed and unsigned, refused
# when the result does not fit; the same in range, and `+%` past the edge, untouched.
$overflowPath = Join-Path $testBuild 'trap-overflow-selfhost.exe'
$overflowWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_overflow\src\main.e') $repo 'x64' 'windows' $overflowPath
if ($LASTEXITCODE -ne 0 -or $overflowWritten -ne 'executable written') { throw 'overflow trap fixture executable emission failed' }
$overflowOutput = & $overflowPath add32 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:14:17: trap\[overflow\]: i32 \+ overflows') { throw "the add32 case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath sub8 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:18:17: trap\[overflow\]: i8 - overflows') { throw "the sub8 case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath mulu16 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:22:17: trap\[overflow\]: u16 \* overflows') { throw "the mulu16 case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath add64 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:26:17: trap\[overflow\]: i64 \+ overflows') { throw "the add64 case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath subusize 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:30:17: trap\[overflow\]: usize - overflows') { throw "the subusize case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath mulusize 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:34:17: trap\[overflow\]: usize \* overflows') { throw "the mulusize case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath muli64 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:38:17: trap\[overflow\]: i64 \* overflows') { throw "the muli64 case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
$overflowOutput = & $overflowPath neg 2>&1
if ($LASTEXITCODE -ne 134 -or ($overflowOutput -join "`n") -notmatch 'main\.e:43:17: trap\[overflow\]: i16 unary - overflows') { throw "the neg case did not trap as section 11 says: exit $LASTEXITCODE, $($overflowOutput -join "`n")" }
& $overflowPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'arithmetic in range, or a wrapping operator, trapped' }
# `@nocheck { ... }`: the debug-only rows elided inside, a release-mode row still
# trapping inside, and the same operation trapping outside.
$nocheckPath = Join-Path $testBuild 'nocheck-selfhost.exe'
$nocheckWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\nocheck\src\main.e') $repo 'x64' 'windows' $nocheckPath
if ($LASTEXITCODE -ne 0 -or $nocheckWritten -ne 'executable written') { throw 'nocheck fixture executable emission failed' }
$nocheckQuiet = & $nocheckPath quiet 2>&1
if ($LASTEXITCODE -ne 0 -or ($nocheckQuiet -join "`n") -ne '') { throw "a check fired inside @nocheck: exit $LASTEXITCODE, $($nocheckQuiet -join "`n")" }
$nocheckDivide = & $nocheckPath divide 2>&1
if ($LASTEXITCODE -ne 134 -or ($nocheckDivide -join "`n") -notmatch 'main\.e:36:21: trap\[divide\]: 7 / 0 divides by zero') { throw "@nocheck disabled a row that traps in release: exit $LASTEXITCODE, $($nocheckDivide -join "`n")" }
$nocheckLoud = & $nocheckPath loud 2>&1
if ($LASTEXITCODE -ne 134 -or ($nocheckLoud -join "`n") -notmatch 'main\.e:41:23: trap\[overflow\]: u8 \+ overflows') { throw "the check outside @nocheck did not fire: exit $LASTEXITCODE, $($nocheckLoud -join "`n")" }
& $nocheckPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the nocheck fixture trapped on its ordinary path' }
# The memory rows in a release build (D355, H03): bounds, null and tag trap with the
# debug record, and `@nocheck` is the one way past them.
$releaseChecksPath = Join-Path $testBuild 'release-checks-selfhost.exe'
$releaseChecksWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\release_checks\src\main.e') $repo 'x64' 'windows' $releaseChecksPath --release
if ($LASTEXITCODE -ne 0 -or $releaseChecksWritten -ne 'executable written') { throw 'release checks fixture executable emission failed' }
foreach ($releaseCheck in @(@('bounds', 'main\.e:22:9: trap\[bounds\]: index 9 out of bounds for len 8'), @('null', 'main\.e:26:16: trap\[null\]: nil dereferenced'), @('tag', 'main\.e:31:23: trap\[tag\]: Node\.Lit read while the tag is 0'))) {
    $releaseCheckOutput = & $releaseChecksPath $releaseCheck[0] 2>&1
    if ($LASTEXITCODE -ne 134 -or ($releaseCheckOutput -join "`n") -notmatch $releaseCheck[1]) { throw "the $($releaseCheck[0]) row did not trap in release: exit $LASTEXITCODE, $($releaseCheckOutput -join "`n")" }
}
$releaseChecksQuiet = & $releaseChecksPath quiet 2>&1
if ($LASTEXITCODE -ne 0 -or ($releaseChecksQuiet -join "`n") -ne '') { throw "a check fired inside @nocheck in release: exit $LASTEXITCODE, $($releaseChecksQuiet -join "`n")" }
# Bounds checks under a proof (D356): `--stats` counts the ones left out, the
# unproven access past the end still traps, and the other shapes keep their checks.
$boundsProofPath = Join-Path $testBuild 'bounds-proof-selfhost.exe'
$boundsProofStats = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\bounds_proof\src\main.e') $repo 'x64' 'windows' $boundsProofPath --release --stats 2>&1
if ($LASTEXITCODE -ne 0) { throw 'bounds proof fixture executable emission failed' }
$boundsElided = ($boundsProofStats -join "`n") -match 'bounds checks elided \| (\d+)'
if (-not $boundsElided -or [int]$Matches[1] -lt 2) { throw "the bounds proof elided no check: $($boundsProofStats -join "`n")" }
& $boundsProofPath none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the proven loop summed wrongly' }
$boundsShifted = & $boundsProofPath shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsShifted -join "`n") -notmatch 'main\.e:26:26: trap\[bounds\]: index 5 out of bounds for len 5') { throw "the unproven access did not trap: exit $LASTEXITCODE, $($boundsShifted -join "`n")" }
foreach ($boundsMode in @('nested', 'reslice', 'guarded', 'conjunct', 'exit_guard', 'width', 'slack', 'equal', 'aliased', 'field')) {
    & $boundsProofPath $boundsMode 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "the $boundsMode loop went wrong under its retained check" }
}
# The guard form (D377): `if at < items.len` proves the block's access; a write of
# the index first keeps the check, which trips at the end.
$boundsGuarded = & $boundsProofPath guarded_shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsGuarded -join "`n") -notmatch 'main\.e:70:17: trap\[bounds\]: index 5 out of bounds for len 5') { throw "the guarded-then-shifted access did not trap: exit $LASTEXITCODE, $($boundsGuarded -join "`n")" }
# The second-local form (D452): `let n = x.len` then `while at < n` proves `x[at]`; the
# shifted read keeps its check, which trips at the end.
$boundsAliased = & $boundsProofPath aliased_shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsAliased -join "`n") -notmatch 'main\.e:280:26: trap\[bounds\]: index 5 out of bounds for len 5') { throw "the access past the aliased length did not trap: exit $LASTEXITCODE, $($boundsAliased -join "`n")" }
# The field base (D462): `while at < bag.items.len` proves `bag.items[at]`; the shifted
# read keeps its check, and so does the loop through a pointer that calls before the
# access -- the call empties the slice and the check trips at index 0.
$boundsField = & $boundsProofPath field_shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsField -join "`n") -notmatch 'main\.e:335:26: trap\[bounds\]: index 5 out of bounds for len 5') { throw "the access past the field length did not trap: exit $LASTEXITCODE, $($boundsField -join "`n")" }
$boundsFieldCall = & $boundsProofPath field_call_shrinks 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsFieldCall -join "`n") -notmatch 'main\.e:325:26: trap\[bounds\]: index 0 out of bounds for len 0') { throw "the field access after a call kept no check: exit $LASTEXITCODE, $($boundsFieldCall -join "`n")" }
$boundsEqual = & $boundsProofPath equal_shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsEqual -join "`n") -notmatch 'main\.e:145:30: trap\[bounds\]: index 5 out of bounds for len 5') { throw "the access past the equal length did not trap: exit $LASTEXITCODE, $($boundsEqual -join "`n")" }
$boundsSlack = & $boundsProofPath slack_shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsSlack -join "`n") -notmatch 'main\.e:121:26: trap\[bounds\]: index 4 out of bounds for len 4') { throw "the access past the slack did not trap: exit $LASTEXITCODE, $($boundsSlack -join "`n")" }
$boundsExit = & $boundsProofPath exit_shifted 2>&1
if ($LASTEXITCODE -ne 134 -or ($boundsExit -join "`n") -notmatch 'main\.e:95:9: trap\[bounds\]: index 5 out of bounds for len 5') { throw "the exit-guard-then-shifted access did not trap: exit $LASTEXITCODE, $($boundsExit -join "`n")" }
# Error detail across a cleanup (D360, H07): a failing close after a failed stat
# leaves the stat's detail to be read, and the next failing cleanup after that read.
$errorDetailPath = Join-Path $testBuild 'error-detail-selfhost.exe'
$errorDetailWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\error_detail\src\main.e') $repo 'x64' 'windows' $errorDetailPath
if ($LASTEXITCODE -ne 0 -or $errorDetailWritten -ne 'executable written') { throw 'error detail fixture emission failed' }
& $errorDetailPath 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "a cleanup's failure overwrote the primary error's detail: exit $LASTEXITCODE" }
# By-value snapshots (D358, H05): `f(x, &x)` reads the old `x`, in both modes.
foreach ($snapshotMode in @(@('debug', @()), @('release', @('--release')))) {
    $snapshotPath = Join-Path $testBuild "by-value-snapshot-$($snapshotMode[0])-selfhost.exe"
    $snapshotWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\by_value_snapshot\src\main.e') $repo 'x64' 'windows' $snapshotPath @($snapshotMode[1])
    if ($LASTEXITCODE -ne 0 -or $snapshotWritten -ne 'executable written') { throw "by-value snapshot fixture emission failed ($($snapshotMode[0]))" }
    & $snapshotPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "a by-value argument saw a write made during its call ($($snapshotMode[0]))" }
}
# The release build: the same program traps on its first `+` in debug and, built with
# `--release`, wraps, truncates, masks and saturates through to exit 0.
$releaseSource = Join-Path $PSScriptRoot 'fixtures\link\release_build\src\main.e'
$releaseDebugPath = Join-Path $testBuild 'release-build-debug-selfhost.exe'
$releaseDebugWritten = & $compiler emit-executable $releaseSource $repo 'x64' 'windows' $releaseDebugPath
if ($LASTEXITCODE -ne 0 -or $releaseDebugWritten -ne 'executable written') { throw 'release fixture debug emission failed' }
$releaseDebugOutput = & $releaseDebugPath 2>&1
if ($LASTEXITCODE -ne 134 -or ($releaseDebugOutput -join "`n") -notmatch 'main\.e:14:19: trap\[overflow\]: u8 \+ overflows') { throw "the release fixture did not trap in debug: exit $LASTEXITCODE, $($releaseDebugOutput -join "`n")" }
$releasePath = Join-Path $testBuild 'release-build-selfhost.exe'
$releaseWritten = & $compiler emit-executable $releaseSource $repo 'x64' 'windows' $releasePath --release
if ($LASTEXITCODE -ne 0 -or $releaseWritten -ne 'executable written') { throw 'release fixture release emission failed' }
$releaseOutput = & $releasePath 2>&1
if ($LASTEXITCODE -ne 0 -or ($releaseOutput -join "`n") -ne '') { throw "the release build did not give section 4's release results: exit $LASTEXITCODE, $($releaseOutput -join "`n")" }
if ((Get-Item -LiteralPath $releasePath).Length -ge (Get-Item -LiteralPath $releaseDebugPath).Length) { throw 'the release build is not smaller than the debug build' }
# Section 12's incremental rebuild: unchanged sources keep every artifact, a body edit
# behind a signature edge rebuilds only its module and links equal to a clean build,
# and a signature edit rebuilds the dependent too.
$incrementalFixture = Join-Path $PSScriptRoot 'fixtures\link\incremental'
$incrementalScratch = Join-Path $testBuild 'incremental-scratch'
$incrementalSource = Join-Path $incrementalScratch 'src'
$incrementalArtifacts = Join-Path $testBuild 'incremental-artifacts'
if (Test-Path -LiteralPath $incrementalScratch) { Remove-Item -LiteralPath $incrementalScratch -Recurse -Force }
if (Test-Path -LiteralPath $incrementalArtifacts) { Remove-Item -LiteralPath $incrementalArtifacts -Recurse -Force }
New-Item -ItemType Directory -Force -Path $incrementalSource, $incrementalArtifacts | Out-Null
Copy-Item (Join-Path $incrementalFixture 'src\*.e') $incrementalSource
$incrementalMain = Join-Path $incrementalSource 'main.e'
$incrementalFirst = & $compiler emit-em-all $incrementalMain $repo 'x64' 'windows' $incrementalArtifacts --release
if ($LASTEXITCODE -ne 0 -or $incrementalFirst -ne 'compiled modules written') { throw 'the incremental fixture did not compile to artifacts' }
$incrementalSame = (& $compiler emit-em-all $incrementalMain $repo 'x64' 'windows' $incrementalArtifacts --release --incremental) -join "`n"
if ($LASTEXITCODE -ne 0 -or $incrementalSame -notmatch 'kept main' -or $incrementalSame -notmatch 'kept dep' -or $incrementalSame -match 'rebuilt') { throw "unchanged sources were rebuilt: $incrementalSame" }
Copy-Item (Join-Path $incrementalFixture 'edits\dep_body.e') (Join-Path $incrementalSource 'dep.e')
$incrementalBody = (& $compiler emit-em-all $incrementalMain $repo 'x64' 'windows' $incrementalArtifacts --release --incremental) -join "`n"
if ($LASTEXITCODE -ne 0 -or $incrementalBody -notmatch 'kept main' -or $incrementalBody -notmatch 'rebuilt dep') { throw "a body edit behind a signature edge did not rebuild only its module: $incrementalBody" }
$incrementalLinked = Join-Path $testBuild 'incremental-linked.exe'
$incrementalArtifactList = @('main', 'dep', 'e.os', 'e.mem') | ForEach-Object { Join-Path $incrementalArtifacts "$_.x64-windows.em" }
$incrementalLinkWritten = & $compiler link-em $incrementalLinked @incrementalArtifactList
if ($LASTEXITCODE -ne 0 -or $incrementalLinkWritten -ne 'artifact executable written') { throw 'the incrementally rebuilt artifacts did not link' }
& $incrementalLinked
if ($LASTEXITCODE -ne 8) { throw "the incrementally rebuilt program did not run the new body: exit $LASTEXITCODE" }
$incrementalClean = Join-Path $testBuild 'incremental-clean.exe'
$incrementalCleanWritten = & $compiler emit-executable $incrementalMain $repo 'x64' 'windows' $incrementalClean --release
if ($LASTEXITCODE -ne 0 -or $incrementalCleanWritten -ne 'executable written') { throw 'the clean build of the edited fixture failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $incrementalLinked).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $incrementalClean).Hash) { throw 'incremental does not equal clean' }
Copy-Item (Join-Path $incrementalFixture 'edits\dep_inlined.e') (Join-Path $incrementalSource 'dep.e')
$incrementalInlined = (& $compiler emit-em-all $incrementalMain $repo 'x64' 'windows' $incrementalArtifacts --release --incremental) -join "`n"
if ($LASTEXITCODE -ne 0 -or $incrementalInlined -notmatch 'rebuilt main' -or $incrementalInlined -notmatch 'rebuilt dep') { throw "a body edit behind a body edge did not rebuild the dependent: $incrementalInlined" }
$incrementalInlinedWritten = & $compiler link-em $incrementalLinked @incrementalArtifactList
if ($LASTEXITCODE -ne 0 -or $incrementalInlinedWritten -ne 'artifact executable written') { throw 'the artifacts after the inlined edit did not link' }
& $incrementalLinked
if ($LASTEXITCODE -ne 9) { throw "the rebuilt dependent did not carry the new inlined body: exit $LASTEXITCODE" }
Copy-Item (Join-Path $incrementalFixture 'edits\dep_signature.e') (Join-Path $incrementalSource 'dep.e')
Copy-Item (Join-Path $incrementalFixture 'edits\main_signature.e') $incrementalMain
$incrementalSignature = (& $compiler emit-em-all $incrementalMain $repo 'x64' 'windows' $incrementalArtifacts --release --incremental) -join "`n"
if ($LASTEXITCODE -ne 0 -or $incrementalSignature -notmatch 'rebuilt main' -or $incrementalSignature -notmatch 'rebuilt dep' -or $incrementalSignature -notmatch 'kept e.os') { throw "a signature edit did not rebuild the dependent: $incrementalSignature" }
# A hot build (D319): `emit-executable --incremental` settles the keep set, writes each
# fresh module's artifact under `.neper/<mode>/em/` and links the image from every
# artifact; a warm one with nothing changed and one after a body edit are each the clean
# build's image byte for byte, in both modes.
$hotFixture = Join-Path $PSScriptRoot 'fixtures\link\incremental'
$hotScratch = Join-Path $testBuild 'hot-scratch'
$hotSource = Join-Path $hotScratch 'src'
if (Test-Path -LiteralPath $hotScratch) { Remove-Item -LiteralPath $hotScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path $hotSource | Out-Null
Copy-Item (Join-Path $hotFixture 'src\*.e') $hotSource
$hotMain = Join-Path $hotSource 'main.e'
foreach ($hotMode in @('--release', '--time')) {
    $hotExe = Join-Path $testBuild "hot-built$hotMode.exe"
    $hotClean = Join-Path $testBuild "hot-clean$hotMode.exe"
    Copy-Item (Join-Path $hotFixture 'src\dep.e') (Join-Path $hotSource 'dep.e')
    $hotFirst = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotFirst -ne 'executable written') { throw "the hot build did not write an executable ($hotMode)" }
    $hotCleanWritten = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotCleanWritten -ne 'executable written') { throw "the clean build failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "a cold hot build is not the clean build ($hotMode)" }
    $hotWarm = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotWarm -ne 'executable written') { throw "the warm hot build failed ($hotMode)" }
    # The manifest says what the warm build kept and why (D363, H14): everything, stable.
    $hotManifestMode = 'debug'
    if ($hotMode -eq '--release') { $hotManifestMode = 'release' }
    $hotManifest = Join-Path $hotScratch ".neper\$hotManifestMode\build-manifest.json"
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=kept:stable' 'dep=kept:stable' 'e.os=kept:stable' 'work.bodies_checked=0' 'work.modules_lowered=0' 'work.functions_lowered=0' 'work.declarations_checked=28'
    if ($LASTEXITCODE -ne 0) { throw "the warm hot build's manifest does not say every module was kept stable and no work was done ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "a warm hot build is not the clean build ($hotMode)" }
    # Trivia apart from identity (D504, H14): a comment's words changed on their own
    # line keep every module, `stable`, and the image is the clean build's.
    Copy-Item (Join-Path $hotFixture 'edits\dep_comment.e') (Join-Path $hotSource 'dep.e')
    $hotComment = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotComment -ne 'executable written') { throw "the warm build after a comment edit failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=kept:stable' 'dep=kept:stable'
    if ($LASTEXITCODE -ne 0) { throw "a comment edit did not keep the module stable ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "the warm build after a comment edit is not the clean build ($hotMode)" }
    # The kept module's input digest is the edited bytes' own (D507, H15), not the artifact's.
    $hotCommentInput = ((Get-Content -Raw -LiteralPath $hotManifest | ConvertFrom-Json).inputs | Where-Object { $_.source.path -eq 'dep.e' }).sha256
    if ($hotCommentInput -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $hotFixture 'edits\dep_comment.e')).Hash.ToLower()) { throw "the manifest's input digest of a kept comment-edited module is not the file's ($hotMode)" }
    Copy-Item (Join-Path $hotFixture 'src\dep.e') (Join-Path $hotSource 'dep.e')
    # An injected key collision (D507, H15): under `--fault-collision` every key is a
    # hit, and a body edit still rebuilds `dep`, proved by the bytes beyond the key.
    Copy-Item (Join-Path $hotFixture 'edits\dep_body.e') (Join-Path $hotSource 'dep.e')
    $hotCollision = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental --fault-collision 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotCollision -ne 'executable written') { throw "the warm build under an injected key collision failed ($hotMode)" }
    & $hotExe
    if ($LASTEXITCODE -ne 8) { throw "an injected key collision kept a stale artifact: exit $LASTEXITCODE ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=kept:edges-hold' 'dep=rebuilt:source-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest under an injected key collision does not record the rebuild ($hotMode)" }
    Copy-Item (Join-Path $hotFixture 'src\dep.e') (Join-Path $hotSource 'dep.e')
    $hotRestored = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotRestored -ne 'executable written') { throw "the warm build after the collision case failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "the warm build after the collision case is not the clean build ($hotMode)" }
    # `--stats` on a warm build (D412): the kept modules are parsed for the counts, and
    # the work rows say nothing was done.
    $hotStats = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental --stats 2>&1
    if ($LASTEXITCODE -ne 0 -or ($hotStats -join "`n") -notmatch 'bodies checked \| 0') { throw "--stats on a warm build failed or did not report zero bodies checked ($hotMode)" }
    # The compiler is an identity (D398, H15): a warm build by another compiler
    # executable -- this one with a byte appended -- rebuilds every module as
    # `compiler-changed` and is the clean build; the original then rebuilds them back.
    $hotOther = Join-Path $testBuild 'hot-other-compiler.exe'
    Copy-Item -LiteralPath $compiler -Destination $hotOther -Force
    [IO.File]::AppendAllText($hotOther, 'x')
    $hotOtherWarm = & $hotOther emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotOtherWarm -ne 'executable written') { throw "the warm hot build by another compiler failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=rebuilt:compiler-changed' 'dep=rebuilt:compiler-changed' 'e.os=rebuilt:compiler-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest of a build by another compiler does not say compiler-changed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "a warm hot build by another compiler is not the clean build ($hotMode)" }
    $hotBack = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotBack -ne 'executable written') { throw "the warm hot build after another compiler failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=rebuilt:compiler-changed' 'dep=rebuilt:compiler-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after another compiler's artifacts does not say compiler-changed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "the warm hot build after another compiler is not the clean build ($hotMode)" }
    # The options are part of the identity (D431, H15): a warm build under another
    # `--inline-cap` rebuilds every module as `options-changed`, and the plain warm
    # build after it rebuilds them back and is the clean build.
    $hotCapped = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental --inline-cap 0 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotCapped -ne 'executable written') { throw "the warm hot build under an inline cap failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=rebuilt:options-changed' 'dep=rebuilt:options-changed' 'e.os=rebuilt:options-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest of a build under an inline cap does not say options-changed ($hotMode)" }
    $hotUncapped = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotUncapped -ne 'executable written') { throw "the warm hot build after an inline cap failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=rebuilt:options-changed' 'dep=rebuilt:options-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a capped build's artifacts does not say options-changed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "the warm hot build after an inline cap is not the clean build ($hotMode)" }
    # A constant's value is a value edge (D492, H14): a warm build after the constant a
    # module folds on changed rebuilds that module as `edge-changed`, exits the other way,
    # and is the clean build of the edited tree. Before D492 the module was kept and the
    # program kept the old value.
    $valueScratch = Join-Path $testBuild 'value-scratch'
    if (Test-Path -LiteralPath $valueScratch) { Remove-Item -LiteralPath $valueScratch -Recurse -Force }
    Copy-Item -Recurse (Join-Path $repo 'tests\selfhost\fixtures\link\incremental_value') $valueScratch
    $valueExe = Join-Path $testBuild "value$hotMode.exe"
    $valueFirst = & $compiler emit-executable (Join-Path $valueScratch 'src\main.e') $repo 'x64' 'windows' $valueExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $valueFirst -ne 'executable written') { throw "the cold build of the value fixture failed ($hotMode)" }
    & $valueExe
    if ($LASTEXITCODE -ne 8) { throw "the value fixture did not exit 8 before the edit ($hotMode)" }
    Copy-Item (Join-Path $valueScratch 'edits\dep_limit.e') (Join-Path $valueScratch 'src\dep.e') -Force
    $valueSecond = & $compiler emit-executable (Join-Path $valueScratch 'src\main.e') $repo 'x64' 'windows' $valueExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $valueSecond -ne 'executable written') { throw "the warm build after the constant's edit failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') (Join-Path $valueScratch ".neper\$hotManifestMode\build-manifest.json") 'main=rebuilt:edge-changed' 'dep=rebuilt:source-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a folded constant's edit does not say edge-changed ($hotMode)" }
    & $valueExe
    if ($LASTEXITCODE -ne 4) { throw "the value fixture did not exit 4 after the edit ($hotMode)" }
    $valueClean = Join-Path $testBuild "value-clean$hotMode.exe"
    $valueCleanWritten = & $compiler emit-executable (Join-Path $valueScratch 'src\main.e') $repo 'x64' 'windows' $valueClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $valueCleanWritten -ne 'executable written') { throw "the clean build of the edited value fixture failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $valueExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $valueClean).Hash) { throw "the warm build after a folded constant's edit is not the clean build ($hotMode)" }
    # A layout a body reads is an edge (D493, H14): a warm build after the record a
    # module reads through a signature was reordered rebuilds that module as
    # `edge-changed`, still exits 7, and is the clean build of the edited tree.
    $layoutScratch = Join-Path $testBuild 'layout-scratch'
    if (Test-Path -LiteralPath $layoutScratch) { Remove-Item -LiteralPath $layoutScratch -Recurse -Force }
    Copy-Item -Recurse (Join-Path $repo 'tests\selfhost\fixtures\link\incremental_layout') $layoutScratch
    $layoutExe = Join-Path $testBuild "layout$hotMode.exe"
    $layoutFirst = & $compiler emit-executable (Join-Path $layoutScratch 'src\main.e') $repo 'x64' 'windows' $layoutExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $layoutFirst -ne 'executable written') { throw "the cold build of the layout fixture failed ($hotMode)" }
    & $layoutExe
    if ($LASTEXITCODE -ne 7) { throw "the layout fixture did not exit 7 before the edit ($hotMode)" }
    Copy-Item (Join-Path $layoutScratch 'edits\dep_layout.e') (Join-Path $layoutScratch 'src\dep.e') -Force
    $layoutSecond = & $compiler emit-executable (Join-Path $layoutScratch 'src\main.e') $repo 'x64' 'windows' $layoutExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $layoutSecond -ne 'executable written') { throw "the warm build after the layout's edit failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') (Join-Path $layoutScratch ".neper\$hotManifestMode\build-manifest.json") 'main=rebuilt:edge-changed' 'dep=rebuilt:source-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a read layout's edit does not say edge-changed ($hotMode)" }
    & $layoutExe
    if ($LASTEXITCODE -ne 7) { throw "the layout fixture did not exit 7 after the edit ($hotMode)" }
    $layoutClean = Join-Path $testBuild "layout-clean$hotMode.exe"
    $layoutCleanWritten = & $compiler emit-executable (Join-Path $layoutScratch 'src\main.e') $repo 'x64' 'windows' $layoutClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $layoutCleanWritten -ne 'executable written') { throw "the clean build of the edited layout fixture failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $layoutExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $layoutClean).Hash) { throw "the warm build after a read layout's edit is not the clean build ($hotMode)" }
    # A protocol function's absence is an edge (D494, H14): a warm build after the module
    # declares the `eq` the supplied rule stood in for rebuilds the instance's module as
    # `edge-changed`, exits the other way, and is the clean build of the edited tree.
    $fallbackScratch = Join-Path $testBuild 'fallback-scratch'
    if (Test-Path -LiteralPath $fallbackScratch) { Remove-Item -LiteralPath $fallbackScratch -Recurse -Force }
    Copy-Item -Recurse (Join-Path $repo 'tests\selfhost\fixtures\link\incremental_fallback') $fallbackScratch
    $fallbackExe = Join-Path $testBuild "fallback$hotMode.exe"
    $fallbackFirst = & $compiler emit-executable (Join-Path $fallbackScratch 'src\main.e') $repo 'x64' 'windows' $fallbackExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $fallbackFirst -ne 'executable written') { throw "the cold build of the fallback fixture failed ($hotMode)" }
    & $fallbackExe
    if ($LASTEXITCODE -ne 3) { throw "the fallback fixture did not exit 3 before the edit ($hotMode)" }
    Copy-Item (Join-Path $fallbackScratch 'edits\dep_declared.e') (Join-Path $fallbackScratch 'src\dep.e') -Force
    $fallbackSecond = & $compiler emit-executable (Join-Path $fallbackScratch 'src\main.e') $repo 'x64' 'windows' $fallbackExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $fallbackSecond -ne 'executable written') { throw "the warm build after the protocol's declaration failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') (Join-Path $fallbackScratch ".neper\$hotManifestMode\build-manifest.json") 'main=rebuilt:edge-changed' 'dep=rebuilt:source-changed'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a protocol's declaration does not say edge-changed ($hotMode)" }
    & $fallbackExe
    if ($LASTEXITCODE -ne 4) { throw "the fallback fixture did not exit 4 after the edit ($hotMode)" }
    $fallbackClean = Join-Path $testBuild "fallback-clean$hotMode.exe"
    $fallbackCleanWritten = & $compiler emit-executable (Join-Path $fallbackScratch 'src\main.e') $repo 'x64' 'windows' $fallbackClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $fallbackCleanWritten -ne 'executable written') { throw "the clean build of the edited fallback fixture failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fallbackExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $fallbackClean).Hash) { throw "the warm build after a protocol's declaration is not the clean build ($hotMode)" }
    # A deleted declaration (D495, H14): the warm build after a dependency lost a name the
    # dependent uses fails as a cold build does -- the resolver's diagnostic naming the
    # module and the member, exit 1 -- and the executable is the one from before.
    $deletedScratch = Join-Path $testBuild 'deleted-scratch'
    if (Test-Path -LiteralPath $deletedScratch) { Remove-Item -LiteralPath $deletedScratch -Recurse -Force }
    Copy-Item -Recurse (Join-Path $repo 'tests\selfhost\fixtures\link\incremental_deleted') $deletedScratch
    $deletedExe = Join-Path $testBuild "deleted$hotMode.exe"
    $deletedFirst = & $compiler emit-executable (Join-Path $deletedScratch 'src\main.e') $repo 'x64' 'windows' $deletedExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $deletedFirst -ne 'executable written') { throw "the cold build of the deleted fixture failed ($hotMode)" }
    & $deletedExe
    if ($LASTEXITCODE -ne 5) { throw "the deleted fixture did not exit 5 before the edit ($hotMode)" }
    Copy-Item (Join-Path $deletedScratch 'edits\dep_without.e') (Join-Path $deletedScratch 'src\dep.e') -Force
    $deletedSecond = & $compiler emit-executable (Join-Path $deletedScratch 'src\main.e') $repo 'x64' 'windows' $deletedExe $hotMode --incremental 2>&1
    if ($LASTEXITCODE -ne 1) { throw "the warm build after a deleted declaration did not exit 1 ($hotMode): $LASTEXITCODE" }
    if (($deletedSecond -join "`n") -notmatch "main.e:7:\d+: error\[E-NAME-9999\]: ``dep`` has no member ``extra``") { throw "the warm build after a deleted declaration did not name the lost member ($hotMode): $deletedSecond" }
    & $deletedExe
    if ($LASTEXITCODE -ne 5) { throw "the executable from before the deleted declaration was rewritten ($hotMode)" }
    # A cyclic artifact reference (D472, H24): an artifact rewritten to import the module
    # that imports it is distrusted and rebuilt as `invalid-artifact`, the image is the
    # clean build's, and the linker over the forged set refuses or links without crashing.
    $cycleScratch = Join-Path $testBuild 'cycle-scratch'
    if (Test-Path -LiteralPath $cycleScratch) { Remove-Item -LiteralPath $cycleScratch -Recurse -Force }
    Copy-Item -Recurse (Join-Path $repo 'tests\selfhost\fixtures\link\artifact_cycle') $cycleScratch
    $cycleExe = Join-Path $testBuild "cycle$hotMode.exe"
    $cycleClean = Join-Path $testBuild "cycle-clean$hotMode.exe"
    $cycleCold = & $compiler emit-executable (Join-Path $cycleScratch 'src\main.e') $repo 'x64' 'windows' $cycleExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $cycleCold -ne 'executable written') { throw "the cold cycle build failed ($hotMode)" }
    $cycleCleanWritten = & $compiler emit-executable (Join-Path $cycleScratch 'src\main.e') $repo 'x64' 'windows' $cycleClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $cycleCleanWritten -ne 'executable written') { throw "the clean cycle build failed ($hotMode)" }
    $cycleManifest = Join-Path $cycleScratch ".neper\$hotManifestMode\build-manifest.json"
    $cycleRing = Join-Path $cycleScratch ".neper\$hotManifestMode\em\ring.x64-windows.em"
    $cycleMain = Join-Path $cycleScratch ".neper\$hotManifestMode\em\main.x64-windows.em"
    & python (Join-Path $repo 'benchmarks/fuzz/corrupt.py') cycle $cycleRing e.os main
    $cycleLinked = & $compiler link-em (Join-Path $testBuild "cycle-link$hotMode.exe") $cycleMain $cycleRing 2>&1 | Out-String
    if ($LASTEXITCODE -gt 2) { throw "the linker over a cyclic artifact set exited $LASTEXITCODE" }
    $cycleWarm = & $compiler emit-executable (Join-Path $cycleScratch 'src\main.e') $repo 'x64' 'windows' $cycleExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $cycleWarm -ne 'executable written') { throw "the warm build over a cyclic artifact failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $cycleExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $cycleClean).Hash) { throw "the warm build over a cyclic artifact is not the clean build ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $cycleManifest 'main=kept:edges-hold' 'ring=rebuilt:invalid-artifact'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a cyclic artifact does not say invalid-artifact ($hotMode)" }
    # The root's own artifact naming itself.
    & python (Join-Path $repo 'benchmarks/fuzz/corrupt.py') cycle $cycleMain ring main
    $cycleSelf = & $compiler emit-executable (Join-Path $cycleScratch 'src\main.e') $repo 'x64' 'windows' $cycleExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $cycleSelf -ne 'executable written') { throw "the warm build over a self-referencing artifact failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $cycleExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $cycleClean).Hash) { throw "the warm build over a self-referencing artifact is not the clean build ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $cycleManifest 'main=rebuilt:invalid-artifact' 'ring=kept:stable'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a self-referencing artifact does not say invalid-artifact ($hotMode)" }
    # The manifest as the anchor (D473, H24): an artifact rewritten with its checksum
    # redone -- no cycle this time, a dependency renamed to another module -- is not the
    # one the manifest recorded, and is rebuilt as `invalid-artifact`; the manifest
    # records every module's checksum, and a warm build over a whole cache is stable.
    & python (Join-Path $repo 'benchmarks/fuzz/corrupt.py') cycle $cycleRing e.os e.io
    $cycleRenamed = & $compiler emit-executable (Join-Path $cycleScratch 'src\main.e') $repo 'x64' 'windows' $cycleExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $cycleRenamed -ne 'executable written') { throw "the warm build over a rewritten artifact failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $cycleExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $cycleClean).Hash) { throw "the warm build over a rewritten artifact is not the clean build ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $cycleManifest 'main=kept:edges-hold' 'ring=rebuilt:invalid-artifact'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after a rewritten artifact does not say invalid-artifact ($hotMode)" }
    $cycleRecorded = (Get-Content -Raw -LiteralPath $cycleManifest | ConvertFrom-Json).incremental
    if (@($cycleRecorded | Where-Object { $_.artifact_crc32c -notmatch '^[0-9a-f]{8}$' }).Count -ne 0) { throw "the manifest does not record every artifact's checksum ($hotMode)" }
    $cycleStable = & $compiler emit-executable (Join-Path $cycleScratch 'src\main.e') $repo 'x64' 'windows' $cycleExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $cycleStable -ne 'executable written') { throw "the warm build over the whole cache failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $cycleManifest 'main=kept:stable' 'ring=kept:stable'
    if ($LASTEXITCODE -ne 0) { throw "the whole cache was not stable ($hotMode)" }
    # The unsafe inventory rides in the artifact (D457): a warm build's manifest lists
    # the same sites as the cold build's, copied from the kept modules' artifacts.
    $inventoryScratch = Join-Path $testBuild 'inventory-scratch'
    if (Test-Path -LiteralPath $inventoryScratch) { Remove-Item -LiteralPath $inventoryScratch -Recurse -Force }
    Copy-Item -Recurse (Join-Path $repo 'tests\conformance\tools\manifest_unsafe') $inventoryScratch
    $inventoryExe = Join-Path $testBuild "inventory$hotMode.exe"
    $inventoryCold = & $compiler emit-executable (Join-Path $inventoryScratch 'src\main.e') $repo 'x64' 'windows' $inventoryExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $inventoryCold -ne 'executable written') { throw "the cold inventory build failed ($hotMode)" }
    $inventoryColdManifest = Get-Content -Raw -LiteralPath (Join-Path $inventoryScratch ".neper\$hotManifestMode\build-manifest.json")
    $inventoryWarm = & $compiler emit-executable (Join-Path $inventoryScratch 'src\main.e') $repo 'x64' 'windows' $inventoryExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $inventoryWarm -ne 'executable written') { throw "the warm inventory build failed ($hotMode)" }
    $inventoryWarmManifest = Get-Content -Raw -LiteralPath (Join-Path $inventoryScratch ".neper\$hotManifestMode\build-manifest.json")
    $inventoryColdSites = ($inventoryColdManifest | ConvertFrom-Json).unsafe | ConvertTo-Json -Compress
    $inventoryWarmSites = ($inventoryWarmManifest | ConvertFrom-Json).unsafe | ConvertTo-Json -Compress
    if ($inventoryColdSites -ne $inventoryWarmSites -or $inventoryColdSites -notmatch '"nocheck"') { throw "the warm build's unsafe inventory differs from the cold build's ($hotMode)" }
    # Artifact-only enumeration (D557, H27): no source, parser or checker is needed.
    # The first artifact names the root; the command hashes every artifact and copies
    # the exact unsafe inventory that the source build wrote into their Inventory sections.
    $inventoryArtifactDir = Join-Path $inventoryScratch ".neper\$hotManifestMode\em"
    $inventoryMainArtifact = Join-Path $inventoryArtifactDir 'main.x64-windows.em'
    $inventoryArtifacts = @($inventoryMainArtifact) + @(Get-ChildItem -LiteralPath $inventoryArtifactDir -Filter '*.em' | Where-Object { $_.FullName -ne $inventoryMainArtifact } | Sort-Object Name | ForEach-Object FullName)
    $inventoryArtifactManifestText = (& $compiler manifest-em @inventoryArtifacts --json) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "the artifact-only manifest failed ($hotMode)" }
    $inventoryArtifactManifest = $inventoryArtifactManifestText | ConvertFrom-Json
    $inventoryArtifactSites = $inventoryArtifactManifest.unsafe | ConvertTo-Json -Compress
    if ($inventoryArtifactSites -ne $inventoryColdSites) { throw "the artifact-only unsafe inventory differs from the source build's ($hotMode)" }
    if ($inventoryArtifactManifest.mode -ne $hotManifestMode -or $inventoryArtifactManifest.root_module -ne 'main' -or @($inventoryArtifactManifest.inputs).Count -ne 0 -or @($inventoryArtifactManifest.artifacts).Count -ne $inventoryArtifacts.Count -or $inventoryArtifactManifest.options.checks -ne 'retained') { throw "the artifact-only manifest has the wrong identity ($hotMode)" }
    for ($artifactAt = 0; $artifactAt -lt $inventoryArtifacts.Count; $artifactAt++) {
        if ($inventoryArtifactManifest.artifacts[$artifactAt].path -ne $inventoryArtifacts[$artifactAt] -or $inventoryArtifactManifest.artifacts[$artifactAt].sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $inventoryArtifacts[$artifactAt]).Hash.ToLowerInvariant()) { throw "the artifact-only manifest has the wrong artifact digest ($hotMode)" }
    }
    # A write that dies (D435, H24): `--fault-write 1` makes the second module's artifact
    # write die after staging, so the build fails with its `.tmp` left; the warm build
    # after it finds every published artifact whole, rebuilds that module alone as
    # `no-artifact`, and is the clean build.
    Copy-Item (Join-Path $hotFixture 'src\dep.e') (Join-Path $hotSource 'dep.e')
    Remove-Item -LiteralPath (Join-Path $hotScratch '.neper') -Recurse -Force
    $hotFaultBuild = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental --fault-write 1 2>&1
    if ($LASTEXITCODE -ne 1 -or ($hotFaultBuild -join "`n") -notmatch 'made to fail by --fault-write') { throw "a build with an injected write fault did not fail as one ($hotMode): $hotFaultBuild" }
    if (-not (Get-ChildItem -LiteralPath (Join-Path $hotScratch ".neper\$hotManifestMode") -Filter '*.tmp' -Recurse)) { throw "the injected write fault left no staged file ($hotMode)" }
    $hotAfterFault = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotAfterFault -ne 'executable written') { throw "the warm hot build after an injected write fault failed ($hotMode)" }
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=kept:edges-hold' 'dep=rebuilt:no-artifact'
    if ($LASTEXITCODE -ne 0) { throw "the manifest after an injected write fault does not say the faulted module alone was rebuilt ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "the warm hot build after an injected write fault is not the clean build ($hotMode)" }
    # A damaged cache (D343, H24): a truncated artifact, a stray `.tmp` of a write that
    # died, and an artifact with bytes flipped behind a valid checksum are each rebuilt
    # or ignored, and the build is the clean build; the `.tmp` is never read.
    $hotArtifact = Get-ChildItem -LiteralPath (Join-Path $hotScratch '.neper') -Recurse -Filter 'dep.*.em' | Select-Object -First 1
    if (-not $hotArtifact) { throw "the hot build left no artifact for dep ($hotMode)" }
    foreach ($damage in @('truncate', 'flip')) {
        & python (Join-Path $repo 'benchmarks/fuzz/corrupt.py') $damage $hotArtifact.FullName
        [IO.File]::WriteAllText(($hotArtifact.FullName + '.tmp'), 'a write that died')
        $hotDamaged = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
        if ($LASTEXITCODE -ne 0 -or $hotDamaged -ne 'executable written') { throw "the hot build over a $damage artifact failed ($hotMode)" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "the hot build over a $damage artifact is not the clean build ($hotMode)" }
        if ((Get-Item -LiteralPath $hotArtifact.FullName).Length -lt 64) { throw "the $damage artifact was not rebuilt ($hotMode)" }
        # The manifest names the damage (D368, H24): `invalid-artifact`, not `no-artifact`.
        & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'dep=rebuilt:invalid-artifact'
        if ($LASTEXITCODE -ne 0) { throw "the manifest after a $damage artifact does not say invalid-artifact ($hotMode)" }
    }
    # A policy is an identity (D369, H15): a warm `--unchecked` build over checked
    # artifacts rebuilds every module (`mode-changed`) and is the clean unchecked build.
    if ($hotMode -eq '--release') {
        $hotUnchecked = Join-Path $testBuild 'hot-unchecked.exe'
        $hotUncheckedClean = Join-Path $testBuild 'hot-unchecked-clean.exe'
        $hotUncheckedWarm = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotUnchecked --release --unchecked --incremental 2>$null
        if ($LASTEXITCODE -ne 0 -or $hotUncheckedWarm -ne 'executable written') { throw 'the warm unchecked hot build failed' }
        $hotUncheckedArtifactDir = Join-Path $hotScratch '.neper\release\em'
        $hotUncheckedMainArtifact = Join-Path $hotUncheckedArtifactDir 'main.x64-windows.em'
        $hotUncheckedArtifacts = @($hotUncheckedMainArtifact) + @(Get-ChildItem -LiteralPath $hotUncheckedArtifactDir -Filter '*.em' | Where-Object { $_.FullName -ne $hotUncheckedMainArtifact } | Sort-Object Name | ForEach-Object FullName)
        $hotUncheckedArtifactManifestText = (& $compiler manifest-em @hotUncheckedArtifacts --json) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'the unchecked artifact-only manifest failed' }
        $hotUncheckedArtifactManifest = $hotUncheckedArtifactManifestText | ConvertFrom-Json
        if ($hotUncheckedArtifactManifest.mode -ne 'release' -or $hotUncheckedArtifactManifest.options.checks -ne 'off') { throw 'the unchecked artifact-only manifest did not preserve the checks policy' }
        & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=rebuilt:mode-changed' 'dep=rebuilt:mode-changed'
        if ($LASTEXITCODE -ne 0) { throw 'an unchecked build over checked artifacts did not rebuild them as mode-changed' }
        $hotUncheckedCleanWritten = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotUncheckedClean --release --unchecked 2>$null
        if ($LASTEXITCODE -ne 0 -or $hotUncheckedCleanWritten -ne 'executable written') { throw 'the clean unchecked build failed' }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotUnchecked).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotUncheckedClean).Hash) { throw 'a warm unchecked build over checked artifacts is not the clean unchecked build' }
        $hotRechecked = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe --release --incremental 2>$null
        if ($LASTEXITCODE -ne 0 -or $hotRechecked -ne 'executable written') { throw 'the checked hot build after an unchecked one failed' }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw 'a checked build over unchecked artifacts is not the clean build' }
    }
    # A corrupt artifact named on the command line is E-LINK-0001, exit 1 (D368, H24).
    $hotCorrupt = Join-Path $hotScratch 'corrupt.em'
    Copy-Item $hotArtifact.FullName $hotCorrupt
    & python (Join-Path $repo 'benchmarks/fuzz/corrupt.py') truncate $hotCorrupt
    $hotCorruptOut = & $compiler validate-em $hotCorrupt 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $hotCorruptOut -notmatch 'E-LINK-0001') { throw "a corrupt artifact was not refused as E-LINK-0001: $hotCorruptOut" }
    Copy-Item (Join-Path $hotFixture 'edits\dep_body.e') (Join-Path $hotSource 'dep.e')
    $hotEdited = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotEdited -ne 'executable written') { throw "the hot build after a body edit failed ($hotMode)" }
    & $hotExe
    if ($LASTEXITCODE -ne 8) { throw "the hot build did not carry the edited body: exit $LASTEXITCODE ($hotMode)" }
    # A body edit behind a signature edge (D363): `dep` rebuilt for its source, `main`
    # kept because every edge held, the rest stable.
    & python (Join-Path $repo 'scripts/check_incremental.py') $hotManifest 'main=kept:edges-hold' 'dep=rebuilt:source-changed' 'e.os=kept:stable'
    if ($LASTEXITCODE -ne 0) { throw "the hot build's manifest after a body edit does not record the expected decisions ($hotMode)" }
    $hotCleanEdited = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotCleanEdited -ne 'executable written') { throw "the clean build of the edited fixture failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "a hot build after a body edit is not the clean build ($hotMode)" }
    # An edit to the body `main` inlines (D322): a body edge, so the unchanged `main` is
    # parsed and rebuilt only now; then a signature edit, which rebuilds both.
    Copy-Item (Join-Path $hotFixture 'edits\dep_inlined.e') (Join-Path $hotSource 'dep.e')
    $hotInlined = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotInlined -ne 'executable written') { throw "the hot build after an inlined-body edit failed ($hotMode)" }
    & $hotExe
    if ($LASTEXITCODE -ne 9) { throw "the hot build did not carry the inlined edit: exit $LASTEXITCODE ($hotMode)" }
    $hotCleanInlined = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotCleanInlined -ne 'executable written') { throw "the clean build of the inlined edit failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "a hot build after an inlined-body edit is not the clean build ($hotMode)" }
    Copy-Item (Join-Path $hotFixture 'edits\dep_signature.e') (Join-Path $hotSource 'dep.e')
    Copy-Item (Join-Path $hotFixture 'edits\main_signature.e') (Join-Path $hotSource 'main.e')
    $hotSigned = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotExe $hotMode --incremental 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotSigned -ne 'executable written') { throw "the hot build after a signature edit failed ($hotMode)" }
    & $hotExe
    if ($LASTEXITCODE -ne 10) { throw "the hot build did not carry the signature edit: exit $LASTEXITCODE ($hotMode)" }
    $hotCleanSigned = & $compiler emit-executable $hotMain $repo 'x64' 'windows' $hotClean $hotMode 2>$null
    if ($LASTEXITCODE -ne 0 -or $hotCleanSigned -ne 'executable written') { throw "the clean build of the signature edit failed ($hotMode)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hotExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $hotClean).Hash) { throw "a hot build after a signature edit is not the clean build ($hotMode)" }
    Copy-Item (Join-Path $hotFixture 'src\main.e') (Join-Path $hotSource 'main.e')
}
# Nested inlining (D212): a release build copies `leaf.add` into `mid.twice` and that
# into `main`, the trap record names leaf.e through both copies with one frame in
# release and three in debug, and an edit to the leaf's body rebuilds all three.
$nestedFixture = Join-Path $PSScriptRoot 'fixtures\link\inline_nested'
$nestedRelease = Join-Path $testBuild 'inline-nested-release.exe'
$nestedReleaseWritten = & $compiler emit-executable (Join-Path $nestedFixture 'src\main.e') $repo 'x64' 'windows' $nestedRelease --release
if ($LASTEXITCODE -ne 0 -or $nestedReleaseWritten -ne 'executable written') { throw 'nested inlining release emission failed' }
& $nestedRelease
if ($LASTEXITCODE -ne 5) { throw "the nested release build did not compute through both copies: exit $LASTEXITCODE" }
# The relocated build (D337): the same sources at two places, named four ways -- from
# inside each as `src/main.e` and `./src/main.e`, and by absolute path -- are one image,
# and its trap names `src/leaf.e`.
$relocA = Join-Path $testBuild 'relocated-a'
$relocB = Join-Path $testBuild 'relocated-b'
foreach ($relocDir in @($relocA, $relocB)) {
    if (Test-Path -LiteralPath $relocDir) { Remove-Item -Recurse -Force -LiteralPath $relocDir }
    New-Item -ItemType Directory -Force -Path $relocDir | Out-Null
    Copy-Item -Recurse (Join-Path $nestedFixture 'src') (Join-Path $relocDir 'src')
}
$relocCases = @(
    @{ Dir = $relocA; Operand = 'src\main.e'; Out = 'rel.exe' },
    @{ Dir = $relocA; Operand = '.\src\main.e'; Out = 'dot.exe' },
    @{ Dir = $relocB; Operand = 'src\main.e'; Out = 'rel.exe' },
    @{ Dir = $relocB; Operand = (Join-Path $relocB 'src\main.e'); Out = 'abs.exe' }
)
foreach ($relocCase in $relocCases) {
    Push-Location $relocCase.Dir
    try {
        $relocWritten = & $compiler emit-executable $relocCase.Operand $repo 'x64' 'windows' $relocCase.Out --release
        if ($LASTEXITCODE -ne 0 -or $relocWritten -ne 'executable written') { throw "the relocated build did not compile: $($relocCase.Operand)" }
    } finally { Pop-Location }
}
$relocHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $relocA 'rel.exe')).Hash
foreach ($relocOther in @((Join-Path $relocA 'dot.exe'), (Join-Path $relocB 'rel.exe'), (Join-Path $relocB 'abs.exe'))) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $relocOther).Hash -ne $relocHash) { throw "a relocated build differs: $relocOther" }
}
$relocTrap = (& (Join-Path $relocB 'abs.exe') trap 2>&1) -join "`n"
if ($LASTEXITCODE -ne 134 -or $relocTrap -notmatch '^src/leaf\.e:3:13: trap\[unreachable\]') { throw "the relocated build's trap is not spelled from the project root: $relocTrap" }
# `-j 1 --perturb` (D331): the inlined release image on one worker, turned around.
$nestedJobs = Join-Path $testBuild 'inline-nested-release-jobs.exe'
$nestedJobsWritten = & $compiler emit-executable (Join-Path $nestedFixture 'src\main.e') $repo 'x64' 'windows' $nestedJobs --release -j 1 --perturb
if ($LASTEXITCODE -ne 0 -or $nestedJobsWritten -ne 'executable written') { throw 'nested inlining release emission under -j 1 --perturb failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $nestedJobs).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $nestedRelease).Hash) { throw 'the release build under -j 1 --perturb is not the default build' }
$nestedOutput = (& $nestedRelease trap 2>&1) -join "`n"
if ($LASTEXITCODE -ne 134 -or $nestedOutput -notmatch 'leaf\.e:3:13: trap\[unreachable\]: leaf gave up\n  at main\.main \(' -or $nestedOutput -match 'at mid\.') { throw "the nested release trap did not name leaf.e with one frame: exit $LASTEXITCODE, $nestedOutput" }
$nestedDebug = Join-Path $testBuild 'inline-nested-debug.exe'
$nestedDebugWritten = & $compiler emit-executable (Join-Path $nestedFixture 'src\main.e') $repo 'x64' 'windows' $nestedDebug
if ($LASTEXITCODE -ne 0 -or $nestedDebugWritten -ne 'executable written') { throw 'nested inlining debug emission failed' }
$nestedOutput = (& $nestedDebug trap 2>&1) -join "`n"
if ($LASTEXITCODE -ne 134 -or $nestedOutput -notmatch 'at leaf\.boom \(.*leaf\.e:3\)\n  at mid\.fail \(.*mid\.e:5\)\n  at main\.main \(.*main\.e:15\)') { throw "the nested debug trap did not walk three frames: exit $LASTEXITCODE, $nestedOutput" }
$nestedScratch = Join-Path $testBuild 'inline-nested-scratch'
$nestedSource = Join-Path $nestedScratch 'src'
$nestedArtifacts = Join-Path $testBuild 'inline-nested-artifacts'
if (Test-Path -LiteralPath $nestedScratch) { Remove-Item -LiteralPath $nestedScratch -Recurse -Force }
if (Test-Path -LiteralPath $nestedArtifacts) { Remove-Item -LiteralPath $nestedArtifacts -Recurse -Force }
New-Item -ItemType Directory -Force -Path $nestedSource, $nestedArtifacts | Out-Null
Copy-Item (Join-Path $nestedFixture 'src\*.e') $nestedSource
$nestedMain = Join-Path $nestedSource 'main.e'
$nestedFirst = & $compiler emit-em-all $nestedMain $repo 'x64' 'windows' $nestedArtifacts --release
if ($LASTEXITCODE -ne 0 -or $nestedFirst -ne 'compiled modules written') { throw 'the nested fixture did not compile to artifacts' }
Copy-Item (Join-Path $nestedFixture 'edits\leaf_body.e') (Join-Path $nestedSource 'leaf.e')
$nestedEdited = (& $compiler emit-em-all $nestedMain $repo 'x64' 'windows' $nestedArtifacts --release --incremental) -join "`n"
if ($LASTEXITCODE -ne 0 -or $nestedEdited -notmatch 'rebuilt main' -or $nestedEdited -notmatch 'rebuilt mid' -or $nestedEdited -notmatch 'rebuilt leaf' -or $nestedEdited -notmatch 'kept e.os') { throw "a leaf body edit did not rebuild through the nested copy: $nestedEdited" }
$nestedLinked = Join-Path $testBuild 'inline-nested-linked.exe'
$nestedArtifactList = @('main', 'mid', 'leaf', 'e.os', 'e.mem', 'e.str') | ForEach-Object { Join-Path $nestedArtifacts "$_.x64-windows.em" }
$nestedLinkWritten = & $compiler link-em $nestedLinked @nestedArtifactList
if ($LASTEXITCODE -ne 0 -or $nestedLinkWritten -ne 'artifact executable written') { throw 'the nested artifacts did not link' }
& $nestedLinked
if ($LASTEXITCODE -ne 6) { throw "the relinked program did not carry the leaf's new body through both copies: exit $LASTEXITCODE" }
# Section 9's compile-time evaluation of a call in a `const` (D218): seven constants
# computed by the interpreter agree with the same functions at run time, one is an
# array length; a call that reaches runtime state, and one that never returns, are
# refused naming the constant.
$comptimeCallPath = Join-Path $testBuild 'comptime-call-selfhost.exe'
$comptimeCallWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\comptime_call\src\main.e') $repo 'x64' 'windows' $comptimeCallPath
if ($LASTEXITCODE -ne 0 -or $comptimeCallWritten -ne 'executable written') { throw 'comptime call fixture executable emission failed' }
& $comptimeCallPath
if ($LASTEXITCODE -ne 0) { throw "a constant evaluated by the interpreter disagrees with run time: exit $LASTEXITCODE" }
Require-Fixture 'check/comptime_call_runtime'
$comptimeRuntime = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\comptime_call_runtime\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($comptimeRuntime -join "`n") -notmatch 'main\.e:8:19: error\[E-COMPTIME-9999\]: constant `CODE` cannot be evaluated at compile time: its call reached a statement it does not evaluate') { throw "a constant reaching runtime state was not refused: $($comptimeRuntime -join "`n")" }
Require-Fixture 'check/comptime_call_budget'
$comptimeBudget = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\comptime_call_budget\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($comptimeBudget -join "`n") -notmatch 'main\.e:6:11: error\[E-COMPTIME-9999\]: constant `FOREVER` cannot be evaluated at compile time: its call reached ten million steps') { throw "a constant past the budget was not refused: $($comptimeBudget -join "`n")" }
Require-Fixture 'check/comptime_call_in_type'
$comptimeInType = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\comptime_call_in_type\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($comptimeInType -join "`n") -notmatch 'main\.e:5:28: error\[E-COMPTIME-9999\]: a constant that calls a function is used in a type') { throw "a calling constant in a type was not refused with its reason: $($comptimeInType -join "`n")" }
# `emit-executable --arena SIZE` (D225): the root arena is the size given. Twelve
# mebibytes fit the default and not eight.
$arenaPath = Join-Path $testBuild 'arena-size-selfhost.exe'
$arenaWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\arena_size\src\main.e') $repo 'x64' 'windows' $arenaPath
if ($LASTEXITCODE -ne 0 -or $arenaWritten -ne 'executable written') { throw 'arena size fixture executable emission failed' }
& $arenaPath
if ($LASTEXITCODE -ne 0) { throw "the default arena did not hold twelve mebibytes: exit $LASTEXITCODE" }
$arenaSmallPath = Join-Path $testBuild 'arena-size-8m-selfhost.exe'
$arenaSmallWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\arena_size\src\main.e') $repo 'x64' 'windows' $arenaSmallPath --arena 8m
if ($LASTEXITCODE -ne 0 -or $arenaSmallWritten -ne 'executable written') { throw 'arena size fixture emission with --arena failed' }
$arenaSmallOutput = & $arenaSmallPath 2>&1
if ($LASTEXITCODE -ne 1 -or ($arenaSmallOutput -join "`n") -notmatch 'error: e\.mem\.Exhausted') { throw "an arena of eight mebibytes held twelve: exit $LASTEXITCODE, $($arenaSmallOutput -join "`n")" }
# docs/tooling.md sections 4 and 9 (D227): `tokens --json` and `parse --json` against the
# conformance corpus, byte for byte, with the exit status the result record carries.
$conformanceRoot = Join-Path $repo 'tests\conformance'
foreach ($case in @(@('tokens', 'every_kind', 0), @('tokens', 'hostile', 1), @('parse', 'every_kind', 0), @('parse', 'recovery', 1), @('parse', 'two_errors', 1), @('parse', 'barrier', 1))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" $($case[0]) --json --path $($case[1]).e `"$conformanceFixture`" > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "$($case[0]) --json on $($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "$($case[0]) --json on $($case[1]).e differs from the conformance corpus" }
}
# `-` reads stdin under `--path` (D289): a fixture piped in with its basename as the
# identity is its own golden, for tokens, parse and fmt; `-` without `--path` is usage.
$stdinActual = Join-Path $testBuild 'conformance-stdin-tokens.jsonl'
cmd /c "`"$compiler`" tokens --json --path every_kind.e - < `"$(Join-Path $conformanceRoot 'tokens\every_kind.e')`" > `"$stdinActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stdinActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tokens\every_kind.expected.jsonl')).Hash) { throw 'tokens --json from stdin differs from the conformance corpus' }
$stdinActual = Join-Path $testBuild 'conformance-stdin-parse.jsonl'
cmd /c "`"$compiler`" parse --json --path every_kind.e - < `"$(Join-Path $conformanceRoot 'parse\every_kind.e')`" > `"$stdinActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stdinActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'parse\every_kind.expected.jsonl')).Hash) { throw 'parse --json from stdin differs from the conformance corpus' }
$stdinActual = Join-Path $testBuild 'conformance-stdin-fmt.jsonl'
cmd /c "`"$compiler`" fmt-file - --json --path fmt.e < `"$(Join-Path $conformanceRoot 'tools\fmt.e')`" > `"$stdinActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stdinActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\fmt.expected.jsonl')).Hash) { throw 'fmt --json from stdin differs from the conformance corpus' }
$stdinActual = Join-Path $testBuild 'conformance-stdin-fmt.e'
cmd /c "`"$compiler`" fmt-file - < `"$(Join-Path $conformanceRoot 'tools\fmt.e')`" > `"$stdinActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stdinActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\fmt.e')).Hash) { throw 'fmt from stdin is not the canonical source' }
# `--overlay PATH=FILE` (D502, H15): a module's text from another file -- the value
# fixture's dependency from its edit -- without touching the tree: the build exits
# the edit's way, and the manifest records the overlay's hash as the input's.
$overlayScratch = Join-Path $testBuild 'overlay-scratch'
if (Test-Path -LiteralPath $overlayScratch) { Remove-Item -LiteralPath $overlayScratch -Recurse -Force }
Copy-Item -Recurse (Join-Path $repo 'tests\selfhost\fixtures\link\incremental_value') $overlayScratch
$overlayExe = Join-Path $testBuild 'overlay.exe'
$overlayBuilt = & $compiler emit-executable (Join-Path $overlayScratch 'src\main.e') $repo 'x64' 'windows' $overlayExe --overlay "dep.e=$(Join-Path $overlayScratch 'edits\dep_limit.e')" 2>&1
if ($LASTEXITCODE -ne 0 -or $overlayBuilt -ne 'executable written') { throw "the build over an overlay failed: $overlayBuilt" }
& $overlayExe
if ($LASTEXITCODE -ne 4) { throw "the build over an overlay did not take the overlay's text (exit $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $overlayScratch 'src\dep.e')).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'tests\selfhost\fixtures\link\incremental_value\src\dep.e')).Hash) { throw 'the overlay touched the file' }
$overlayManifest = Get-Content -Raw -LiteralPath (Join-Path $overlayScratch '.neper\debug\build-manifest.json') | ConvertFrom-Json
$overlayInput = ($overlayManifest.inputs | Where-Object { $_.source.path -eq 'dep.e' }).sha256
if ($overlayInput -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $overlayScratch 'edits\dep_limit.e')).Hash.ToLower()) { throw "the manifest does not record the overlay's hash as the input's" }
$overlayPlain = & $compiler emit-executable (Join-Path $overlayScratch 'src\main.e') $repo 'x64' 'windows' $overlayExe 2>&1
& $overlayExe
if ($LASTEXITCODE -ne 8) { throw "the build without the overlay did not read the file (exit $LASTEXITCODE)" }
# An overlay on a check and on a query (D524, H15): the root's buffer with a second
# call of `dep.answer` -- `uses-file` counts two, the file untouched -- and a buffer
# that does not check, refused by `check-file` while the file still checks.
$overlayMore = Join-Path $overlayScratch 'main_more.e'
[IO.File]::WriteAllText($overlayMore, ([IO.File]::ReadAllText((Join-Path $overlayScratch 'src\main.e')) + "`nfn again() -> i32 {`n    ret dep.answer()`n}`n"))
$overlayUses = & $compiler uses-file (Join-Path $overlayScratch 'src\main.e') $repo 'x64' 'windows' --json --symbol dep.answer --overlay "main.e=$overlayMore"
if ($LASTEXITCODE -ne 0 -or ($overlayUses | Where-Object { $_ -match '"record":"use"' }).Count -ne 3) { throw 'uses-file over an overlay of the root did not count the buffer''s calls' }
$overlayUsesPlain = & $compiler uses-file (Join-Path $overlayScratch 'src\main.e') $repo 'x64' 'windows' --json --symbol dep.answer
if ($LASTEXITCODE -ne 0 -or ($overlayUsesPlain | Where-Object { $_ -match '"record":"use"' }).Count -ne 2) { throw 'uses-file without the overlay did not read the file' }
$overlayBad = Join-Path $overlayScratch 'dep_bad.e'
[IO.File]::WriteAllText($overlayBad, "const LIMIT: usize = 3usize`n`nfn answer() -> i32 {`n    ret true`n}`n")
$overlayCheck = & $compiler check-file (Join-Path $overlayScratch 'src\main.e') $repo 'x64' 'windows' --json --overlay "dep.e=$overlayBad"
if ($LASTEXITCODE -ne 1 -or ($overlayCheck -join "`n") -notmatch 'E-TYPE-0002') { throw "check-file over an overlay that does not check did not report it (exit $LASTEXITCODE)" }
$overlayCheckPlain = & $compiler check-file (Join-Path $overlayScratch 'src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $overlayCheckPlain -ne 'module check ok') { throw 'check-file without the overlay did not read the file' }
# A trap inside a dependency (D503): the run record names the module's source and line.
$trapModuleActual = Join-Path $testBuild 'conformance-tools-run-trap-module.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run `"$(Join-Path $conformanceRoot 'tools\run_trap_module\src\main.e')`" `"$repo`" x64 windows conformance-tools-run-trap-module.out --json > `"$trapModuleActual`""
if ((Select-String -LiteralPath $trapModuleActual -Pattern '"trap":\{"kind":"bounds","span":\{"source":\{"root":"project-src","path":"deep.e"\},"byte_start":\d+,"byte_end":\d+,"line":3' -Quiet) -ne $true) { throw 'a trap inside a dependency does not name its source' }
if ((Select-String -LiteralPath $trapModuleActual -Pattern '\{"function":"deep.pick","source":\{"root":"project-src","path":"deep.e"\},"line":3\}' -Quiet) -ne $true) { throw 'a frame inside a dependency does not name its source' }
& python (Join-Path $repo 'scripts/validate_stream.py') $trapModuleActual
if ($LASTEXITCODE -ne 0) { throw 'the run record over a trap in a dependency does not validate' }
# The operand's own frame under its identity (D519): `project-src`, as the trap's span is.
if ((Select-String -LiteralPath $trapModuleActual -Pattern '\{"function":"main.main","source":\{"root":"project-src","path":"main.e"\},"line":9\}' -Quiet) -ne $true) { throw 'the operand frame of a trap record is not under its identity' }
# Provenance through inlining (D519, H19): in release, `deep.pick` is inlined into `main`,
# and the frame at `deep.e` names it as `inlined_from`.
$trapInlinedActual = Join-Path $testBuild 'conformance-tools-run-trap-inlined.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run `"$(Join-Path $conformanceRoot 'tools\run_trap_module\src\main.e')`" `"$repo`" x64 windows conformance-tools-run-trap-inlined.out --release --json > `"$trapInlinedActual`""
if ((Select-String -LiteralPath $trapInlinedActual -Pattern '\{"function":"main.main","source":\{"root":"project-src","path":"deep.e"\},"line":3,"inlined_from":"deep.pick"\}' -Quiet) -ne $true) { throw 'a frame inlined from another module does not name its origin' }
& python (Join-Path $repo 'scripts/validate_stream.py') $trapInlinedActual
if ($LASTEXITCODE -ne 0) { throw 'the run record over an inlined trap does not validate' }
# The index marks the boundaries a declaration holds (D513, H27): the unsafe fixture's
# symbols carry the kinds of the manifest's inventory that name them.
$indexUnsafeActual = Join-Path $testBuild 'conformance-tools-index-unsafe.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\manifest_unsafe')`" && `"$compiler`" index-file src/main.e `"$repo`" x64 windows --json > `"$indexUnsafeActual`""
if ($LASTEXITCODE -ne 0) { throw 'index-file --json over the unsafe fixture failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $indexUnsafeActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/index_unsafe.expected.jsonl')).Hash) { throw 'index-file --json over the unsafe fixture differs from the conformance corpus' }
# `-` on `check-file` (D490) and `index` (D488): the module from stdin under its `--path` identity is the file's golden.
$stdinActual = Join-Path $testBuild 'conformance-stdin-check.jsonl'
cmd /c "`"$compiler`" check-file - `"$repo`" x64 windows --json --path scope.e < `"$(Join-Path $conformanceRoot 'reject\scope.e')`" > `"$stdinActual`""
if ($LASTEXITCODE -ne 1) { throw "check-file --json from stdin exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stdinActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'reject\scope.expected.jsonl')).Hash) { throw 'check-file --json from stdin differs from the conformance corpus' }
$stdinActual = Join-Path $testBuild 'conformance-stdin-index.jsonl'
cmd /c "`"$compiler`" index-file - `"$repo`" x64 windows --json --path index.e < `"$(Join-Path $conformanceRoot 'tools\index.e')`" > `"$stdinActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stdinActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\index.expected.jsonl')).Hash) { throw 'index --json from stdin differs from the conformance corpus' }
cmd /c "`"$compiler`" tokens --json - < `"$(Join-Path $conformanceRoot 'tokens\every_kind.e')`" > nul 2>&1"
if ($LASTEXITCODE -ne 1) { throw "tokens - without --path exited $LASTEXITCODE, not 1" }
# `--absolute-paths` (D290): the operand's absolute spelling as `absolute_path` beside its
# identity and nothing else -- the stream with that field taken out is the golden. An
# absolute operand is spelled as given; a relative one under the current directory.
$absoluteActual = Join-Path $testBuild 'conformance-absolute-check.jsonl'
$absoluteFixture = Join-Path $conformanceRoot 'reject\scope.e'
cmd /c "`"$compiler`" check-file `"$absoluteFixture`" `"$repo`" x64 windows --json --absolute-paths > `"$absoluteActual`""
if ($LASTEXITCODE -ne 1) { throw "check-file --absolute-paths exited $LASTEXITCODE, not 1" }
$absoluteField = ',"absolute_path":"' + $absoluteFixture.Replace('\', '\\') + '"'
$absoluteText = [IO.File]::ReadAllText($absoluteActual)
if (-not $absoluteText.Contains($absoluteField)) { throw "--absolute-paths did not write the operand's absolute path" }
[IO.File]::WriteAllText($absoluteActual, $absoluteText.Replace($absoluteField, ''), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $absoluteActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'reject\scope.expected.jsonl')).Hash) { throw '--absolute-paths changed more than absolute_path on check' }
Copy-Item -LiteralPath (Join-Path $conformanceRoot 'tokens\every_kind.e') -Destination (Join-Path $testBuild 'every_kind.e') -Force
$absoluteActual = Join-Path $testBuild 'conformance-absolute-tokens.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" tokens --json --absolute-paths every_kind.e > `"$absoluteActual`""
$absoluteField = ',"absolute_path":"' + (Join-Path $testBuild 'every_kind.e').Replace('\', '\\') + '"'
$absoluteText = [IO.File]::ReadAllText($absoluteActual)
if (-not $absoluteText.Contains($absoluteField)) { throw "--absolute-paths did not spell a relative operand under the current directory" }
[IO.File]::WriteAllText($absoluteActual, $absoluteText.Replace($absoluteField, ''), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $absoluteActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tokens\every_kind.expected.jsonl')).Hash) { throw '--absolute-paths changed more than absolute_path on tokens' }
# `.` and `..` collapsed in `absolute_path` (D489): a roundabout spelling of the same file.
cmd /c "cd /d `"$testBuild`" && `"$compiler`" tokens --json --absolute-paths .\..\$(Split-Path -Leaf $testBuild)\every_kind.e > `"$absoluteActual`""
$absoluteText = [IO.File]::ReadAllText($absoluteActual)
if (-not $absoluteText.Contains($absoluteField)) { throw "--absolute-paths did not collapse the . and .. segments of the operand" }
# `check-file ... --json` (D228) against accept/ and reject/: a diagnostic record per
# error with its span, the result with the exit status, nothing on stderr.
foreach ($case in @(@('accept', 'scalar', 0), @('accept', 'aggregate', 0), @('reject', 'enum_values', 1), @('reject', 'lexical', 1), @('reject', 'when_local', 1), @('reject', 'scope', 1), @('reject', 'barrier', 1), @('reject', 'module_missing', 1), @('reject', 'qualifier_collision', 1), @('reject', 'reserved_local', 1), @('reject', 'try_not_fallible', 1), @('reject', 'return_count', 1), @('reject', 'generic_inference', 1), @('reject', 'condition_type', 1), @('reject', 'atomic_ordering', 1), @('reject', 'nesting', 1), @('accept', 'safety', 0), @('reject', 'safety_use_after_move', 1), @('reject', 'safety_cleanup_forgotten', 1), @('reject', 'safety_overwrite', 1), @('reject', 'safety_undef', 1), @('reject', 'safety_unchecked', 1), @('reject', 'safety_deferred_consumed', 1), @('reject', 'safety_moved_in_loop', 1), @('reject', 'safety_partial_move', 1), @('reject', 'safety_cleanup_signature', 1), @('reject', 'safety_borrowed', 1), @('reject', 'safety_borrowed_return', 1), @('reject', 'safety_copy', 1), @('reject', 'safety_copy_elements', 1), @('reject', 'safety_copy_generic', 1), @('reject', 'safety_handle_leak', 1), @('reject', 'safety_moved_while_borrowed', 1), @('reject', 'safety_arena_moved', 1), @('reject', 'safety_pushed_twice', 1), @('accept', 'regions', 0), @('reject', 'regions_reset', 1), @('reject', 'regions_view', 1), @('reject', 'regions_pointer_mutation', 1), @('reject', 'regions_join', 1), @('reject', 'safety_detached_frame', 1), @('reject', 'safety_thread_shared', 1), @('reject', 'safety_guard_leak', 1), @('reject', 'safety_thread_alias', 1), @('reject', 'regions_alias', 1), @('reject', 'safety_thread_slice', 1), @('reject', 'type_mismatch', 1), @('reject', 'safety_thread_field', 1), @('reject', 'safety_thread_reassign', 1), @('reject', 'safety_copy_toolchain', 1), @('reject', 'safety_rwguard_leak', 1), @('reject', 'safety_thread_group_leak', 1), @('reject', 'type_mismatch_fix', 1), @('reject', 'name_near', 1), @('reject', 'member_near', 1), @('reject', 'field_near', 1), @('reject', 'instance_site', 1), @('reject', 'instance_chain', 1), @('reject', 'each_function', 1), @('reject', 'safety_undef_value', 1), @('reject', 'type_near', 1), @('reject', 'type_mismatch_call', 1))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    $conformanceStderr = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).stderr"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`" 2> `"$conformanceStderr`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-Item -LiteralPath $conformanceStderr).Length -ne 0) { throw "check-file --json on $($case[0])/$($case[1]).e wrote to stderr" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
# D672-D715: alias-aware region/thread identity and deferred-reset timing.
foreach ($case in @(@('reject', 'regions_pointer_chain', 1), @('reject', 'regions_arena_alias', 1), @('reject', 'safety_thread_context_alias', 1), @('accept', 'regions_deferred_after_alloc', 0), @('reject', 'regions_deferred_escape', 1), @('reject', 'regions_arena_pointer_copy', 1), @('reject', 'regions_mark_copy', 1), @('reject', 'regions_accessor_alias', 1), @('reject', 'safety_thread_slice_context', 1), @('reject', 'regions_deferred_slice_escape', 1), @('reject', 'regions_deferred_pointer_escape', 1), @('reject', 'regions_deferred_pointer_alias_escape', 1), @('reject', 'regions_deferred_aggregate_escape', 1), @('reject', 'regions_deferred_aggregate_copy_escape', 1), @('reject', 'regions_deferred_aggregate_assignment_escape', 1), @('reject', 'safety_thread_aggregate_field_context', 1), @('reject', 'regions_aggregate_field_mutation', 1), @('reject', 'regions_aggregate_field_accessor', 1), @('reject', 'regions_deferred_nested_aggregate_escape', 1), @('reject', 'regions_deferred_nested_field_assignment_escape', 1), @('reject', 'regions_second_aggregate_field_alias', 1), @('reject', 'regions_deferred_second_aggregate_escape', 1), @('reject', 'regions_deferred_second_aggregate_copy_escape', 1), @('reject', 'regions_deferred_second_field_assignment_escape', 1), @('reject', 'safety_thread_second_aggregate_field_context', 1), @('reject', 'regions_third_aggregate_field_alias', 1), @('reject', 'regions_deferred_third_aggregate_escape', 1), @('reject', 'regions_deferred_third_aggregate_copy_escape', 1), @('reject', 'regions_deferred_third_field_assignment_escape', 1), @('reject', 'safety_thread_third_aggregate_field_context', 1), @('reject', 'regions_nested_second_field_alias', 1), @('reject', 'regions_deferred_nested_second_escape', 1), @('reject', 'regions_deferred_nested_second_copy_escape', 1), @('reject', 'regions_deferred_nested_pointer_assignment_escape', 1), @('reject', 'safety_thread_nested_second_field_context', 1), @('reject', 'regions_array_second_element_alias', 1), @('reject', 'regions_deferred_array_escape', 1), @('reject', 'regions_deferred_array_copy_escape', 1), @('reject', 'regions_deferred_array_element_assignment_escape', 1), @('reject', 'safety_thread_array_element_context', 1), @('reject', 'regions_dynamic_array_element_alias', 1), @('reject', 'regions_deferred_dynamic_array_element_escape', 1), @('reject', 'regions_dynamic_array_element_mutation', 1), @('reject', 'safety_thread_dynamic_array_element_context', 1), @('reject', 'regions_nested_dynamic_array_element_alias', 1))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
# D716-D720: runtime-indexed affine fixed-array ownership and slice candidates.
foreach ($case in @(@('reject', 'safety_dynamic_array_read', 1), @('reject', 'safety_dynamic_array_move', 1), @('reject', 'safety_dynamic_array_overwrite', 1), @('reject', 'safety_dynamic_array_store_leak', 1), @('reject', 'safety_dynamic_array_slice_offset', 1))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
# D721-D725: explicit ownership transfer and exhaustive cleanup for resource slices.
foreach ($case in @(@('reject', 'safety_owned_slice_leak', 1), @('reject', 'safety_owned_slice_partial', 1), @('accept', 'safety_owned_slice_sweep', 0), @('accept', 'safety_owned_slice_transfer', 0), @('accept', 'safety_owned_slice_offset_transfer', 0))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
# D731-D735: declared, proved, propagated and serialized result-borrow summaries.
foreach ($case in @(@('reject', 'regions_borrow_contract_name', 1), @('reject', 'regions_borrow_contract_body', 1), @('accept', 'regions_borrow_contract_aggregate', 0), @('reject', 'regions_borrow_contract_call', 1), @('reject', 'regions_borrow_contract_generic', 1), @('accept', 'regions_borrow_contract_artifact', 0))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
$borrowSummaryArtifact = Join-Path $testBuild 'borrow-summary.x64-windows.em'
$borrowSummaryWritten = & $compiler emit-em (Join-Path $conformanceRoot 'accept\regions_borrow_contract_artifact.e') $repo x64 windows $borrowSummaryArtifact
if ($LASTEXITCODE -ne 0 -or $borrowSummaryWritten -ne 'compiled module written') { throw 'writing the borrow-summary artifact failed' }
$borrowSummaryBytes = [IO.File]::ReadAllBytes($borrowSummaryArtifact)
$borrowSummaryInterface = [BitConverter]::ToUInt64($borrowSummaryBytes, 64)
if ([BitConverter]::ToUInt32($borrowSummaryBytes, [int]$borrowSummaryInterface + 44) -ne 2) { throw 'the function interface did not serialize borrow_from=2' }
# D736-D740: declared, proved, propagated and serialized no-escape inputs.
foreach ($case in @(@('accept', 'regions_noescape_contract', 0), @('reject', 'regions_noescape_contract_name', 1), @('accept', 'regions_noescape_multi_contract', 0), @('reject', 'regions_noescape_multi_contract_duplicate', 1), @('reject', 'regions_noescape_contract_return', 1), @('reject', 'regions_noescape_multi_return', 1), @('reject', 'regions_noescape_contract_global', 1), @('reject', 'regions_noescape_multi_global', 1), @('accept', 'regions_noescape_contract_forward', 0), @('accept', 'regions_noescape_multi_forward', 0), @('reject', 'regions_noescape_contract_call', 1), @('reject', 'regions_noescape_multi_call', 1), @('reject', 'regions_noescape_contract_callback', 1), @('reject', 'regions_noescape_contract_thread', 1), @('accept', 'regions_noescape_contract_generic', 0), @('accept', 'regions_noescape_contract_artifact', 0), @('accept', 'regions_noescape_multi_artifact', 0))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
$noescapeSummaryArtifact = Join-Path $testBuild 'noescape-summary.x64-windows.em'
$noescapeSummaryWritten = & $compiler emit-em (Join-Path $conformanceRoot 'accept\regions_noescape_contract_artifact.e') $repo x64 windows $noescapeSummaryArtifact
if ($LASTEXITCODE -ne 0 -or $noescapeSummaryWritten -ne 'compiled module written') { throw 'writing the noescape-summary artifact failed' }
$noescapeSummaryBytes = [IO.File]::ReadAllBytes($noescapeSummaryArtifact)
$noescapeSummaryInterface = [BitConverter]::ToUInt64($noescapeSummaryBytes, 64)
if ([BitConverter]::ToUInt16($noescapeSummaryBytes, 4) -ne 14) { throw 'the noescape-summary artifact did not use format 14' }
if ([BitConverter]::ToUInt32($noescapeSummaryBytes, [int]$noescapeSummaryInterface + 48) -ne 1 -or [BitConverter]::ToUInt32($noescapeSummaryBytes, [int]$noescapeSummaryInterface + 52) -ne 2) { throw 'the function interface did not serialize noescape={2}' }
$noescapeMultiArtifact = Join-Path $testBuild 'noescape-multi.x64-windows.em'
$noescapeMultiWritten = & $compiler emit-em (Join-Path $conformanceRoot 'accept\regions_noescape_multi_artifact.e') $repo x64 windows $noescapeMultiArtifact
if ($LASTEXITCODE -ne 0 -or $noescapeMultiWritten -ne 'compiled module written') { throw 'writing the multi-input noescape artifact failed' }
$noescapeMultiBytes = [IO.File]::ReadAllBytes($noescapeMultiArtifact)
$noescapeMultiInterface = [BitConverter]::ToUInt64($noescapeMultiBytes, 64)
if ([BitConverter]::ToUInt32($noescapeMultiBytes, [int]$noescapeMultiInterface + 48) -ne 2 -or [BitConverter]::ToUInt32($noescapeMultiBytes, [int]$noescapeMultiInterface + 52) -ne 1 -or [BitConverter]::ToUInt32($noescapeMultiBytes, [int]$noescapeMultiInterface + 56) -ne 2) { throw 'the function interface did not serialize noescape={1,2}' }
# A consuming dereference follows its lexical pointer alias to the pinned resource
# (D610, H01).
$pointerMoveActual = Join-Path $testBuild 'conformance-reject-safety_pointer_move.jsonl'
cmd /c "`"$compiler`" check-file `"$(Join-Path $conformanceRoot 'reject\safety_pointer_move.e')`" `"$repo`" x64 windows --json > `"$pointerMoveActual`""
if ($LASTEXITCODE -ne 1) { throw "check-file --json on reject/safety_pointer_move.e exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $pointerMoveActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'reject\safety_pointer_move.expected.jsonl')).Hash) { throw 'check-file --json on reject/safety_pointer_move.e differs from the conformance corpus' }
# A concrete generic aggregate is classified from its substituted resource fields
# (D611, H01).
$genericAggregateActual = Join-Path $testBuild 'conformance-reject-safety_generic_aggregate.jsonl'
cmd /c "`"$compiler`" check-file `"$(Join-Path $conformanceRoot 'reject\safety_generic_aggregate.e')`" `"$repo`" x64 windows --json > `"$genericAggregateActual`""
if ($LASTEXITCODE -ne 1) { throw "check-file --json on reject/safety_generic_aggregate.e exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $genericAggregateActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'reject\safety_generic_aggregate.expected.jsonl')).Hash) { throw 'check-file --json on reject/safety_generic_aggregate.e differs from the conformance corpus' }
# A tagged union is affine as a whole when one of its payloads is affine
# (D612, H01).
$taggedResourceActual = Join-Path $testBuild 'conformance-reject-safety_tagged_resource.jsonl'
cmd /c "`"$compiler`" check-file `"$(Join-Path $conformanceRoot 'reject\safety_tagged_resource.e')`" `"$repo`" x64 windows --json > `"$taggedResourceActual`""
if ($LASTEXITCODE -ne 1) { throw "check-file --json on reject/safety_tagged_resource.e exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $taggedResourceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'reject\safety_tagged_resource.expected.jsonl')).Hash) { throw 'check-file --json on reject/safety_tagged_resource.e differs from the conformance corpus' }
# A resource closer may take context before its final owned parameter, but the
# owned resource must be last (D613, H01/H13).
foreach ($closerCase in @(@('accept', 'safety_resource_closer', 0), @('reject', 'safety_cleanup_position', 1))) {
    $closerActual = Join-Path $testBuild "conformance-$($closerCase[0])-$($closerCase[1]).jsonl"
    cmd /c "`"$compiler`" check-file `"$(Join-Path $conformanceRoot "$($closerCase[0])\$($closerCase[1]).e")`" `"$repo`" x64 windows --json > `"$closerActual`""
    if ($LASTEXITCODE -ne $closerCase[2]) { throw "check-file --json on $($closerCase[0])/$($closerCase[1]).e exited $LASTEXITCODE, not $($closerCase[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $closerActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "$($closerCase[0])\$($closerCase[1]).expected.jsonl")).Hash) { throw "check-file --json on $($closerCase[0])/$($closerCase[1]).e differs from the conformance corpus" }
}
# A reject fixture that is a project (D297): a cycle and an ambiguous variant need
# more than one module, so the operand is `reject/<name>/src/main.e`.
foreach ($rejectProject in @('module_cycle', 'module_variants', 'safety_opaque')) {
    $rejectProjectActual = Join-Path $testBuild "conformance-reject-$rejectProject.jsonl"
    cmd /c "`"$compiler`" check-file `"$(Join-Path $conformanceRoot "reject\$rejectProject\src\main.e")`" `"$repo`" x64 windows --json > `"$rejectProjectActual`""
    if ($LASTEXITCODE -ne 1) { throw "check-file --json on reject/$rejectProject exited $LASTEXITCODE, not 1" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $rejectProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "reject\$rejectProject.expected.jsonl")).Hash) { throw "check-file --json on reject/$rejectProject differs from the conformance corpus" }
}
# An accept fixture that is a project (D348): a declared resource lives in its own module.
$acceptProjectActual = Join-Path $testBuild 'conformance-accept-safety_resource.jsonl'
cmd /c "`"$compiler`" check-file `"$(Join-Path $conformanceRoot 'accept\safety_resource\src\main.e')`" `"$repo`" x64 windows --json > `"$acceptProjectActual`""
if ($LASTEXITCODE -ne 0) { throw "check-file --json on accept/safety_resource exited $LASTEXITCODE, not 0" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $acceptProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'accept\safety_resource.expected.jsonl')).Hash) { throw 'check-file --json on accept/safety_resource differs from the conformance corpus' }
# `info --json` (D229): the capability record for this host, byte for byte.
$infoActual = Join-Path $testBuild 'conformance-tools-info.jsonl'
cmd /c "`"$compiler`" info --json > `"$infoActual`""
if ($LASTEXITCODE -ne 0) { throw "info --json exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $infoActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\info.x64-windows.expected.jsonl')).Hash) { throw "info --json differs from the conformance corpus" }
# `check-project --json` (D262): every module under a project's src in byte order, each
# checked in its own process under its path relative to src, one stream; two of the
# fixture's three modules carry an error.
$checkProjectActual = Join-Path $testBuild 'conformance-tools-check-project.jsonl'
cmd /c "`"$compiler`" check-project `"$(Join-Path $conformanceRoot 'tools/check_project')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$checkProjectActual`""
if ($LASTEXITCODE -ne 1) { throw "check-project --json exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $checkProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/check_project.expected.jsonl')).Hash) { throw "check-project --json differs from the conformance corpus" }
# `--language-version` (D283): the advertised 0.1 is accepted on any command and taken
# off the arguments; another is E-CLI-9999 before any source is read, as a stream under
# `--json` whose header names the command.
$versionActual = Join-Path $testBuild 'conformance-tools-info-version.jsonl'
cmd /c "`"$compiler`" info --json --language-version 0.1 > `"$versionActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $versionActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/info.x64-windows.expected.jsonl')).Hash) { throw '--language-version 0.1 changed the info stream' }
cmd /c "`"$compiler`" info --json --language-version 9.9 > `"$versionActual`""
if ($LASTEXITCODE -ne 2) { throw "an unadvertised language version exited $LASTEXITCODE, not 2" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $versionActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/info_version.expected.jsonl')).Hash) { throw 'an unadvertised language version is not refused as the conformance corpus says' }
# `emit-executable --json` (D230): the build stream, the executable named as given,
# a rejected program's diagnostics as records; both byte for byte from testBuild.
# A build writes `.neper/<mode>/build-manifest.json` under the project root, making the
# directory when it is missing (D254, D287); the repo is the corpus's project root, so
# the mode directory is removed first to prove the build makes it.
if (Test-Path -LiteralPath (Join-Path $repo '.neper\debug')) { Remove-Item -Recurse -Force -LiteralPath (Join-Path $repo '.neper\debug') }
# The runtime's arena (D552, H05): a project whose own `e.mem` lays `Arena` out otherwise is refused at the build, E-LINK-0002.
foreach ($case in @(@('tools\build.e', 'build', 0), @('reject\scope.e', 'build_reject', 1), @('reject\arena_layout\src\main.e', 'arena_layout', 1))) {
    $buildActual = Join-Path $testBuild "conformance-tools-$($case[1]).jsonl"
    cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot $case[0])`" `"$repo`" x64 windows conformance-tools-$($case[1]).out --json > `"$buildActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "emit-executable --json on $($case[0]) exited $LASTEXITCODE" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $buildActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools\$($case[1]).expected.jsonl")).Hash) { throw "emit-executable --json on $($case[0]) differs from the conformance corpus" }
}
Copy-Item -LiteralPath (Join-Path $testBuild 'conformance-tools-build.out') -Destination (Join-Path $testBuild 'conformance-tools-build.exe') -Force
& (Join-Path $testBuild 'conformance-tools-build.exe')
if ($LASTEXITCODE -ne 0) { throw "the executable of build --json exited $LASTEXITCODE" }
# The manifest the build.e build wrote: valid against the schema, naming the executable
# as given with the SHA-256 of the bytes on disk.
$manifestPath = Join-Path $repo '.neper\debug\build-manifest.json'
if (-not (Test-Path -LiteralPath (Join-Path $repo '.neper\debug') -PathType Container)) { throw 'the build did not make .neper/debug/' }
& python (Join-Path $repo 'scripts/validate_stream.py') $manifestPath
if ($LASTEXITCODE -ne 0) { throw 'the build manifest a build writes does not validate against the v1 schema' }
# The artifact's path is project-relative (D293): the executable was named beside the
# test build directory, and the manifest spells it from the repo.
$manifestArtifact = [regex]::Match([IO.File]::ReadAllText($manifestPath), '"artifacts":\[\{"path":"build/windows/tests/selfhost/conformance-tools-build.out","kind":"executable","target":"x64-windows","sha256":"([0-9a-f]{64})"').Groups[1].Value
if ($manifestArtifact -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $testBuild 'conformance-tools-build.out')).Hash.ToLower()) { throw "the build manifest does not carry the executable's SHA-256" }
# Reproducible builds (D261): the same source built again is the same bytes, and the
# manifest of the second build carries the same artifact hash as the first -- so a
# manifest is a witness two builds can be compared by, without the executables.
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot 'tools\build.e')`" `"$repo`" x64 windows conformance-tools-build-again.out > nul"
if ($LASTEXITCODE -ne 0) { throw "the second build of build.e exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $testBuild 'conformance-tools-build.out')).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $testBuild 'conformance-tools-build-again.out')).Hash) { throw 'the same source built twice is not the same executable' }
# `compare-manifests` (D482): the two builds' manifests agree -- the artifact's path is
# where it was written, not what it is -- and a debug manifest against a release one
# names the mode and the artifact.
$manifestFirst = Join-Path $testBuild 'manifest-first.json'
Copy-Item -LiteralPath $manifestPath -Destination $manifestFirst -Force
$manifestAgain = [regex]::Match([IO.File]::ReadAllText($manifestPath), '"artifacts":\[\{"path":"build/windows/tests/selfhost/conformance-tools-build-again.out","kind":"executable","target":"x64-windows","sha256":"([0-9a-f]{64})"').Groups[1].Value
if ($manifestAgain -ne $manifestArtifact) { throw "the second build's manifest does not carry the first build's artifact hash" }
$compared = & $compiler compare-manifests $manifestFirst $manifestPath
if ($LASTEXITCODE -ne 0 -or $compared -ne 'manifests agree') { throw "the manifests of two builds of the same source differ: $compared" }
# The image's digest reused when the image is the one on disk (D332): a third build of
# the same source into the same output finds its own bytes at the output path, skips the
# write -- the file's mtime stays -- and takes the digest from the manifest that
# recorded it, which is still the executable's.
$imageStamp = (Get-Item -LiteralPath (Join-Path $testBuild 'conformance-tools-build-again.out')).LastWriteTimeUtc.Ticks
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot 'tools\build.e')`" `"$repo`" x64 windows conformance-tools-build-again.out > nul"
if ($LASTEXITCODE -ne 0) { throw "the third build of build.e exited $LASTEXITCODE" }
if ((Get-Item -LiteralPath (Join-Path $testBuild 'conformance-tools-build-again.out')).LastWriteTimeUtc.Ticks -ne $imageStamp) { throw 'a build whose image is already the file at the output path rewrote it' }
$manifestReused = [regex]::Match([IO.File]::ReadAllText($manifestPath), '"artifacts":\[\{"path":"build/windows/tests/selfhost/conformance-tools-build-again.out","kind":"executable","target":"x64-windows","sha256":"([0-9a-f]{64})"').Groups[1].Value
if ($manifestReused -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $testBuild 'conformance-tools-build-again.out')).Hash.ToLower()) { throw "the digest reused from the previous manifest is not the image's" }
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot 'tools\contract.e')`" `"$repo`" x64 windows conformance-tools-compare-debug.out > nul"
if ($LASTEXITCODE -ne 0) { throw "the debug build of contract.e exited $LASTEXITCODE" }
$manifestDebug = Join-Path $testBuild 'manifest-debug.json'
Copy-Item -LiteralPath $manifestPath -Destination $manifestDebug -Force
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot 'tools\contract.e')`" `"$repo`" x64 windows conformance-tools-compare-release.out --release > nul"
if ($LASTEXITCODE -ne 0) { throw "the release build of contract.e exited $LASTEXITCODE" }
$comparedModes = Join-Path $testBuild 'conformance-tools-compare-manifests.jsonl'
cmd /c "`"$compiler`" compare-manifests `"$manifestDebug`" `"$(Join-Path $repo '.neper\release\build-manifest.json')`" --json > `"$comparedModes`""
if ($LASTEXITCODE -ne 0) { throw "compare-manifests --json exited $LASTEXITCODE" }
if ((Select-String -LiteralPath $comparedModes -Pattern '"record":"difference","kind":"mode","name":"","left":"debug","right":"release"' -Quiet) -ne $true) { throw 'compare-manifests does not name the mode' }
if ((Select-String -LiteralPath $comparedModes -Pattern '"record":"difference","kind":"artifact"' -Quiet) -ne $true) { throw 'compare-manifests does not name the artifact' }
if ((Select-String -LiteralPath $comparedModes -Pattern '"same":false' -Quiet) -ne $true) { throw 'compare-manifests calls two modes the same' }
& python (Join-Path $repo 'scripts/validate_stream.py') $comparedModes
if ($LASTEXITCODE -ne 0) { throw 'the difference records do not validate against the schema' }
# Spec section 2's spelling (D276): `neper build FILE -o OUT --json` from a binary that
# has the toolchain's lib/ beside it is the same stream as the positional form.
$shortRoot = Join-Path $repo 'build\windows\short'
if (Test-Path -LiteralPath $shortRoot) { Remove-Item -Recurse -Force -LiteralPath $shortRoot }
[void](New-Item -ItemType Directory -Force -Path $shortRoot)
Copy-Item -Recurse -LiteralPath (Join-Path $repo 'lib') -Destination (Join-Path $shortRoot 'lib')
$shortCompiler = Join-Path $shortRoot 'neper-self-short.exe'
Copy-Item -LiteralPath $compiler -Destination $shortCompiler -Force
$buildShortActual = Join-Path $testBuild 'conformance-tools-build-short.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$shortCompiler`" build `"$(Join-Path $conformanceRoot 'tools\build.e')`" -o conformance-tools-build.out --json > `"$buildShortActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $buildShortActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\build.expected.jsonl')).Hash) { throw 'the short build spelling differs from the positional form' }
# `neper test FILE` (D292): the short spelling is the test stream, its WORKDIR
# `.neper/debug/test/` under the operand's project -- the repo here -- made by the command.
$testShortActual = Join-Path $testBuild 'conformance-tools-test-short.jsonl'
if (Test-Path -LiteralPath (Join-Path $repo '.neper\debug\test')) { Remove-Item -Recurse -Force -LiteralPath (Join-Path $repo '.neper\debug\test') }
cmd /c "`"$shortCompiler`" test `"$(Join-Path $conformanceRoot 'tools\test.e')`" > `"$testShortActual`""
if ($LASTEXITCODE -ne 1) { throw "the short test spelling exited $LASTEXITCODE, expected 1" }
if (-not (Test-Path -LiteralPath (Join-Path $repo '.neper\debug\test\nptest-runner.e'))) { throw 'the short test spelling did not work under .neper/debug/test/' }
[IO.File]::WriteAllText($testShortActual, ([IO.File]::ReadAllText($testShortActual) -replace '"duration_ms":\d+', '"duration_ms":0' -replace '[^" (]*nptest-runner\.e', 'nptest-runner.e'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testShortActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\test.expected.jsonl')).Hash) { throw 'the short test spelling differs from the positional form' }
# `neper check` and `neper test` with no operand (D294): the project the current
# directory is in, as the project forms, working under its `.neper/debug/<command>/`.
$checkShortActual = Join-Path $testBuild 'conformance-tools-check-project-short.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\check_project')`" && `"$shortCompiler`" check > `"$checkShortActual`""
if ($LASTEXITCODE -ne 1) { throw "the operand-less check exited $LASTEXITCODE, expected 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $checkShortActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\check_project.expected.jsonl')).Hash) { throw 'the operand-less check differs from check-project' }
$testShortProjectActual = Join-Path $testBuild 'conformance-tools-test-project-short.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\test_project')`" && `"$shortCompiler`" test > `"$testShortProjectActual`""
if ($LASTEXITCODE -ne 1) { throw "the operand-less test exited $LASTEXITCODE, expected 1" }
[IO.File]::WriteAllText($testShortProjectActual, ([IO.File]::ReadAllText($testShortProjectActual) -replace '"duration_ms":\d+', '"duration_ms":0'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testShortProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\test_project.expected.jsonl')).Hash) { throw 'the operand-less test differs from test-project' }
# `fmt FILE` formats the file in place, and `fmt` / `fmt --check` with no operand cover
# every `.e` under the project's src/ and lib/ (D295): a project of one non-canonical
# file fails the check, is formatted to the corpus's canonical text, then passes.
$fmtProject = Join-Path $testBuild 'fmt_project'
if (Test-Path -LiteralPath $fmtProject) { Remove-Item -Recurse -Force -LiteralPath $fmtProject }
[void](New-Item -ItemType Directory -Force -Path (Join-Path $fmtProject 'src'))
Copy-Item -LiteralPath (Join-Path $conformanceRoot 'format\layout.e') -Destination (Join-Path $fmtProject 'src\layout.e')
cmd /c "cd /d `"$fmtProject`" && `"$shortCompiler`" fmt --check > nul 2> nul"
if ($LASTEXITCODE -ne 1) { throw "fmt --check over a non-canonical project exited $LASTEXITCODE, not 1" }
cmd /c "cd /d `"$fmtProject`" && `"$shortCompiler`" fmt"
if ($LASTEXITCODE -ne 0) { throw "fmt over the project exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fmtProject 'src\layout.e')).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'format\layout.expected.e')).Hash) { throw 'fmt over the project did not write the canonical text' }
cmd /c "cd /d `"$fmtProject`" && `"$shortCompiler`" fmt --check"
if ($LASTEXITCODE -ne 0) { throw "fmt --check over the formatted project exited $LASTEXITCODE" }
Copy-Item -LiteralPath (Join-Path $conformanceRoot 'format\layout.e') -Destination (Join-Path $testBuild 'fmt-in-place.e') -Force
cmd /c "`"$shortCompiler`" fmt `"$(Join-Path $testBuild 'fmt-in-place.e')`""
if ($LASTEXITCODE -ne 0) { throw "fmt FILE exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $testBuild 'fmt-in-place.e')).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'format\layout.expected.e')).Hash) { throw 'fmt FILE did not format the file in place' }
# `index-project --json` (D298): every module under a project's src and lib, each
# indexed under its path from the root, one stream -- another target's variant left
# out (D544, `util.arm64.e`); and `neper index` with no operand
# from inside the project is the same stream.
$indexProjectActual = Join-Path $testBuild 'conformance-tools-index-project.jsonl'
cmd /c "`"$compiler`" index-project `"$(Join-Path $conformanceRoot 'tools\index_project')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$indexProjectActual`""
if ($LASTEXITCODE -ne 0) { throw "index-project --json exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $indexProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\index_project.expected.jsonl')).Hash) { throw 'index-project --json differs from the conformance corpus' }
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\index_project')`" && `"$shortCompiler`" index > `"$indexProjectActual`""
if ($LASTEXITCODE -ne 0) { throw "the operand-less index exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $indexProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\index_project.expected.jsonl')).Hash) { throw 'the operand-less index differs from index-project' }
# `run --json` (D231): the build stream plus one `run` record of the program's whole
# stdout, stderr and exit status, byte for byte.
$runActual = Join-Path $testBuild 'conformance-tools-run.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run `"$(Join-Path $conformanceRoot 'tools/run.e')`" `"$repo`" x64 windows conformance-tools-run.out --json > `"$runActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/run.expected.jsonl')).Hash) { throw "run --json differs from the conformance corpus" }
# `run --json` on a program that traps (D253): section 11's record read back as the
# `trap` payload. The operand is spelled relative to the test build dir, whose depth is
# the same on both hosts, so the child's stderr -- and the golden -- carry no host path.
$runTrapActual = Join-Path $testBuild 'conformance-tools-run-trap.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run ../../../../tests/conformance/tools/run_trap.e `"$repo`" x64 windows conformance-tools-run-trap.out --json > `"$runTrapActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runTrapActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/run_trap.expected.jsonl')).Hash) { throw "run --json on a trapping program differs from the conformance corpus" }
# `run --json -- ARGS...` (D267): what follows `--` reaches the program, spaces and all.
$runArgsActual = Join-Path $testBuild 'conformance-tools-run-args.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run ../../../../tests/conformance/tools/run_args.e `"$repo`" x64 windows conformance-tools-run-args.out --json -- first `"second word`" 3 > `"$runArgsActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runArgsActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/run_args.expected.jsonl')).Hash) { throw "run --json with program arguments differs from the conformance corpus" }
# `run --json --capture N` (D370, H18): the record holds the first N bytes of each stream,
# the result says how many there were and that the capture is not complete.
$runFloodActual = Join-Path $testBuild 'conformance-tools-run-flood.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run ../../../../tests/conformance/tools/run_flood.e `"$repo`" x64 windows conformance-tools-run-flood.out --json --capture 50 > `"$runFloodActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runFloodActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/run_flood.expected.jsonl')).Hash) { throw "run --json --capture differs from the conformance corpus" }
if ((Get-Item -LiteralPath (Join-Path $testBuild 'conformance-tools-run-flood.out.stdout')).Length -ne 296) { throw 'the whole flood output is not in the file beside the executable' }
# `--explain --json` (D408, H20): every inlining decision a record of the build stream,
# in worker order -- one worker here, so module order -- byte for byte per host.
$explainInlineActual = Join-Path $testBuild 'conformance-tools-explain-inline.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable ../../../../tests/conformance/tools/contract.e `"$repo`" x64 windows conformance-tools-explain-inline.out --release --explain --json -j 1 > `"$explainInlineActual`""
if ($LASTEXITCODE -ne 0) { throw "emit-executable --explain --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $explainInlineActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/explain_inline.x64-windows.expected.jsonl')).Hash) { throw "emit-executable --explain --json differs from the conformance corpus" }
# Progress records (D454, D561, H18): under `--json --time` every phase is a record
# of the stream, with a contiguous one-based sequence, and the result still ends it.
$progressActual = Join-Path $testBuild 'conformance-tools-progress.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable ../../../../tests/conformance/tools/contract.e `"$repo`" x64 windows conformance-tools-progress.out --json --time > `"$progressActual`""
if ($LASTEXITCODE -ne 0) { throw "emit-executable --json --time failed" }
if ((Select-String -LiteralPath $progressActual -Pattern '"record":"progress","phase":"lower and codegen"' -Quiet) -ne $true) { throw 'the build stream under --time carries no progress record for the lowering' }
& python -c "import json,sys; rows=[json.loads(x) for x in open(sys.argv[1])]; progress=[r for r in rows if r.get('record')=='progress']; assert len(progress)>1 and [r['sequence'] for r in progress]==list(range(1,len(progress)+1)) and rows[-1].get('record')=='result'" $progressActual
if ($LASTEXITCODE -ne 0) { throw 'the progress sequence is not contiguous or the result is not final' }
& python (Join-Path $repo 'scripts/validate_stream.py') $progressActual
if ($LASTEXITCODE -ne 0) { throw 'the progress records do not validate against the schema' }
# `--stats` as a record (D476, H18): under `--json` the table is one flat `stats`
# record of the stream before the result, a snake_case key per row with the unit
# as its suffix, `--stats-full`'s pools as `pool_<name>_capacity` and `_used`.
$statsActual = Join-Path $testBuild 'conformance-tools-stats.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable ../../../../tests/conformance/tools/contract.e `"$repo`" x64 windows conformance-tools-stats.out --json --stats-full > `"$statsActual`""
if ($LASTEXITCODE -ne 0) { throw "emit-executable --json --stats-full failed" }
& python (Join-Path $repo 'scripts/check_stats_record.py') $statsActual
if ($LASTEXITCODE -ne 0) { throw 'the stats record is not one flat record before the result' }
& python (Join-Path $repo 'scripts/validate_stream.py') $statsActual
if ($LASTEXITCODE -ne 0) { throw 'the stats record does not validate against the schema' }
# Per-instance cost (D453, H06): every generic instance's instructions and bytes as
# `instance-cost` records of the build stream, after the lowering.
$explainInstancesActual = Join-Path $testBuild 'conformance-tools-explain-instances.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable ../../../../tests/conformance/tools/instances.e `"$repo`" x64 windows conformance-tools-explain-instances.out --release --explain --json -j 1 > `"$explainInstancesActual`""
if ($LASTEXITCODE -ne 0) { throw "emit-executable --explain --json over instances failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $explainInstancesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/explain_instances.x64-windows.expected.jsonl')).Hash) { throw "the instance-cost records differ from the conformance corpus" }
# `index --json` (D232): the operand module's symbol records, byte for byte (target-independent).
$indexActual = Join-Path $testBuild 'conformance-tools-index.jsonl'
cmd /c "`"$compiler`" index-file `"$(Join-Path $conformanceRoot 'tools/index.e')`" `"$repo`" x64 windows --json > `"$indexActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $indexActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/index.expected.jsonl')).Hash) { throw "index --json differs from the conformance corpus" }
# A resource closer is a semantic reference (D560, H17), though its contextual
# `resource(close)` spelling is neither an expression nor an ordinary type use.
$indexResource = & $compiler index-file (Join-Path $conformanceRoot 'tools/index_resource.e') $repo 'x64' 'windows' --json
if ($LASTEXITCODE -ne 0) { throw 'index-file over a resource closer failed' }
$indexResourceRefs = @($indexResource | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.record -eq 'reference' -and $_.role -eq 'protocol' -and $_.target_qualified_name -eq 'index_resource.close' })
if ($indexResourceRefs.Count -ne 1 -or $indexResourceRefs[0].spelling -ne 'close') { throw 'the index did not resolve resource(close) to its closer' }
# `plan-rename-file --json` (D376, H29): the plan byte for byte; applied to a copy it
# re-checks, the new name has uses at the old sites, and a second apply is refused.
$planActual = Join-Path $testBuild 'conformance-tools-plan-rename.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-rename-file explain.e `"$repo`" x64 windows --json --symbol explain.same --to alike > `"$planActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-rename-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $planActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename.x64-windows.expected.jsonl')).Hash) { throw "plan-rename-file --json differs from the conformance corpus" }
$planScratch = Join-Path $testBuild 'plan-scratch'
if (Test-Path -LiteralPath $planScratch) { Remove-Item -LiteralPath $planScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $planScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools/explain.e') (Join-Path $planScratch 'src')
& $compiler apply-plan $planActual --root (Join-Path $planScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the rename plan did not apply' }
$planChecked = & $compiler check-file (Join-Path $planScratch 'src/explain.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $planChecked -ne 'module check ok') { throw "the renamed program does not check: $planChecked" }
$planUses = & $compiler uses-file (Join-Path $planScratch 'src/explain.e') $repo 'x64' 'windows' --json --symbol explain.alike
if ($LASTEXITCODE -ne 0 -or (($planUses | Where-Object { $_ -match '"record":"use"' }) | ForEach-Object { ($_ -replace '.*"byte_start":(\d+).*', '$1') } | Sort-Object -Unique).Count -ne 2) { throw 'the renamed function is not used at the two sites' }
$planStale = & $compiler apply-plan $planActual --root (Join-Path $planScratch 'src') --json 2>$null
if ($LASTEXITCODE -eq 0) { throw 'a plan over changed files was applied' }
# The file named (D547, H29): the refusal says which precondition no longer holds.
if (($planStale -join "`n") -notmatch '"code":"E-TOOL-0003","message":"`explain.e` changed since the plan was made; nothing applied","symbol":"explain.e"') { throw "the stale plan's refusal did not name the file: $planStale" }
# Uses and a rename through an alias, past a same-spelled function and local (D509,
# H17): from inside the project with the operand as `src/main.e`, every module under
# `project-src`; the plan applied to a copy checks and runs the same.
$aliasFixture = Join-Path $conformanceRoot 'tools\uses_alias'
$aliasUsesActual = Join-Path $testBuild 'conformance-tools-uses-alias.jsonl'
cmd /c "cd /d `"$aliasFixture`" && `"$compiler`" uses-file src/main.e `"$repo`" x64 windows --json --symbol deep.pick > `"$aliasUsesActual`""
if ($LASTEXITCODE -ne 0) { throw 'uses-file --json through an alias failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $aliasUsesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses_alias.expected.jsonl')).Hash) { throw 'uses-file --json through an alias differs from the conformance corpus' }
$aliasOther = cmd /c "cd /d `"$aliasFixture`" && `"$compiler`" uses-file src/main.e `"$repo`" x64 windows --json --symbol other.pick"
if ($LASTEXITCODE -ne 0 -or ($aliasOther | Where-Object { $_ -match '"record":"use"' }).Count -ne 2) { throw 'the same-spelled function of the other module does not have its own two uses' }
$aliasPlanActual = Join-Path $testBuild 'conformance-tools-plan-rename-alias.jsonl'
cmd /c "cd /d `"$aliasFixture`" && `"$compiler`" plan-rename-file src/main.e `"$repo`" x64 windows --json --symbol deep.pick --to choose > `"$aliasPlanActual`""
if ($LASTEXITCODE -ne 0) { throw 'plan-rename-file --json through an alias failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $aliasPlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_alias.x64-windows.expected.jsonl')).Hash) { throw 'plan-rename-file --json through an alias differs from the conformance corpus' }
$aliasScratch = Join-Path $testBuild 'alias-scratch'
if (Test-Path -LiteralPath $aliasScratch) { Remove-Item -LiteralPath $aliasScratch -Recurse -Force }
Copy-Item -Recurse $aliasFixture $aliasScratch
& $compiler apply-plan $aliasPlanActual --root (Join-Path $aliasScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the rename plan through an alias did not apply' }
if ((Get-Content -Raw -LiteralPath (Join-Path $aliasScratch 'src\other.e')) -ne (Get-Content -Raw -LiteralPath (Join-Path $aliasFixture 'src\other.e'))) { throw 'the rename through an alias touched the same-spelled function of the other module' }
$aliasExe = Join-Path $testBuild 'alias.exe'
$aliasBuilt = & $compiler emit-executable (Join-Path $aliasScratch 'src\main.e') $repo 'x64' 'windows' $aliasExe 2>&1
if ($LASTEXITCODE -ne 0 -or $aliasBuilt -ne 'executable written') { throw "the renamed program through an alias does not build: $aliasBuilt" }
& $aliasExe
if ($LASTEXITCODE -ne 8) { throw "the renamed program through an alias behaves differently (exit $LASTEXITCODE)" }
# A function only a constant reaches (D510, H17): its call in the initializer is a
# use, and the rename plan rewrites it; before, the plan had the declaration alone.
$comptimeFixture = Join-Path $conformanceRoot 'tools\uses_comptime'
$comptimeUsesActual = Join-Path $testBuild 'conformance-tools-uses-comptime.jsonl'
cmd /c "cd /d `"$comptimeFixture`" && `"$compiler`" uses-file src/main.e `"$repo`" x64 windows --json --symbol main.twice > `"$comptimeUsesActual`""
if ($LASTEXITCODE -ne 0) { throw 'uses-file --json of a function only a constant reaches failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $comptimeUsesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses_comptime.expected.jsonl')).Hash) { throw 'uses-file --json of a function only a constant reaches differs from the conformance corpus' }
$comptimePlanActual = Join-Path $testBuild 'conformance-tools-plan-rename-comptime.jsonl'
cmd /c "cd /d `"$comptimeFixture`" && `"$compiler`" plan-rename-file src/main.e `"$repo`" x64 windows --json --symbol main.twice --to double > `"$comptimePlanActual`""
if ($LASTEXITCODE -ne 0) { throw 'plan-rename-file --json of a function only a constant reaches failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $comptimePlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_comptime.x64-windows.expected.jsonl')).Hash) { throw 'plan-rename-file --json of a function only a constant reaches differs from the conformance corpus' }
$comptimeScratch = Join-Path $testBuild 'comptime-scratch'
if (Test-Path -LiteralPath $comptimeScratch) { Remove-Item -LiteralPath $comptimeScratch -Recurse -Force }
Copy-Item -Recurse $comptimeFixture $comptimeScratch
& $compiler apply-plan $comptimePlanActual --root (Join-Path $comptimeScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the rename plan of a function only a constant reaches did not apply' }
$comptimeExe = Join-Path $testBuild 'comptime-renamed.exe'
$comptimeBuilt = & $compiler emit-executable (Join-Path $comptimeScratch 'src\main.e') $repo 'x64' 'windows' $comptimeExe 2>&1
if ($LASTEXITCODE -ne 0 -or $comptimeBuilt -ne 'executable written') { throw "the renamed program of a function only a constant reaches does not build: $comptimeBuilt" }
& $comptimeExe
if ($LASTEXITCODE -ne 8) { throw "the renamed program of a function only a constant reaches behaves differently (exit $LASTEXITCODE)" }
# A function taken as a value and called through it (D511, H17): its two `value`
# uses, the one indirect call counted, and the rename plan rewriting both sites and
# the declaration, applied to a copy that builds and runs the same.
$callbackFixture = Join-Path $conformanceRoot 'tools\uses_callback'
$callbackUsesActual = Join-Path $testBuild 'conformance-tools-uses-callback.jsonl'
cmd /c "cd /d `"$callbackFixture`" && `"$compiler`" uses-file src/main.e `"$repo`" x64 windows --json --symbol main.twice > `"$callbackUsesActual`""
if ($LASTEXITCODE -ne 0) { throw 'uses-file --json of a callback failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $callbackUsesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses_callback.expected.jsonl')).Hash) { throw 'uses-file --json of a callback differs from the conformance corpus' }
$callbackPlanActual = Join-Path $testBuild 'conformance-tools-plan-rename-callback.jsonl'
cmd /c "cd /d `"$callbackFixture`" && `"$compiler`" plan-rename-file src/main.e `"$repo`" x64 windows --json --symbol main.twice --to double > `"$callbackPlanActual`""
if ($LASTEXITCODE -ne 0) { throw 'plan-rename-file --json of a callback failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $callbackPlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_callback.x64-windows.expected.jsonl')).Hash) { throw 'plan-rename-file --json of a callback differs from the conformance corpus' }
$callbackScratch = Join-Path $testBuild 'callback-scratch'
if (Test-Path -LiteralPath $callbackScratch) { Remove-Item -LiteralPath $callbackScratch -Recurse -Force }
Copy-Item -Recurse $callbackFixture $callbackScratch
& $compiler apply-plan $callbackPlanActual --root (Join-Path $callbackScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the rename plan of a callback did not apply' }
$callbackExe = Join-Path $testBuild 'callback.exe'
$callbackBuilt = & $compiler emit-executable (Join-Path $callbackScratch 'src\main.e') $repo 'x64' 'windows' $callbackExe 2>&1
if ($LASTEXITCODE -ne 0 -or $callbackBuilt -ne 'executable written') { throw "the renamed program of a callback does not build: $callbackBuilt" }
& $callbackExe
if ($LASTEXITCODE -ne 8) { throw "the renamed program of a callback behaves differently (exit $LASTEXITCODE)" }
# A plan into generated text (D512, D563, H17/H19): mapped call sites in the
# operand and a dependency name their owners and originals; apply-plan refuses all.
$generatedFixture = Join-Path $conformanceRoot 'tools\plan_generated'
$generatedPlanActual = Join-Path $testBuild 'conformance-tools-plan-generated.jsonl'
cmd /c "cd /d `"$generatedFixture`" && `"$compiler`" plan-rename-file src/main.e `"$repo`" x64 windows --json --symbol deep.pick --to choose > `"$generatedPlanActual`""
if ($LASTEXITCODE -ne 0) { throw 'plan-rename-file --json over generated modules failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $generatedPlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_generated.x64-windows.expected.jsonl')).Hash) { throw 'plan-rename-file --json over generated modules differs from the conformance corpus' }
$generatedScratch = Join-Path $testBuild 'generated-scratch'
if (Test-Path -LiteralPath $generatedScratch) { Remove-Item -LiteralPath $generatedScratch -Recurse -Force }
Copy-Item -Recurse $generatedFixture $generatedScratch
$generatedApply = & $compiler apply-plan $generatedPlanActual --root (Join-Path $generatedScratch 'src') 2>&1 | Out-String
if ($LASTEXITCODE -ne 2 -or $generatedApply -notmatch 'a generator owns') { throw "apply-plan did not refuse an edit a generator owns (exit $LASTEXITCODE): $generatedApply" }
if ((Get-Content -Raw -LiteralPath (Join-Path $generatedScratch 'src\deep.e')) -ne (Get-Content -Raw -LiteralPath (Join-Path $generatedFixture 'src\deep.e'))) { throw 'a refused plan applied its plain edit' }
# The uses of a type (D516, H17): every annotation and literal naming it, in both modules.
$typeUsesActual = Join-Path $testBuild 'conformance-tools-uses-type.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\plan_rename_type')`" && `"$compiler`" uses-file src/main.e `"$repo`" x64 windows --json --symbol deep.Rec > `"$typeUsesActual`""
if ($LASTEXITCODE -ne 0) { throw 'uses-file --json over a type failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $typeUsesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses_type.expected.jsonl')).Hash) { throw 'uses-file --json over a type differs from the conformance corpus' }
# A type's rename (D515, D517, H17, H29): every reference through the alias and bare,
# the declaration, and the `cmp` function spelled with the type's name; applied to
# a copy, the program builds and exits the same.
$typeFixture = Join-Path $conformanceRoot 'tools\plan_rename_type'
$typePlanActual = Join-Path $testBuild 'conformance-tools-plan-rename-type.jsonl'
cmd /c "cd /d `"$typeFixture`" && `"$compiler`" plan-rename-file src/main.e `"$repo`" x64 windows --json --symbol deep.Rec --to Pair > `"$typePlanActual`""
if ($LASTEXITCODE -ne 0) { throw 'plan-rename-file --json over a type failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $typePlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_type.x64-windows.expected.jsonl')).Hash) { throw 'plan-rename-file --json over a type differs from the conformance corpus' }
$typeScratch = Join-Path $testBuild 'type-scratch'
if (Test-Path -LiteralPath $typeScratch) { Remove-Item -LiteralPath $typeScratch -Recurse -Force }
Copy-Item -Recurse $typeFixture $typeScratch
& $compiler apply-plan $typePlanActual --root (Join-Path $typeScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the rename plan over a type did not apply' }
if ((Select-String -LiteralPath (Join-Path $typeScratch 'src\main.e'), (Join-Path $typeScratch 'src\deep.e') -Pattern 'Rec\b' -Quiet) -eq $true) { throw 'the rename plan over a type left a reference behind' }
$typeExe = Join-Path $testBuild 'type-renamed.exe'
$typeBuilt = & $compiler emit-executable (Join-Path $typeScratch 'src\main.e') $repo 'x64' 'windows' $typeExe 2>&1
if ($LASTEXITCODE -ne 0 -or $typeBuilt -ne 'executable written') { throw "the program with a renamed type does not build: $typeBuilt" }
& $typeExe
if ($LASTEXITCODE -ne 12) { throw "the program with a renamed type behaves differently (exit $LASTEXITCODE)" }
if ((Select-String -LiteralPath (Join-Path $typeScratch 'src\deep.e') -Pattern 'fn pair_cmp' -Quiet) -ne $true) { throw 'the rename plan over a type did not carry its cmp function' }
# A function found by its spelling (D518, H17): renaming `rec_cmp` on its own is refused, the type named.
$protocolRefused = Join-Path $testBuild 'conformance-tools-plan-rename-protocol-refused.jsonl'
cmd /c "cd /d `"$typeFixture`" && `"$compiler`" plan-rename-file src/main.e `"$repo`" x64 windows --json --symbol deep.rec_cmp --to compare > `"$protocolRefused`""
if ($LASTEXITCODE -ne 2) { throw "a rename of a protocol function by its own name did not exit 2 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $protocolRefused).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_protocol_refused.expected.jsonl')).Hash) { throw 'a refused rename of a protocol function differs from the conformance corpus' }
# `plan-replace-expression-file --json` (D414, H29): one expression's plan byte for byte,
# applied to a copy it checks; a span that is not one expression is refused with exit 2.
$replaceActual = Join-Path $testBuild 'conformance-tools-plan-replace.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-replace-expression-file contract.e `"$repo`" x64 windows --json --span 693:703 --with 131072usize > `"$replaceActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-replace-expression-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $replaceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_replace.x64-windows.expected.jsonl')).Hash) { throw "plan-replace-expression-file --json differs from the conformance corpus" }
$replaceScratch = Join-Path $testBuild 'plan-replace-scratch'
if (Test-Path -LiteralPath $replaceScratch) { Remove-Item -LiteralPath $replaceScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $replaceScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools/contract.e') (Join-Path $replaceScratch 'src')
& $compiler apply-plan $replaceActual --root (Join-Path $replaceScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the replace-expression plan did not apply' }
$replaceChecked = & $compiler check-file (Join-Path $replaceScratch 'src/contract.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $replaceChecked -ne 'module check ok') { throw "the program with the replaced expression does not check: $replaceChecked" }
$replaceRefused = Join-Path $testBuild 'conformance-tools-plan-replace-refused.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-replace-expression-file contract.e `"$repo`" x64 windows --json --span 693:700 --with 1usize > `"$replaceRefused`""
if ($LASTEXITCODE -ne 2) { throw "a plan over a span that is not one expression did not exit 2 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $replaceRefused).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_replace_refused.expected.jsonl')).Hash) { throw "a refused plan-replace-expression-file differs from the conformance corpus" }
# `plan-change-signature-file --json` (D415, H29): the parameters reordered, every call
# re-rendered, applied to a copy it checks; a repeated index is refused with exit 2.
$signatureActual = Join-Path $testBuild 'conformance-tools-plan-signature.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-change-signature-file signature.e `"$repo`" x64 windows --json --symbol signature.adjust --order 2,0,1 > `"$signatureActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-change-signature-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $signatureActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_signature.x64-windows.expected.jsonl')).Hash) { throw "plan-change-signature-file --json differs from the conformance corpus" }
$signatureScratch = Join-Path $testBuild 'plan-signature-scratch'
if (Test-Path -LiteralPath $signatureScratch) { Remove-Item -LiteralPath $signatureScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $signatureScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools/signature.e') (Join-Path $signatureScratch 'src')
& $compiler apply-plan $signatureActual --root (Join-Path $signatureScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the change-signature plan did not apply' }
$signatureChecked = & $compiler check-file (Join-Path $signatureScratch 'src/signature.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $signatureChecked -ne 'module check ok') { throw "the program with the changed signature does not check: $signatureChecked" }
if (-not (Select-String -LiteralPath (Join-Path $signatureScratch 'src/signature.e') -Pattern 'fn adjust\(offset: f32, reading: f32, gain: f32\)' -Quiet)) { throw 'the signature was not reordered' }
# A parameter removed (D439, H17): `0,1` drops `scale`, which the body never names,
# from the declaration and every call; `0,2` would drop `gain`, which it reads, refused.
$removeActual = Join-Path $testBuild 'conformance-tools-plan-signature-remove.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-change-signature-file signature_remove.e `"$repo`" x64 windows --json --symbol signature_remove.adjust --order 0,1 > `"$removeActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-change-signature-file with a removal failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $removeActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_signature_remove.x64-windows.expected.jsonl')).Hash) { throw "plan-change-signature-file with a removal differs from the conformance corpus" }
$removeScratch = Join-Path $testBuild 'plan-signature-remove-scratch'
if (Test-Path -LiteralPath $removeScratch) { Remove-Item -LiteralPath $removeScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $removeScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools\signature_remove.e') (Join-Path $removeScratch 'src\signature_remove.e')
& $compiler apply-plan $removeActual --root (Join-Path $removeScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the removal plan could not be applied' }
$removeChecked = & $compiler check-file (Join-Path $removeScratch 'src/signature_remove.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $removeChecked -ne 'module check ok') { throw "the program with the removed parameter does not check: $removeChecked" }
if (-not (Select-String -LiteralPath (Join-Path $removeScratch 'src/signature_remove.e') -Pattern 'fn adjust\(reading: f32, gain: f32\)' -Quiet)) { throw 'the parameter was not removed' }
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-change-signature-file signature_remove.e `"$repo`" x64 windows --json --symbol signature_remove.adjust --order 0,2 > `"$(Join-Path $testBuild 'conformance-tools-plan-signature-remove-refused.jsonl')`""
if ($LASTEXITCODE -ne 2) { throw "removing a parameter the body names did not exit 2 (got $LASTEXITCODE)" }
if (-not (Select-String -LiteralPath (Join-Path $testBuild 'conformance-tools-plan-signature-remove-refused.jsonl') -Pattern 'the body names it' -Quiet)) { throw 'the refusal did not name the parameter the body reads' }
$signatureRefused = Join-Path $testBuild 'conformance-tools-plan-signature-refused.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-change-signature-file signature.e `"$repo`" x64 windows --json --symbol signature.adjust --order 0,0 > `"$signatureRefused`""
if ($LASTEXITCODE -ne 2) { throw "a plan with a repeated index did not exit 2 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $signatureRefused).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_signature_refused.expected.jsonl')).Hash) { throw "a refused plan-change-signature-file differs from the conformance corpus" }
# An error's uses and rename (D451, H17): every value naming it, bare or qualified,
# and the declaration's name token; the renamed program checks.
$errorUsesActual = Join-Path $testBuild 'conformance-tools-uses-error.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" uses-file errors_project/src/main.e `"$repo`" x64 windows --json --symbol faults.Stalled > `"$errorUsesActual`""
if ($LASTEXITCODE -ne 0) { throw "uses-file --json over an error failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $errorUsesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses_error.expected.jsonl')).Hash) { throw "uses-file --json over an error differs from the conformance corpus" }
$errorPlanActual = Join-Path $testBuild 'conformance-tools-plan-rename-error.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-rename-file errors_project/src/main.e `"$repo`" x64 windows --json --symbol faults.Stalled --to Blocked > `"$errorPlanActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-rename-file --json over an error failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $errorPlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_error.x64-windows.expected.jsonl')).Hash) { throw "plan-rename-file --json over an error differs from the conformance corpus" }
$errorScratch = Join-Path $testBuild 'plan-rename-error-scratch'
if (Test-Path -LiteralPath $errorScratch) { Remove-Item -LiteralPath $errorScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $errorScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools\errors_project\src\*.e') (Join-Path $errorScratch 'src')
& $compiler apply-plan $errorPlanActual --root (Join-Path $errorScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the error rename plan could not be applied' }
$errorChecked = & $compiler check-file (Join-Path $errorScratch 'src/main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $errorChecked -ne 'module check ok') { throw "the program with the renamed error does not check: $errorChecked" }
if ((Select-String -Path (Join-Path $errorScratch 'src\*.e') -Pattern 'Stalled' -Quiet) -or -not (Select-String -LiteralPath (Join-Path $errorScratch 'src/faults.e') -Pattern 'error Blocked' -Quiet)) { throw 'the error was not renamed everywhere' }
# A field's uses and rename (D420, H17): every access and literal naming it, byte for
# byte; the rename applied to a copy checks, and the new name has the five uses.
$fieldUsesActual = Join-Path $testBuild 'conformance-tools-uses-field.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" uses-file contract.e `"$repo`" x64 windows --json --symbol contract.Counter.hits > `"$fieldUsesActual`""
if ($LASTEXITCODE -ne 0) { throw "uses-file --json on a field failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fieldUsesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses_field.expected.jsonl')).Hash) { throw "uses-file --json on a field differs from the conformance corpus" }
$fieldPlanActual = Join-Path $testBuild 'conformance-tools-plan-rename-field.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-rename-file contract.e `"$repo`" x64 windows --json --symbol contract.Counter.hits --to count > `"$fieldPlanActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-rename-file --json on a field failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fieldPlanActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_rename_field.x64-windows.expected.jsonl')).Hash) { throw "plan-rename-file --json on a field differs from the conformance corpus" }
$fieldScratch = Join-Path $testBuild 'plan-rename-field-scratch'
if (Test-Path -LiteralPath $fieldScratch) { Remove-Item -LiteralPath $fieldScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $fieldScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools/contract.e') (Join-Path $fieldScratch 'src')
& $compiler apply-plan $fieldPlanActual --root (Join-Path $fieldScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the field rename plan did not apply' }
$fieldChecked = & $compiler check-file (Join-Path $fieldScratch 'src/contract.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $fieldChecked -ne 'module check ok') { throw "the program with the renamed field does not check: $fieldChecked" }
$fieldUses = & $compiler uses-file (Join-Path $fieldScratch 'src/contract.e') $repo 'x64' 'windows' --json --symbol contract.Counter.count
if ($LASTEXITCODE -ne 0 -or @($fieldUses | Where-Object { $_ -match '"record":"use"' }).Count -ne 5) { throw 'the renamed field is not used at the five sites' }
# The subject's snapshot (D407, H15): the renamed program's differs from the original's.
$snapshotBefore = (& $compiler context-file (Join-Path $conformanceRoot 'tools/explain.e') $repo 'x64' 'windows' --json --symbol explain.main --budget 1 | Select-String -Pattern '"snapshot":"([0-9a-f]{16})"').Matches[0].Groups[1].Value
$snapshotAfter = (& $compiler context-file (Join-Path $planScratch 'src/explain.e') $repo 'x64' 'windows' --json --symbol explain.main --budget 1 | Select-String -Pattern '"snapshot":"([0-9a-f]{16})"').Matches[0].Groups[1].Value
if ($snapshotBefore.Length -ne 16 -or $snapshotBefore -eq $snapshotAfter) { throw "the snapshot did not change with the program ($snapshotBefore / $snapshotAfter)" }
# `plan-add-parameter-file --json` (D406, H17): the signature-change plan byte for byte;
# applied to a copy it checks with the parameter last; a function named as a value is
# refused with exit 2 and the diagnostic naming the site.
$parameterActual = Join-Path $testBuild 'conformance-tools-plan-parameter.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-add-parameter-file contract.e `"$repo`" x64 windows --json --symbol contract.total --parameter `"scale: i64`" --argument 1i64 > `"$parameterActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-add-parameter-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $parameterActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_parameter.x64-windows.expected.jsonl')).Hash) { throw "plan-add-parameter-file --json differs from the conformance corpus" }
$parameterScratch = Join-Path $testBuild 'plan-parameter-scratch'
if (Test-Path -LiteralPath $parameterScratch) { Remove-Item -LiteralPath $parameterScratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $parameterScratch 'src') | Out-Null
Copy-Item (Join-Path $conformanceRoot 'tools/contract.e') (Join-Path $parameterScratch 'src')
& $compiler apply-plan $parameterActual --root (Join-Path $parameterScratch 'src') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the add-parameter plan did not apply' }
$parameterChecked = & $compiler check-file (Join-Path $parameterScratch 'src/contract.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $parameterChecked -ne 'module check ok') { throw "the program with the added parameter does not check: $parameterChecked" }
if (-not (Select-String -LiteralPath (Join-Path $parameterScratch 'src/contract.e') -Pattern 'fn total\(c: \*const Counter, scale: i64\) -> i64' -Quiet)) { throw 'the added parameter is not last in the declaration' }
# An argument per call (D455, H29): `--arguments FILE` names the call at 28:17 and a
# default for the rest; the plan carries `2i64` at that call.
$parameterSitesActual = Join-Path $testBuild 'conformance-tools-plan-parameter-sites.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-add-parameter-file contract.e `"$repo`" x64 windows --json --symbol contract.total --parameter `"scale: i64`" --arguments parameter_sites.txt > `"$parameterSitesActual`""
if ($LASTEXITCODE -ne 0) { throw "plan-add-parameter-file --arguments failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $parameterSitesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_parameter_sites.x64-windows.expected.jsonl')).Hash) { throw "plan-add-parameter-file --arguments differs from the conformance corpus" }
$parameterRefused = Join-Path $testBuild 'conformance-tools-plan-parameter-refused.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" plan-add-parameter-file contract.e `"$repo`" x64 windows --json --symbol contract.bump --parameter `"by: i64`" --argument 1i64 > `"$parameterRefused`""
if ($LASTEXITCODE -ne 2) { throw "a plan over a function named as a value did not exit 2 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $parameterRefused).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/plan_parameter_refused.expected.jsonl')).Hash) { throw "a refused plan-add-parameter-file differs from the conformance corpus" }
# `explain-file --json` (D359): every dispatch and instantiation the checker decided, byte
# for byte (target-independent).
$explainActual = Join-Path $testBuild 'conformance-tools-explain.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" explain-file explain.e `"$repo`" x64 windows --json > `"$explainActual`""
if ($LASTEXITCODE -ne 0) { throw "explain-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $explainActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/explain.expected.jsonl')).Hash) { throw "explain-file --json differs from the conformance corpus" }
# `explain-file --json` over a program that does not check (D430, H06): the records
# before the failure -- a dispatch that found nothing, with why and the foreign
# candidate -- then the diagnostic and a result of exit 1.
# An `if` over constants folds (D500): two settled conditions as `phase` records, the
# one over a local none, and the program runs; pinned by the corpus.
$foldConstActual = Join-Path $testBuild 'conformance-tools-fold-const.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" explain-file fold_const.e `"$repo`" x64 windows --json > `"$foldConstActual`""
if ($LASTEXITCODE -ne 0) { throw "explain-file --json on fold_const.e failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $foldConstActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/fold_const.expected.jsonl')).Hash) { throw 'the constant folds differ from the conformance corpus' }
if ((Select-String -LiteralPath $foldConstActual -Pattern '"record":"phase","construct":"if"' -AllMatches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum -ne 2) { throw 'a constant condition did not fold, or one over a local did' }
$foldConstExe = Join-Path $testBuild 'fold-const.exe'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable fold_const.e `"$repo`" x64 windows `"$foldConstExe`" --release > nul"
if ($LASTEXITCODE -ne 0) { throw "the fold_const fixture did not build" }
& $foldConstExe
if ($LASTEXITCODE -ne 0) { throw "the fold_const fixture exited $LASTEXITCODE" }
# The phase and the layouts (D463, H06): a settled `if` is a `phase` record per way it
# folded, and the operand's aggregates end the stream with their layouts.
$explainFoldActual = Join-Path $testBuild 'conformance-tools-explain-fold.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" explain-file explain_fold.e `"$repo`" x64 windows --json > `"$explainFoldActual`""
if ($LASTEXITCODE -ne 0) { throw "explain-file --json on explain_fold.e failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $explainFoldActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/explain_fold.expected.jsonl')).Hash) { throw "the phase and layout records differ from the conformance corpus" }
$explainWhenActual = Join-Path $testBuild 'conformance-tools-explain-when.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" explain-file explain_when.e `"$repo`" x64 windows --json > `"$explainWhenActual`""
if ($LASTEXITCODE -ne 0) { throw "explain-file --json on explain_when.e failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $explainWhenActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/explain_when.expected.jsonl')).Hash) { throw "the when phase record differs from the conformance corpus" }
foreach ($explainNone in @(@('explain_none/src/main.e', 'explain_none'), @('explain_arm.e', 'explain_arm'))) {
    $explainNoneActual = Join-Path $testBuild "conformance-tools-$($explainNone[1]).jsonl"
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" explain-file $($explainNone[0]) `"$repo`" x64 windows --json > `"$explainNoneActual`""
    if ($LASTEXITCODE -ne 1) { throw "explain-file --json on $($explainNone[0]) exited $LASTEXITCODE, not 1" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $explainNoneActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools/$($explainNone[1]).expected.jsonl")).Hash) { throw "explain-file --json on $($explainNone[0]) differs from the conformance corpus" }
}
# `context-file --json` (D361): one function's facts with provenance, budgeted; the
# target names the host, so the golden is per host.
$contextActual = Join-Path $testBuild 'conformance-tools-context.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file explain.e `"$repo`" x64 windows --json --symbol explain.main --budget 8 > `"$contextActual`""
if ($LASTEXITCODE -ne 0) { throw "context-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $contextActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/context.x64-windows.expected.jsonl')).Hash) { throw "context-file --json differs from the conformance corpus" }
# A body's moves and folded ifs as facts (D486, H17): two subjects of one fixture.
$movesActual = Join-Path $testBuild 'conformance-tools-context-moves.jsonl'
if (Test-Path -LiteralPath $movesActual) { Remove-Item -LiteralPath $movesActual }
foreach ($movesSubject in @('context_moves.open_and_close', 'context_moves.width', 'context_moves.views', 'context_moves.ends')) {
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file context_moves.e `"$repo`" x64 windows --json --symbol $movesSubject --budget 16 >> `"$movesActual`""
    if ($LASTEXITCODE -ne 0) { throw "context-file --json --symbol $movesSubject exited $LASTEXITCODE" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $movesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/context_moves.x64-windows.expected.jsonl')).Hash) { throw 'context-file --json over moves and a folded if differs from the conformance corpus' }
# A constant and a global as subjects (D437, H08): the declaration, the value, and
# for the global that every thread shares it.
$subjectsActual = Join-Path $testBuild 'conformance-tools-subjects.jsonl'
if (Test-Path -LiteralPath $subjectsActual) { Remove-Item -LiteralPath $subjectsActual }
foreach ($subject in @('subjects.LIMIT', 'subjects.counter')) {
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file subjects.e `"$repo`" x64 windows --json --symbol $subject --budget 8 >> `"$subjectsActual`""
    if ($LASTEXITCODE -ne 0) { throw "context-file --json --symbol $subject failed" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $subjectsActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/subjects.x64-windows.expected.jsonl')).Hash) { throw "context-file --json over a constant and a global differs from the conformance corpus" }
# The caller's contract from a signature (D396, H11): four subjects of one fixture --
# an allocating, fallible, thread-starting main; a mutation; a borrow; a const read.
$contractActual = Join-Path $testBuild 'conformance-tools-contract.jsonl'
if (Test-Path -LiteralPath $contractActual) { Remove-Item -LiteralPath $contractActual }
foreach ($subject in @('contract.main', 'contract.bump', 'contract.first', 'contract.total')) {
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file contract.e `"$repo`" x64 windows --json --symbol $subject --budget 16 >> `"$contractActual`""
    if ($LASTEXITCODE -ne 0) { throw "context-file --json failed on $subject" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $contractActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/contract.x64-windows.expected.jsonl')).Hash) { throw "context-file --json contract facts differ from the conformance corpus" }
# `query-batch --json --batch FILE` (D409, H16): six queries over one check, each its own
# stream in order, two refused, the process exiting 2 for them; byte for byte per host.
$batchActual = Join-Path $testBuild 'conformance-tools-batch.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" query-batch contract.e `"$repo`" x64 windows --json --batch batch.txt > `"$batchActual`""
if ($LASTEXITCODE -ne 2) { throw "query-batch with refused lines did not exit 2 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $batchActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/batch.x64-windows.expected.jsonl')).Hash) { throw "query-batch --json differs from the conformance corpus" }
# A batch over a program that does not check (D523, H18): one stream under `query-batch`,
# the diagnostic, exit 1 -- no line of it can be answered.
$batchBroken = Join-Path $testBuild 'conformance-tools-batch-broken.jsonl'
$batchBrokenStderr = Join-Path $testBuild 'conformance-tools-batch-broken.stderr'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" query-batch query_broken.e `"$repo`" x64 windows --json --batch batch_broken.txt > `"$batchBroken`" 2> `"$batchBrokenStderr`""
if ($LASTEXITCODE -ne 1) { throw "query-batch over a program that does not check exited $LASTEXITCODE, not 1" }
if ((Get-Item -LiteralPath $batchBrokenStderr).Length -ne 0) { throw 'query-batch over a program that does not check wrote to stderr' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $batchBroken).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/batch_broken.expected.jsonl')).Hash) { throw 'query-batch over a program that does not check differs from the conformance corpus' }
# A batch retains nothing between lines (D410, D558, H16): `memory` separates
# the checked snapshot, the session baseline and the largest temporary request.
$batchMemory = & $compiler query-batch (Join-Path $conformanceRoot 'tools/contract.e') $repo 'x64' 'windows' --json --batch (Join-Path $conformanceRoot 'tools/batch_memory.txt')
if ($LASTEXITCODE -ne 0) { throw "query-batch with memory lines failed" }
$batchMemoryRecords = @($batchMemory | Where-Object { $_ -match '"arena_used"' } | ForEach-Object { ($_ | ConvertFrom-Json).data })
if ($batchMemoryRecords.Count -ne 2 -or $batchMemoryRecords[0].request_peak -ne 0 -or $batchMemoryRecords[1].request_peak -le 0 -or $batchMemoryRecords[0].session_used -ne $batchMemoryRecords[1].session_used -or $batchMemoryRecords[1].arena_used -ne $batchMemoryRecords[1].session_used -or $batchMemoryRecords[1].snapshot_used -ge $batchMemoryRecords[1].session_used -or $batchMemoryRecords[1].arena_capacity -lt $batchMemoryRecords[1].arena_used) { throw "the batch retained request memory or reported the wrong accounting ($($batchMemoryRecords | ConvertTo-Json -Compress))" }
# Ten thousand queries under one fixed snapshot (D559, H16): all complete, the
# largest request is reported, and live allocation returns to the session baseline.
$batchSoakInput = Join-Path $testBuild 'batch-soak.txt'
$batchSoakOutput = Join-Path $testBuild 'batch-soak.jsonl'
$batchSoakText = [Text.StringBuilder]::new(280000)
$null = $batchSoakText.AppendLine('memory')
for ($batchSoakAt = 0; $batchSoakAt -lt 10000; $batchSoakAt++) { $null = $batchSoakText.AppendLine('context contract.main 8') }
$null = $batchSoakText.AppendLine('memory')
[IO.File]::WriteAllText($batchSoakInput, $batchSoakText.ToString())
cmd /c "`"$compiler`" query-batch `"$(Join-Path $conformanceRoot 'tools/contract.e')`" `"$repo`" x64 windows --json --batch `"$batchSoakInput`" > `"$batchSoakOutput`""
if ($LASTEXITCODE -ne 0) { throw "the 10,000-query batch soak failed" }
$batchSoakMemory = @(Select-String -LiteralPath $batchSoakOutput -Pattern '"arena_used"' | ForEach-Object { ($_.Line | ConvertFrom-Json).data })
if ($batchSoakMemory.Count -ne 2 -or $batchSoakMemory[0].queries_completed -ne 0 -or $batchSoakMemory[1].queries_completed -ne 10000 -or $batchSoakMemory[1].request_peak -le 0 -or $batchSoakMemory[0].session_used -ne $batchSoakMemory[1].session_used -or $batchSoakMemory[1].arena_used -ne $batchSoakMemory[1].session_used) { throw "the 10,000-query batch did not reclaim to its fixed baseline ($($batchSoakMemory | ConvertTo-Json -Compress))" }
# The catalogue (D397, H11): every function of the module, subjects and facts under one
# budget; the byte budget (D400, H08) ends the page at the record that crosses it.
$catalogActual = Join-Path $testBuild 'conformance-tools-catalog.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file contract.e `"$repo`" x64 windows --json --module contract --budget 64 --bytes 3000 > `"$catalogActual`""
if ($LASTEXITCODE -ne 0) { throw "context-file --module failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $catalogActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/catalog.x64-windows.expected.jsonl')).Hash) { throw "context-file --module differs from the conformance corpus" }
# A planned-only module (D571, H11/SL11) is named and unavailable, never callable.
$unavailableCatalogActual = Join-Path $testBuild 'conformance-tools-catalog-unavailable.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file contract.e `"$repo`" x64 windows --json --module e.gpu --budget 64 > `"$unavailableCatalogActual`""
if ($LASTEXITCODE -ne 2) { throw "the unavailable module catalogue exited $LASTEXITCODE, not 2" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $unavailableCatalogActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/catalog_unavailable.expected.jsonl')).Hash) { throw "the unavailable module catalogue differs from the conformance corpus" }
# API verification (D570, D574, H11): a non-test function reached by an executable
# @test is verified and names one witness; an unused generic template stays present.
$verifiedCatalogActual = Join-Path $testBuild 'conformance-tools-catalog-verified.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" context-file test_project/src/nested/deep.e `"$repo`" x64 windows --json --module helper --budget 64 > `"$verifiedCatalogActual`""
if ($LASTEXITCODE -ne 0) { throw "the verified API catalogue failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $verifiedCatalogActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/catalog_verified.x64-windows.expected.jsonl')).Hash) { throw "the verified API catalogue differs from the conformance corpus" }
# `--unchecked` as context (D555, H27): every subject kind says the image's checks
# are off and carries exactly one whole-image boundary. The standalone flag works
# on either side of a paging pair; the catalogue repeats the boundary per subject.
$uncheckedCases = @(
    @('contract.e', 'contract.main', $true),
    @('contract.e', 'contract.Counter', $false),
    @('subjects.e', 'subjects.LIMIT', $true),
    @('subjects.e', 'subjects.counter', $false)
)
foreach ($uncheckedCase in $uncheckedCases) {
    $uncheckedTail = if ($uncheckedCase[2]) { @('--unchecked', '--budget', '64') } else { @('--budget', '64', '--unchecked') }
    $uncheckedContext = & $compiler context-file (Join-Path $conformanceRoot "tools/$($uncheckedCase[0])") $repo 'x64' 'windows' --json --symbol $uncheckedCase[1] @uncheckedTail
    if ($LASTEXITCODE -ne 0) { throw "context-file --unchecked failed on $($uncheckedCase[1])" }
    if (@($uncheckedContext | Select-String -SimpleMatch '"checks":"off"').Count -ne 1) { throw "context-file --unchecked did not mark $($uncheckedCase[1]) checks off" }
    if (@($uncheckedContext | Select-String -SimpleMatch '"value":"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary"').Count -ne 1) { throw "context-file --unchecked did not emit exactly one whole-image boundary for $($uncheckedCase[1])" }
}
$uncheckedCatalog = & $compiler context-file (Join-Path $conformanceRoot 'tools/contract.e') $repo 'x64' 'windows' --json --module contract --unchecked --budget 64
if ($LASTEXITCODE -ne 0) { throw 'context-file --module --unchecked failed' }
$uncheckedCatalogSubjects = @($uncheckedCatalog | Select-String -SimpleMatch '"record":"subject"').Count
if ($uncheckedCatalogSubjects -ne 4) { throw "context-file --module --unchecked returned $uncheckedCatalogSubjects subjects, not 4" }
if (@($uncheckedCatalog | Select-String -SimpleMatch '"checks":"off"').Count -ne $uncheckedCatalogSubjects) { throw 'context-file --module --unchecked did not mark every subject checks off' }
if (@($uncheckedCatalog | Select-String -SimpleMatch '"value":"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary"').Count -ne $uncheckedCatalogSubjects) { throw 'context-file --module --unchecked did not emit one whole-image boundary per subject' }
# The batch path carries one intended image policy across every context/catalog
# line without giving up its one load and check (D556, H27).
$uncheckedBatch = & $compiler query-batch (Join-Path $conformanceRoot 'tools/contract.e') $repo 'x64' 'windows' --json --batch (Join-Path $conformanceRoot 'tools/batch_unchecked.txt') --unchecked
if ($LASTEXITCODE -ne 0) { throw 'query-batch --unchecked failed' }
$uncheckedBatchSubjects = @($uncheckedBatch | Select-String -SimpleMatch '"record":"subject"').Count
if ($uncheckedBatchSubjects -ne 6) { throw "query-batch --unchecked returned $uncheckedBatchSubjects subjects, not 6" }
if (@($uncheckedBatch | Select-String -SimpleMatch '"checks":"off"').Count -ne $uncheckedBatchSubjects) { throw 'query-batch --unchecked did not mark every subject checks off' }
if (@($uncheckedBatch | Select-String -SimpleMatch '"value":"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary"').Count -ne $uncheckedBatchSubjects) { throw 'query-batch --unchecked did not emit one whole-image boundary per subject' }
# `--deadline MS` (D399, H16): a deadline already passed cancels the build at the first
# checkpoint -- one diagnostic, a result of exit code 3, no image written.
$deadlineActual = Join-Path $testBuild 'conformance-tools-deadline.jsonl'
$deadlineImage = Join-Path $testBuild 'deadline-never.exe'
if (Test-Path -LiteralPath $deadlineImage) { Remove-Item -LiteralPath $deadlineImage }
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable contract.e `"$repo`" x64 windows `"$deadlineImage`" --json --deadline 0 > `"$deadlineActual`""
if ($LASTEXITCODE -ne 3) { throw "a build past its deadline did not exit 3 (got $LASTEXITCODE)" }
if (Test-Path -LiteralPath $deadlineImage) { throw "a build past its deadline wrote an image" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $deadlineActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/deadline.expected.jsonl')).Hash) { throw "the cancelled build's stream differs from the conformance corpus" }
# Metamorphic tests (D438, H10): a fixture without its comments builds the same image,
# and with its declarations reversed behaves the same.
$metamorphicOut = Join-Path $testBuild 'metamorphic'
& python (Join-Path $repo 'benchmarks/metamorphic/metamorphic.py') $compiler $repo 'x64' 'windows' $metamorphicOut (Join-Path $PSScriptRoot 'fixtures\link\algo_sort\src\main.e') (Join-Path $PSScriptRoot 'fixtures\link\algo_bitset\src\main.e') (Join-Path $PSScriptRoot 'fixtures\link\control\src\main.e') (Join-Path $PSScriptRoot 'fixtures\link\atomic_ops\src\main.e')
if ($LASTEXITCODE -ne 0) { throw 'a metamorphic transformation changed what a fixture builds or does' }
# The bootstrap as the codegen's oracle (D456, H10): seventeen neper0 programs built
# by the C bootstrap and by this compiler must exit and print alike.
& python (Join-Path $repo 'benchmarks/differential/bootstrap.py') $compiler $neper $repo 'x64' 'windows' (Join-Path $testBuild 'bootstrap-oracle') (Join-Path $repo 'tests\neper0\arena-alloc.e') (Join-Path $repo 'tests\neper0\array.e') (Join-Path $repo 'tests\neper0\struct.e') (Join-Path $repo 'tests\neper0\slice.e') (Join-Path $repo 'tests\neper0\defer.e') (Join-Path $repo 'tests\neper0\range.e') (Join-Path $repo 'tests\neper0\unsigned-ops.e') (Join-Path $repo 'tests\neper0\multiple-return.e') (Join-Path $repo 'tests\neper0\constant-folding.e') (Join-Path $repo 'tests\neper0\enum-union-switch.e') (Join-Path $repo 'tests\neper0\generic-function.e') (Join-Path $repo 'tests\neper0\generic-aggregate.e') (Join-Path $repo 'tests\neper0\protocol-iteration.e') (Join-Path $repo 'tests\neper0\slice-iterate.e') (Join-Path $repo 'tests\neper0\slice-mutate.e') (Join-Path $repo 'tests\neper0\os-intrinsics.e') (Join-Path $repo 'tests\neper0\aggregate-abi.e')
if ($LASTEXITCODE -ne 0) { throw 'a program built by the bootstrap and by the self-hosted compiler behaves differently' }
# Differential execution against an independent oracle (D449, H10): the library's
# SHA-256, SHA3-256 and base64 over random inputs against Python's hashlib and base64.
& python (Join-Path $repo 'benchmarks/differential/differential.py') $compiler $repo 'x64' 'windows' (Join-Path $testBuild 'differential') --cases 60 --seed 7
if ($LASTEXITCODE -ne 0) { throw 'the library disagrees with the independent oracle' }
# `--instances N` (D426, H06): a budget over the specializations a build makes -- three
# instances past a budget of two is E-COMPTIME-0001 and exit 1; a budget of three builds.
$instancesActual = Join-Path $testBuild 'conformance-tools-instances.jsonl'
$instancesImage = Join-Path $testBuild 'instances.exe'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable instances.e `"$repo`" x64 windows `"$instancesImage`" --json --instances 2 > `"$instancesActual`""
if ($LASTEXITCODE -ne 1) { throw "a build past its instance budget did not exit 1 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $instancesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/instances.expected.jsonl')).Hash) { throw "the refused build's stream differs from the conformance corpus" }
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable instances.e `"$repo`" x64 windows `"$instancesImage`" --release --instances 3 > nul"
if ($LASTEXITCODE -ne 0) { throw "a build within its instance budget failed ($LASTEXITCODE)" }
& $instancesImage
if ($LASTEXITCODE -ne 0) { throw "the instances fixture exited $LASTEXITCODE" }
# `--comptime-steps N` (D474, H24): a budget over the interpreter's steps in the whole
# build -- 1210 for a constant summed over a hundred iterations -- refused as
# E-COMPTIME-0002 under a budget of ten, built under one of a hundred thousand.
$stepsActual = Join-Path $testBuild 'conformance-tools-comptime-steps.jsonl'
$stepsImage = Join-Path $testBuild 'comptime-steps.exe'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable comptime_steps.e `"$repo`" x64 windows `"$stepsImage`" --json --comptime-steps 10 > `"$stepsActual`""
if ($LASTEXITCODE -ne 1) { throw "a build past its comptime step budget did not exit 1 (got $LASTEXITCODE)" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stepsActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/comptime_steps.expected.jsonl')).Hash) { throw "the refused build's stream differs from the conformance corpus" }
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable comptime_steps.e `"$repo`" x64 windows `"$stepsImage`" --release --comptime-steps 100000 > nul"
if ($LASTEXITCODE -ne 0) { throw "a build within its comptime step budget failed ($LASTEXITCODE)" }
& $stepsImage
if ($LASTEXITCODE -ne 0) { throw "the comptime steps fixture exited $LASTEXITCODE" }
# A deadline inside an evaluation (D496, H16): a constant of seconds under a deadline
# of fifty milliseconds is cancelled in well under a second, exit 3, the declarations
# named as the phase.
$longActual = Join-Path $testBuild 'conformance-tools-comptime-long.jsonl'
$longStarted = Get-Date
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" emit-executable comptime_long.e `"$repo`" x64 windows `"$(Join-Path $testBuild 'comptime-long.exe')`" --json --deadline 50 > `"$longActual`""
if ($LASTEXITCODE -ne 3) { throw "a build whose deadline passed inside an evaluation did not exit 3 (got $LASTEXITCODE)" }
if (((Get-Date) - $longStarted).TotalMilliseconds -gt 2000) { throw 'a deadline inside an evaluation was not honoured until the evaluation ended' }
if ((Select-String -LiteralPath $longActual -Pattern '"cancelled_after":"check declarations"' -Quiet) -ne $true) { throw 'the cancellation inside an evaluation does not name the declarations' }
# A deadline inside a phase (D422, H16): the compiler's own build under a deadline
# it cannot meet is cancelled by a worker between two modules -- exit 3, no image.
$deadlineInside = Join-Path $testBuild 'deadline-inside.exe'
if (Test-Path -LiteralPath $deadlineInside) { Remove-Item -LiteralPath $deadlineInside }
$deadlineOutput = & $compiler emit-executable (Join-Path $repo 'src/main.e') $repo 'x64' 'windows' $deadlineInside --release --deadline 150 --json 2>$null
if ($LASTEXITCODE -ne 3) { throw "the compiler's build under a 150 ms deadline did not exit 3 (got $LASTEXITCODE)" }
if (Test-Path -LiteralPath $deadlineInside) { throw 'a build cancelled inside a phase wrote an image' }
if (($deadlineOutput -join "`n") -notmatch '"code":"E-CLI-0001"') { throw 'a build cancelled inside a phase did not say so' }
# `test-impact-file --json --changed m1,m2` (D423, H10): the tests an edit reaches, over
# the test project -- every test when `helper` changes, the nested one alone when
# `nested.deep` does; a module the program has not is refused with exit 2.
foreach ($impactCase in @(@('helper', 'impact'), @('nested.deep', 'impact_local'))) {
    $impactActual = Join-Path $testBuild "conformance-tools-$($impactCase[1]).jsonl"
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" test-impact-file test_project/src/nested/deep.e `"$repo`" x64 windows --json --changed $($impactCase[0]) > `"$impactActual`""
    if ($LASTEXITCODE -ne 0) { throw "test-impact-file --json failed for $($impactCase[0])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $impactActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools/$($impactCase[1]).expected.jsonl")).Hash) { throw "test-impact-file --json differs from the conformance corpus for $($impactCase[0])" }
}
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" test-impact-file test_project/src/nested/deep.e `"$repo`" x64 windows --json --changed nowhere > `"$(Join-Path $testBuild 'conformance-tools-impact-refused.jsonl')`""
if ($LASTEXITCODE -ne 2) { throw "test-impact-file over an unknown module did not exit 2 (got $LASTEXITCODE)" }
# A query over a program that does not check (D520, H08, H18): the stream, exit 1.
foreach ($brokenCase in @(@('context-file', '--symbol', 'query_broken.helper', 'context_broken'), @('uses-file', '--symbol', 'query_broken.helper', 'uses_broken'), @('plan-rename-file', '--symbol', 'query_broken.helper', 'plan_rename_broken'))) {
    $brokenActual = Join-Path $testBuild "conformance-tools-$($brokenCase[3]).jsonl"
    $brokenStderr = Join-Path $testBuild "conformance-tools-$($brokenCase[3]).stderr"
    $brokenTail = ''
    if ($brokenCase[0] -eq 'plan-rename-file') { $brokenTail = ' --to aide' }
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" $($brokenCase[0]) query_broken.e `"$repo`" x64 windows --json $($brokenCase[1]) $($brokenCase[2])$brokenTail > `"$brokenActual`" 2> `"$brokenStderr`""
    if ($LASTEXITCODE -ne 1) { throw "$($brokenCase[0]) --json over a program that does not check exited $LASTEXITCODE, not 1" }
    if ((Get-Item -LiteralPath $brokenStderr).Length -ne 0) { throw "$($brokenCase[0]) --json over a program that does not check wrote to stderr" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $brokenActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools/$($brokenCase[3]).expected.jsonl")).Hash) { throw "$($brokenCase[0]) --json over a program that does not check differs from the conformance corpus" }
}
# A dependency that does not parse (D521, H18): the stream under the query's header, exit 1;
# and `index-file` over the file itself begins with its header.
foreach ($syntaxCase in @(@('context-file', 'context_syntax'), @('uses-file', 'uses_syntax'), @('explain-file', 'explain_syntax'))) {
    $syntaxActual = Join-Path $testBuild "conformance-tools-$($syntaxCase[1]).jsonl"
    $syntaxStderr = Join-Path $testBuild "conformance-tools-$($syntaxCase[1]).stderr"
    $syntaxTail = ' --symbol main.main'
    if ($syntaxCase[0] -eq 'explain-file') { $syntaxTail = '' }
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\query_syntax')`" && `"$compiler`" $($syntaxCase[0]) src/main.e `"$repo`" x64 windows --json$syntaxTail > `"$syntaxActual`" 2> `"$syntaxStderr`""
    if ($LASTEXITCODE -ne 1) { throw "$($syntaxCase[0]) --json over a dependency that does not parse exited $LASTEXITCODE, not 1" }
    if ((Get-Item -LiteralPath $syntaxStderr).Length -ne 0) { throw "$($syntaxCase[0]) --json over a dependency that does not parse wrote to stderr" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $syntaxActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools/$($syntaxCase[1]).expected.jsonl")).Hash) { throw "$($syntaxCase[0]) --json over a dependency that does not parse differs from the conformance corpus" }
}
# `dis-file --json` and `build-manifest-file --json` over the same (D522): the envelope.
foreach ($syntaxCommand in @(@('dis-file', 'dis_syntax'), @('build-manifest-file', 'manifest_syntax'))) {
    $syntaxCommandActual = Join-Path $testBuild "conformance-tools-$($syntaxCommand[1]).jsonl"
    $syntaxCommandStderr = Join-Path $testBuild "conformance-tools-$($syntaxCommand[1]).stderr"
    cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\query_syntax')`" && `"$compiler`" $($syntaxCommand[0]) src/main.e `"$repo`" x64 windows --json > `"$syntaxCommandActual`" 2> `"$syntaxCommandStderr`""
    if ($LASTEXITCODE -ne 1) { throw "$($syntaxCommand[0]) --json over a dependency that does not parse exited $LASTEXITCODE, not 1" }
    if ((Get-Item -LiteralPath $syntaxCommandStderr).Length -ne 0) { throw "$($syntaxCommand[0]) --json over a dependency that does not parse wrote to stderr" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $syntaxCommandActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools/$($syntaxCommand[1]).expected.jsonl")).Hash) { throw "$($syntaxCommand[0]) --json over a dependency that does not parse differs from the conformance corpus" }
}
$indexSyntaxActual = Join-Path $testBuild 'conformance-tools-index-syntax.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools\query_syntax')`" && `"$compiler`" index-file src/dep.e `"$repo`" x64 windows --json > `"$indexSyntaxActual`""
if ($LASTEXITCODE -ne 1) { throw "index-file --json over a file that does not parse exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $indexSyntaxActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/index_syntax.expected.jsonl')).Hash) { throw 'index-file --json over a file that does not parse differs from the conformance corpus' }
# `uses-file --json` (D362): every resolved use of one function, target-independent.
$usesActual = Join-Path $testBuild 'conformance-tools-uses.jsonl'
cmd /c "cd /d `"$(Join-Path $conformanceRoot 'tools')`" && `"$compiler`" uses-file explain.e `"$repo`" x64 windows --json --symbol explain.same > `"$usesActual`""
if ($LASTEXITCODE -ne 0) { throw "uses-file --json failed" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $usesActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/uses.expected.jsonl')).Hash) { throw "uses-file --json differs from the conformance corpus" }
# `dis --json` (D233): one record of hex bytes per emitted function, byte for byte per host.
$disActual = Join-Path $testBuild 'conformance-tools-dis.jsonl'
cmd /c "`"$compiler`" dis-file `"$(Join-Path $conformanceRoot 'tools/dis.e')`" `"$repo`" x64 windows --json > `"$disActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $disActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/dis.x64-windows.expected.jsonl')).Hash) { throw "dis --json differs from the conformance corpus" }
# `dis-file --json --release` (D542, D565, H19): inlined runs retain a nested copy's chain.
$disInlinedActual = Join-Path $testBuild 'conformance-tools-dis-inlined.jsonl'
cmd /c "`"$compiler`" dis-file `"$(Join-Path $conformanceRoot 'tools/dis_inlined.e')`" `"$repo`" x64 windows --json --release > `"$disInlinedActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $disInlinedActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/dis_inlined.x64-windows.expected.jsonl')).Hash) { throw "dis --json --release differs from the conformance corpus" }
# `fmt --json` (D234): the operand's canonical layout, byte for byte (target-independent);
# the fixture is already canonical, so this also pins idempotence.
$fmtActual = Join-Path $testBuild 'conformance-tools-fmt.jsonl'
cmd /c "`"$compiler`" fmt-file `"$(Join-Path $conformanceRoot 'tools/fmt.e')`" --json > `"$fmtActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fmtActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/fmt.expected.jsonl')).Hash) { throw "fmt --json differs from the conformance corpus" }
# The format corpus (D255): each `format/<name>.e` is a non-canonical source and
# `format/<name>.expected.e` what `fmt` makes of it, byte for byte; the canonical side
# passes `--check`, which pins idempotence.
foreach ($formatCase in @('layout', 'types')) {
    $formatActual = Join-Path $testBuild "conformance-format-$formatCase.e"
    cmd /c "`"$compiler`" fmt-file `"$(Join-Path $conformanceRoot "format/$formatCase.e")`" > `"$formatActual`""
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $formatActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "format/$formatCase.expected.e")).Hash) { throw "fmt on format/$formatCase.e differs from the conformance corpus" }
    cmd /c "`"$compiler`" fmt-file `"$(Join-Path $conformanceRoot "format/$formatCase.expected.e")`" --check --json > nul"
    if ($LASTEXITCODE -ne 0) { throw "the canonical side of format/$formatCase is not canonical" }
}
# `fmt --json` on what it refuses (D257): an invalid token under its lexical code and a
# comment splitting an attribute from its declaration under E-FORMAT-9999, exit 1.
$fmtRejectActual = Join-Path $testBuild 'conformance-tools-fmt-reject.jsonl'
cmd /c "`"$compiler`" fmt-file `"$(Join-Path $conformanceRoot 'tools/fmt_reject.e')`" --json > `"$fmtRejectActual`""
if ($LASTEXITCODE -ne 1) { throw "fmt --json on a refused source exited $LASTEXITCODE, not 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fmtRejectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/fmt_reject.expected.jsonl')).Hash) { throw "fmt --json on a refused source differs from the conformance corpus" }
# `fmt --check --json` (D244): a canonical source passes, a non-canonical one reports E-FORMAT-0001.
cmd /c "`"$compiler`" fmt-file `"$(Join-Path $conformanceRoot 'tools/fmt.e')`" --check --json > `"$(Join-Path $testBuild 'fmt-check-ok.jsonl')`""
if ($LASTEXITCODE -ne 0) { throw "fmt --check on a canonical source did not exit 0" }
$fmtCheckActual = Join-Path $testBuild 'conformance-tools-fmt-check.jsonl'
cmd /c "`"$compiler`" fmt-file `"$(Join-Path $conformanceRoot 'tools/fmt_check.e')`" --check --json > `"$fmtCheckActual`""
if ($LASTEXITCODE -ne 1) { throw "fmt --check on a non-canonical source exited $LASTEXITCODE, expected 1" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fmtCheckActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/fmt_check.expected.jsonl')).Hash) { throw "fmt --check --json differs from the conformance corpus" }
# `build-manifest --json` (D236): the canonical manifest with each input's SHA-256, byte for byte.
$manifestActual = Join-Path $testBuild 'conformance-tools-manifest.jsonl'
cmd /c "`"$compiler`" build-manifest-file `"$(Join-Path $conformanceRoot 'tools/manifest.e')`" `"$repo`" x64 windows --json > `"$manifestActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $manifestActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/manifest.x64-windows.expected.jsonl')).Hash) { throw "build-manifest --json differs from the conformance corpus" }
# The operand's source map as an input (D467, H19): listed with its hash and `kind`.
$manifestMapActual = Join-Path $testBuild 'conformance-tools-manifest-map.jsonl'
cmd /c "`"$compiler`" build-manifest-file `"$(Join-Path $conformanceRoot 'tools/generated_map.e')`" `"$repo`" x64 windows --json > `"$manifestMapActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $manifestMapActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/manifest_map.x64-windows.expected.jsonl')).Hash) { throw "the manifest of an operand with a source map differs from the conformance corpus" }
# On a project (D265): inputs under `project-src`, and the one module beyond the root as a
# dependency with its interface hash -- the source with function bodies left out -- and its
# body hash.
$manifestProjectActual = Join-Path $testBuild 'conformance-tools-manifest-project.jsonl'
cmd /c "`"$compiler`" build-manifest-file `"$(Join-Path $conformanceRoot 'tools/manifest_project/src/main.e')`" `"$repo`" x64 windows --json > `"$manifestProjectActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $manifestProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/manifest_project.x64-windows.expected.jsonl')).Hash) { throw "build-manifest --json on a project differs from the conformance corpus" }
# The `unsafe` inventory (D371, H27): every declared and trusted escape hatch, by kind.
$manifestUnsafeActual = Join-Path $testBuild 'conformance-tools-manifest-unsafe.jsonl'
cmd /c "`"$compiler`" build-manifest-file `"$(Join-Path $conformanceRoot 'tools/manifest_unsafe/src/main.e')`" `"$repo`" x64 windows --json > `"$manifestUnsafeActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $manifestUnsafeActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/manifest_unsafe.x64-windows.expected.jsonl')).Hash) { throw "the unsafe inventory differs from the conformance corpus" }
# `test --json` (D240): @test discovery, a per-process run of each, section 7's stream; the
# fixture has a passing and a failing test so the command exits 1. Target-independent golden.
$testActual = Join-Path $testBuild 'conformance-tools-test.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test.e')`" `"$repo`" x64 windows `"$($testBuild.Replace('\', '/'))`" --json > `"$testActual`""
if ($LASTEXITCODE -ne 1) { throw "test --json exited $LASTEXITCODE, expected 1" }
# duration_ms is real wall time (D241): normalise it out before the byte-exact compare.
# The crashed test's stderr spells the runner by WORKDIR (D253): normalise that too.
[IO.File]::WriteAllText($testActual, ([IO.File]::ReadAllText($testActual) -replace '"duration_ms":\d+', '"duration_ms":0' -replace [regex]::Escape($testBuild.Replace('\', '/') + '/nptest-runner.e'), 'nptest-runner.e'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test.expected.jsonl')).Hash) { throw "test --json differs from the conformance corpus" }
# `test --json --only n1,n2` (D424, H10): the named tests alone, the rest not run.
$testOnlyActual = Join-Path $testBuild 'conformance-tools-test-only.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test.e')`" `"$repo`" x64 windows `"$($testBuild.Replace('\', '/'))`" --json --only arithmetic_holds,reports_a_failure > `"$testOnlyActual`""
if ($LASTEXITCODE -ne 1) { throw "test --json --only exited $LASTEXITCODE, expected 1" }
[IO.File]::WriteAllText($testOnlyActual, ([IO.File]::ReadAllText($testOnlyActual) -replace '"duration_ms":\d+', '"duration_ms":0'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testOnlyActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_only.expected.jsonl')).Hash) { throw "test --json --only differs from the conformance corpus" }
# `test --json` on a `@test` that is not a test (D256): E-TEST-9999 at the declaration,
# exit 2, nothing compiled or run.
$rejectActual = Join-Path $testBuild 'conformance-tools-test-reject.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test_reject.e')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$rejectActual`""
if ($LASTEXITCODE -ne 2) { throw "test --json on a non-test exited $LASTEXITCODE, not 2" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $rejectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_reject.expected.jsonl')).Hash) { throw "test --json on a non-test differs from the conformance corpus" }
# `test-project --json` (D263): every module under a project's src in byte order, each
# run through `test-file --json --path REL` in its own process with its runner built as
# part of the project, the records merged; a module with no tests is counted and skipped.
$testProjectActual = Join-Path $testBuild 'conformance-tools-test-project.jsonl'
cmd /c "`"$compiler`" test-project `"$(Join-Path $conformanceRoot 'tools/test_project')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$testProjectActual`""
if ($LASTEXITCODE -ne 1) { throw "test-project --json exited $LASTEXITCODE, not 1" }
[IO.File]::WriteAllText($testProjectActual, ([IO.File]::ReadAllText($testProjectActual) -replace '"duration_ms":\d+', '"duration_ms":0'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testProjectActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_project.expected.jsonl')).Hash) { throw "test-project --json differs from the conformance corpus" }
# `test --json` on a test that does not compile (D264): the runner's source map brings
# the compiler's diagnostic back at the operand's own span, the generated one related,
# before the E-CLI-9999 that says nothing ran; exit 2.
$compileErrorActual = Join-Path $testBuild 'conformance-tools-test-compile-error.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test_compile_error.e')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$compileErrorActual`""
if ($LASTEXITCODE -ne 2) { throw "test --json on a test that does not compile exited $LASTEXITCODE, not 2" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $compileErrorActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_compile_error.expected.jsonl')).Hash) { throw "test --json on a test that does not compile differs from the conformance corpus" }
& python (Join-Path $repo 'scripts/validate_stream.py') (Join-Path $testBuild 'nptest-runner.e.map.json') | Out-Null
if ($LASTEXITCODE -ne 0) { throw "the runner's source map does not validate against the v1 schema" }
# The language card is the render of the grammar (D374, H28): a card whose hash is not
# the render of grammar.ebnf's revision is drift, and the suite refuses it.
& python (Join-Path $repo 'scripts/render_card.py') --check | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docs/llm-neper-card.md is not the render of docs/grammar.ebnf; run python scripts/render_card.py' }
# The card's examples are checked by the compiler (D404, H11): every ```neper fence
# checks clean, every ```neper reject E-CODE fence is refused with that code.
& python (Join-Path $repo 'scripts/card_examples.py') $compiler $repo x64 windows (Join-Path $testBuild 'card-examples') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'an example of docs/llm-neper-card.src.md does not do what its fence says' }
# A stale source map beside the operand is E-TOOL-0001 and no artifact (D264).
$staleActual = Join-Path $testBuild 'conformance-tools-stale-map.jsonl'
Remove-Item -ErrorAction SilentlyContinue -LiteralPath (Join-Path $testBuild 'conformance-tools-stale-map.out')
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot 'tools/stale_map.e')`" `"$repo`" x64 windows conformance-tools-stale-map.out --json > `"$staleActual`""
if ($LASTEXITCODE -ne 1) { throw "a stale source map exited $LASTEXITCODE, not 1" }
if (Test-Path -LiteralPath (Join-Path $testBuild 'conformance-tools-stale-map.out')) { throw 'a stale source map still wrote an artifact' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $staleActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/stale_map.expected.jsonl')).Hash) { throw "a stale source map is not refused as the conformance corpus says" }
# A stale map beside an operand that does not compile (D300): the analysis still runs,
# its diagnostic follows the E-TOOL-0001 at its own unmapped span; exit 1, no artifact.
$staleErrorActual = Join-Path $testBuild 'conformance-tools-stale-map-error.jsonl'
Remove-Item -ErrorAction SilentlyContinue -LiteralPath (Join-Path $testBuild 'conformance-tools-stale-map-error.out')
cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot 'tools/stale_map_error.e')`" `"$repo`" x64 windows conformance-tools-stale-map-error.out --json > `"$staleErrorActual`""
if ($LASTEXITCODE -ne 1) { throw "a stale source map over a rejected operand exited $LASTEXITCODE, not 1" }
if (Test-Path -LiteralPath (Join-Path $testBuild 'conformance-tools-stale-map-error.out')) { throw 'a stale source map over a rejected operand wrote an artifact' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $staleErrorActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/stale_map_error.expected.jsonl')).Hash) { throw 'analysis under a stale source map differs from the conformance corpus' }
# A version 2 map (D373, H19): the generator's input is hashed, a regeneration-owned
# mapping says so in the related location, and a changed input is E-TOOL-0001.
# Combined inputs (D464, H19): every `generator.inputs` entry is checked and the first changed
# one is named; one input's line became two declarations, each mapped to the one original span.
foreach ($mapCase in @(@('generated_map', 'a regeneration-owned mapping'), @('stale_generator', 'a changed generator input'), @('hand_edited', 'a hand-edited generated file'), @('combined_inputs', 'a generator with combined inputs'), @('combined_stale', 'a changed combined input'), @('nested_map', 'a nested source map'), @('nested_stale', 'a stale nested source map'), @('nested_deep', 'a chain of four nested maps'))) {
    $mapActual = Join-Path $testBuild "conformance-tools-$($mapCase[0]).jsonl"
    Remove-Item -ErrorAction SilentlyContinue -LiteralPath (Join-Path $testBuild "conformance-tools-$($mapCase[0]).out")
    cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot "tools/$($mapCase[0]).e")`" `"$repo`" x64 windows conformance-tools-$($mapCase[0]).out --json > `"$mapActual`""
    if ($LASTEXITCODE -ne 1) { throw "$($mapCase[1]) exited $LASTEXITCODE, not 1" }
    if (Test-Path -LiteralPath (Join-Path $testBuild "conformance-tools-$($mapCase[0]).out")) { throw "$($mapCase[1]) still wrote an artifact" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $mapActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools/$($mapCase[0]).expected.jsonl")).Hash) { throw "$($mapCase[1]) differs from the conformance corpus" }
}
# An operand that defines `main` and carries tests (D281): the runner renames the
# operand's `main`, both tests run, and a compile error after the rename still maps back.
$testMainActual = Join-Path $testBuild 'conformance-tools-test-main.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test_main.e')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$testMainActual`""
if ($LASTEXITCODE -ne 0) { throw "test --json on an operand with main exited $LASTEXITCODE" }
[IO.File]::WriteAllText($testMainActual, ([IO.File]::ReadAllText($testMainActual) -replace '"duration_ms":\d+', '"duration_ms":0'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testMainActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_main.expected.jsonl')).Hash) { throw "test --json on an operand with main differs from the conformance corpus" }
$testMainErrorActual = Join-Path $testBuild 'conformance-tools-test-main-error.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test_main_error.e')`" `"$repo`" x64 windows `"$testBuild`" --json > `"$testMainErrorActual`""
if ($LASTEXITCODE -ne 2) { throw "a compile error past the renamed main exited $LASTEXITCODE, not 2" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $testMainErrorActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_main_error.expected.jsonl')).Hash) { throw "a compile error past the renamed main differs from the conformance corpus" }
# `test --json` with a deadline (D246): a test that never returns is ended by the runner's
# own watchdog thread and reported `timeout`. 400ms keeps the suite quick.
$timeoutActual = Join-Path $testBuild 'conformance-tools-test-timeout.jsonl'
cmd /c "`"$compiler`" test-file `"$(Join-Path $conformanceRoot 'tools/test_timeout.e')`" `"$repo`" x64 windows `"$testBuild`" 400 --json > `"$timeoutActual`""
if ($LASTEXITCODE -ne 1) { throw "test --json deadline exited $LASTEXITCODE, expected 1" }
[IO.File]::WriteAllText($timeoutActual, ([IO.File]::ReadAllText($timeoutActual) -replace '"duration_ms":\d+', '"duration_ms":0'), (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $timeoutActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/test_timeout.expected.jsonl')).Hash) { throw "test --json deadline differs from the conformance corpus" }
# An operand that cannot be read answers with section 1's envelope on every `--json`
# command (D260): the header, one location-free E-CLI-9999, the result exiting 2 with the
# command's zero counts. The expected stream is built here from that shape.
$noOperand = Join-Path $testBuild 'no-such-operand.e'
$unreadableActual = Join-Path $testBuild 'conformance-unreadable.jsonl'
foreach ($case in @(
    @('tokens', '{"tokens":0,"diagnostics":1}', "tokens --json `"$noOperand`""),
    @('parse', '{"tokens":0,"diagnostics":1}', "parse --json `"$noOperand`""),
    @('fmt', '{"diagnostics":1}', "fmt-file `"$noOperand`" --json"),
    @('fmt', '{"diagnostics":1}', "fmt-file `"$noOperand`" --check --json"),
    @('dis', '{"functions":0}', "dis-file `"$noOperand`" `"$repo`" x64 windows --json"),
    @('test', '{"tests":0}', "test-file `"$noOperand`" `"$repo`" x64 windows `"$testBuild`" --json"))) {
    cmd /c "`"$compiler`" $($case[2]) > `"$unreadableActual`""
    if ($LASTEXITCODE -ne 2) { throw "$($case[0]) --json on an unreadable operand exited $LASTEXITCODE, not 2" }
    $unreadableExpected = "{`"schema`":`"neper-stream`",`"version`":1,`"record`":`"header`",`"command`":`"$($case[0])`",`"tool_version`":`"0.1.0`",`"language_version`":`"0.1`",`"grammar_revision`":3}`n{`"record`":`"diagnostic`",`"severity`":`"error`",`"code`":`"E-CLI-9999`",`"message`":`"the operand cannot be read`",`"span`":null,`"parent`":null,`"related`":[],`"fixes`":[]}`n{`"record`":`"result`",`"ok`":false,`"exit_code`":2,`"data`":$($case[1])}`n"
    if ([IO.File]::ReadAllText($unreadableActual) -ne $unreadableExpected) { throw "$($case[0]) --json on an unreadable operand is not section 1's envelope" }
}
# Every record of the corpus against docs/schemas/neper-v1.schema.json (D250). The
# goldens are what the commands emit, byte for byte, so validating them validates the
# emitters; the script skips itself where the `jsonschema` package is absent.
& python (Join-Path $repo 'scripts/validate_stream.py')
if ($LASTEXITCODE -ne 0) { throw "the conformance corpus does not validate against the v1 schema" }
# Section 11's debug fills (D217): a fresh allocation reads 0xCD and a reset's memory
# 0xDD in the debug build, and neither in release.
$fillsPath = Join-Path $testBuild 'debug-fills-selfhost.exe'
$fillsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\debug_fills\src\main.e') $repo 'x64' 'windows' $fillsPath
if ($LASTEXITCODE -ne 0 -or $fillsWritten -ne 'executable written') { throw 'debug fills fixture executable emission failed' }
& $fillsPath debug
if ($LASTEXITCODE -ne 0) { throw "the debug build did not fill allocations and resets: exit $LASTEXITCODE" }
$fillsReleasePath = Join-Path $testBuild 'debug-fills-release-selfhost.exe'
$fillsReleaseWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\debug_fills\src\main.e') $repo 'x64' 'windows' $fillsReleasePath --release
if ($LASTEXITCODE -ne 0 -or $fillsReleaseWritten -ne 'executable written') { throw 'debug fills release emission failed' }
& $fillsReleasePath release
if ($LASTEXITCODE -ne 0) { throw "the release build filled memory: exit $LASTEXITCODE" }
# Section 6's `when` (D216): conditions over `target.arch` and `target.os`, settled at
# compile time, the taken arms adding up to 17 on Windows, four of them through a
# condition the interpreter evaluates (D220), and `target.arch`/`target.os` as values
# -- compared, switched over, passed -- adding 56 (D223); a condition over runtime
# state is refused.
$whenPath = Join-Path $testBuild 'when-target-selfhost.exe'
$whenWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\when_target\src\main.e') $repo 'x64' 'windows' $whenPath
if ($LASTEXITCODE -ne 0 -or $whenWritten -ne 'executable written') { throw 'when fixture executable emission failed' }
& $whenPath
if ($LASTEXITCODE -ne 73) { throw "when and the target namespace did not settle for windows/x64: exit $LASTEXITCODE" }
Require-Fixture 'check/when_condition'
$whenOutput = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\when_condition\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($whenOutput -join "`n") -notmatch 'main\.e:5:10: error\[E-COMPTIME-9999\]: a `when` condition cannot be evaluated at compile time: it reached a name that is no local or constant') { throw "a when condition over runtime state was not refused: $($whenOutput -join "`n")" }
# The trap protocol's backtrace: one `  at module.function` line per frame, from the
# trapping function up to main, after the record; a debug build does not inline, so
# `deeper` is a frame (D211).
$backtracePath = Join-Path $testBuild 'trap-backtrace-selfhost.exe'
$backtraceWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\trap_backtrace\src\main.e') $repo 'x64' 'windows' $backtracePath
if ($LASTEXITCODE -ne 0 -or $backtraceWritten -ne 'executable written') { throw 'backtrace fixture executable emission failed' }
$backtraceOutput = (& $backtracePath 2>&1) -join "`n"
if ($LASTEXITCODE -ne 134 -or $backtraceOutput -notmatch 'helper\.e:1:50: trap\[bounds\]: index 7 out of bounds for len 5\n  at helper\.pick \(.*helper\.e:1\)\n  at main\.deeper \(.*main\.e:12\)\n  at main\.main \(.*main\.e:16\)') { throw "the trap did not print its backtrace: exit $LASTEXITCODE, $backtraceOutput" }
# `e.path` is pure: the same answers on both platforms, so the fixture asserts exact
# strings rather than only that nothing failed.
# `os.syscall` exists on Linux alone, so on this target the name must not resolve at
# all -- an unknown name, not something that fails when called. `run.sh` is where the
# intrinsic itself is exercised.
$syscallAbsent = & $compiler check-file (Join-Path $PSScriptRoot 'fixtures\link\os_syscall\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($syscallAbsent -join "`n") -notmatch 'error\[E-NAME-9999\]') { throw "os.syscall resolved on a non-Linux target: $($syscallAbsent -join "`n")" }
$pathPurePath = Join-Path $testBuild 'path-pure-selfhost.exe'
$pathPureWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\path_pure\src\main.e') $repo 'x64' 'windows' $pathPurePath
if ($LASTEXITCODE -ne 0 -or $pathPureWritten -ne 'executable written') { throw 'e.path executable emission failed' }
& $pathPurePath
if ($LASTEXITCODE -ne 0) { throw "an e.path answer is wrong (section code $LASTEXITCODE)" }
$metaReflectPath = Join-Path $testBuild 'meta-reflect-selfhost.exe'
$metaReflectWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\meta_reflect\src\main.e') $repo 'x64' 'windows' $metaReflectPath
if ($LASTEXITCODE -ne 0 -or $metaReflectWritten -ne 'executable written') { throw 'reflection executable emission failed' }
& $metaReflectPath
if ($LASTEXITCODE -ne 0) { throw 'a comptime field walk, get, set or member value is wrong' }
$channelPath = Join-Path $testBuild 'channel-semantics-selfhost.exe'
$channelWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\channel_semantics\src\main.e') $repo 'x64' 'windows' $channelPath
if ($LASTEXITCODE -ne 0 -or $channelWritten -ne 'executable written') { throw 'e.channel executable emission failed' }
& $channelPath
if ($LASTEXITCODE -ne 0) { throw 'an e.channel operation is wrong uncontended' }
$channelThreadsPath = Join-Path $testBuild 'channel-threads-selfhost.exe'
$channelThreadsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\channel_threads\src\main.e') $repo 'x64' 'windows' $channelThreadsPath
if ($LASTEXITCODE -ne 0 -or $channelThreadsWritten -ne 'executable written') { throw 'contended e.channel executable emission failed' }
& $channelThreadsPath
if ($LASTEXITCODE -ne 0) { throw 'an e.channel handoff lost, duplicated or failed to wake' }
# `e.sync`. The uncontended half first, where every fence promise lives and where a
# wrong wait fails in milliseconds; then the half a single thread cannot check, where
# a mutex that does not exclude loses increments and the total comes out short.
$syncPath = Join-Path $testBuild 'sync-semantics-selfhost.exe'
$syncWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\sync_semantics\src\main.e') $repo 'x64' 'windows' $syncPath
if ($LASTEXITCODE -ne 0 -or $syncWritten -ne 'executable written') { throw 'e.sync executable emission failed' }
& $syncPath
if ($LASTEXITCODE -ne 0) { throw 'an e.sync primitive is wrong uncontended' }
$syncThreadsPath = Join-Path $testBuild 'sync-threads-selfhost.exe'
$syncThreadsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\sync_threads\src\main.e') $repo 'x64' 'windows' $syncThreadsPath
if ($LASTEXITCODE -ne 0 -or $syncThreadsWritten -ne 'executable written') { throw 'contended e.sync executable emission failed' }
& $syncThreadsPath
if ($LASTEXITCODE -ne 0) { throw 'an e.sync lock did not exclude, or a wait did not wake' }
# A lock as a resource (D379, H04): guards released on every exit, workers excluded.
$syncGuardPath = Join-Path $testBuild 'sync-guard-selfhost.exe'
$syncGuardWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\sync_guard\src\main.e') $repo 'x64' 'windows' $syncGuardPath
if ($LASTEXITCODE -ne 0 -or $syncGuardWritten -ne 'executable written') { throw 'sync guard executable emission failed' }
& $syncGuardPath
if ($LASTEXITCODE -ne 0) { throw 'a guard did not exclude or was not released' }
# A group of threads as one resource (D434, H04): joined on every exit, by `defer` too.
$threadGroupPath = Join-Path $testBuild 'thread-group-selfhost.exe'
$threadGroupWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\thread_group\src\main.e') $repo 'x64' 'windows' $threadGroupPath
if ($LASTEXITCODE -ne 0 -or $threadGroupWritten -ne 'executable written') { throw 'thread group executable emission failed' }
& $threadGroupPath
if ($LASTEXITCODE -ne 0) { throw 'a thread group was not started or joined whole' }
# Read and write locks as resources (D433, H04): readers together, a writer alone.
$syncRwGuardPath = Join-Path $testBuild 'sync-rwguard-selfhost.exe'
$syncRwGuardWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\sync_rwguard\src\main.e') $repo 'x64' 'windows' $syncRwGuardPath
if ($LASTEXITCODE -ne 0 -or $syncRwGuardWritten -ne 'executable written') { throw 'sync rwguard executable emission failed' }
& $syncRwGuardPath
if ($LASTEXITCODE -ne 0) { throw 'a read or write guard did not exclude or was not released' }
# Section 8's blocking primitives, under the wake that a bug here turns into a hang.
$futexPath = Join-Path $testBuild 'os-futex-selfhost.exe'
$futexWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\os_futex\src\main.e') $repo 'x64' 'windows' $futexPath
if ($LASTEXITCODE -ne 0 -or $futexWritten -ne 'executable written') { throw 'futex executable emission failed' }
& $futexPath
if ($LASTEXITCODE -ne 0) { throw 'os.wait_u32 or a wake is wrong' }
# Section 8's atomics. The ordering rules are settled while checking, so each is pinned
# to its message; the operations themselves are run, because `and`, `or`, `xor`, `min`
# and `max` are compare-and-swap loops whose widening and signedness a check cannot see.
$atomicDiagnostics = @(
    @('atomic_load_release', 'main\.e:8:34: error\[E-MEM-9999\]: `atomic\.load` may not take the ordering `\.Release`'),
    @('atomic_store_acquire', 'main\.e:8:33: error\[E-MEM-9999\]: `atomic\.store` may not take the ordering `\.Acquire`'),
    @('atomic_cas_failure', 'main\.e:9:65: error\[E-MEM-9999\]: `atomic\.cas` may not take the ordering `\.SeqCst`'),
    @('atomic_element', 'main\.e:5:14: error\[E-MEM-9999\]: `Atomic\[f64\]` is not a type: an atomic holds an integer or a pointer')
)
# docs/diagnostics.md's codes for the module graph, the scanner and the command line
# (D215): each at the module that wrote the `use`, the token the scanner refused, or
# the usage line, under its registered code.
$codeDiagnostics = @(
    @('module_missing', 'main\.e:1:1: error\[E-MODULE-0001\]: `use nowhere` names no module under the source root or the toolchain'),
    @('module_cycle', 'b\.e:1:1: error\[E-MODULE-0002\]: `use main` closes an import cycle'),
    @('lex_literal', 'main\.e:3:13: error\[E-LEX-0003\]: invalid token'),
    @('lex_tab', 'main\.e:3:1: error\[E-LEX-0002\]: invalid token'),
    @('lex_utf8', 'main\.e:2:21: error\[E-LEX-0001\]: invalid token')
)
foreach ($case in $codeDiagnostics) {
    Require-Fixture ("check/" + $case[0])
    $codeOutput = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($codeOutput -join "`n") -notmatch $case[1]) {
        throw "diagnostic code for $($case[0]) is wrong: $($codeOutput -join "`n")"
    }
}
$cliOutput = & $compiler 2>&1
if ($LASTEXITCODE -ne 1 -or ($cliOutput -join "`n") -notmatch 'error\[E-CLI-9999\]: usage: ') { throw "an empty command line was not refused under E-CLI-9999: $($cliOutput -join "`n")" }
foreach ($case in $atomicDiagnostics) {
    Require-Fixture ("check/" + $case[0])
    $atomicOutput = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($atomicOutput -join "`n") -notmatch $case[1]) {
        throw "atomic diagnostic for $($case[0]) is wrong: $($atomicOutput -join "`n")"
    }
}
# Section 4's register-only rule: a `Mask[T, N]` has no storage form, so every position
# that would store one is refused while checking, each naming the position it is.
$maskDiagnostics = @(
    @('mask_field', 'main\.e:4:23: error\[E-TYPE-9999\]: `Mask\[T, N\]` is register-only \(section 4\): a field may not hold one'),
    @('mask_array', 'main\.e:5:18: error\[E-TYPE-9999\]: `Mask\[T, N\]` is register-only \(section 4\): an array element may not hold one'),
    @('mask_pointer', 'main\.e:4:14: error\[E-TYPE-9999\]: `Mask\[T, N\]` is register-only \(section 4\): a pointer may not point at one'),
    @('mask_address', 'main\.e:6:13: error\[E-TYPE-9999\]: `Mask\[T, N\]` is register-only \(section 4\): a pointer may not point at one'),
    @('mask_size_of', 'main\.e:6:29: error\[E-TYPE-9999\]: `Mask\[T, N\]` is register-only \(section 4\): `mem\.size_of` and `mem\.align_of` have no answer for one'),
    @('mask_alloc', 'main\.e:6:31: error\[E-TYPE-9999\]: `Mask\[T, N\]` is register-only \(section 4\): a slice element may not hold one')
)
foreach ($case in $maskDiagnostics) {
    Require-Fixture ("check/" + $case[0])
    $maskOutput = & $compiler check-file (Join-Path $repo "tests\selfhost\fixtures\check\$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($maskOutput -join "`n") -notmatch $case[1]) {
        throw "mask diagnostic for $($case[0]) is wrong: $($maskOutput -join "`n")"
    }
}
$atomicOpsPath = Join-Path $testBuild 'atomic-ops-selfhost.exe'
$atomicOpsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\atomic_ops\src\main.e') $repo 'x64' 'windows' $atomicOpsPath
if ($LASTEXITCODE -ne 0 -or $atomicOpsWritten -ne 'executable written') { throw 'atomic executable emission failed' }
& $atomicOpsPath
if ($LASTEXITCODE -ne 0) { throw 'an atomic operation, width or ordering is wrong' }
# The one check a single thread cannot make: that `lock` is really on the instruction.
# Without it the four workers lose updates and the total comes out short.
$atomicThreadsPath = Join-Path $testBuild 'atomic-threads-selfhost.exe'
$atomicThreadsWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\atomic_threads\src\main.e') $repo 'x64' 'windows' $atomicThreadsPath
if ($LASTEXITCODE -ne 0 -or $atomicThreadsWritten -ne 'executable written') { throw 'contended atomic executable emission failed' }
& $atomicThreadsPath
if ($LASTEXITCODE -ne 0) { throw 'contended atomic increments lost updates' }
# An alias to a generic instantiation cannot resolve in `collect_aliases`' first pass,
# which runs before any aggregate is registered, so a field naming one holds the alias
# name until the second pass. `lead` and `tail` bracket the instances, so a size or
# offset taken from an unexpanded field type is a wrong value and not just a wrong type.
$genericInstanceAliasPath = Join-Path $testBuild 'generic-instance-alias-selfhost.exe'
$genericInstanceAliasWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\generic_instance_alias\src\main.e') $repo 'x64' 'windows' $genericInstanceAliasPath
if ($LASTEXITCODE -ne 0 -or $genericInstanceAliasWritten -ne 'executable written') { throw 'aliased generic instance executable emission failed' }
& $genericInstanceAliasPath
if ($LASTEXITCODE -ne 0) { throw 'a field whose type is a generic instance reached through an alias is laid out wrong' }
$genericInstancesExecutablePath = Join-Path $testBuild 'generic-instances-selfhost.exe'
$genericInstancesExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\generic_instances\src\main.e') $repo 'x64' 'windows' $genericInstancesExecutablePath
if ($LASTEXITCODE -ne 0 -or $genericInstancesExecutableWritten -ne 'executable written') { throw 'multi-instance generic PE executable emission failed' }
& $genericInstancesExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'distinct generic instances of one template did not keep distinct code' }
$genericInstancesArtifacts = Join-Path $testBuild 'generic-instances'
$genericInstancesCopy = Join-Path $testBuild 'generic-instances-copy'
New-Item -ItemType Directory -Force -Path $genericInstancesArtifacts | Out-Null
New-Item -ItemType Directory -Force -Path $genericInstancesCopy | Out-Null
$genericInstancesArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\generic_instances\src\main.e') $repo 'x64' 'windows' $genericInstancesArtifacts
if ($LASTEXITCODE -ne 0 -or $genericInstancesArtifactsWritten -ne 'compiled modules written') { throw 'multi-instance generic artifact emission failed' }
$genericInstancesCopyWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\generic_instances\src\main.e') $repo 'x64' 'windows' $genericInstancesCopy
if ($LASTEXITCODE -ne 0 -or $genericInstancesCopyWritten -ne 'compiled modules written') { throw 'repeated multi-instance generic artifact emission failed' }
$genericInstancesRootPath = Join-Path $genericInstancesArtifacts 'main.x64-windows.em'
$genericInstancesDepPath = Join-Path $genericInstancesArtifacts 'dep.x64-windows.em'
foreach ($artifactPath in @($genericInstancesRootPath, $genericInstancesDepPath)) {
    if (-not (Test-Path -LiteralPath $artifactPath)) { throw 'multi-instance generic artifact set is incomplete' }
    $artifactValidation = & $compiler validate-em $artifactPath
    if ($LASTEXITCODE -ne 0 -or $artifactValidation -ne 'compiled module valid') { throw "multi-instance generic artifact is invalid: $artifactPath" }
    $copyPath = Join-Path $genericInstancesCopy (Split-Path -Leaf $artifactPath)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $copyPath).Hash) { throw 'multi-instance generic artifact emission is not deterministic' }
}
$genericInstancesEdge = & $compiler check-em-edge $genericInstancesRootPath $genericInstancesDepPath
if ($LASTEXITCODE -ne 0 -or $genericInstancesEdge -ne 'dependency current') { throw 'multi-edge generic dependency was rejected' }
$genericInstancesRootRecords = Get-EmCodeRecords $genericInstancesRootPath
$genericInstancesDepRecords = Get-EmCodeRecords $genericInstancesDepPath
if ($genericInstancesDepRecords.Count -ne 0) { throw 'the module declaring a generic template still owns its instances' }
# Seven instances plus `neper_report_failure`, the failure line's function (D199), which
# is code of the root module too.
if ($genericInstancesRootRecords.Count -ne 8) { throw 'the instantiating module did not receive every instance it uses' }
$genericInstancesArtifactExecutable = Join-Path $testBuild 'generic-instances-from-artifacts.exe'
$genericInstancesArtifactWritten = & $compiler link-em $genericInstancesArtifactExecutable $genericInstancesRootPath $genericInstancesDepPath
if ($LASTEXITCODE -ne 0 -or $genericInstancesArtifactWritten -ne 'artifact executable written') { throw 'multi-instance generic compiled modules did not link' }
& $genericInstancesArtifactExecutable
if ($LASTEXITCODE -ne 0) { throw 'multi-instance generic compiled-module executable failed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $genericInstancesArtifactExecutable).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $genericInstancesExecutablePath).Hash) { throw 'multi-instance generic compiled-module and source links differ' }
$foldingFixture = Join-Path $PSScriptRoot 'fixtures\link\generic_folding\src\main.e'
$foldingDirect = Join-Path $testBuild 'generic-folding-selfhost.exe'
$foldingDirectWritten = & $compiler emit-executable $foldingFixture $repo 'x64' 'windows' $foldingDirect
if ($LASTEXITCODE -ne 0 -or $foldingDirectWritten -ne 'executable written') { throw 'shared generic instance executable emission failed' }
& $foldingDirect
if ($LASTEXITCODE -ne 0) { throw 'two modules sharing one generic instance produced wrong results' }
$foldingArtifacts = Join-Path $testBuild 'generic-folding'
New-Item -ItemType Directory -Force -Path $foldingArtifacts | Out-Null
$foldingWritten = & $compiler emit-em-all $foldingFixture $repo 'x64' 'windows' $foldingArtifacts
if ($LASTEXITCODE -ne 0 -or $foldingWritten -ne 'compiled modules written') { throw 'shared generic instance artifact emission failed' }
if ((Get-EmCodeRecords (Join-Path $foldingArtifacts 'lib.x64-windows.em')).Count -ne 0) { throw 'a template-only module still owns compiled code' }
$foldingOne = Get-EmCodeRecords (Join-Path $foldingArtifacts 'one.x64-windows.em')
$foldingTwo = Get-EmCodeRecords (Join-Path $foldingArtifacts 'two.x64-windows.em')
if ($foldingOne.Count -ne 2 -or $foldingTwo.Count -ne 2) { throw 'an instantiating module did not receive its own instance copy' }
if ($foldingOne[1].Instance -ne 1 -or $foldingTwo[1].Instance -ne 1) { throw 'an owned instance carries the wrong discriminator' }
if ($foldingOne[1].ContentHash -ne $foldingTwo[1].ContentHash) { throw 'identical instances in two modules do not share a content hash' }
$foldedExecutable = Join-Path $testBuild 'generic-folding-from-artifacts.exe'
$foldedWritten = & $compiler link-em $foldedExecutable (Join-Path $foldingArtifacts 'main.x64-windows.em') (Join-Path $foldingArtifacts 'one.x64-windows.em') (Join-Path $foldingArtifacts 'two.x64-windows.em') (Join-Path $foldingArtifacts 'lib.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $foldedWritten -ne 'artifact executable written') { throw 'compiled modules with a shared instance did not link' }
& $foldedExecutable
if ($LASTEXITCODE -ne 0) { throw 'executable linked from folded compiled modules failed' }
# A shared instance is emitted once per module, so an artifact link keeps two identical copies
# where the whole-program build keeps two as well: the two must match byte for byte, the property
# D156 restored by not sharing one copy in the artifact linker alone.
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $foldedExecutable).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $foldingDirect).Hash) { throw 'a shared generic instance links differently from artifacts than from source' }
$bitwiseExecutablePath = Join-Path $testBuild 'bitwise-selfhost.exe'
$bitwiseExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\bitwise\src\main.e') $repo 'x64' 'windows' $bitwiseExecutablePath
if ($LASTEXITCODE -ne 0 -or $bitwiseExecutableWritten -ne 'executable written') { throw 'bitwise PE executable emission failed' }
& $bitwiseExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'wrapping or bitwise semantics failed in the self-hosted PE executable' }
$divisionExecutablePath = Join-Path $testBuild 'division-selfhost.exe'
$divisionExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\division\src\main.e') $repo 'x64' 'windows' $divisionExecutablePath
if ($LASTEXITCODE -ne 0 -or $divisionExecutableWritten -ne 'executable written') { throw 'division PE executable emission failed' }
& $divisionExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'signed or unsigned division semantics failed in the self-hosted PE executable' }
$shiftExecutablePath = Join-Path $testBuild 'shifts-selfhost.exe'
$shiftExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\shifts\src\main.e') $repo 'x64' 'windows' $shiftExecutablePath
if ($LASTEXITCODE -ne 0 -or $shiftExecutableWritten -ne 'executable written') { throw 'shift PE executable emission failed' }
& $shiftExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'left or signed-right shift semantics failed in the self-hosted PE executable' }
$localsLowered = & $compiler nir-file (Join-Path $PSScriptRoot 'fixtures\nir\locals\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $localsLowered -ne 'module nir ok') { throw 'parameters and local storage did not lower to canonical NIR' }
$localsGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\locals\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $localsGenerated -ne 'module codegen ok') { throw 'scalar local storage did not select x64 instructions' }
$storageExecutablePath = Join-Path $testBuild 'storage-selfhost.exe'
$storageExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\storage\src\main.e') $repo 'x64' 'windows' $storageExecutablePath
if ($LASTEXITCODE -ne 0 -or $storageExecutableWritten -ne 'executable written') { throw 'storage PE executable emission failed' }
& $storageExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'mutable local storage failed in the self-hosted PE executable' }
$aggregateExecutablePath = Join-Path $testBuild 'aggregate-selfhost.exe'
$aggregateExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\aggregate\src\main.e') $repo 'x64' 'windows' $aggregateExecutablePath
if ($LASTEXITCODE -ne 0 -or $aggregateExecutableWritten -ne 'executable written') { throw 'aggregate PE executable emission failed' }
& $aggregateExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'aggregate layout, literal storage, or field access failed in the self-hosted PE executable' }
# `@reorder` (D239): the opt-in alignment sort. The reordered struct is 16 bytes where
# declaration order pads the same three fields to 24, and every field still reads and
# writes through its own offset; a value of one crossing an FFI boundary is refused.
$reorderExecutablePath = Join-Path $testBuild 'reorder-selfhost.exe'
$reorderExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\reorder\src\main.e') $repo 'x64' 'windows' $reorderExecutablePath
if ($LASTEXITCODE -ne 0 -or $reorderExecutableWritten -ne 'executable written') { throw '@reorder PE executable emission failed' }
& $reorderExecutablePath
if ($LASTEXITCODE -ne 0) { throw "@reorder did not pack the struct or did not keep its fields: exit $LASTEXITCODE" }
Require-Fixture 'check/reorder_extern'
$reorderExternOutput = & $compiler check-file (Join-Path $repo 'tests\selfhost\fixtures\check\reorder_extern\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reorderExternOutput -join "`n") -notmatch 'main\.e:11:1: error\[E-TYPE-9999\]: @reorder is legal on a struct or a union that crosses no FFI boundary') { throw "a @reorder struct crossing an FFI boundary was not refused: $($reorderExternOutput -join "`n")" }
$advancedExecutablePath = Join-Path $testBuild 'advanced-selfhost.exe'
$advancedExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\advanced\src\main.e') $repo 'x64' 'windows' $advancedExecutablePath
if ($LASTEXITCODE -ne 0 -or $advancedExecutableWritten -ne 'executable written') { throw 'advanced self-host PE executable emission failed' }
& $advancedExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'multiple returns, caller slots, strings, stack arguments, slices, or for loops failed in the self-hosted PE executable' }
$constantExecutablePath = Join-Path $testBuild 'constant-folding-selfhost.exe'
$constantExecutableWritten = & $compiler emit-executable (Join-Path $repo 'tests\neper0\constant-folding.e') $repo 'x64' 'windows' $constantExecutablePath
if ($LASTEXITCODE -ne 0 -or $constantExecutableWritten -ne 'executable written') { throw 'evaluated constants did not lower into a PE executable' }
$constantOutput = & $constantExecutablePath
if ($LASTEXITCODE -ne 0 -or $constantOutput -ne 'constant folding ok') { throw 'local evaluated constants failed in the self-hosted PE executable' }
$genericNeper0Path = Join-Path $testBuild 'generic-neper0-selfhost.exe'
$genericNeper0Written = & $compiler emit-executable (Join-Path $repo 'tests\neper0\generic-function.e') $repo 'x64' 'windows' $genericNeper0Path
if ($LASTEXITCODE -ne 0 -or $genericNeper0Written -ne 'executable written') { throw 'value-comptime generic expressions did not lower into a PE executable' }
$genericNeper0Output = & $genericNeper0Path
if ($LASTEXITCODE -ne 0 -or $genericNeper0Output -ne 'generic function ok') { throw 'value-comptime generic expressions failed in the self-hosted PE executable' }
$switchExecutablePath = Join-Path $testBuild 'enum-union-switch-selfhost.exe'
$switchExecutableWritten = & $compiler emit-executable (Join-Path $repo 'tests\neper0\enum-union-switch.e') $repo 'x64' 'windows' $switchExecutablePath
if ($LASTEXITCODE -ne 0 -or $switchExecutableWritten -ne 'executable written') { throw 'enum, union, tagged-union, or switch lowering failed' }
$switchOutput = & $switchExecutablePath
if ($LASTEXITCODE -ne 0 -or $switchOutput -ne 'enum union switch ok') { throw 'enum, union, tagged-union, or switch execution failed' }
$deferExecutablePath = Join-Path $testBuild 'defer-selfhost.exe'
$deferExecutableWritten = & $compiler emit-executable (Join-Path $repo 'tests\neper0\defer.e') $repo 'x64' 'windows' $deferExecutablePath
if ($LASTEXITCODE -ne 0 -or $deferExecutableWritten -ne 'executable written') { throw 'defer cleanup did not lower into a PE executable' }
$deferOutput = & $deferExecutablePath
if ($LASTEXITCODE -ne 0 -or $deferOutput -ne 'defer ok') { throw 'defer capture, ordering, or control-flow cleanup failed' }
$protocolExecutablePath = Join-Path $testBuild 'protocol-iteration-selfhost.exe'
$protocolExecutableWritten = & $compiler emit-executable (Join-Path $repo 'tests\neper0\protocol-iteration.e') $repo 'x64' 'windows' $protocolExecutablePath
if ($LASTEXITCODE -ne 0 -or $protocolExecutableWritten -ne 'executable written') { throw 'custom iterator protocol did not lower into a PE executable' }
$protocolOutput = & $protocolExecutablePath
if ($LASTEXITCODE -ne 0 -or $protocolOutput -ne 'protocol iteration ok') { throw 'custom iterator protocol call, aggregate result, or cleanup failed' }
$hashSurface = Get-Content (Join-Path $repo 'lib\e\algo\hash.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.algo.hash contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedHashSurface = @('XxHash64', 'Crc32', 'fnv1a32', 'fnv1a64', 'xxhash64', 'xxhash64_init', 'xxhash64_update', 'xxhash64_done', 'crc32', 'crc32_init', 'crc32_update', 'crc32_done', 'adler32')
if (($hashSurface -join "`n") -ne ($expectedHashSurface -join "`n")) { throw 'e.algo.hash public declarations differ from module-apis.md' }
$hashParsed = & $compiler parse-file (Join-Path $repo 'lib\e\algo\hash.e')
if ($LASTEXITCODE -ne 0 -or $hashParsed -ne 'parse file ok') { throw 'e.algo.hash exceeded or failed CLI parser storage' }
$hashExecutablePath = Join-Path $testBuild 'algo-hash-selfhost.exe'
$hashExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_hash\src\main.e') $repo 'x64' 'windows' $hashExecutablePath
if ($LASTEXITCODE -ne 0 -or $hashExecutableWritten -ne 'executable written') { throw 'e.algo.hash did not compile into a PE executable' }
$hashOutput = & $hashExecutablePath
if ($LASTEXITCODE -ne 0 -or $hashOutput -ne 'algo hash ok') { throw 'e.algo.hash one-shot or streaming behavior failed' }
$bitsetSurface = Get-Content (Join-Path $repo 'lib\e\algo\bitset.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.algo.bitset contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedBitsetSurface = @('BitSet', 'TooSmall', 'init', 'len', 'clear_all', 'fill_all', 'get', 'set', 'unset', 'toggle', 'count', 'first_set', 'next_set', 'union_in_place', 'intersect_in_place', 'difference_in_place', 'complement_in_place', 'is_subset', 'eq')
if (($bitsetSurface -join "`n") -ne ($expectedBitsetSurface -join "`n")) { throw 'e.algo.bitset public declarations differ from module-apis.md' }
$bitsetParsed = & $compiler parse-file (Join-Path $repo 'lib\e\algo\bitset.e')
if ($LASTEXITCODE -ne 0 -or $bitsetParsed -ne 'parse file ok') { throw 'e.algo.bitset failed CLI parsing' }
$bitsetExecutablePath = Join-Path $testBuild 'algo-bitset-selfhost.exe'
$bitsetExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_bitset\src\main.e') $repo 'x64' 'windows' $bitsetExecutablePath
if ($LASTEXITCODE -ne 0 -or $bitsetExecutableWritten -ne 'executable written') { throw 'e.algo.bitset did not compile into a PE executable' }
$bitsetOutput = & $bitsetExecutablePath
if ($LASTEXITCODE -ne 0 -or $bitsetOutput -ne 'algo bitset ok') { throw 'e.algo.bitset behavior or storage invariants failed' }
$ringSurface = Get-Content (Join-Path $repo 'lib\e\data\ring.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.data.ring contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedRingSurface = @('Ring', 'Iter', 'init', 'len', 'capacity', 'push', 'push_overwrite', 'pop', 'peek', 'clear', 'iter', 'iter_next')
if (($ringSurface -join "`n") -ne ($expectedRingSurface -join "`n")) { throw 'e.data.ring public declarations differ from module-apis.md' }
$ringParsed = & $compiler parse-file (Join-Path $repo 'lib\e\data\ring.e')
if ($LASTEXITCODE -ne 0 -or $ringParsed -ne 'parse file ok') { throw 'e.data.ring failed CLI parsing' }
$ringExecutablePath = Join-Path $testBuild 'data-ring-selfhost.exe'
$ringExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_ring\src\main.e') $repo 'x64' 'windows' $ringExecutablePath
if ($LASTEXITCODE -ne 0 -or $ringExecutableWritten -ne 'executable written') { throw 'e.data.ring did not compile into a PE executable' }
$ringOutput = & $ringExecutablePath
if ($LASTEXITCODE -ne 0 -or $ringOutput -ne 'data ring ok') { throw 'e.data.ring FIFO, overwrite, iteration, or empty-capacity behavior failed' }
# `e.cancel` (D347, SL03): tokens, controls, deadlines and a request shared by threads.
foreach ($cancelMode in @(@(), @('--release'))) {
    $cancelPath = Join-Path $testBuild ('cancel-selfhost' + $cancelMode.Count + '.exe')
    $cancelWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\cancel\src\main.e') $repo 'x64' 'windows' $cancelPath @cancelMode
    if ($LASTEXITCODE -ne 0 -or $cancelWritten -ne 'executable written') { throw 'link/cancel did not compile' }
    $cancelOutput = & $cancelPath
    if ($LASTEXITCODE -ne 0 -or $cancelOutput -ne 'cancel ok') { throw "link/cancel failed check $LASTEXITCODE" }
}
# D330: a promoted local copied from a later-declared local and reassigned in the same block.
foreach ($promoteMode in @(@(), @('--release'))) {
    $promotePath = Join-Path $testBuild ('promote-copy-selfhost' + $promoteMode.Count + '.exe')
    $promoteWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\promote_copy\src\main.e') $repo 'x64' 'windows' $promotePath @promoteMode
    if ($LASTEXITCODE -ne 0 -or $promoteWritten -ne 'executable written') { throw 'link/promote_copy did not compile' }
    $promoteOutput = & $promotePath
    if ($LASTEXITCODE -ne 0 -or $promoteOutput -ne 'promote copy ok') { throw "link/promote_copy read the wrong local: $promoteOutput" }
}
$dequeSurface = Get-Content (Join-Path $repo 'lib\e\data\deque.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.data.deque contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedDequeSurface = @('Deque', 'Iter', 'init', 'len', 'reserve', 'push_front', 'push_back', 'pop_front', 'pop_back', 'get', 'clear', 'iter', 'iter_next')
if (($dequeSurface -join "`n") -ne ($expectedDequeSurface -join "`n")) { throw 'e.data.deque public declarations differ from module-apis.md' }
$dequeParsed = & $compiler parse-file (Join-Path $repo 'lib\e\data\deque.e')
if ($LASTEXITCODE -ne 0 -or $dequeParsed -ne 'parse file ok') { throw 'e.data.deque failed CLI parsing' }
$dequeExecutablePath = Join-Path $testBuild 'data-deque-selfhost.exe'
$dequeExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_deque\src\main.e') $repo 'x64' 'windows' $dequeExecutablePath
if ($LASTEXITCODE -ne 0 -or $dequeExecutableWritten -ne 'executable written') { throw 'e.data.deque did not compile into a PE executable' }
$dequeOutput = & $dequeExecutablePath
if ($LASTEXITCODE -ne 0 -or $dequeOutput -ne 'data deque ok') { throw 'e.data.deque growth, wraparound, iteration, or empty-capacity behavior failed' }
$listSurface = Get-Content (Join-Path $repo 'lib\e\data\list.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.data.list contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedListSurface = @('List', 'Iter', 'init', 'from_slice', 'slice', 'slice_const', 'reserve', 'push', 'pop', 'insert', 'remove', 'clear', 'iter', 'iter_next')
if (($listSurface -join "`n") -ne ($expectedListSurface -join "`n")) { throw 'e.data.list public declarations differ from module-apis.md' }
$listParsed = & $compiler parse-file (Join-Path $repo 'lib\e\data\list.e')
if ($LASTEXITCODE -ne 0 -or $listParsed -ne 'parse file ok') { throw 'e.data.list failed CLI parsing' }
$listExecutablePath = Join-Path $testBuild 'data-list-selfhost.exe'
$listExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_list\src\main.e') $repo 'x64' 'windows' $listExecutablePath
if ($LASTEXITCODE -ne 0 -or $listExecutableWritten -ne 'executable written') { throw 'e.data.list did not compile into a PE executable' }
$listOutput = & $listExecutablePath
if ($LASTEXITCODE -ne 0 -or $listOutput -ne 'data list ok') { throw 'e.data.list growth, insertion, removal, copy, view, or iteration behavior failed' }
$sortSurface = Get-Content (Join-Path $repo 'lib\e\algo\sort.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.algo.sort contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedSortSurface = @('in_place', 'in_place_by', 'stable_in_place', 'stable_in_place_by', 'radix_u32_in_place', 'radix_u64_in_place', 'is_sorted')
if (($sortSurface -join "`n") -ne ($expectedSortSurface -join "`n")) { throw 'e.algo.sort public declarations differ from module-apis.md' }
$sortParsed = & $compiler parse-file (Join-Path $repo 'lib\e\algo\sort.e')
if ($LASTEXITCODE -ne 0 -or $sortParsed -ne 'parse file ok') { throw 'e.algo.sort failed CLI parsing' }
$sortExecutablePath = Join-Path $testBuild 'algo-sort-selfhost.exe'
$sortExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\algo_sort\src\main.e') $repo 'x64' 'windows' $sortExecutablePath
if ($LASTEXITCODE -ne 0 -or $sortExecutableWritten -ne 'executable written') { throw 'e.algo.sort did not compile into a PE executable' }
$sortOutput = & $sortExecutablePath
if ($LASTEXITCODE -ne 0 -or $sortOutput -ne 'algo sort ok') { throw 'e.algo.sort ordering, stability, radix, or arena behavior failed' }
$heapSurface = Get-Content (Join-Path $repo 'lib\e\data\heap.e') |
    Where-Object { $_ -match '^(?:type|fn|error|const|var) ' } |
    ForEach-Object {
        if ($_ -notmatch '^(?:type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)') { throw 'e.data.heap contains an unreadable public declaration' }
        $Matches[1]
    }
$expectedHeapSurface = @('Heap', 'HeapBy', 'Iter', 'init', 'from_slice', 'len', 'push', 'peek', 'pop', 'clear', 'init_by', 'from_slice_by', 'len_by', 'push_by', 'peek_by', 'pop_by', 'clear_by', 'heapify_in_place', 'heapify_in_place_by', 'iter', 'iter_by', 'iter_next')
if (($heapSurface -join "`n") -ne ($expectedHeapSurface -join "`n")) { throw 'e.data.heap public declarations differ from module-apis.md' }
$heapParsed = & $compiler parse-file (Join-Path $repo 'lib\e\data\heap.e')
if ($LASTEXITCODE -ne 0 -or $heapParsed -ne 'parse file ok') { throw 'e.data.heap failed CLI parsing' }
$heapExecutablePath = Join-Path $testBuild 'data-heap-selfhost.exe'
$heapExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\data_heap\src\main.e') $repo 'x64' 'windows' $heapExecutablePath
if ($LASTEXITCODE -ne 0 -or $heapExecutableWritten -ne 'executable written') { throw 'e.data.heap did not compile into a PE executable' }
$heapOutput = & $heapExecutablePath
if ($LASTEXITCODE -ne 0 -or $heapOutput -ne 'data heap ok') { throw 'e.data.heap ordering, bulk construction, iteration, or user-cmp behavior failed' }
$sameNameExecutablePath = Join-Path $testBuild 'generic-same-name-selfhost.exe'
$sameNameWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\generic_same_name\src\main.e') $repo 'x64' 'windows' $sameNameExecutablePath
if ($LASTEXITCODE -ne 0 -or $sameNameWritten -ne 'executable written') { throw 'same-named generic templates did not compile into a PE executable' }
& $sameNameExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'instances of same-named templates from different modules collided' }
$hostExecutablePath = Join-Path $testBuild 'host-memory-clock-selfhost.exe'
$hostExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\host-memory-clock.e') $repo 'x64' 'windows' $hostExecutablePath
if ($LASTEXITCODE -ne 0 -or $hostExecutableWritten -ne 'executable written') { throw 'Windows args, memory, or clock intrinsics did not link' }
$hostOutput = & $hostExecutablePath 'alpha' 'beta'
if ($LASTEXITCODE -ne 0 -or $hostOutput -ne 'host memory clock ok') { throw 'Windows args, memory, or clock intrinsic behavior failed' }
$ownCompilerPath = Join-Path $testBuild 'neper-own.exe'
& $compiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $ownCompilerPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ownCompilerPath)) { throw 'compiler-owned PE linker did not emit the compiler' }
# The arena dry (D546, H07): a compiler built with an arena of 96 MB cannot hold its own
# sources, and says so as the limit it is, under the query's header, exit 1 -- where it
# had said the operand cannot be read, or that name resolution failed.
$smallCompiler = Join-Path $testBuild 'neper-small.exe'
& $compiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $smallCompiler --arena 96m | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $smallCompiler)) { throw 'the compiler with a 96 MB arena did not build' }
$smallOut = & $smallCompiler check-file (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' --json 2>$null
if ($LASTEXITCODE -ne 1) { throw "the compiler with a 96 MB arena did not exit 1 over its own sources (got $LASTEXITCODE)" }
if ($smallOut.Count -ne 3 -or $smallOut[0] -notmatch '"record":"header","command":"check"' -or $smallOut[1] -notmatch '"code":"E-TYPE-9999","message":"resource limit: the compiler''s arena is exhausted' -or $smallOut[2] -notmatch '"exit_code":1') { throw "the compiler with a 96 MB arena did not name the limit under the header: $smallOut" }
$ownSelfTest = & $ownCompilerPath self-test
if ($LASTEXITCODE -ne 0 -or $ownSelfTest -ne 'selfhost lexer ok') { throw 'compiler-owned PE compiler self-test failed' }
$ownAdvancedPath = Join-Path $testBuild 'advanced-own.exe'
& $ownCompilerPath emit-executable (Join-Path $PSScriptRoot 'fixtures\link\advanced\src\main.e') $repo 'x64' 'windows' $ownAdvancedPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ownAdvancedPath)) { throw 'compiler-owned PE compiler did not emit the advanced fixture' }
& $ownAdvancedPath
if ($LASTEXITCODE -ne 0) { throw 'compiler-owned PE compiler emitted a failing advanced fixture' }
$ownOsHelperPath = Join-Path $testBuild 'os-spawn-helper-own.exe'
& $ownCompilerPath emit-executable (Join-Path $repo 'tests\neper0\os-spawn-helper.e') $repo 'x64' 'windows' $ownOsHelperPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ownOsHelperPath)) { throw 'compiler-owned PE compiler did not emit the OS spawn helper' }
$ownOsPath = Join-Path $testBuild 'os-intrinsics-own.exe'
& $ownCompilerPath emit-executable (Join-Path $repo 'tests\neper0\os-intrinsics.e') $repo 'x64' 'windows' $ownOsPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ownOsPath)) { throw 'compiler-owned PE compiler did not emit the OS intrinsic fixture' }
$ownOsFile = Join-Path $testBuild 'os-intrinsics-own.txt'
$ownOsOutput = & $ownOsPath $ownOsFile $testBuild $ownOsHelperPath
if ($LASTEXITCODE -ne 0 -or $ownOsOutput -ne 'intrinsic ok') { throw 'compiler-owned PE args, file, directory, memory, clock, process, or handle inheritance behavior failed' }
if ([IO.File]::ReadAllText($ownOsFile) -ne 'neper os!') { throw 'compiler-owned PE file write or append behavior failed' }
$stableCompilerPath = Join-Path $testBuild 'neper-own-stable.exe'
& $ownCompilerPath emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $stableCompilerPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stableCompilerPath)) { throw 'compiler-owned PE compiler did not emit its stable stage' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $ownCompilerPath).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'compiler-owned PE stages are not byte-for-byte deterministic' }
# `-j N` and `--perturb` (D331): the compiler built on one worker, and on three with
# the schedule turned around, is the stable stage byte for byte.
foreach ($jobsCase in @(@('-j', '1'), @('-j', '3', '--perturb'))) {
    $jobsPath = Join-Path $testBuild ('neper-own-jobs' + $jobsCase.Count + '.exe')
    & $ownCompilerPath emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $jobsPath @jobsCase | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $jobsPath)) { throw "the compiler did not build under $jobsCase" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $jobsPath).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw "the compiler built under $jobsCase is not the stable stage" }
}
# The deterministic half of the performance gate (D506, H25): the image and the workers'
# arena high-water of sc500k in both modes, built by the stable stage on eight workers,
# against the host's static baseline; a breach is a number a decision row has to name.
$staticMeasured = Join-Path $testBuild 'static-windows.json'
& python (Join-Path $repo 'benchmarks/baseline/static.py') --compiler $ownCompilerPath --repo $repo --host windows --out $staticMeasured --fixtures (Join-Path $testBuild 'baseline-fixtures')
if ($LASTEXITCODE -ne 0) { throw 'the static measurement of sc500k failed' }
& python (Join-Path $repo 'benchmarks/baseline/gate.py') $staticMeasured --baseline (Join-Path $repo 'benchmarks/baseline/results/static-windows.json')
if ($LASTEXITCODE -ne 0) { throw 'the static performance gate breached: re-pin benchmarks/baseline/results/static-windows.json in the decision that names why' }
# The formatted compiler (D525, H10): every module of the compiler through `fmt -` into a
# scratch tree, a compiler built from it, and the compiler it builds from the original
# sources is the stable stage byte for byte -- the formatter changed nothing that reaches
# the code, over sixty-five thousand lines.
$formattedSrc = Join-Path $testBuild 'formatted-src'
if (Test-Path -LiteralPath $formattedSrc) { Remove-Item -LiteralPath $formattedSrc -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $formattedSrc 'src') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'src') -File | ForEach-Object {
    if ($_.Extension -eq '.e') {
        cmd /c "`"$compiler`" fmt - < `"$($_.FullName)`" > `"$(Join-Path $formattedSrc "src\$($_.Name)")`""
        if ($LASTEXITCODE -ne 0) { throw "fmt of $($_.Name) failed" }
    } else {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $formattedSrc 'src')
    }
}
$formattedCompiler = Join-Path $testBuild 'neper-formatted.exe'
& $ownCompilerPath emit-executable (Join-Path $formattedSrc 'src\main.e') $repo 'x64' 'windows' $formattedCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $formattedCompiler)) { throw 'the compiler did not build from its formatted sources' }
$formattedBuilt = Join-Path $testBuild 'neper-by-formatted.exe'
& $formattedCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $formattedBuilt | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $formattedBuilt)) { throw 'the compiler built from formatted sources did not build the compiler' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $formattedBuilt).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler built from formatted sources does not build the stable stage' }
# The compiler without its comments (D526, H10): every comment of `src/` blanked to
# spaces through the token stream, and the compiler built from the result is the
# stable stage byte for byte -- comments are trivia over sixty-five thousand lines.
$blankedSrc = Join-Path $testBuild 'blanked-src'
& python (Join-Path $repo 'benchmarks/metamorphic/strip_comments.py') $compiler (Join-Path $repo 'src') (Join-Path $blankedSrc 'src')
if ($LASTEXITCODE -ne 0) { throw 'the comments of the compiler could not be blanked' }
$blankedCompiler = Join-Path $testBuild 'neper-blanked.exe'
& $ownCompilerPath emit-executable (Join-Path $blankedSrc 'src\main.e') $repo 'x64' 'windows' $blankedCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $blankedCompiler)) { throw 'the compiler did not build from its sources without comments' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $blankedCompiler).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler built without its comments is not the stable stage' }
# The compiler with its literals hoisted (D527, H03, H10): every typed integer literal of
# `src/` made a module constant, and the compiler built from the result is the stable
# stage byte for byte -- the proofs read a named constant as they read a literal.
$hoistedSrc = Join-Path $testBuild 'hoisted-src'
& python (Join-Path $repo 'benchmarks/metamorphic/hoist_constants.py') $compiler (Join-Path $repo 'src') (Join-Path $hoistedSrc 'src')
if ($LASTEXITCODE -ne 0) { throw 'the literals of the compiler could not be hoisted' }
$hoistedCompiler = Join-Path $testBuild 'neper-hoisted.exe'
& $ownCompilerPath emit-executable (Join-Path $hoistedSrc 'src\main.e') $repo 'x64' 'windows' $hoistedCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $hoistedCompiler)) { throw 'the compiler did not build from its sources with the literals hoisted' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $hoistedCompiler).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler built with its literals hoisted is not the stable stage' }
# The compiler with its locals renamed (D528, H10, H17): every local and parameter of
# `src/` renamed through the index, and the compiler built from the result is the
# stable stage byte for byte -- the index names every reference of a large module.
$renamedSrc = Join-Path $testBuild 'renamed-src'
& python (Join-Path $repo 'benchmarks/metamorphic/rename_locals.py') $compiler $repo (Join-Path $repo 'src') (Join-Path $renamedSrc 'src') windows
if ($LASTEXITCODE -ne 0) { throw 'the locals of the compiler could not be renamed' }
$renamedCompiler = Join-Path $testBuild 'neper-renamed.exe'
& $ownCompilerPath emit-executable (Join-Path $renamedSrc 'src\main.e') $repo 'x64' 'windows' $renamedCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $renamedCompiler)) { throw 'the compiler did not build from its sources with the locals renamed' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $renamedCompiler).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler built with its locals renamed is not the stable stage' }
# The compiler with its functions and types renamed (D529, D560, H10, H17): every function
# but `main` and every type of `src/` and `lib/` renamed through one cross-root index, and
# the compiler built from the result builds the original sources to the stable stage
# byte for byte -- its own names reach its own image and nothing else.
$resymbolledSrc = Join-Path $testBuild 'resymbolled-src'
& python (Join-Path $repo 'benchmarks/metamorphic/rename_symbols.py') $compiler $repo (Join-Path $repo 'src') (Join-Path $resymbolledSrc 'src') windows (Join-Path $repo 'lib') (Join-Path $resymbolledSrc 'lib')
if ($LASTEXITCODE -ne 0) { throw 'the symbols of the compiler could not be renamed' }
$resymbolledCompiler = Join-Path $testBuild 'neper-resymbolled.exe'
& $ownCompilerPath emit-executable (Join-Path $resymbolledSrc 'src\main.e') $resymbolledSrc 'x64' 'windows' $resymbolledCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $resymbolledCompiler)) { throw 'the compiler did not build from its sources with the symbols renamed' }
$byResymbolled = Join-Path $testBuild 'neper-by-resymbolled.exe'
& $resymbolledCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byResymbolled | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $byResymbolled)) { throw 'the compiler with renamed symbols did not build the compiler' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $byResymbolled).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler with renamed symbols does not build the stable stage' }
# The compiler with a conflict-free set of parameter lists reversed (D562, H10,
# H17): one checked query batch supplies the structured plans, apply-plan commits
# their twelve thousand edits together, and the result builds the stable stage.
$parameterSrc = Join-Path $testBuild 'parameter-src'
& python (Join-Path $repo 'benchmarks/metamorphic/reorder_parameters.py') $compiler $repo (Join-Path $repo 'src') (Join-Path $parameterSrc 'src') windows
if ($LASTEXITCODE -ne 0) { throw 'the parameters of the compiler could not be reordered' }
$parameterCompiler = Join-Path $testBuild 'neper-parameters.exe'
& $ownCompilerPath emit-executable (Join-Path $parameterSrc 'src\main.e') $repo 'x64' 'windows' $parameterCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $parameterCompiler)) { throw 'the compiler did not build from its sources with parameters reordered' }
$byParameters = Join-Path $testBuild 'neper-by-parameters.exe'
& $parameterCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byParameters | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $byParameters)) { throw 'the compiler with reordered parameters did not build the compiler' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $byParameters).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler with reordered parameters does not build the stable stage' }
# The compiler with every struct's fields reversed (D530, H10): another layout for
# every one of its records, and the compiler built from the result builds the original
# sources to the stable stage byte for byte -- nothing in it reads a struct by layout.
$reversedSrc = Join-Path $testBuild 'reversed-src'
& python (Join-Path $repo 'benchmarks/metamorphic/reverse_fields.py') $compiler (Join-Path $repo 'src') (Join-Path $reversedSrc 'src')
if ($LASTEXITCODE -ne 0) { throw 'the fields of the compiler could not be reversed' }
$reversedCompiler = Join-Path $testBuild 'neper-reversed.exe'
& $ownCompilerPath emit-executable (Join-Path $reversedSrc 'src\main.e') $repo 'x64' 'windows' $reversedCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $reversedCompiler)) { throw 'the compiler did not build from its sources with the fields reversed' }
$byReversed = Join-Path $testBuild 'neper-by-reversed.exe'
& $reversedCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byReversed | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $byReversed)) { throw 'the compiler with reversed fields did not build the compiler' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $byReversed).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler with reversed fields does not build the stable stage' }
# The compiler with its declarations reversed (D531, H10): every module's declarations
# in the opposite order, another layout of the compiler's own image, and it builds the
# original sources to the stable stage byte for byte.
$reorderedSrc = Join-Path $testBuild 'reordered-src'
& python (Join-Path $repo 'benchmarks/metamorphic/reorder_declarations.py') (Join-Path $repo 'src') (Join-Path $reorderedSrc 'src')
if ($LASTEXITCODE -ne 0) { throw 'the declarations of the compiler could not be reordered' }
$reorderedCompiler = Join-Path $testBuild 'neper-reordered.exe'
& $ownCompilerPath emit-executable (Join-Path $reorderedSrc 'src\main.e') $repo 'x64' 'windows' $reorderedCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $reorderedCompiler)) { throw 'the compiler did not build from its sources with the declarations reordered' }
$byReordered = Join-Path $testBuild 'neper-by-reordered.exe'
& $reorderedCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byReordered | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $byReordered)) { throw 'the compiler with reordered declarations did not build the compiler' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $byReordered).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler with reordered declarations does not build the stable stage' }
# The standard library turned too (D532, H10): a project of the compiler's sources as
# they are and `lib/` with every comment blanked, then with every literal hoisted, then
# with every local and parameter renamed (D550), built to the stable stage byte for
# byte -- the library reaches every image.
foreach ($libTurn in @(@('strip_comments.py', 'lib-blanked', @()), @('hoist_constants.py', 'lib-hoisted', @()), @('rename_locals.py', 'lib-renamed', @($repo)))) {
    $libProject = Join-Path $testBuild $libTurn[1]
    if (Test-Path -LiteralPath $libProject) { Remove-Item -LiteralPath $libProject -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $libProject | Out-Null
    Copy-Item -Recurse (Join-Path $repo 'src') (Join-Path $libProject 'src')
    & python (Join-Path $repo "benchmarks/metamorphic/$($libTurn[0])") $compiler @($libTurn[2]) (Join-Path $repo 'lib') (Join-Path $libProject 'lib')
    if ($LASTEXITCODE -ne 0) { throw "the library could not be turned by $($libTurn[0])" }
    $libCompiler = Join-Path $testBuild "neper-$($libTurn[1]).exe"
    & $ownCompilerPath emit-executable (Join-Path $libProject 'src\main.e') $libProject 'x64' 'windows' $libCompiler | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $libCompiler)) { throw "the compiler did not build against the library turned by $($libTurn[0])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $libCompiler).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw "the compiler built against the library turned by $($libTurn[0]) is not the stable stage" }
}
# The formatted library (D549, H10): every module of `lib/` through `fmt -` into a
# project of the compiler's sources, the compiler built against it, and the compiler
# that one builds from the original tree is the stable stage byte for byte -- the
# formatter moves lines, which reach the image as trap sites, so the turn is one on.
$formattedLib = Join-Path $testBuild 'lib-formatted'
if (Test-Path -LiteralPath $formattedLib) { Remove-Item -LiteralPath $formattedLib -Recurse -Force }
New-Item -ItemType Directory -Force -Path $formattedLib | Out-Null
Copy-Item -Recurse (Join-Path $repo 'src') (Join-Path $formattedLib 'src')
& python (Join-Path $repo 'benchmarks/metamorphic/format_tree.py') $compiler (Join-Path $repo 'lib') (Join-Path $formattedLib 'lib') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the library could not be formatted' }
$formattedLibCompiler = Join-Path $testBuild 'neper-lib-formatted.exe'
& $ownCompilerPath emit-executable (Join-Path $formattedLib 'src\main.e') $formattedLib 'x64' 'windows' $formattedLibCompiler | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $formattedLibCompiler)) { throw 'the compiler did not build against the formatted library' }
$byFormattedLib = Join-Path $testBuild 'neper-by-lib-formatted.exe'
& $formattedLibCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byFormattedLib | Out-Null
if ($LASTEXITCODE -ne 0 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $byFormattedLib).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw 'the compiler built against the formatted library does not build the stable stage' }
# The library's fields reversed and its declarations reordered (D551, H10): each turn
# in a project of the compiler's sources, the compiler built against it, and the
# compiler that one builds from the original tree is the stable stage -- one turn on,
# since a layout reaches the image. The foreign modules and `e.mem` keep their
# layouts: the other side of an `extern` and the embedded runtime read them.
foreach ($libOnTurn in @(@('reverse_fields.py', 'lib-fields', $true), @('reorder_declarations.py', 'lib-order', $false))) {
    $libOnProject = Join-Path $testBuild $libOnTurn[1]
    if (Test-Path -LiteralPath $libOnProject) { Remove-Item -LiteralPath $libOnProject -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $libOnProject | Out-Null
    Copy-Item -Recurse (Join-Path $repo 'src') (Join-Path $libOnProject 'src')
    if ($libOnTurn[2]) {
        & python (Join-Path $repo "benchmarks/metamorphic/$($libOnTurn[0])") $compiler (Join-Path $repo 'lib') (Join-Path $libOnProject 'lib') | Out-Null
    } else {
        & python (Join-Path $repo "benchmarks/metamorphic/$($libOnTurn[0])") (Join-Path $repo 'lib') (Join-Path $libOnProject 'lib') | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "the library could not be turned by $($libOnTurn[0])" }
    $libOnCompiler = Join-Path $testBuild "neper-$($libOnTurn[1]).exe"
    & $ownCompilerPath emit-executable (Join-Path $libOnProject 'src\main.e') $libOnProject 'x64' 'windows' $libOnCompiler | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $libOnCompiler)) { throw "the compiler did not build against the library turned by $($libOnTurn[0])" }
    $byLibOn = Join-Path $testBuild "neper-by-$($libOnTurn[1]).exe"
    & $libOnCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byLibOn | Out-Null
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $byLibOn).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw "the compiler built against the library turned by $($libOnTurn[0]) does not build the stable stage" }
}
# The turns in release (D533, H10): the release self-build is the release stable
# stage, built twice byte for byte; the trees whose image holds -- blanked, hoisted,
# locals renamed -- build the same release image; the compilers of the other turns
# and of the library's build the release stable stage.
$releaseStable = Join-Path $testBuild 'neper-own-release.exe'
& $ownCompilerPath emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $releaseStable --release | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $releaseStable)) { throw 'the release self-build failed' }
$releaseAgain = Join-Path $testBuild 'neper-own-release-again.exe'
& $ownCompilerPath emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $releaseAgain --release | Out-Null
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $releaseAgain).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseStable).Hash) { throw 'the release self-build is not byte-for-byte deterministic' }
foreach ($releaseTree in @($blankedSrc, $hoistedSrc, $renamedSrc)) {
    $releaseTurn = Join-Path $testBuild ("neper-release-" + (Split-Path -Leaf $releaseTree) + '.exe')
    & $ownCompilerPath emit-executable (Join-Path $releaseTree 'src\main.e') $repo 'x64' 'windows' $releaseTurn --release | Out-Null
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseTurn).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseStable).Hash) { throw "the release build of $(Split-Path -Leaf $releaseTree) is not the release stable stage" }
}
foreach ($turnCompiler in @($formattedCompiler, $resymbolledCompiler, $parameterCompiler, $reversedCompiler, $reorderedCompiler)) {
    $releaseBy = Join-Path $testBuild ('release-by-' + (Split-Path -Leaf $turnCompiler))
    & $turnCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $releaseBy --release | Out-Null
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseBy).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseStable).Hash) { throw "$(Split-Path -Leaf $turnCompiler) does not build the release stable stage" }
}
foreach ($libTurn in @('lib-blanked', 'lib-hoisted')) {
    $libRelease = Join-Path $testBuild "neper-$libTurn-release.exe"
    & $ownCompilerPath emit-executable (Join-Path $testBuild "$libTurn\src\main.e") (Join-Path $testBuild $libTurn) 'x64' 'windows' $libRelease --release | Out-Null
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $libRelease).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseStable).Hash) { throw "the release build against $libTurn is not the release stable stage" }
}
# The warm path under the turns (D534, H14): a project of the compiler's sources
# built cold with artifacts, then every module replaced by its blanked text -- every
# module kept `stable` and the image the cold build's -- then one module by its
# hoisted text and one by its locals-renamed text -- that module rebuilt, the rest
# kept, the image the cold build's each time.
$warmProject = Join-Path $testBuild 'warm-turns'
if (Test-Path -LiteralPath $warmProject) { Remove-Item -LiteralPath $warmProject -Recurse -Force }
New-Item -ItemType Directory -Force -Path $warmProject | Out-Null
Copy-Item -Recurse (Join-Path $repo 'src') (Join-Path $warmProject 'src')
$warmExe = Join-Path $testBuild 'neper-warm-turns.exe'
$warmCold = Join-Path $testBuild 'neper-warm-turns-cold.exe'
$warmManifest = Join-Path $warmProject '.neper\debug\build-manifest.json'
& $ownCompilerPath emit-executable (Join-Path $warmProject 'src\main.e') $repo 'x64' 'windows' $warmCold --incremental | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the cold build of the compiler with artifacts failed' }
Copy-Item (Join-Path $blankedSrc 'src\*.e') (Join-Path $warmProject 'src')
& $ownCompilerPath emit-executable (Join-Path $warmProject 'src\main.e') $repo 'x64' 'windows' $warmExe --incremental | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the warm build of the compiler after blanking every comment failed' }
$warmDecisions = (Get-Content -Raw -LiteralPath $warmManifest | ConvertFrom-Json).incremental
if (($warmDecisions | Where-Object { $_.reason -ne 'stable' }).Count -ne 0) { throw 'a warm build after blanking every comment of the compiler rebuilt a module' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $warmExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $warmCold).Hash) { throw 'the warm build after blanking every comment is not the cold build' }
Copy-Item (Join-Path $hoistedSrc 'src\lex.e') (Join-Path $warmProject 'src\lex.e')
& $ownCompilerPath emit-executable (Join-Path $warmProject 'src\main.e') $repo 'x64' 'windows' $warmExe --incremental | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the warm build of the compiler after hoisting one module failed' }
& python (Join-Path $repo 'scripts/check_incremental.py') $warmManifest 'lex=rebuilt:source-changed' 'check=kept:edges-hold' 'main=kept:edges-hold' 'binary=kept:stable'
if ($LASTEXITCODE -ne 0) { throw 'the warm build after hoisting one module did not keep the rest' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $warmExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $warmCold).Hash) { throw 'the warm build after hoisting one module is not the cold build' }
Copy-Item (Join-Path $renamedSrc 'src\check.e') (Join-Path $warmProject 'src\check.e')
& $ownCompilerPath emit-executable (Join-Path $warmProject 'src\main.e') $repo 'x64' 'windows' $warmExe --incremental | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the warm build of the compiler after renaming one module''s locals failed' }
& python (Join-Path $repo 'scripts/check_incremental.py') $warmManifest 'check=rebuilt:source-changed' 'lex=kept:stable' 'main=kept:edges-hold'
if ($LASTEXITCODE -ne 0) { throw 'the warm build after renaming one module''s locals did not keep the rest' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $warmExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $warmCold).Hash) { throw 'the warm build after renaming one module''s locals is not the cold build' }
# The warm path under the turns in release (D536, H14): the same three edits over a
# cold release build with artifacts; a module that inlines from the edited one is
# rebuilt by its body edge, and the image is the cold release build's each time.
$warmRelease = Join-Path $testBuild 'warm-turns-release'
if (Test-Path -LiteralPath $warmRelease) { Remove-Item -LiteralPath $warmRelease -Recurse -Force }
New-Item -ItemType Directory -Force -Path $warmRelease | Out-Null
Copy-Item -Recurse (Join-Path $repo 'src') (Join-Path $warmRelease 'src')
$warmReleaseExe = Join-Path $testBuild 'neper-warm-release.exe'
$warmReleaseCold = Join-Path $testBuild 'neper-warm-release-cold.exe'
$warmReleaseManifest = Join-Path $warmRelease '.neper\release\build-manifest.json'
& $ownCompilerPath emit-executable (Join-Path $warmRelease 'src\main.e') $repo 'x64' 'windows' $warmReleaseCold --release --incremental | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the cold release build of the compiler with artifacts failed' }
Copy-Item (Join-Path $blankedSrc 'src\*.e') (Join-Path $warmRelease 'src')
& $ownCompilerPath emit-executable (Join-Path $warmRelease 'src\main.e') $repo 'x64' 'windows' $warmReleaseExe --release --incremental | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'the warm release build after blanking every comment failed' }
if (((Get-Content -Raw -LiteralPath $warmReleaseManifest | ConvertFrom-Json).incremental | Where-Object { $_.reason -ne 'stable' }).Count -ne 0) { throw 'a warm release build after blanking every comment rebuilt a module' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $warmReleaseExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $warmReleaseCold).Hash) { throw 'the warm release build after blanking every comment is not the cold build' }
Copy-Item (Join-Path $hoistedSrc 'src\lex.e') (Join-Path $warmRelease 'src\lex.e')
& $ownCompilerPath emit-executable (Join-Path $warmRelease 'src\main.e') $repo 'x64' 'windows' $warmReleaseExe --release --incremental | Out-Null
& python (Join-Path $repo 'scripts/check_incremental.py') $warmReleaseManifest 'lex=rebuilt:source-changed' 'binary=kept:stable'
if ($LASTEXITCODE -ne 0) { throw 'the warm release build after hoisting one module did not rebuild it alone' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $warmReleaseExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $warmReleaseCold).Hash) { throw 'the warm release build after hoisting one module is not the cold build' }
Copy-Item (Join-Path $renamedSrc 'src\check.e') (Join-Path $warmRelease 'src\check.e')
& $ownCompilerPath emit-executable (Join-Path $warmRelease 'src\main.e') $repo 'x64' 'windows' $warmReleaseExe --release --incremental | Out-Null
& python (Join-Path $repo 'scripts/check_incremental.py') $warmReleaseManifest 'check=rebuilt:source-changed' 'lex=kept:stable'
if ($LASTEXITCODE -ne 0) { throw 'the warm release build after renaming one module''s locals did not rebuild it' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $warmReleaseExe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $warmReleaseCold).Hash) { throw 'the warm release build after renaming one module''s locals is not the cold build' }
# The plans over the compiler (D537, H17, H29): `check.same`, called at five hundred
# and forty sites in thirteen modules, and the type `check.Type`, referenced at
# nearly four hundred, each renamed by its plan applied to a project of the sources,
# and the compiler built from the result builds the stable stage byte for byte.
# And the signature plans (D538): `check.same`'s parameters in the other order at every
# call, then a parameter added with an argument at every call; the same test.
foreach ($planTurn in @(@('plan-rename-file', '--symbol check.same --to alike', 'plan-fn'), @('plan-rename-file', '--symbol check.Type --to Kind2', 'plan-type'), @('plan-change-signature-file', '--symbol check.same --order 1,0', 'plan-order'), @('plan-add-parameter-file', '--symbol check.same --parameter "extra: usize" --argument 0usize', 'plan-add'))) {
    $planProject = Join-Path $testBuild $planTurn[2]
    if (Test-Path -LiteralPath $planProject) { Remove-Item -LiteralPath $planProject -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $planProject | Out-Null
    Copy-Item -Recurse (Join-Path $repo 'src') (Join-Path $planProject 'src')
    $planTurnFile = Join-Path $testBuild "$($planTurn[2]).jsonl"
    cmd /c "cd /d `"$planProject`" && `"$compiler`" $($planTurn[0]) src/main.e `"$repo`" x64 windows --json $($planTurn[1]) > `"$planTurnFile`""
    if ($LASTEXITCODE -ne 0) { throw "the plan $($planTurn[2]) over the compiler failed" }
    & $compiler apply-plan $planTurnFile --root (Join-Path $planProject 'src') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "the plan $($planTurn[2]) over the compiler did not apply" }
    $planCompiler = Join-Path $testBuild "neper-$($planTurn[2]).exe"
    & $ownCompilerPath emit-executable (Join-Path $planProject 'src\main.e') $repo 'x64' 'windows' $planCompiler | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $planCompiler)) { throw "the compiler did not build after the plan $($planTurn[2])" }
    $byPlan = Join-Path $testBuild "neper-by-$($planTurn[2]).exe"
    & $planCompiler emit-executable (Join-Path $repo 'src\main.e') $repo 'x64' 'windows' $byPlan | Out-Null
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $byPlan).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $stableCompilerPath).Hash) { throw "the compiler changed by the plan $($planTurn[2]) does not build the stable stage" }
}
# The deadline inside a function (D540, H16): a function of eight thousand statements,
# and `--fault-cancel N` passing the deadline at the Nth statement -- inside its check
# at 4096, inside its lowering at 12288 -- each exit 3 with the place named, no image.
$longFunction = Join-Path $testBuild 'long-function.e'
& python -c "lines=['use e.os','','fn main() -> err {','    var x = 0usize']+['    x = x + 1usize']*8000+['    os.exit(i32(x % 200usize))','    ret ok','}']; open(r'$longFunction','w',newline='\n').write('\n'.join(lines)+'\n')"
$longExe = Join-Path $testBuild 'long-function.exe'
$longBuilt = & $compiler emit-executable $longFunction $repo 'x64' 'windows' $longExe 2>&1
if ($LASTEXITCODE -ne 0 -or $longBuilt -ne 'executable written') { throw "the function of eight thousand statements did not build: $longBuilt" }
foreach ($cancelCase in @(@(4096, 'the body sweep, inside a function'), @(12288, 'lowering, inside a function'))) {
    if (Test-Path -LiteralPath $longExe) { Remove-Item -LiteralPath $longExe -Force }
    $cancelOut = & $compiler emit-executable $longFunction $repo 'x64' 'windows' $longExe --fault-cancel $cancelCase[0] --json 2>$null
    if ($LASTEXITCODE -ne 3) { throw "a deadline at statement $($cancelCase[0]) did not cancel the build with exit 3 (got $LASTEXITCODE)" }
    if (($cancelOut -join "`n") -notmatch [regex]::Escape("`"cancelled_after`":`"$($cancelCase[1])`"")) { throw "a deadline at statement $($cancelCase[0]) was not reported as $($cancelCase[1])" }
    if (Test-Path -LiteralPath $longExe) { throw 'a build cancelled inside a function wrote an image' }
}
# The buffers grow to the function (D541, H14): thirty thousand and seven statements
# in one function -- past the link's row scratch and the writer's code scratch --
# build, and the image answers the arithmetic.
$longerFunction = Join-Path $testBuild 'longer-function.e'
& python -c "lines=['use e.os','','fn main() -> err {','    var x = 0usize']+['    x = x + 1usize']*30007+['    os.exit(i32(x % 200usize))','    ret ok','}']; open(r'$longerFunction','w',newline='\n').write('\n'.join(lines)+'\n')"
$longerExe = Join-Path $testBuild 'longer-function.exe'
$longerBuilt = & $compiler emit-executable $longerFunction $repo 'x64' 'windows' $longerExe 2>&1
if ($LASTEXITCODE -ne 0 -or $longerBuilt -ne 'executable written') { throw "the function of thirty thousand statements did not build: $longerBuilt" }
& $longerExe
if ($LASTEXITCODE -ne 7) { throw "the function of thirty thousand statements answered $LASTEXITCODE, not 7" }
$branchesLowered = & $compiler nir-file (Join-Path $PSScriptRoot 'fixtures\nir\branches\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $branchesLowered -ne 'module nir ok') { throw 'if branches and fallthrough merges did not lower to canonical NIR' }
$branchesGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\branches\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $branchesGenerated -ne 'module codegen ok') { throw 'conditional branches did not select and patch x64 control flow' }
$loopsLowered = & $compiler nir-file (Join-Path $PSScriptRoot 'fixtures\nir\loops\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $loopsLowered -ne 'module nir ok') { throw 'while condition and back-edge did not lower to canonical NIR' }
$loopsGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\loops\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $loopsGenerated -ne 'module codegen ok') { throw 'while back-edges did not select and patch x64 control flow' }
$controlExecutablePath = Join-Path $testBuild 'control-selfhost.exe'
$controlExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\control\src\main.e') $repo 'x64' 'windows' $controlExecutablePath
if ($LASTEXITCODE -ne 0 -or $controlExecutableWritten -ne 'executable written') { throw 'control-flow PE executable emission failed' }
& $controlExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'branches, loops, short-circuit logic, or direct calls failed in the self-hosted PE executable' }
# `else if` (D245): the grammar's chained form, lowered as the nested if it is.
$elseIfExecutablePath = Join-Path $testBuild 'else-if-selfhost.exe'
$elseIfExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\else_if\src\main.e') $repo 'x64' 'windows' $elseIfExecutablePath
if ($LASTEXITCODE -ne 0 -or $elseIfExecutableWritten -ne 'executable written') { throw 'else-if PE executable emission failed' }
& $elseIfExecutablePath
if ($LASTEXITCODE -ne 0) { throw "else-if chains failed check $LASTEXITCODE in the self-hosted PE executable" }
# `ret (expr) op y` (D247): a grouped return value that carries a binary operator.
$retGroupExecutablePath = Join-Path $testBuild 'ret-group-selfhost.exe'
$retGroupExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/ret_group/src/main.e') $repo 'x64' 'windows' $retGroupExecutablePath
if ($LASTEXITCODE -ne 0 -or $retGroupExecutableWritten -ne 'executable written') { throw 'ret-group PE executable emission failed' }
& $retGroupExecutablePath
if ($LASTEXITCODE -ne 0) { throw "grouped return expressions failed check $LASTEXITCODE in the self-hosted PE executable" }
# `e.math.fixed` (D267): Q16.16 arithmetic and angles in turns.
$mathFixedExecutablePath = Join-Path $testBuild 'math-fixed-selfhost.exe'
$mathFixedExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/math_fixed/src/main.e') $repo 'x64' 'windows' $mathFixedExecutablePath
if ($LASTEXITCODE -ne 0 -or $mathFixedExecutableWritten -ne 'executable written') { throw 'math.fixed PE executable emission failed' }
& $mathFixedExecutablePath
if ($LASTEXITCODE -ne 0) { throw "e.math.fixed failed check $LASTEXITCODE in the self-hosted PE executable" }
# `e.game.loop` and `e.game.ecs` (D268): the fixed step and the entity store.
$gameCoreExecutablePath = Join-Path $testBuild 'game-core-selfhost.exe'
$gameCoreExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_core/src/main.e') $repo 'x64' 'windows' $gameCoreExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameCoreExecutableWritten -ne 'executable written') { throw 'game core PE executable emission failed' }
& $gameCoreExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.game.loop or e.game.ecs failed a check in the self-hosted PE executable' }
# `e.game.grid` and `e.game.tilemap` (D270): coordinates and layered tile grids.
$gameGridExecutablePath = Join-Path $testBuild 'game-grid-selfhost.exe'
$gameGridExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_grid/src/main.e') $repo 'x64' 'windows' $gameGridExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameGridExecutableWritten -ne 'executable written') { throw 'game grid PE executable emission failed' }
& $gameGridExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.game.grid or e.game.tilemap failed a check in the self-hosted PE executable' }
# `e.game.collide2d` and `e.game.vision` (D272): swept boxes and shadowcast fog.
$gameSightExecutablePath = Join-Path $testBuild 'game-sight-selfhost.exe'
$gameSightExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_sight/src/main.e') $repo 'x64' 'windows' $gameSightExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameSightExecutableWritten -ne 'executable written') { throw 'game sight PE executable emission failed' }
& $gameSightExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.game.collide2d or e.game.vision failed a check in the self-hosted PE executable' }
# `e.game.dialog` and `e.game.particle` (D279): branching conversation and particle pools.
$gameStoryExecutablePath = Join-Path $testBuild 'game-story-selfhost.exe'
$gameStoryExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_story/src/main.e') $repo 'x64' 'windows' $gameStoryExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameStoryExecutableWritten -ne 'executable written') { throw 'game story PE executable emission failed' }
& $gameStoryExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.game.dialog or e.game.particle failed a check in the self-hosted PE executable' }
# `e.game.sprite` and `e.game.camera` (D282): clip playback and the ordered draw list.
$gameViewExecutablePath = Join-Path $testBuild 'game-view-selfhost.exe'
$gameViewExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_view/src/main.e') $repo 'x64' 'windows' $gameViewExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameViewExecutableWritten -ne 'executable written') { throw 'game view PE executable emission failed' }
& $gameViewExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.game.sprite or e.game.camera failed a check in the self-hosted PE executable' }
# `e.game.ai` and `e.game.input` (D289): steering, behaviour trees, A* and input buffering.
$gameMindExecutablePath = Join-Path $testBuild 'game-mind-selfhost.exe'
$gameMindExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_mind/src/main.e') $repo 'x64' 'windows' $gameMindExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameMindExecutableWritten -ne 'executable written') { throw 'game mind PE executable emission failed' }
& $gameMindExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.game.ai or e.game.input failed a check in the self-hosted PE executable' }
# `e.net.snapshot` and `e.game.netsync` (D296): quantised deltas, prediction and rollback.
$gameNetExecutablePath = Join-Path $testBuild 'game-net-selfhost.exe'
$gameNetExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures/link/game_net/src/main.e') $repo 'x64' 'windows' $gameNetExecutablePath
if ($LASTEXITCODE -ne 0 -or $gameNetExecutableWritten -ne 'executable written') { throw 'game net PE executable emission failed' }
& $gameNetExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'e.net.snapshot or e.game.netsync failed a check in the self-hosted PE executable' }
$moduleExecutablePath = Join-Path $testBuild 'modules-selfhost.exe'
$moduleExecutableWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\modules\src\main.e') $repo 'x64' 'windows' $moduleExecutablePath
if ($LASTEXITCODE -ne 0 -or $moduleExecutableWritten -ne 'executable written') { throw 'multi-module PE executable emission failed' }
& $moduleExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'cross-module calls failed in the self-hosted PE executable' }
$collisionExecutablePath = Join-Path $testBuild 'error-collision-selfhost.exe'
$collisionOutput = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\error_collision\src\main.e') $repo 'x64' 'windows' $collisionExecutablePath 2>&1
$collisionExit = $LASTEXITCODE
if ($collisionExit -ne 1 -or ($collisionOutput -join "`n") -notmatch 'main\.E49B7D00B' -or ($collisionOutput -join "`n") -notmatch 'main\.E9E692E7E') { throw 'error hash collision was not rejected with both qualified names' }
if (Test-Path -LiteralPath $collisionExecutablePath) { throw 'error hash collision wrote an executable before rejection' }
$moduleArtifactPath = Join-Path $testBuild 'modules.x64-windows.em'
$moduleArtifactCopyPath = Join-Path $testBuild 'modules-copy.x64-windows.em'
$moduleArtifactWritten = & $compiler emit-em (Join-Path $PSScriptRoot 'fixtures\link\modules\src\main.e') $repo 'x64' 'windows' $moduleArtifactPath
if ($LASTEXITCODE -ne 0 -or $moduleArtifactWritten -ne 'compiled module written') { throw 'compiled-module emission failed' }
$moduleArtifactCopyWritten = & $compiler emit-em (Join-Path $PSScriptRoot 'fixtures\link\modules\src\main.e') $repo 'x64' 'windows' $moduleArtifactCopyPath
if ($LASTEXITCODE -ne 0 -or $moduleArtifactCopyWritten -ne 'compiled module written') { throw 'repeated compiled-module emission failed' }
$moduleArtifactHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $moduleArtifactPath).Hash
$moduleArtifactCopyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $moduleArtifactCopyPath).Hash
if ($moduleArtifactHash -ne $moduleArtifactCopyHash) { throw 'compiled-module output is not deterministic' }
$moduleArtifactBytes = [IO.File]::ReadAllBytes($moduleArtifactPath)
if ($moduleArtifactBytes.Length -lt 104 -or [Text.Encoding]::ASCII.GetString($moduleArtifactBytes[0..3]) -ne 'NEPM') { throw 'compiled-module header is invalid' }
if ([BitConverter]::ToUInt16($moduleArtifactBytes, 4) -ne 14 -or [BitConverter]::ToUInt16($moduleArtifactBytes, 6) -ne 32) { throw 'compiled-module version or header size is invalid' }
if ([BitConverter]::ToUInt32($moduleArtifactBytes, 20) -ne 9) { throw 'compiled-module section count is invalid' }
if ([BitConverter]::ToUInt64($moduleArtifactBytes, 96) -le 4) { throw 'compiled-module omitted its foreign signature dependency' }
$interfaceArtifactPath = Join-Path $testBuild 'interface.x64-windows.em'
$interfaceArtifactWritten = & $compiler emit-em (Join-Path $PSScriptRoot 'fixtures\em\interface\src\main.e') $repo 'x64' 'windows' $interfaceArtifactPath
if ($LASTEXITCODE -ne 0 -or $interfaceArtifactWritten -ne 'compiled module written') { throw 'full interface artifact emission failed' }
$interfaceArtifactBytes = [IO.File]::ReadAllBytes($interfaceArtifactPath)
$interfaceOffset = [BitConverter]::ToUInt64($interfaceArtifactBytes, 64)
if ([BitConverter]::ToUInt32($interfaceArtifactBytes, [int]$interfaceOffset + 8) -ne 6) { throw 'compiled-module interface omitted a declaration kind' }
if ([BitConverter]::ToUInt64($interfaceArtifactBytes, [int]$interfaceOffset + 28) -eq 0) { throw 'compiled-module function signature hash is zero' }
$hashModuleArtifacts = Join-Path $testBuild 'hash-module'
New-Item -ItemType Directory -Force -Path $hashModuleArtifacts | Out-Null
$hashModuleArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\hash_module\src\main.e') $repo 'x64' 'windows' $hashModuleArtifacts
if ($LASTEXITCODE -ne 0 -or $hashModuleArtifactsWritten -ne 'compiled modules written') { throw 'void-return hash-module artifact emission failed' }
$hashModuleRootPath = Join-Path $hashModuleArtifacts 'main.x64-windows.em'
$hashModuleLibraryPath = Join-Path $hashModuleArtifacts 'e.algo.hash.x64-windows.em'
if (-not (Test-Path -LiteralPath $hashModuleRootPath) -or -not (Test-Path -LiteralPath $hashModuleLibraryPath)) { throw 'hash-module artifact set is incomplete' }
$hashModuleValidation = & $compiler validate-em $hashModuleRootPath
if ($LASTEXITCODE -ne 0 -or $hashModuleValidation -ne 'compiled module valid') { throw 'void-return root artifact is invalid' }
$hashModuleLibraryBytes = [IO.File]::ReadAllBytes($hashModuleLibraryPath)
$hashModuleInterfaceOffset = [BitConverter]::ToUInt64($hashModuleLibraryBytes, 64)
if ([BitConverter]::ToUInt32($hashModuleLibraryBytes, [int]$hashModuleInterfaceOffset + 8) -ne 13) { throw 'e.algo.hash artifact interface is incomplete' }
$hashRuntimeArtifacts = Join-Path $testBuild 'hash-runtime'
New-Item -ItemType Directory -Force -Path $hashRuntimeArtifacts | Out-Null
$hashRuntimeArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\algo_hash\src\main.e') $repo 'x64' 'windows' $hashRuntimeArtifacts
if ($LASTEXITCODE -ne 0 -or $hashRuntimeArtifactsWritten -ne 'compiled modules written') { throw 'runtime-backed hash artifact emission failed' }
foreach ($artifactName in @('main', 'e.algo.hash', 'e.io', 'e.mem', 'e.os')) {
    $artifactPath = Join-Path $hashRuntimeArtifacts ($artifactName + '.x64-windows.em')
    if (-not (Test-Path -LiteralPath $artifactPath)) { throw "runtime-backed hash artifact set omitted $artifactName" }
    $artifactValidation = & $compiler validate-em $artifactPath
    if ($LASTEXITCODE -ne 0 -or $artifactValidation -ne 'compiled module valid') { throw "runtime-backed hash artifact is invalid: $artifactName" }
}
$hostDependencyArtifacts = Join-Path $testBuild 'host-dependency'
New-Item -ItemType Directory -Force -Path $hostDependencyArtifacts | Out-Null
$hostDependencyArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\host_dependency\src\main.e') $repo 'x64' 'windows' $hostDependencyArtifacts
if ($LASTEXITCODE -ne 0 -or $hostDependencyArtifactsWritten -ne 'compiled modules written') { throw 'host-intrinsic dependency artifact emission failed' }
$runtimeHostEdge = & $compiler check-em-edge (Join-Path $hostDependencyArtifacts 'main.x64-windows.em') (Join-Path $hostDependencyArtifacts 'e.os.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $runtimeHostEdge -ne 'dependency current') { throw 'lowered host intrinsic did not retain its source-level dependency edge' }
$allArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\link\modules\src\main.e') $repo 'x64' 'windows' $testBuild
if ($LASTEXITCODE -ne 0 -or $allArtifactsWritten -ne 'compiled modules written') { throw 'per-module artifact emission failed' }
$rootModuleArtifactPath = Join-Path $testBuild 'main.x64-windows.em'
$dependencyModuleArtifactPath = Join-Path $testBuild 'dep.x64-windows.em'
if (-not (Test-Path -LiteralPath $rootModuleArtifactPath) -or -not (Test-Path -LiteralPath $dependencyModuleArtifactPath)) { throw 'per-module artifact set is incomplete' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $rootModuleArtifactPath).Hash -ne $moduleArtifactHash) { throw 'root artifact changed when emitted with its dependency set' }
$validatedArtifact = & $compiler validate-em $rootModuleArtifactPath
if ($LASTEXITCODE -ne 0 -or $validatedArtifact -ne 'compiled module valid') { throw 'packed compiled-module validation failed' }
$legacyValueAbiArtifact = Join-Path $testBuild 'main.value-abi-v0.x64-windows.em'
Copy-Item -LiteralPath $rootModuleArtifactPath -Destination $legacyValueAbiArtifact -Force
$legacyValueAbiBytes = [IO.File]::ReadAllBytes($legacyValueAbiArtifact)
$legacyValueAbiBytes[4] = 10
$legacyValueAbiBytes[5] = 0
[IO.File]::WriteAllBytes($legacyValueAbiArtifact, $legacyValueAbiBytes)
$legacyValueAbiOutput = & $compiler validate-em $legacyValueAbiArtifact 2>&1
if ($LASTEXITCODE -ne 1 -or ($legacyValueAbiOutput -join "`n") -notmatch 'UnsupportedVersion') { throw 'the pre-snapshot value ABI artifact was not rejected' }
$artifactExecutablePath = Join-Path $testBuild 'modules-from-artifacts.exe'
$artifactExecutableWritten = & $compiler link-em $artifactExecutablePath $rootModuleArtifactPath $dependencyModuleArtifactPath
if ($LASTEXITCODE -ne 0 -or $artifactExecutableWritten -ne 'artifact executable written') { throw 'PE executable link from compiled modules failed' }
& $artifactExecutablePath
if ($LASTEXITCODE -ne 0) { throw 'PE executable linked from compiled modules did not run' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $artifactExecutablePath).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $moduleExecutablePath).Hash) { throw 'compiled-module and clean-source PE links differ' }
$currentEdge = & $compiler check-em-edge $rootModuleArtifactPath $dependencyModuleArtifactPath
if ($LASTEXITCODE -ne 0 -or $currentEdge -ne 'dependency current') { throw 'matching compiled-module dependency was rejected' }
$mergedErrorTables = & $compiler check-em-errors $rootModuleArtifactPath $dependencyModuleArtifactPath
if ($LASTEXITCODE -ne 0 -or $mergedErrorTables -ne 'error tables merged') { throw 'compatible compiled-module error tables were rejected' }
$collisionArtifacts = Join-Path $testBuild 'error-collision'
New-Item -ItemType Directory -Force -Path $collisionArtifacts | Out-Null
$collisionArtifactsWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\error_collision\src\main.e') $repo 'x64' 'windows' $collisionArtifacts
if ($LASTEXITCODE -ne 0 -or $collisionArtifactsWritten -ne 'compiled modules written') { throw 'colliding error-table artifacts could not be emitted independently' }
$artifactCollisionOutput = & $compiler check-em-errors (Join-Path $collisionArtifacts 'main.x64-windows.em') (Join-Path $collisionArtifacts 'dep.x64-windows.em') 2>&1
$artifactCollisionExit = $LASTEXITCODE
if ($artifactCollisionExit -ne 1 -or ($artifactCollisionOutput -join "`n") -notmatch 'main\.E08DED258' -or ($artifactCollisionOutput -join "`n") -notmatch 'dep\.E29EBB918') { throw 'compiled-module error table collision was not rejected with both qualified names' }
$artifactCollisionExecutable = Join-Path $collisionArtifacts 'collision.exe'
$artifactLinkCollisionOutput = & $compiler link-em $artifactCollisionExecutable (Join-Path $collisionArtifacts 'main.x64-windows.em') (Join-Path $collisionArtifacts 'dep.x64-windows.em') 2>&1
if ($LASTEXITCODE -ne 1 -or ($artifactLinkCollisionOutput -join "`n") -notmatch 'main\.E08DED258' -or (Test-Path -LiteralPath $artifactCollisionExecutable)) { throw 'artifact linker did not reject an error collision before writing output' }
$bodyEditArtifacts = Join-Path $testBuild 'body-edit'
$signatureEditArtifacts = Join-Path $testBuild 'signature-edit'
New-Item -ItemType Directory -Force -Path $bodyEditArtifacts, $signatureEditArtifacts | Out-Null
$bodyEditWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\body_edit\src\main.e') $repo 'x64' 'windows' $bodyEditArtifacts
if ($LASTEXITCODE -ne 0 -or $bodyEditWritten -ne 'compiled modules written') { throw 'body-edit artifact emission failed' }
$signatureEditWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\signature_edit\src\main.e') $repo 'x64' 'windows' $signatureEditArtifacts
if ($LASTEXITCODE -ne 0 -or $signatureEditWritten -ne 'compiled modules written') { throw 'signature-edit artifact emission failed' }
$bodyEdge = & $compiler check-em-edge $rootModuleArtifactPath (Join-Path $bodyEditArtifacts 'dep.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $bodyEdge -ne 'dependency current') { throw 'signature-only dependency was invalidated by a body edit' }
$signatureEdge = & $compiler check-em-edge $rootModuleArtifactPath (Join-Path $signatureEditArtifacts 'dep.x64-windows.em') 2>&1
if ($LASTEXITCODE -ne 1 -or ($signatureEdge -join "`n") -notmatch 'dependency stale') { throw 'signature dependency was not invalidated by a signature edit' }
$valueBaseArtifacts = Join-Path $testBuild 'value-base'
$valueEditArtifacts = Join-Path $testBuild 'value-edit'
New-Item -ItemType Directory -Force -Path $valueBaseArtifacts, $valueEditArtifacts | Out-Null
$valueBaseWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\value_base\src\main.e') $repo 'x64' 'windows' $valueBaseArtifacts
if ($LASTEXITCODE -ne 0 -or $valueBaseWritten -ne 'compiled modules written') { throw 'constant-value base artifact emission failed' }
$valueEditWritten = & $compiler emit-em-all (Join-Path $PSScriptRoot 'fixtures\em\value_edit\src\main.e') $repo 'x64' 'windows' $valueEditArtifacts
if ($LASTEXITCODE -ne 0 -or $valueEditWritten -ne 'compiled modules written') { throw 'constant-value edit artifact emission failed' }
$currentValueEdge = & $compiler check-em-edge (Join-Path $valueBaseArtifacts 'main.x64-windows.em') (Join-Path $valueBaseArtifacts 'dep.x64-windows.em')
if ($LASTEXITCODE -ne 0 -or $currentValueEdge -ne 'dependency current') { throw 'matching constant value dependency was rejected' }
$staleValueEdge = & $compiler check-em-edge (Join-Path $valueBaseArtifacts 'main.x64-windows.em') (Join-Path $valueEditArtifacts 'dep.x64-windows.em') 2>&1
if ($LASTEXITCODE -ne 1 -or ($staleValueEdge -join "`n") -notmatch 'dependency stale') { throw 'constant value dependency was not invalidated by a value edit' }
$scalarOpsLowered = & $compiler nir-file (Join-Path $PSScriptRoot 'fixtures\nir\scalar_ops\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $scalarOpsLowered -ne 'module nir ok') { throw 'casts, unary operators, and call statements did not lower to canonical NIR' }
$scalarOpsGenerated = & $compiler codegen-file (Join-Path $PSScriptRoot 'fixtures\nir\scalar_ops\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $scalarOpsGenerated -ne 'module codegen ok') { throw 'integer casts and unary operators did not select x64 instructions' }
$compositeChecked = & $compiler check-file (Join-Path $checkRoot 'composite_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $compositeChecked -ne 'module check ok') { throw 'valid composite types did not type-check' }
$qualifiedChecked = & $compiler check-file (Join-Path $checkRoot 'qualified_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $qualifiedChecked -ne 'module check ok') { throw 'qualified calls did not type-check' }
$aliasChecked = & $compiler check-file (Join-Path $checkRoot 'alias_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $aliasChecked -ne 'module check ok') { throw 'type aliases did not canonicalize' }
$constantChecked = & $compiler check-file (Join-Path $checkRoot 'constant_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $constantChecked -ne 'module check ok') { throw 'integer constants did not evaluate' }
$constantGenerated = & $compiler codegen-file (Join-Path $checkRoot 'constant_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $constantGenerated -ne 'module codegen ok') { throw 'local and qualified evaluated constants did not lower' }
$constantAliasChecked = & $compiler check-file (Join-Path $checkRoot 'constant_alias_array_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $constantAliasChecked -ne 'module check ok') { throw 'constant-backed array aliases did not resolve' }
$constantOperatorsChecked = & $compiler check-file (Join-Path $checkRoot 'constant_operators_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $constantOperatorsChecked -ne 'module check ok') { throw 'compile-time integer operators did not produce exact values' }
$intrinsicChecked = & $compiler check-file (Join-Path $checkRoot 'intrinsic_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $intrinsicChecked -ne 'module check ok') { throw 'fixed intrinsic signatures did not type-check' }
$multiResultChecked = & $compiler check-file (Join-Path $checkRoot 'multi_result_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $multiResultChecked -ne 'module check ok') { throw 'multiple returns did not type-check' }
$tryChecked = & $compiler check-file (Join-Path $checkRoot 'try_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $tryChecked -ne 'module check ok') { throw 'try result consumption did not type-check' }
$intrinsicMultiChecked = & $compiler check-file (Join-Path $checkRoot 'intrinsic_multi_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $intrinsicMultiChecked -ne 'module check ok') { throw 'fallible intrinsic results did not type-check' }
$allocChecked = & $compiler check-file (Join-Path $checkRoot 'alloc_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $allocChecked -ne 'module check ok') { throw 'generic mem.alloc specialization did not type-check' }
$genericChecked = & $compiler check-file (Join-Path $checkRoot 'generic_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $genericChecked -ne 'module check ok') { throw 'generic source functions did not type-check' }
$genericDeclarationChecked = & $compiler check-file (Join-Path $checkRoot 'generic_declaration_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $genericDeclarationChecked -ne 'module check ok') { throw 'dependent generic declarations did not type-check before instantiation' }
$qualifiedGenericChecked = & $compiler check-file (Join-Path $checkRoot 'generic_qualified_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $qualifiedGenericChecked -ne 'module check ok') { throw 'qualified generic source functions did not type-check' }
$genericMultiChecked = & $compiler check-file (Join-Path $checkRoot 'generic_multi_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $genericMultiChecked -ne 'module check ok') { throw 'fallible generic source functions did not type-check' }
$indexChecked = & $compiler check-file (Join-Path $checkRoot 'index_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $indexChecked -ne 'module check ok') { throw 'index and slice expressions did not type-check' }
$aggregateChecked = & $compiler check-file (Join-Path $checkRoot 'aggregate_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $aggregateChecked -ne 'module check ok') { throw 'aggregate literals and field places did not type-check' }
$genericAggregateChecked = & $compiler check-file (Join-Path $checkRoot 'generic_aggregate_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $genericAggregateChecked -ne 'module check ok') { throw 'generic aggregate specialization did not type-check' }
$nestedGenericAggregateChecked = & $compiler check-file (Join-Path $checkRoot 'nested_generic_aggregate_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $nestedGenericAggregateChecked -ne 'module check ok') { throw 'nested generic aggregate specialization did not type-check' }
$genericAggregateAliasChecked = & $compiler check-file (Join-Path $checkRoot 'generic_aggregate_alias_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $genericAggregateAliasChecked -ne 'module check ok') { throw 'generic aggregate aliases did not type-check' }
$compoundChecked = & $compiler check-file (Join-Path $checkRoot 'compound_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $compoundChecked -ne 'module check ok') { throw 'compound assignments did not type-check' }
$languageConstructsChecked = & $compiler check-file (Join-Path $checkRoot 'language_constructs_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $languageConstructsChecked -ne 'module check ok') { throw 'enum, error, loop and shift constructs did not type-check' }
$deferChecked = & $compiler check-file (Join-Path $checkRoot 'defer_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $deferChecked -ne 'module check ok') { throw 'deferred calls, discards and blocks did not type-check' }
$switchChecked = & $compiler check-file (Join-Path $checkRoot 'switch_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $switchChecked -ne 'module check ok') { throw 'enum, tagged-union and scalar switches did not type-check' }
$tagChecked = & $compiler check-file (Join-Path $checkRoot 'tag_valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $tagChecked -ne 'module check ok') { throw 'tagged-union tag values did not type-check' }
$checkFailures = @(
    @('missing_context', 'MissingContext'),
    @('binding_mismatch', 'TypeMismatch'),
    @('return_mismatch', 'InvalidReturn'),
    @('condition_mismatch', 'InvalidCondition'),
    @('argument_mismatch', 'TypeMismatch'),
    @('argument_count', 'ArgumentCount'),
    @('invalid_operator', 'InvalidOperator'),
    @('numeric_mismatch', 'TypeMismatch'),
    @('immutable_assignment', 'ImmutableAssignment'),
    @('void_value', 'TypeMismatch'),
    @('cast_untyped', 'MissingContext'),
    @('cast_mismatch', 'TypeMismatch'),
    @('address_of_slice', 'TypeMismatch'),
    @('bool_ordering', 'InvalidOperator'),
    @('void_parameter', 'InvalidType'),
    @('missing_return_value', 'InvalidReturn'),
    @('missing_return', 'MissingReturn'),
    @('const_slice_to_mutable', 'TypeMismatch'),
    @('const_pointer_to_mutable', 'TypeMismatch'),
    @('array_length_mismatch', 'TypeMismatch'),
    @('array_element_mismatch', 'TypeMismatch'),
    @('array_length_type', 'TypeMismatch'),
    @('array_length_overflow', 'TypeMismatch'),
    @('array_length_division_zero', 'TypeMismatch'),
    @('inferred_array_type', 'Unsupported'),
    @('void_slice', 'InvalidType'),
    @('void_pointer_deref', 'InvalidOperator'),
    @('nil_without_context', 'MissingContext'),
    @('qualified_argument_mismatch', 'TypeMismatch'),
    @('qualified_argument_count', 'ArgumentCount'),
    @('qualified_not_callable', 'UnknownCallable'),
    @('alias_cycle', 'AliasCycle'),
    @('alias_pointer_cycle', 'AliasCycle'),
    @('alias_mismatch', 'TypeMismatch'),
    @('alias_const_to_mutable', 'TypeMismatch'),
    @('alias_void_parameter', 'InvalidType'),
    @('alias_void_slice', 'InvalidType'),
    @('alias_void_array', 'InvalidType'),
    @('generic_type_bare', 'Unsupported'),
    @('constant_cycle', 'ConstantCycle'),
    @('constant_type_mismatch', 'TypeMismatch'),
    @('constant_missing_context', 'MissingContext'),
    @('constant_overflow', 'ConstantOverflow'),
    @('constant_arithmetic_overflow', 'ConstantOverflow'),
    @('constant_signed_overflow', 'ConstantOverflow'),
    @('constant_operand_overflow', 'ConstantOverflow'),
    @('constant_unsigned_negative', 'ConstantOverflow'),
    @('constant_unsigned_operator', 'InvalidOperator'),
    @('constant_invalid_reference', 'InvalidConstant'),
    @('constant_division_zero', 'InvalidConstant'),
    @('constant_shift_range', 'InvalidConstant'),
    @('constant_shift_signed', 'InvalidOperator'),
    @('constant_bitwise_missing_context', 'MissingContext'),
    @('array_length_shift_range', 'TypeMismatch'),
    @('array_length_constant_type', 'TypeMismatch'),
    @('intrinsic_argument_count', 'ArgumentCount'),
    @('intrinsic_argument_mismatch', 'TypeMismatch'),
    @('intrinsic_pointer_mismatch', 'TypeMismatch'),
    @('intrinsic_result_mismatch', 'TypeMismatch'),
    @('intrinsic_multi_argument_mismatch', 'TypeMismatch'),
    @('intrinsic_multi_unsupported', 'ArgumentCount'),
    @('multi_result_count', 'ArgumentCount'),
    @('multi_result_assignment_type', 'TypeMismatch'),
    @('multi_result_invalid_return', 'InvalidReturn'),
    @('multi_result_invalid_type', 'InvalidReturn'),
    @('tuple_annotation', 'InvalidType'),
    @('try_invalid_callee', 'InvalidTry'),
    @('try_invalid_caller', 'InvalidTry'),
    @('try_statement_results', 'ArgumentCount'),
    @('try_binding_count', 'ArgumentCount'),
    @('call_result_ignored', 'ArgumentCount'),
    @('multi_return_void', 'InvalidType'),
    @('error_return_not_last', 'InvalidType'),
    @('extern_error_return', 'InvalidType'),
    @('extern_multi_return', 'InvalidType'),
    @('extern_slice_parameter', 'InvalidType'),
    @('extern_slice_return', 'InvalidType'),
    @('variadic_narrow_argument', 'TypeMismatch'),
    @('unreachable_argument', 'TypeMismatch'),
    @('enum_cast_width', 'TypeMismatch'),
    @('trunc_float_argument', 'TypeMismatch'),
    @('intrinsic_generic_unsupported', 'ArgumentCount'),
    @('alloc_argument_type', 'TypeMismatch'),
    @('alloc_arena_type', 'TypeMismatch'),
    @('alloc_argument_count', 'ArgumentCount'),
    @('alloc_missing_type_argument', 'ArgumentCount'),
    @('alloc_type_argument_count', 'ArgumentCount'),
    @('alloc_value_type_argument', 'InvalidType'),
    @('alloc_void', 'InvalidType'),
    @('alloc_result_type', 'TypeMismatch'),
    @('generic_untyped_inference', 'MissingContext'),
    @('generic_conflicting_inference', 'TypeMismatch'),
    @('generic_argument_count', 'ArgumentCount'),
    @('generic_argument_kind', 'InvalidType'),
    @('generic_body_mismatch', 'InvalidReturn'),
    @('generic_integer_conflict', 'TypeMismatch'),
    @('generic_partial_missing', 'MissingContext'),
    @('generic_declaration_binding', 'TypeMismatch'),
    @('generic_declaration_operator', 'InvalidOperator'),
    @('generic_declaration_missing_return', 'MissingReturn'),
    @('generic_declaration_call_count', 'ArgumentCount'),
    @('generic_declaration_index', 'InvalidReturn'),
    @('generic_declaration_generic_arity', 'ArgumentCount'),
    @('generic_declaration_unknown_field', 'InvalidType'),
    @('generic_declaration_invalid_len', 'InvalidOperator'),
    @('generic_declaration_pointer_arithmetic', 'InvalidOperator'),
    @('generic_declaration_literal_field', 'InvalidType'),
    @('generic_declaration_array_count', 'InvalidReturn'),
    @('generic_declaration_switch_body', 'TypeMismatch'),
    @('generic_declaration_duplicate_default', 'DuplicateCase'),
    @('generic_declaration_const_pointer', 'ImmutableAssignment'),
    @('generic_declaration_instantiation_operator', 'InvalidOperator'),
    @('index_type', 'TypeMismatch'),
    @('index_non_indexable', 'InvalidOperator'),
    @('index_count', 'ArgumentCount'),
    @('index_empty', 'ArgumentCount'),
    @('slice_bound_type', 'TypeMismatch'),
    @('const_slice_assignment', 'ImmutableAssignment'),
    @('array_parameter_assignment', 'ImmutableAssignment'),
    @('string_assignment', 'ImmutableAssignment'),
    @('pointer_index', 'InvalidOperator'),
    @('len_non_indexable', 'InvalidOperator'),
    @('const_pointer_assignment', 'ImmutableAssignment'),
    @('array_slice_mutability', 'TypeMismatch'),
    @('aggregate_missing_field', 'ArgumentCount'),
    @('aggregate_duplicate_field', 'ArgumentCount'),
    @('aggregate_unknown_field', 'InvalidType'),
    @('aggregate_field_mismatch', 'InvalidReturn'),
    @('array_literal_count', 'InvalidReturn'),
    @('array_literal_type', 'InvalidReturn'),
    @('immutable_field_assignment', 'ImmutableAssignment'),
    @('union_literal_count', 'ArgumentCount'),
    @('tagged_payload_missing', 'InvalidReturn'),
    @('tagged_void_payload', 'InvalidReturn'),
    @('unknown_field_access', 'InvalidType'),
    @('generic_aggregate_arity', 'ArgumentCount'),
    @('generic_aggregate_kind', 'InvalidType'),
    @('generic_aggregate_identity', 'InvalidReturn'),
    @('generic_aggregate_field_type', 'InvalidReturn'),
    @('nested_generic_aggregate_mismatch', 'InvalidReturn'),
    @('compound_unsupported', 'InvalidOperator'),
    @('enum_unknown_member', 'InvalidType'),
    @('enum_type_mismatch', 'InvalidReturn'),
    @('shift_signed_count', 'InvalidOperator'),
    @('shift_untyped_value', 'InvalidOperator'),
    @('for_non_iterable', 'InvalidOperator'),
    @('break_outside_loop', 'Unsupported'),
    @('defer_return', 'InvalidReturn'),
    @('defer_try', 'InvalidTry'),
    @('defer_outer_break', 'Unsupported'),
    @('defer_fallible_call', 'ArgumentCount'),
    @('switch_non_exhaustive', 'NonExhaustiveSwitch'),
    @('switch_duplicate_case', 'DuplicateCase'),
    @('switch_duplicate_default', 'DuplicateCase'),
    @('switch_non_constant', 'InvalidConstant'),
    @('switch_invalid_subject', 'InvalidSwitch'),
    @('switch_invalid_capture', 'InvalidSwitch'),
    @('tag_invalid_type', 'InvalidType'),
    @('tag_unknown_member', 'InvalidType'),
    @('tag_capture', 'InvalidSwitch'),
    @('switch_missing_return', 'MissingReturn')
)
foreach ($case in $checkFailures) {
    $checkOutput = & $compiler check-file (Join-Path $checkRoot "$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($checkOutput -join "`n") -notmatch ': error\[E-[A-Z]+-[0-9]{4}\]: ') {
        throw "scalar type-check fixture $($case[0]) returned the wrong result"
    }
}
$neper0Root = Join-Path $repo 'tests\neper0'
$diagnosticReference = Join-Path $testBuild 'diagnostic-reference.exe'
foreach ($source in Get-ChildItem $neper0Root -Filter '*.e' | Sort-Object Name) {
    $shouldReject = $source.Name -like '*-error.e' -and $source.Name -ne 'os-error.e'
    $parityOutput = & $compiler check-file $source.FullName $repo 'x64' 'windows' 2>&1
    $parityExit = $LASTEXITCODE
    if ($shouldReject) {
        if ($parityExit -eq 0) { throw "self-hosted front end accepted rejected neper-0 fixture $($source.Name)" }
        $referenceOutput = & $neper build $source.FullName --output $diagnosticReference 2>&1
        $referenceExit = $LASTEXITCODE
        if ($referenceExit -ne $parityExit -or ($referenceOutput -join "`n") -cne ($parityOutput -join "`n")) {
            throw "self-hosted diagnostic parity failed for neper-0 fixture $($source.Name)"
        }
    } else {
        if ($parityExit -ne 0 -or ($parityOutput -join "`n") -notmatch 'module check ok') {
            throw "self-hosted front end rejected accepted neper-0 fixture $($source.Name)"
        }
    }
}
$scopeRoot = Join-Path $PSScriptRoot 'fixtures\scope'
$validScopes = & $compiler resolve-file (Join-Path $scopeRoot 'valid\src\main.e') $repo 'x64' 'windows'
if ($LASTEXITCODE -ne 0 -or $validScopes -ne 'module resolve ok') { throw 'disjoint lexical scope reuse failed' }
$moduleShadow = & $compiler resolve-file (Join-Path $scopeRoot 'module_shadow\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($moduleShadow -join "`n") -notmatch 'error: resolve\.ModuleShadow') { throw 'module name shadowing was not rejected' }
$qualifierShadow = & $compiler resolve-file (Join-Path $scopeRoot 'qualifier_shadow\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($qualifierShadow -join "`n") -notmatch 'error: resolve\.ModuleShadow') { throw 'qualifier shadowing was not rejected' }
$duplicateLocal = & $compiler resolve-file (Join-Path $scopeRoot 'duplicate_local\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($duplicateLocal -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'same-block local reuse was not rejected' }
$nestedShadow = & $compiler resolve-file (Join-Path $scopeRoot 'nested_shadow\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($nestedShadow -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'nested local shadowing was not rejected' }
$duplicateParameter = & $compiler resolve-file (Join-Path $scopeRoot 'duplicate_parameter\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($duplicateParameter -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'duplicate parameter was not rejected' }
$parameterShadow = & $compiler resolve-file (Join-Path $scopeRoot 'parameter_shadow\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($parameterShadow -join "`n") -notmatch 'error: resolve\.ModuleShadow') { throw 'parameter/module shadowing was not rejected' }
$reservedLocal = & $compiler resolve-file (Join-Path $scopeRoot 'reserved_local\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedLocal -join "`n") -notmatch 'error: resolve\.ReservedLocal') { throw 'reserved local name was not rejected' }
$tupleDuplicate = & $compiler resolve-file (Join-Path $scopeRoot 'tuple_duplicate\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($tupleDuplicate -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'tuple binding duplicate was not rejected' }
$forShadow = & $compiler resolve-file (Join-Path $scopeRoot 'for_shadow\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($forShadow -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'for binding shadowing was not rejected' }
$switchCapture = & $compiler resolve-file (Join-Path $scopeRoot 'switch_capture\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($switchCapture -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'switch capture shadowing was not rejected' }
$sharedDuplicate = & $compiler resolve-file (Join-Path $scopeRoot 'shared_duplicate\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($sharedDuplicate -join "`n") -notmatch 'error: resolve\.DuplicateLocal') { throw 'shared local duplicate was not rejected' }
$declarationDuplicate = & $compiler resolve-file (Join-Path $scopeRoot 'declaration_duplicate\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($declarationDuplicate -join "`n") -notmatch 'error: resolve\.DuplicateName') { throw 'duplicate module-scope declaration was not rejected' }
$qualifierCollision = & $compiler resolve-file (Join-Path $scopeRoot 'qualifier_collision\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($qualifierCollision -join "`n") -notmatch 'error: resolve\.QualifierCollision') { throw 'declaration over a use qualifier was not rejected' }
$reservedDeclaration = & $compiler resolve-file (Join-Path $scopeRoot 'reserved_declaration\src\main.e') $repo 'x64' 'windows' 2>&1
if ($LASTEXITCODE -ne 1 -or ($reservedDeclaration -join "`n") -notmatch 'error: resolve\.ReservedName') { throw 'reserved declaration name was not rejected' }
# Every spec section 5 and section 14 name collision reports an exact token, the
# offending name and its registered docs/diagnostics.md code.
$nameDiagnostics = @(
    @('module_shadow', 'main\.e:4:9: error\[E-NAME-0003\]: `helper` already names a module-scope function; a local or parameter may not reuse it'),
    @('parameter_shadow', 'main\.e:2:8: error\[E-NAME-0003\]: `value` already names a module-scope function; a local or parameter may not reuse it'),
    @('qualifier_shadow', 'main\.e:4:9: error\[E-NAME-0003\]: `d` already names a module-scope use qualifier; a local or parameter may not reuse it'),
    @('duplicate_local', 'main\.e:3:9: error\[E-NAME-0003\]: `value` is already bound in an active scope'),
    @('duplicate_parameter', 'main\.e:1:20: error\[E-NAME-0003\]: `value` is already bound in an active scope'),
    @('reserved_local', 'main\.e:2:9: error\[E-NAME-0003\]: `u8` is a reserved name and cannot name a local or parameter'),
    @('declaration_duplicate', 'main\.e:3:4: error\[E-NAME-0001\]: `Thing` already names a module-scope error; each name may be declared once per namespace'),
    @('qualifier_collision', 'main\.e:3:4: error\[E-NAME-0002\]: `d` collides with a use qualifier in this module'),
    @('reserved_declaration', 'main\.e:1:4: error\[E-NAME-0003\]: `u8` is a reserved name and cannot name a declaration')
)
foreach ($case in $nameDiagnostics) {
    $nameOutput = & $compiler check-file (Join-Path $scopeRoot "$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($nameOutput -join "`n") -notmatch $case[1]) {
        throw "name collision diagnostic for $($case[0]) is wrong: $($nameOutput -join "`n")"
    }
}
$capacityDeclarations = 0..259 | ForEach-Object { "error Capacity$_" }
$capacityItems = 0..129 | ForEach-Object { '0u8' }
$capacitySource = ($capacityDeclarations -join "`n") + "`nfn capacity() {`n    let values = [_]u8{ " + ($capacityItems -join ', ') + " }`n}`n"
$capacityParse = & $compiler parse $capacitySource
if ($LASTEXITCODE -ne 0 -or $capacityParse -ne 'parse ok') {
    throw 'self-hosted parser retained a hidden list limit'
}
$invalid = & $compiler scan '#' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalid -join "`n") -notmatch 'lex.InvalidSource') {
    throw 'self-hosted compiler invalid-source result failed'
}
$invalidParse = & $compiler parse 'fn broken() -> err {' 2>&1
if ($LASTEXITCODE -ne 1 -or ($invalidParse -join "`n") -notmatch '<argument>:1:21: error\[E-SYNTAX-9999\]: unexpected end of file') {
    throw 'self-hosted compiler invalid-syntax result failed'
}
# Spec section 5: a keyword in a binding position is rejected by name and reason,
# not as a bare syntax error, because it reads as an ordinary name.
$reservedBindings = @(
    @('reserved_binding_let', 'main\.e:2:9: error\[E-NAME-0003\]: `zero` is a keyword and cannot name a local or parameter'),
    @('reserved_binding_parameter', 'main\.e:1:8: error\[E-NAME-0003\]: `zero` is a keyword and cannot name a local or parameter')
)
foreach ($case in $reservedBindings) {
    $reservedOutput = & $compiler check-file (Join-Path $scopeRoot "$($case[0])\src\main.e") $repo 'x64' 'windows' 2>&1
    if ($LASTEXITCODE -ne 1 -or ($reservedOutput -join "`n") -notmatch $case[1]) {
        throw "reserved binding diagnostic for $($case[0]) is wrong: $($reservedOutput -join "`n")"
    }
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
# The last native command above is an expected-failure case, so $LASTEXITCODE is
# still 1 here. Report the suite's own result instead of inheriting that.
exit 0
