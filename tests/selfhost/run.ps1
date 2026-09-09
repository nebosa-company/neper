$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\windows\neper.exe'
$testBuild = Join-Path $repo 'build\windows\tests\selfhost'
& (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$compiler = Join-Path $testBuild 'neper-self.exe'
$compilerAsm = Join-Path $testBuild 'neper-self.asm'
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
if ($LASTEXITCODE -ne 1 -or ($cycleGraph -join "`n") -notmatch 'error: graph\.ImportCycle') {
    throw 'module import cycle was not rejected'
}
$duplicateGraph = & $compiler graph-file (Join-Path $graphRoot 'duplicate\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($duplicateGraph -join "`n") -notmatch 'error: graph\.DuplicateModule') {
    throw 'duplicate source-root module was not rejected'
}
$aliasGraph = & $compiler graph-file (Join-Path $graphRoot 'alias\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($aliasGraph -join "`n") -notmatch 'error: graph\.DuplicateQualifier') {
    throw 'duplicate import qualifier was not rejected'
}
$missingGraph = & $compiler graph-file (Join-Path $graphRoot 'missing\src\main.e') $repo 'x64' 'windows' '' 2>&1
if ($LASTEXITCODE -ne 1 -or ($missingGraph -join "`n") -notmatch 'error: project\.ModuleNotFound') {
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
        $cursor += 24 + $length + $relocations * 16
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
# A slice is formattable under section 4 but needs the expansion to recurse into an
# element at a time, which it does not do yet, so the build stops rather than quietly
# formatting nothing. Rejected at lowering, not at checking, so it needs an emission.
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
    @('atomic_load_release', 'main\.e:8:34: error\[E-TYPE-9999\]: `atomic\.load` may not take the ordering `\.Release`'),
    @('atomic_store_acquire', 'main\.e:8:33: error\[E-TYPE-9999\]: `atomic\.store` may not take the ordering `\.Acquire`'),
    @('atomic_cas_failure', 'main\.e:9:65: error\[E-TYPE-9999\]: `atomic\.cas` may not take the ordering `\.SeqCst`'),
    @('atomic_element', 'main\.e:5:14: error\[E-TYPE-9999\]: `Atomic\[f64\]` is not a type: an atomic holds an integer or a pointer')
)
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
if ($genericInstancesRootRecords.Count -ne 7) { throw 'the instantiating module did not receive every instance it uses' }
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
if ([BitConverter]::ToUInt16($moduleArtifactBytes, 4) -ne 2 -or [BitConverter]::ToUInt16($moduleArtifactBytes, 6) -ne 32) { throw 'compiled-module version or header size is invalid' }
if ([BitConverter]::ToUInt32($moduleArtifactBytes, 20) -ne 6) { throw 'compiled-module section count is invalid' }
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
