# Regenerates docs/ui/looks/ref/flutter. Needs Flutter on PATH (offline is fine) and the cupertino_icons font in the pub cache.
# Usage: pwsh scripts/flutter_refs/run.ps1   (from the repo root)
$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$proj = 'D:/Temp/flutter-looks'
New-Item -ItemType Directory -Force "$proj/test" | Out-Null
Copy-Item scripts/flutter_refs/pubspec.yaml $proj
Copy-Item scripts/flutter_refs/*.dart "$proj/test"
$out = "$repo/docs/ui/looks/ref/flutter"
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $proj
flutter pub get --offline
$env:OUT = $out
foreach ($f in 'neper', 'material', 'cupertino') { flutter test "test/${f}_test.dart" }
Pop-Location
$rows = Get-Content "$out/manifest.csv"
Set-Content "$out/manifest.csv" (@('file,family,mode,control,state,ratio,neper_id,flutter_widget') + $rows)
