param(
    [Parameter(Mandatory = $true)][string[]]$ObjectPath
)

$ErrorActionPreference = 'Stop'

function Read-U16([byte[]]$data, [int]$offset) {
    [BitConverter]::ToUInt16($data, $offset)
}

function Read-U32([byte[]]$data, [int]$offset) {
    [BitConverter]::ToUInt32($data, $offset)
}

function Get-CoffSections([string]$path) {
    [byte[]]$data = [IO.File]::ReadAllBytes($path)
    $count = Read-U16 $data 2
    $table = 20 + (Read-U16 $data 16)
    for ($i = 0; $i -lt $count; $i++) {
        $header = $table + $i * 40
        $name = [Text.Encoding]::ASCII.GetString($data, $header, 8).TrimEnd([char]0)
        $size = [int](Read-U32 $data ($header + 16))
        $raw = [int](Read-U32 $data ($header + 20))
        [byte[]]$content = if ($size) { $data[$raw..($raw + $size - 1)] } else { @() }
        [pscustomobject]@{ Name = $name; Data = $content; Path = $path }
    }
}

$typeKinds = [Collections.Generic.HashSet[int]]::new()
$symbolKinds = [Collections.Generic.HashSet[int]]::new()
$regrelNames = [Collections.Generic.HashSet[string]]::new()
$regrelCount = 0

foreach ($path in $ObjectPath) {
    foreach ($section in Get-CoffSections $path) {
        [byte[]]$data = $section.Data
        if ($section.Name -eq '.debug$T') {
            if ($data.Length -lt 4 -or (Read-U32 $data 0) -ne 4) {
                throw "invalid CodeView type signature in $path"
            }
            $offset = 4
            while ($offset -lt $data.Length) {
                if ($offset + 4 -gt $data.Length) { throw "truncated CodeView type record in $path" }
                $length = Read-U16 $data $offset
                if ($length -lt 2 -or $offset + $length + 2 -gt $data.Length) {
                    throw "invalid CodeView type record length in $path"
                }
                [void]$typeKinds.Add((Read-U16 $data ($offset + 2)))
                $offset += $length + 2
            }
        } elseif ($section.Name -eq '.debug$S') {
            if ($data.Length -lt 4 -or (Read-U32 $data 0) -ne 4) { continue }
            $offset = 4
            while ($offset + 8 -le $data.Length) {
                $subsection = Read-U32 $data $offset
                $length = [int](Read-U32 $data ($offset + 4))
                $body = $offset + 8
                if ($body + $length -gt $data.Length) { throw "invalid CodeView subsection length in $path" }
                if ($subsection -eq 0xF1) {
                    $record = $body
                    while ($record -lt $body + $length) {
                        if ($record + 4 -gt $body + $length) { throw "truncated CodeView symbol record in $path" }
                        $recordLength = Read-U16 $data $record
                        $kind = Read-U16 $data ($record + 2)
                        if ($recordLength -lt 2 -or $record + $recordLength + 2 -gt $body + $length) {
                            throw "invalid CodeView symbol record length in $path"
                        }
                        [void]$symbolKinds.Add($kind)
                        if ($kind -eq 0x1111) {
                            if ($recordLength -lt 13) { throw "short S_REGREL32 record in $path" }
                            $register = Read-U16 $data ($record + 12)
                            if ($register -ne 334) { throw "S_REGREL32 is not relative to rbp in $path" }
                            $nameStart = $record + 14
                            $nameLength = 0
                            while ($nameStart + $nameLength -lt $record + $recordLength + 2 -and
                                   $data[$nameStart + $nameLength] -ne 0) { $nameLength++ }
                            $name = [Text.Encoding]::UTF8.GetString($data, $nameStart, $nameLength)
                            [void]$regrelNames.Add($name)
                            $regrelCount++
                        }
                        $record += $recordLength + 2
                    }
                }
                $offset = $body + (($length + 3) -band -4)
            }
        }
    }
}

foreach ($kind in @(0x1001, 0x1002, 0x1008, 0x1201, 0x1203, 0x1503, 0x1505, 0x1506, 0x1507)) {
    if (-not $typeKinds.Contains($kind)) { throw ('missing CodeView type record 0x{0:X4}' -f $kind) }
}
foreach ($kind in @(0x0006, 0x1012, 0x1108, 0x1110, 0x1111)) {
    if (-not $symbolKinds.Contains($kind)) { throw ('missing CodeView symbol record 0x{0:X4}' -f $kind) }
}
foreach ($name in @('value', 'copy', 'big', 'values', 'kind', 'raw', 'node')) {
    if (-not $regrelNames.Contains($name)) { throw "missing frame-relative debug local '$name'" }
}
if ($regrelCount -lt 12) { throw 'too few frame-relative CodeView locals were emitted' }
