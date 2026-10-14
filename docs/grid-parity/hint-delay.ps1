param([string]$Proc,[int]$X,[int]$Y)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class TT { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
public struct RECT { public int L,T,R,B; } }
"@
[TT]::SetProcessDPIAware() | Out-Null
$p = Get-Process $Proc | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle; [TT]::SetForegroundWindow($h) | Out-Null
$r = New-Object TT+RECT; [TT]::GetWindowRect($h,[ref]$r) | Out-Null
$px = $r.L + $X; $py = $r.T + $Y
function Grab { $b = New-Object System.Drawing.Bitmap 160,26; $g=[System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($px+10,$py+22,0,0,$b.Size); $g.Dispose(); $b }
function Same($a,$b){ for($i=0;$i -lt 160;$i+=3){ for($j=0;$j -lt 26;$j+=3){ if($a.GetPixel($i,$j).ToArgb() -ne $b.GetPixel($i,$j).ToArgb()){ return $false } } } return $true }
[TT]::SetCursorPos($r.L+5,$r.T+600) | Out-Null; Start-Sleep -Milliseconds 1500
$base = Grab
$sw=[System.Diagnostics.Stopwatch]::StartNew()
[TT]::SetCursorPos($px,$py) | Out-Null
$hit=-1
while($sw.ElapsedMilliseconds -lt 3000){ $c = Grab; if(-not (Same $base $c)){ $hit=$sw.ElapsedMilliseconds; break } }
"$Proc tooltip region changed at $hit ms"
