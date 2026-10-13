param([string]$Proc = 'mtgstudio', [string]$Dir = 'D:\Temp\claude\gt\states', [string]$Script)
# steps: "move x y" | "click x y" | "rclick x y" | "dclick x y" | "key VK" | "wait ms" | "shot name"  (x y relative to the window's top-left)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class AW {
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
public struct RECT { public int L,T,R,B; } }
"@
[AW]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $Dir | Out-Null
$p = Get-Process $Proc | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
[AW]::SetForegroundWindow($h) | Out-Null
function Rect { $r = New-Object AW+RECT; [AW]::GetWindowRect($h, [ref]$r) | Out-Null; $r }
foreach ($s in ($Script -split ";")) {
  $s = $s.Trim()
  $t = $s -split ' '
  $r = Rect
  switch ($t[0]) {
    'move'   { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 400 }
    'click'  { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 150; [AW]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [AW]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600 }
    'dclick' { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 150; 1..2 | ForEach-Object { [AW]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [AW]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60 }; Start-Sleep -Milliseconds 600 }
    'rclick' { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 150; [AW]::mouse_event(8,0,0,0,[UIntPtr]::Zero); [AW]::mouse_event(16,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600 }
    'key'    { [AW]::keybd_event([byte][int]$t[1],0,0,[UIntPtr]::Zero); [AW]::keybd_event([byte][int]$t[1],0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 500 }
    'wait'   { Start-Sleep -Milliseconds ([int]$t[1]) }
    'shot'   {
      # the full screen, so popup menus (separate windows) are in it; cropped to the window plus margin
      $w = $r.R - $r.L; $hh = $r.B - $r.T
      $bmp = New-Object System.Drawing.Bitmap ($w + 40), ($hh + 40)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($r.L - 0, $r.T - 0, 0, 0, $bmp.Size)
      $bmp.Save((Join-Path $Dir ($t[1] + '.png'))); $bmp.Dispose()
    }
  }
}
