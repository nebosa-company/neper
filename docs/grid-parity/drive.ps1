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
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
public struct RECT { public int L,T,R,B; } }
"@
[AW]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $Dir | Out-Null
$p = Get-Process $Proc | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
if (-not $h -or $h -eq [IntPtr]::Zero) { throw "no window for ${Proc}: refusing to click" }
[AW]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [AW]::keybd_event(0x12,0,2,[UIntPtr]::Zero)
[AW]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
function FrontIsTarget0 { $fp = 0; [AW]::GetWindowThreadProcessId([AW]::GetForegroundWindow(), [ref]$fp) | Out-Null; return ($fp -eq $p.Id) }
function FrontIsTarget { for ($k = 0; $k -lt 6; $k++) { if (FrontIsTarget0) { return $true }; [AW]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [AW]::keybd_event(0x12,0,2,[UIntPtr]::Zero); [AW]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 500 }; return $false }
if (-not (FrontIsTarget)) { throw "${Proc} is not in front: refusing to click" }
function Rect { $r = New-Object AW+RECT; [AW]::GetWindowRect($h, [ref]$r) | Out-Null; $r }
& (Join-Path $PSScriptRoot 'mouse-warning.ps1') show
try {
foreach ($s in ($Script -split ";")) {
  $s = $s.Trim()
  $t = $s -split ' '
  $r = Rect
  if (($t[0] -ne "wait") -and ($t[0] -ne "shot") -and (-not (FrontIsTarget))) { throw "${Proc} lost the foreground before ${s}: stopping" }
  switch ($t[0]) {
    'move'   { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 400 }
    'click'  { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 150; [AW]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [AW]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600 }
    'dclick' { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 150; 1..2 | ForEach-Object { [AW]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [AW]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60 }; Start-Sleep -Milliseconds 600 }
    'rclick' { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 150; [AW]::mouse_event(8,0,0,0,[UIntPtr]::Zero); [AW]::mouse_event(16,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600 }
    'key'    { [AW]::keybd_event([byte][int]$t[1],0,0,[UIntPtr]::Zero); [AW]::keybd_event([byte][int]$t[1],0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 500 }
    'kd'     { [AW]::keybd_event([byte][int]$t[1],0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
    'ku'     { [AW]::keybd_event([byte][int]$t[1],0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 150 }
    'down'   { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 200; [AW]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 300 }
    'drag'   { $x0 = [int]$t[1]; $y0 = [int]$t[2]; $x1 = [int]$t[3]; $y1 = [int]$t[4]; foreach ($i in 1..12) { [AW]::SetCursorPos($r.L + $x0 + [int](($x1-$x0)*$i/12), $r.T + $y0 + [int](($y1-$y0)*$i/12)) | Out-Null; Start-Sleep -Milliseconds 60 }; Start-Sleep -Milliseconds 400 }
    'up'     { [AW]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 500 }
    'wheel'  { [AW]::SetCursorPos($r.L + [int]$t[1], $r.T + [int]$t[2]) | Out-Null; Start-Sleep -Milliseconds 200; [AW]::mouse_event(0x0800,0,0,[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]([int]$t[3] * 120)),0),[UIntPtr]::Zero); Start-Sleep -Milliseconds 600 }
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
} finally {
  & (Join-Path $PSScriptRoot 'mouse-warning.ps1') hide
}
