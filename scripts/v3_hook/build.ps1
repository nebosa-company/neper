# Builds v3hook.dll and inject.exe (both x86) into D:\Temp\claude\v3run\hook. Needs zig (D:\tools\zig). Nothing is written to the repo or to v3.
$out = 'D:\Temp\claude\v3run\hook'; New-Item -ItemType Directory -Force $out | Out-Null
$zig = 'D:\tools\zig\zig.exe'
& $zig cc -target x86-windows-gnu -O2 -shared -o "$out\v3hook.dll" "$PSScriptRoot\v3hook.c" -lpsapi -luser32 -lkernel32
& $zig cc -target x86-windows-gnu -O2 -municode -o "$out\inject.exe" "$PSScriptRoot\inject.c" -lkernel32
Get-ChildItem $out
if($LASTEXITCODE -ne 0){ throw 'build failed' }
