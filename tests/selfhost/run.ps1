$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$neper = Join-Path $repo 'build\neper.exe'
$testBuild = Join-Path $repo 'build\tests\selfhost'
& (Join-Path $repo 'scripts\build-bootstrap.ps1') | Out-Null
New-Item -ItemType Directory -Force -Path $testBuild | Out-Null

$compiler = Join-Path $testBuild 'neper-self.exe'
& $neper build (Join-Path $repo 'src\main.e') --arena 1g --output $compiler
if ($LASTEXITCODE -ne 0) { throw 'self-hosted compiler slice did not build' }
$lexer = & $compiler self-test
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
$toolchainGraph = & $compiler graph-file (Join-Path $nestedRoot 'src\main.e') $repo 'x64' 'windows' 'main' 'e.io' 'e.mem' 'e.os' 'util.math'
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
if ($LASTEXITCODE -ne 1 -or ($invalidGraph -join "`n") -notmatch 'error: parse\.InvalidSyntax') {
    throw 'invalid imported source returned the wrong error'
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
if ([BitConverter]::ToUInt16($moduleArtifactBytes, 4) -ne 1 -or [BitConverter]::ToUInt16($moduleArtifactBytes, 6) -ne 32) { throw 'compiled-module version or header size is invalid' }
if ([BitConverter]::ToUInt32($moduleArtifactBytes, 20) -ne 6) { throw 'compiled-module section count is invalid' }
if ([BitConverter]::ToUInt64($moduleArtifactBytes, 96) -le 4) { throw 'compiled-module omitted its foreign signature dependency' }
$interfaceArtifactPath = Join-Path $testBuild 'interface.x64-windows.em'
$interfaceArtifactWritten = & $compiler emit-em (Join-Path $PSScriptRoot 'fixtures\em\interface\src\main.e') $repo 'x64' 'windows' $interfaceArtifactPath
if ($LASTEXITCODE -ne 0 -or $interfaceArtifactWritten -ne 'compiled module written') { throw 'full interface artifact emission failed' }
$interfaceArtifactBytes = [IO.File]::ReadAllBytes($interfaceArtifactPath)
$interfaceOffset = [BitConverter]::ToUInt64($interfaceArtifactBytes, 64)
if ([BitConverter]::ToUInt32($interfaceArtifactBytes, [int]$interfaceOffset + 8) -ne 6) { throw 'compiled-module interface omitted a declaration kind' }
if ([BitConverter]::ToUInt64($interfaceArtifactBytes, [int]$interfaceOffset + 28) -eq 0) { throw 'compiled-module function signature hash is zero' }
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
