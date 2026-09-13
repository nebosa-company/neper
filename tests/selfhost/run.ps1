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
# code section offset is at byte 136; each record is a 24-byte header followed by
# its machine code and its relocations.
function Get-EmCodeRecords([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $code = [int][BitConverter]::ToUInt64($bytes, 136)
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
        $cursor += 24 + $length + $relocations * 20
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
Push-Location $fsScratch
& $fsBasicsPath
$fsBasicsExit = $LASTEXITCODE
Pop-Location
if ($fsBasicsExit -ne 0) { throw "e.fs answered wrongly: exit $fsBasicsExit" }
# `e.proc` against a real child, which is the fixture's own image. The child fills its stderr
# pipe before its stdout is drained, so `output` returning at all is what proves the two
# streams are read at once; a child that never stops is what proves the limit ends it.
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
    @('protocol_signature', 'main\.e:6:9: error\[E-TYPE-0003\]: protocol `point_cmp` must take `Point` by value as its first parameter'),
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
    @('thread_create_context', 'main\.e:16:5: error\[E-TYPE-0002\]: initializer type does not match binding')
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
if ($LASTEXITCODE -ne 1 -or ($genericFieldLeak -join "`n") -notmatch 'main\.e:8:5: error\[E-TYPE-9999\]: type checking failed: check\.InvalidType') {
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
# the minimum divided by -1, and a shift count past the width, each with its record.
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
# Nested inlining (D212): a release build copies `leaf.add` into `mid.twice` and that
# into `main`, the trap record names leaf.e through both copies with one frame in
# release and three in debug, and an edit to the leaf's body rebuilds all three.
$nestedFixture = Join-Path $PSScriptRoot 'fixtures\link\inline_nested'
$nestedRelease = Join-Path $testBuild 'inline-nested-release.exe'
$nestedReleaseWritten = & $compiler emit-executable (Join-Path $nestedFixture 'src\main.e') $repo 'x64' 'windows' $nestedRelease --release
if ($LASTEXITCODE -ne 0 -or $nestedReleaseWritten -ne 'executable written') { throw 'nested inlining release emission failed' }
& $nestedRelease
if ($LASTEXITCODE -ne 5) { throw "the nested release build did not compute through both copies: exit $LASTEXITCODE" }
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
foreach ($case in @(@('tokens', 'every_kind', 0), @('tokens', 'hostile', 1), @('parse', 'every_kind', 0), @('parse', 'recovery', 1))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    cmd /c "`"$compiler`" $($case[0]) --json --path $($case[1]).e `"$conformanceFixture`" > `"$conformanceActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "$($case[0]) --json on $($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "$($case[0]) --json on $($case[1]).e differs from the conformance corpus" }
}
# `check-file ... --json` (D228) against accept/ and reject/: a diagnostic record per
# error with its span, the result with the exit status, nothing on stderr.
foreach ($case in @(@('accept', 'scalar', 0), @('reject', 'enum_values', 1), @('reject', 'lexical', 1), @('reject', 'when_local', 1), @('reject', 'scope', 1))) {
    $conformanceFixture = Join-Path $conformanceRoot "$($case[0])\$($case[1]).e"
    $conformanceExpected = Join-Path $conformanceRoot "$($case[0])\$($case[1]).expected.jsonl"
    $conformanceActual = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).jsonl"
    $conformanceStderr = Join-Path $testBuild "conformance-$($case[0])-$($case[1]).stderr"
    cmd /c "`"$compiler`" check-file `"$conformanceFixture`" `"$repo`" x64 windows --json > `"$conformanceActual`" 2> `"$conformanceStderr`""
    if ($LASTEXITCODE -ne $case[2]) { throw "check-file --json on $($case[0])/$($case[1]).e exited $LASTEXITCODE, not $($case[2])" }
    if ((Get-Item -LiteralPath $conformanceStderr).Length -ne 0) { throw "check-file --json on $($case[0])/$($case[1]).e wrote to stderr" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $conformanceExpected).Hash) { throw "check-file --json on $($case[0])/$($case[1]).e differs from the conformance corpus" }
}
# `info --json` (D229): the capability record for this host, byte for byte.
$infoActual = Join-Path $testBuild 'conformance-tools-info.jsonl'
cmd /c "`"$compiler`" info --json > `"$infoActual`""
if ($LASTEXITCODE -ne 0) { throw "info --json exited $LASTEXITCODE" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $infoActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools\info.x64-windows.expected.jsonl')).Hash) { throw "info --json differs from the conformance corpus" }
# `emit-executable --json` (D230): the build stream, the executable named as given,
# a rejected program's diagnostics as records; both byte for byte from testBuild.
foreach ($case in @(@('tools\build.e', 'build', 0), @('reject\scope.e', 'build_reject', 1))) {
    $buildActual = Join-Path $testBuild "conformance-tools-$($case[1]).jsonl"
    cmd /c "cd /d `"$testBuild`" && `"$compiler`" emit-executable `"$(Join-Path $conformanceRoot $case[0])`" `"$repo`" x64 windows conformance-tools-$($case[1]).out --json > `"$buildActual`""
    if ($LASTEXITCODE -ne $case[2]) { throw "emit-executable --json on $($case[0]) exited $LASTEXITCODE" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $buildActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot "tools\$($case[1]).expected.jsonl")).Hash) { throw "emit-executable --json on $($case[0]) differs from the conformance corpus" }
}
Copy-Item -LiteralPath (Join-Path $testBuild 'conformance-tools-build.out') -Destination (Join-Path $testBuild 'conformance-tools-build.exe') -Force
& (Join-Path $testBuild 'conformance-tools-build.exe')
if ($LASTEXITCODE -ne 0) { throw "the executable of build --json exited $LASTEXITCODE" }
# `run --json` (D231): the build stream plus one `run` record of the program's whole
# stdout, stderr and exit status, byte for byte.
$runActual = Join-Path $testBuild 'conformance-tools-run.jsonl'
cmd /c "cd /d `"$testBuild`" && `"$compiler`" run `"$(Join-Path $conformanceRoot 'tools/run.e')`" `"$repo`" x64 windows conformance-tools-run.out --json > `"$runActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/run.expected.jsonl')).Hash) { throw "run --json differs from the conformance corpus" }
# `index --json` (D232): the operand module's symbol records, byte for byte (target-independent).
$indexActual = Join-Path $testBuild 'conformance-tools-index.jsonl'
cmd /c "`"$compiler`" index-file `"$(Join-Path $conformanceRoot 'tools/index.e')`" `"$repo`" x64 windows --json > `"$indexActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $indexActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/index.expected.jsonl')).Hash) { throw "index --json differs from the conformance corpus" }
# `dis --json` (D233): one record of hex bytes per emitted function, byte for byte per host.
$disActual = Join-Path $testBuild 'conformance-tools-dis.jsonl'
cmd /c "`"$compiler`" dis-file `"$(Join-Path $conformanceRoot 'tools/dis.e')`" `"$repo`" x64 windows --json > `"$disActual`""
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $disActual).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conformanceRoot 'tools/dis.x64-windows.expected.jsonl')).Hash) { throw "dis --json differs from the conformance corpus" }
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
if ([BitConverter]::ToUInt16($moduleArtifactBytes, 4) -ne 4 -or [BitConverter]::ToUInt16($moduleArtifactBytes, 6) -ne 32) { throw 'compiled-module version or header size is invalid' }
if ([BitConverter]::ToUInt32($moduleArtifactBytes, 20) -ne 8) { throw 'compiled-module section count is invalid' }
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
