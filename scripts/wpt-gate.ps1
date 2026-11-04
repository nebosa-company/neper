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
    [string]$Tsv = ""
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Exe)) { throw "runner not found: $Exe" }
if (-not (Test-Path $List)) { throw "list not found: $List" }
if ($Tsv -eq "") { $Tsv = [System.IO.Path]::ChangeExtension($List, ".tsv") }

$lines = & $Exe $Root $List 2>&1
$summary = ($lines | Select-String '^wpt ' | Select-Object -Last 1).Line
$rows = @()
foreach ($line in $lines) {
    if ($line -notmatch '^FILE (\S+) (\d+)/(\d+)') { continue }
    $rows += [pscustomobject]@{ path = $matches[1]; passed = [int]$matches[2]; total = [int]$matches[3] }
}
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
