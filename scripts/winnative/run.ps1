# Runs the native Win32 gallery (light and dark, 100 % and 150 %) and writes docs\ui\looks\ref\windows-native.
# Order matters: the instances share the hook's memory block (Local\v3hover), so they run one after the other.
param([string]$Only = '-', [string]$Case = '', [switch]$NoBuild, [int[]]$Dpis = @(100, 150))
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
$bin = 'D:\Temp\claude\winnative'; $out = "$bin\out"
if (-not $NoBuild) { & "$PSScriptRoot\build.ps1" | Out-Null }
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
foreach ($theme in 'light', 'dark') {
  foreach ($dpi in $Dpis) {
    $a = @($out, $theme, "$dpi", $Only); if ($Case) { $a += $Case }
    $p = Start-Process "$bin\gallery.exe" -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput "$bin\run-$theme-$dpi.txt"
    if (-not $p.WaitForExit(600000)) { $p.Kill(); Write-Warning "$theme $dpi timed out" }   # a modal loop that never ends: the grabs written so far are kept
  }
}
python "$PSScriptRoot\finish.py" $out "$root\docs\ui\looks\ref\windows-native"
