param([string]$Proc = 'mtgstudio', [string]$Out = 'D:\Temp\claude\gt\ref.png', [int]$X = 20, [int]$Y = 20, [int]$W = 0, [int]$H = 0)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SW { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x,int y,int cx,int cy,uint f);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
public struct RECT { public int L,T,R,B; } }
"@
[SW]::SetProcessDPIAware() | Out-Null
$p = Get-Process $Proc | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
[SW]::ShowWindow($h, 9) | Out-Null
if ($W -gt 0) { [SW]::SetWindowPos($h, [IntPtr](-1), $X, $Y, $W, $H, 0x0040) | Out-Null } else { [SW]::SetWindowPos($h, [IntPtr](-1), $X, $Y, 0, 0, 0x0041) | Out-Null }
Start-Sleep -Milliseconds 800
$r = New-Object SW+RECT; [SW]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R-$r.L), ($r.B-$r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out); "$($r.L) $($r.T) $($r.R) $($r.B)"
