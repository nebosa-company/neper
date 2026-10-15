param([string]$Exe = 'D:\Temp\claude\v3run\mtgstudio.exe', [string]$Out = 'D:\Temp\claude\v3grabs', [int]$Seconds = 25, [int]$Shots = 4)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> ForPid(uint pid) {
    var res = new List<IntPtr>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) res.Add(h); return true; }, IntPtr.Zero);
    return res;
  }
}
'@
[void][W]::SetProcessDPIAware()
New-Item -ItemType Directory -Force $Out | Out-Null
$p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru
$seen = @{}
$log = @()
for ($i = 0; $i -lt $Seconds; $i++) {
  Start-Sleep -Seconds 1
  if ($p.HasExited) { $log += "exited at ${i}s code $($p.ExitCode)"; break }
  foreach ($h in [W]::ForPid($p.Id)) {
    $t = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($h, $t, 256)
    $c = New-Object System.Text.StringBuilder 256; [void][W]::GetClassName($h, $c, 256)
    $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -lt 20 -or $hh -lt 20) { continue }
    $key = "$($h.ToInt64())"
    $count = [int]$seen[$key]
    if ($count -ge $Shots) { continue }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
    $ok = [W]::PrintWindow($h, $dc, 2)
    $g.ReleaseHdc($dc); $g.Dispose()
    $safe = ($t.ToString() -replace '[^A-Za-z0-9]+', '_').Trim('_'); if (-not $safe) { $safe = 'untitled' }
    $f = Join-Path $Out ("{0:D2}s_{1}_{2}_{3}.png" -f $i, $safe, $c.ToString(), $key)
    $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $seen[$key] = $count + 1
    $log += "${i}s title='$($t)' class=$($c) ${w}x${hh} printed=$ok -> $f"
  }
}
$log
if (-not $p.HasExited) { 'still running pid ' + $p.Id }
