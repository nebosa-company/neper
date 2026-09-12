$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'src\runtime_elf_x64.s'
$output = Join-Path $repo 'src\runtime_elf_x64.e'
$build = Join-Path $repo 'build\windows\runtime-embed'
New-Item -ItemType Directory -Force -Path $build | Out-Null

function Convert-ToWslPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    return '/mnt/' + $drive + $full.Substring(2).Replace('\', '/')
}

$object = Join-Path $build 'runtime_elf_x64.o'
$binary = Join-Path $build 'runtime_elf_x64.bin'
$sourceWsl = Convert-ToWslPath $source
$objectWsl = Convert-ToWslPath $object
$binaryWsl = Convert-ToWslPath $binary
& wsl -d Ubuntu-24.04 -- as --64 $sourceWsl -o $objectWsl
if ($LASTEXITCODE -ne 0) { throw 'assembling the ELF runtime failed' }
& wsl -d Ubuntu-24.04 -- objcopy -O binary --only-section=.text $objectWsl $binaryWsl
if ($LASTEXITCODE -ne 0) { throw 'extracting the ELF runtime failed' }
$symbols = & wsl -d Ubuntu-24.04 -- nm -n --defined-only $objectWsl
if ($LASTEXITCODE -ne 0) { throw 'reading ELF runtime symbols failed' }

$bytes = [IO.File]::ReadAllBytes($binary)
$builder = [Text.StringBuilder]::new()
[void]$builder.AppendLine('// Generated x86-64 Linux syscall runtime. Source: runtime_elf_x64.s.')
[void]$builder.AppendLine()
[void]$builder.AppendLine('use check')
[void]$builder.AppendLine('use emit_x64')
[void]$builder.AppendLine()
[void]$builder.AppendLine('// The first `limit` bytes of a chunk that starts `from` bytes into the runtime.')
[void]$builder.AppendLine('fn append_blob(output: *emit_x64.Buffer, bytes: str, from: usize, limit: usize) -> err {')
[void]$builder.AppendLine('    var at = 0usize')
[void]$builder.AppendLine('    while at < bytes.len && from + at < limit {')
[void]$builder.AppendLine('        try emit_x64.byte(output, usize(bytes[at]))')
[void]$builder.AppendLine('        at += 1usize')
[void]$builder.AppendLine('    }')
[void]$builder.AppendLine('    ret ok')
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine('// The runtime up to `limit` bytes: a prefix, because the source is ordered so that a')
[void]$builder.AppendLine('// function calls only what precedes it, and the linker cuts after the last one reached.')
[void]$builder.AppendLine('fn append(output: *emit_x64.Buffer, limit: usize) -> err {')
for ($offset = 0; $offset -lt $bytes.Length; $offset += 64) {
    $end = [Math]::Min($offset + 64, $bytes.Length)
    $escaped = [Text.StringBuilder]::new()
    for ($at = $offset; $at -lt $end; $at++) {
        [void]$escaped.Append(('\x{0:x2}' -f $bytes[$at]))
    }
    $prefix = if ($end -eq $bytes.Length) { '    ret append_blob(output, "' } else { '    try append_blob(output, "' }
    [void]$builder.AppendLine($prefix + $escaped + ('", {0}usize, limit)' -f $offset))
}
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine(('fn size() -> usize {{ ret {0}usize }}' -f $bytes.Length))
[void]$builder.AppendLine()
$table = @()
foreach ($line in $symbols) {
    if ($line -match '^([0-9a-fA-F]+)\s+[A-Z]\s+(neper_[a-z0-9_]+)$') {
        $table += [pscustomobject]@{ Name = $matches[2]; Offset = [Convert]::ToUInt64($matches[1], 16) }
    }
}
[void]$builder.AppendLine('fn symbol_offset(name: str) -> (usize, bool) {')
foreach ($entry in $table) {
    [void]$builder.AppendLine(('    if check.same(name, "{0}") {{ ret ({1}usize, true) }}' -f $entry.Name, $entry.Offset))
}
[void]$builder.AppendLine('    ret (0usize, false)')
[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.AppendLine('// Where a function ends: the start of the next, or the end of the runtime for the last.')
[void]$builder.AppendLine('fn symbol_end(name: str) -> (usize, bool) {')
for ($index = 0; $index -lt $table.Count; $index++) {
    $end = if ($index + 1 -lt $table.Count) { $table[$index + 1].Offset } else { $bytes.Length }
    [void]$builder.AppendLine(('    if check.same(name, "{0}") {{ ret ({1}usize, true) }}' -f $table[$index].Name, $end))
}
[void]$builder.AppendLine('    ret (0usize, false)')
[void]$builder.AppendLine('}')

[IO.File]::WriteAllText($output, $builder.ToString(), [Text.UTF8Encoding]::new($false))
Write-Output $output
