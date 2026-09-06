$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'src\runtime_pe_x64.asm'
$output = Join-Path $repo 'src\runtime_pe_x64.e'
$build = Join-Path $repo 'build\runtime-embed'
$object = Join-Path $build 'runtime_pe_x64.obj'
New-Item -ItemType Directory -Force -Path $build | Out-Null

$vsDevCmd = $env:NEPER_VSDEVCMD
if (-not $vsDevCmd) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installation) { $vsDevCmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat' }
    }
}
if (-not $vsDevCmd -and (Test-Path -LiteralPath 'D:\VS\Community\Common7\Tools\VsDevCmd.bat')) { $vsDevCmd = 'D:\VS\Community\Common7\Tools\VsDevCmd.bat' }
if (-not $vsDevCmd) { throw 'Visual Studio C++ tools were not found' }
$command = 'call "{0}" -arch=x64 -host_arch=x64 >nul && ml64 /nologo /c /Fo"{1}" "{2}"' -f $vsDevCmd, $object, $source
cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw 'assembling the PE runtime failed' }

$bytes = [IO.File]::ReadAllBytes($object)
$sectionCount = [BitConverter]::ToUInt16($bytes, 2)
$symbolOffset = [BitConverter]::ToUInt32($bytes, 8)
$symbolCount = [BitConverter]::ToUInt32($bytes, 12)
$text = $null
for ($section = 0; $section -lt $sectionCount; $section++) {
    $offset = 20 + $section * 40
    $name = [Text.Encoding]::ASCII.GetString($bytes, $offset, 8).Trim([char]0)
    if ($name -eq '.text$mn') {
        $text = [pscustomobject]@{
            Size = [BitConverter]::ToUInt32($bytes, $offset + 16)
            Raw = [BitConverter]::ToUInt32($bytes, $offset + 20)
            Relocations = [BitConverter]::ToUInt32($bytes, $offset + 24)
            RelocationCount = [BitConverter]::ToUInt16($bytes, $offset + 32)
            Number = $section + 1
        }
    }
}
if (-not $text) { throw 'PE runtime object has no text section' }

$stringTable = $symbolOffset + $symbolCount * 18
function Read-CoffName([int]$Index) {
    $offset = $symbolOffset + $Index * 18
    if ([BitConverter]::ToUInt32($bytes, $offset) -eq 0) {
        $nameOffset = [BitConverter]::ToUInt32($bytes, $offset + 4)
        $at = $stringTable + $nameOffset
        $end = $at
        while ($bytes[$end] -ne 0) { $end++ }
        return [Text.Encoding]::ASCII.GetString($bytes, $at, $end - $at)
    }
    return [Text.Encoding]::ASCII.GetString($bytes, $offset, 8).Trim([char]0)
}

$symbolNames = @{}
$publicSymbols = @()
for ($index = 0; $index -lt $symbolCount;) {
    $offset = $symbolOffset + $index * 18
    $name = Read-CoffName $index
    $symbolNames[$index] = $name
    $value = [BitConverter]::ToUInt32($bytes, $offset + 8)
    $sectionNumber = [BitConverter]::ToInt16($bytes, $offset + 12)
    $storageClass = $bytes[$offset + 16]
    $auxiliaryCount = $bytes[$offset + 17]
    if ($sectionNumber -eq $text.Number -and $storageClass -eq 2 -and $name.StartsWith('neper_') -and $name -ne 'neper_entry') {
        $publicSymbols += [pscustomobject]@{ Name = $name; Value = $value }
    }
    $index += 1 + $auxiliaryCount
}

$imports = @('CloseHandle','CreateFileW','ExitProcess','FindClose','FindFirstFileW','FindNextFileW','GetCommandLineW','GetLastError','GetStdHandle','MultiByteToWideChar','ReadFile','VirtualAlloc','WideCharToMultiByte','WriteFile','GetSystemTimeAsFileTime','QueryPerformanceCounter','QueryPerformanceFrequency','CreateProcessW','SetHandleInformation','WaitForSingleObject','GetExitCodeProcess')
$importIndices = @{}
for ($index = 0; $index -lt $imports.Count; $index++) { $importIndices['__imp_' + $imports[$index]] = $index }
$relocations = @()
for ($index = 0; $index -lt $text.RelocationCount; $index++) {
    $offset = $text.Relocations + $index * 10
    $address = [BitConverter]::ToUInt32($bytes, $offset)
    $targetIndex = [BitConverter]::ToUInt32($bytes, $offset + 4)
    $type = [BitConverter]::ToUInt16($bytes, $offset + 8)
    if ($type -ne 4) { throw "unsupported PE runtime relocation type $type" }
    $relocations += [pscustomobject]@{ Address = $address; Name = $symbolNames[[int]$targetIndex] }
}

$image = [byte[]]::new($text.Size)
[Array]::Copy($bytes, $text.Raw, $image, 0, $text.Size)
$builder = [Text.StringBuilder]::new()
[void]$builder.AppendLine('// Generated x86-64 Windows runtime image. Source: runtime_pe_x64.asm.')
[void]$builder.AppendLine()
[void]$builder.AppendLine('use check')
[void]$builder.AppendLine('use emit_x64')
[void]$builder.AppendLine()
[void]$builder.AppendLine('error InvalidRuntime')
[void]$builder.AppendLine()
[void]$builder.AppendLine('fn append_blob(output: *emit_x64.Buffer, bytes: str) -> err {')
[void]$builder.AppendLine('    var at = 0usize')
[void]$builder.AppendLine('    while at < bytes.len {')
[void]$builder.AppendLine('        try emit_x64.byte(output, usize(bytes[at]))')
[void]$builder.AppendLine('        at += 1usize')
[void]$builder.AppendLine('    }')
[void]$builder.AppendLine('    ret ok')
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine('fn append(output: *emit_x64.Buffer) -> err {')
for ($offset = 0; $offset -lt $image.Length; $offset += 64) {
    $end = [Math]::Min($offset + 64, $image.Length)
    $escaped = [Text.StringBuilder]::new()
    for ($at = $offset; $at -lt $end; $at++) { [void]$escaped.Append(('\x{0:x2}' -f $image[$at])) }
    $prefix = if ($end -eq $image.Length) { '    ret append_blob(output, "' } else { '    try append_blob(output, "' }
    [void]$builder.AppendLine($prefix + $escaped + '")')
}
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine(('fn size() -> usize {{ ret {0}usize }}' -f $image.Length))
[void]$builder.AppendLine()
[void]$builder.AppendLine('fn symbol_offset(name: str) -> (usize, bool) {')
foreach ($symbol in ($publicSymbols | Sort-Object Value)) { [void]$builder.AppendLine(('    if check.same(name, "{0}") {{ ret ({1}usize, true) }}' -f $symbol.Name, $symbol.Value)) }
[void]$builder.AppendLine('    ret (0usize, false)')
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine('fn patch_import(output: *emit_x64.Buffer, runtime_file: usize, runtime_rva: usize, displacement_at: usize, iat_rva: usize, import_index: usize) -> err {')
[void]$builder.AppendLine('    let next_rva = runtime_rva + displacement_at + 4usize')
[void]$builder.AppendLine('    let target_rva = iat_rva + import_index * 8usize')
[void]$builder.AppendLine('    if target_rva < next_rva { ret InvalidRuntime }')
[void]$builder.AppendLine('    ret emit_x64.patch_little_u32(output, runtime_file + displacement_at, target_rva - next_rva)')
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine('fn patch(output: *emit_x64.Buffer, runtime_file: usize, runtime_rva: usize, main_file: usize, iat_rva: usize) -> err {')
foreach ($relocation in $relocations) {
    if ($relocation.Name -eq 'main') { [void]$builder.AppendLine(('    try emit_x64.patch_relative32(output, runtime_file + {0}usize, main_file)' -f $relocation.Address)) }
    elseif ($importIndices.ContainsKey($relocation.Name)) { [void]$builder.AppendLine(('    try patch_import(output, runtime_file, runtime_rva, {0}usize, iat_rva, {1}usize)' -f $relocation.Address, $importIndices[$relocation.Name])) }
    else { throw "unsupported PE runtime relocation $($relocation.Name)" }
}
[void]$builder.AppendLine('    ret ok')
[void]$builder.AppendLine('}')
[IO.File]::WriteAllText($output, $builder.ToString(), [Text.UTF8Encoding]::new($false))
Write-Output $output
