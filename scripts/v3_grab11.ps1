# True 1:1 window grab of the v3 COPY (dot-source it; used by v3_states_lib.ps1 and grab_v3_dialogs.ps1).
#
# Why: v3 is DPI unaware. On a desktop scaled above 100 % the system draws it at 100 % and DWM stretches the surface, so PrintWindow(flag 2,
# PW_RENDERFULLCONTENT), which takes the composed surface and hands it back at 100 %, returns a bilinear resample of the stretch: every glyph
# is smeared (see docs/ui/looks/ref/windows-1to1/README.md). PrintWindow(flag 0) sends WM_PRINT and the controls paint themselves at 96 dpi: crisp,
# integer-pixel Tahoma. But flag 0 draws the classic caption frame, so the frame (title bar, borders) is kept from the flag 2 grab and only
# the CLIENT rectangle is replaced by the flag 0 grab. A client that comes back flat (a child that does not answer WM_PRINT) stays as flag 2.
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class G {
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
  // window size and client rectangle inside the window: w, h, cx, cy, cw, ch
  public static int[] Geo(IntPtr h) {
    RECT wr; GetWindowRect(h, out wr); RECT cr; GetClientRect(h, out cr); POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o);
    return new[]{ wr.R - wr.L, wr.B - wr.T, o.X - wr.L, o.Y - wr.T, cr.R, cr.B }; }
}
'@
function Print-Bmp($h,$w,$hh,$flag){ $b=New-Object System.Drawing.Bitmap $w,$hh; $g=[System.Drawing.Graphics]::FromImage($b); $dc=$g.GetHdc(); [void][G]::PrintWindow($h,$dc,$flag); $g.ReleaseHdc($dc); $g.Dispose(); $b }
function Flat-Rect($b,$x,$y,$w,$h){ $c=$b.GetPixel($x,$y); for($j=$y;$j -lt $y+$h;$j+=4){ for($i=$x;$i -lt $x+$w;$i+=4){ if($b.GetPixel($i,$j).ToArgb() -ne $c.ToArgb()){ return $false } } }; $true }
# Pixels more than 2 levels apart between two grabs inside a rectangle. With V3_GRAB_LOG set, Grab11 logs it per grab (flag 0 against flag 2):
# 0 for a popup means its flag 2 grab was never resampled.
function Diff-Count($a,$b,$x,$y,$w,$h){ $n=0; for($j=$y;$j -lt $y+$h;$j++){ for($i=$x;$i -lt $x+$w;$i++){ $p=$a.GetPixel($i,$j); $q=$b.GetPixel($i,$j); if([math]::Abs($p.R-$q.R) -gt 2 -or [math]::Abs($p.G-$q.G) -gt 2 -or [math]::Abs($p.B-$q.B) -gt 2){ $n++ } } }; $n }
function Grab11($h,$f){
  $o=[G]::Geo($h); $w=$o[0]; $hh=$o[1]; $cx=$o[2]; $cy=$o[3]; $cw=$o[4]; $ch=$o[5]
  $b2=Print-Bmp $h $w $hh 2
  if($cw -gt 0 -and $ch -gt 0 -and $cx -ge 0 -and $cy -ge 0 -and ($cx+$cw) -le $w -and ($cy+$ch) -le $hh){
    $b0=Print-Bmp $h $w $hh 0
    if($env:V3_GRAB_LOG){ $d=-1; if($cw*$ch -le 120000){ $d=Diff-Count $b0 $b2 $cx $cy $cw $ch }; Add-Content $env:V3_GRAB_LOG ("{0}`tclient {1},{2} {3}x{4}`tflag0Flat={5}`tflag2Flat={6}`tflag0vs2Px={7}" -f (Split-Path $f -Leaf),$cx,$cy,$cw,$ch,(Flat-Rect $b0 $cx $cy $cw $ch),(Flat-Rect $b2 $cx $cy $cw $ch),$d) }
    if(-not (Flat-Rect $b0 $cx $cy $cw $ch) -or (Flat-Rect $b2 $cx $cy $cw $ch)){
      $g=[System.Drawing.Graphics]::FromImage($b2); $r=New-Object System.Drawing.Rectangle $cx,$cy,$cw,$ch
      $g.DrawImage($b0,$r,$r,[System.Drawing.GraphicsUnit]::Pixel); $g.Dispose() }
    $b0.Dispose() }
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  $b2.Save($f,[System.Drawing.Imaging.ImageFormat]::Png); $b2.Dispose() }
