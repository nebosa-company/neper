# Builds glyphs.exe (x64, no hook needed) and writes the glyph oracle into docs\ui\looks\ref\windows-native\glyphs (see the README there).
# Real GDI ClearType, every code 32..255 of Segoe UI and Tahoma, regular and bold, at the sizes the Windows looks use. No window is shown.
param([switch]$NoBuild)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
$bin = 'D:\Temp\claude\winnative'; $raw = "$bin\glyphs"
New-Item -ItemType Directory -Force $raw | Out-Null
if (-not $NoBuild) {
  & 'D:\tools\zig\zig.exe' cc -target x86_64-windows-gnu -O1 -o "$bin\glyphs.exe" "$PSScriptRoot\glyphs.c" -lgdi32 -luser32
  if ($LASTEXITCODE -ne 0) { throw 'glyphs build failed' }
}
Remove-Item "$raw\*" -Force -ErrorAction SilentlyContinue
$q = 5  # CLEARTYPE_QUALITY; finish.py's check shows it equals the message font's DEFAULT_QUALITY and differs from NATURAL
$segoe = 11, 12, 13, 14, 15, 16, 18, 24
$tahoma = 11, 12, 13, 14, 16, 21
$base = @('000000', 'FFFFFF', 'FFFFFF', '000000')
$looks = @('FFFFFF', '202020', '000000', 'F0F0F0', '6D6D6D', 'F0F0F0', 'FFFFFF', '0078D7')
foreach ($spec in @(@('Segoe UI', $segoe), @('Tahoma', $tahoma))) {
  foreach ($weight in 400, 700) {
    foreach ($px in $spec[1]) {
      $pairs = $base
      if ($weight -eq 400 -and (($spec[0] -eq 'Segoe UI' -and $px -eq 12) -or ($spec[0] -eq 'Tahoma' -and $px -eq 11))) { $pairs = $base + $looks }
      & "$bin\glyphs.exe" $raw $spec[0] $weight $px $q @pairs
      if ($LASTEXITCODE -ne 0) { throw "glyphs failed: $($spec[0]) $weight $px" }
    }
  }
}
& "$bin\glyphs.exe" $raw --blend 5
& "$bin\glyphs.exe" $raw --blend 6
& "$bin\glyphs.exe" $raw --blend2 5
& "$bin\glyphs.exe" $raw --settings | Out-File "$raw\settings.txt" -Encoding ascii
python "$PSScriptRoot\glyphs_finish.py" $raw "$root\docs\ui\looks\ref\windows-native\glyphs"
