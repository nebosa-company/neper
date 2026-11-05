<#
.SYNOPSIS
Runs the script-side WPT runner over a list and diffs the per-file result against a baseline.

.DESCRIPTION
The browser tracker's gate rule is "no drops". This turns that rule into one line: run a
list, record `path<TAB>passed<TAB>total`, and if a baseline exists, print every file whose
count changed. It exits 1 when a file dropped, so a batch can be gated in a single command
instead of eyeballing a summary line.

Example:
  scripts/wpt-gate.ps1 -Exe build/windows/web-run-js39.exe -Root D:/data/wpt-script -List tmp/wpt/dom-n2.txt
  scripts/wpt-gate.ps1 ... -Baseline tmp/wpt/baseline-dom-n2.tsv

  # first run of a list, writes the baseline:
  scripts/wpt-gate.ps1 ... -Update
#>
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$List,
    [string]$Baseline = "",
    [switch]$Update,
    [string]$Tsv = "",
    [int]$Chunk = 40,
    [int]$ChunkTimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Exe)) { throw "runner not found: $Exe" }
if (-not (Test-Path $List)) { throw "list not found: $List" }
if ($Tsv -eq "") { $Tsv = [System.IO.Path]::ChangeExtension($List, ".tsv") }

# The script runner leaks something per file (handover: the select-element abort is a cumulative
# threshold between 117 and 140 files), so a long list is run in separate processes and the FILE
# lines merged. Without this a suite of a few hundred files can lose most of its results to an
# abort with a stale program pointer.
$entries = Get-Content $List | Where-Object { $_.Trim() -ne "" }
$rows = @()
$chunkFiles = 0
$chunkPassed = 0
$chunkSubtests = 0
$failedChunks = @()
$at = 0
while ($at -lt $entries.Count) {
    $take = [Math]::Min($Chunk, $entries.Count - $at)
    $part = $entries[$at..($at + $take - 1)]
    $first = $at
    $at += $take
    $tmpList = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Tsv), "chunk-" + $at + ".txt")
    $part | Set-Content $tmpList -Encoding utf8
    # A chunk runs in its own process with a timeout: a test that sits at the interpreter's 5 GB
    # memory limit can take many minutes, and the whole gate must not wait on it.
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Tsv), "chunk-" + $at + ".out")
    $errFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Tsv), "chunk-" + $at + ".err")
    $proc = Start-Process -FilePath $Exe -ArgumentList @($Root, $tmpList) -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $finished = $proc.WaitForExit($ChunkTimeoutSeconds * 1000)
    if (-not $finished) {
        Stop-Process -Id $proc.Id -Force
        $failedChunks += "files $first-$($at - 1) (timed out after $ChunkTimeoutSeconds s)"
        Remove-Item $tmpList, $outFile, $errFile -Force -ErrorAction SilentlyContinue
        continue
    }
    $lines = Get-Content $outFile -ErrorAction SilentlyContinue
    Remove-Item $tmpList, $outFile, $errFile -Force -ErrorAction SilentlyContinue
    # A chunk that ran to the end prints its summary line; without it the chunk aborted, and the
    # merged totals would silently come out short, so say so.
    if (-not ($lines | Select-String '^wpt ')) {
        $failedChunks += "files $first-$($at - 1) (no summary)"
    }
    foreach ($line in $lines) {
        if ($line -notmatch '^FILE (\S+) (\d+)/(\d+)') { continue }
        $rows += [pscustomobject]@{ path = $matches[1]; passed = [int]$matches[2]; total = [int]$matches[3] }
        $chunkPassed += [int]$matches[2]
        $chunkSubtests += [int]$matches[3]
        $chunkFiles += 1
    }
}
foreach ($f in $failedChunks) { Write-Output "CHUNK ABORTED $f" }
$summary = "wpt $chunkFiles files $chunkSubtests subtests $chunkPassed pass"
if ($failedChunks.Count -gt 0) { $summary = "$summary  ($($failedChunks.Count) chunk(s) aborted)" }
$rows | ForEach-Object { "$($_.path)`t$($_.passed)`t$($_.total)" } | Set-Content $Tsv -Encoding utf8

if ($Update) {
    if ($Baseline -ne "") { Copy-Item $Tsv $Baseline -Force }
    Write-Output "$summary  (baseline written to $Baseline)"
    exit 0
}

if ($Baseline -eq "" -or -not (Test-Path $Baseline)) {
    Write-Output "$summary  (no baseline; results in $Tsv)"
    exit 0
}

$before = @{}
foreach ($line in Get-Content $Baseline) {
    $parts = $line -split "`t"
    if ($parts.Count -ge 3) { $before[$parts[0]] = [int]$parts[1] }
}
$drops = 0
$gains = 0
foreach ($row in $rows) {
    if ($before.ContainsKey($row.path)) {
        $delta = $row.passed - $before[$row.path]
        if ($delta -lt 0) { Write-Output "DROP $($row.path): $($before[$row.path]) -> $($row.passed)"; $drops += 1 }
        elseif ($delta -gt 0) { Write-Output "GAIN $($row.path): $($before[$row.path]) -> $($row.passed)"; $gains += 1 }
    } else {
        Write-Output "NEW  $($row.path): $($row.passed)/$($row.total)"
    }
}
foreach ($path in $before.Keys) {
    if (-not ($rows | Where-Object { $_.path -eq $path })) { Write-Output "MISSING $path (was $($before[$path]))"; $drops += 1 }
}
Write-Output "$summary  drops: $drops  gains: $gains"
if ($drops -gt 0) { exit 1 }
