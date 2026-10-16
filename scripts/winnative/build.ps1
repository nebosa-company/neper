# Builds gallery.exe (x86: the pointer hook is x86) + v3hook.dll into D:\Temp\claude\winnative. Needs zig (D:\tools\zig). Writes nothing to the repo.
$out = 'D:\Temp\claude\winnative'; New-Item -ItemType Directory -Force $out | Out-Null
$zig = 'D:\tools\zig\zig.exe'
& $zig cc -target x86-windows-gnu -O2 -shared -o "$out\v3hook.dll" "$PSScriptRoot\..\v3_hook\v3hook.c" -lpsapi -luser32 -lkernel32
if ($LASTEXITCODE -ne 0) { throw 'hook build failed' }
& $zig cc -target x86-windows-gnu -O1 -o "$out\gallery.exe" "$PSScriptRoot\gallery.c" -lcomctl32 -luxtheme -ldwmapi -lgdi32 -luser32 -lshell32 -lkernel32 -lole32 -loleaut32
if ($LASTEXITCODE -ne 0) { throw 'gallery build failed' }
Copy-Item "$PSScriptRoot\gallery.manifest" $out -Force
Get-ChildItem $out | Where-Object { $_.Extension -in '.exe','.dll','.manifest' }
