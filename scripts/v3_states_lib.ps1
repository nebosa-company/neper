# Shared helpers for driving a COPY of MTG Studio v3 with posted window messages only (no SendInput / mouse_event / keybd_event / SetCursorPos).
# Dot-source it:  . scripts\v3_states_lib.ps1   (used by grab_v3_states.ps1; also handy for interactive probing).
# The process is DPI unaware on purpose, like v3: every rect and pixel is 100 %.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc e, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr ChildWindowFromPointEx(IntPtr h, POINT p, uint f);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetFocus();
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Text(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static int[] Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return new[]{r.L, r.T, r.R-r.L, r.B-r.T}; }
  public static uint Tid(IntPtr h) { uint p; return GetWindowThreadProcessId(h, out p); }
  public static List<IntPtr> ForPid(uint pid) {
    var res = new List<IntPtr>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) res.Add(h); return true; }, IntPtr.Zero);
    return res;
  }
  public static List<IntPtr> Children(IntPtr h) {
    var res = new List<IntPtr>();
    EnumChildWindows(h, (c, l) => { res.Add(c); return true; }, IntPtr.Zero);
    return res;
  }
  public static bool Alive(IntPtr h) { IntPtr r; return SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 2, 1500, out r) != IntPtr.Zero; }
  // deepest visible child of top at a SCREEN point: returns {hwnd, clientX, clientY}
  public static long[] Deep(IntPtr top, int sx, int sy) {
    IntPtr cur = top;
    for (int i = 0; i < 20; i++) {
      POINT p; p.X = sx; p.Y = sy; ScreenToClient(cur, ref p);
      IntPtr c = ChildWindowFromPointEx(cur, p, 1 /*skip invisible*/);
      if (c == IntPtr.Zero || c == cur) return new long[]{ cur.ToInt64(), p.X, p.Y };
      cur = c;
    }
    POINT q; q.X = sx; q.Y = sy; ScreenToClient(cur, ref q);
    return new long[]{ cur.ToInt64(), q.X, q.Y };
  }
  // programmatic focus: attach our input queue to the target thread, SetFocus, detach (no physical input involved)
  public static IntPtr FocusOn(IntPtr h) {
    uint t = Tid(h), me = GetCurrentThreadId();
    AttachThreadInput(me, t, true);
    IntPtr r = SetFocus(h);
    AttachThreadInput(me, t, false);
    return r;
  }
}
'@

$script:Exe = 'D:\Temp\claude\v3run\mtgstudio_s.exe'   # patched copy, mutex renamed so it runs beside a normal instance (see Make-PatchedCopy)
# v3 allows one instance per session (named mutex MtgStudioSetupRunPreventionMutex). When the maintainer's own v3 is running, the plain copy
# only shows "already started". This writes mtgstudio_s.exe: the same bytes with the last mutex character changed (x -> y). Never touches the repo.
function Make-PatchedCopy($src='D:\Temp\claude\v3run\mtgstudio.exe',$dst='D:\Temp\claude\v3run\mtgstudio_s.exe'){
  if(Test-Path $dst){ return }
  $b=[IO.File]::ReadAllBytes($src); $pat=[Text.Encoding]::Unicode.GetBytes('MtgStudioSetupRunPreventionMutex'); $hit=0
  for($i=0;$i -le $b.Length-$pat.Length;$i++){ if($b[$i] -eq $pat[0]){ $ok=$true; for($j=1;$j -lt $pat.Length;$j++){ if($b[$i+$j] -ne $pat[$j]){$ok=$false;break} }; if($ok){ $b[$i+$pat.Length-2]=[byte][char]'y'; $hit++ } } }
  if($hit -ne 1){ throw "expected 1 mutex string, found $hit" }
  [IO.File]::WriteAllBytes($dst,$b) }
Make-PatchedCopy
$script:Out = 'D:\repos\neper\docs\ui\looks\ref\windows\states'
$script:p = $null
$script:Rows = New-Object System.Collections.ArrayList
$script:MenuX=[ordered]@{File=25;Cards=60;Search=105;View=149;'Card Art'=197;Online=249;Reports=299;Tools=347;Admin=390;Help=431}

function Top($p) { @([W]::ForPid($p.Id) | % { [pscustomobject]@{H=$_; C=[W]::Cls($_); T=[W]::Text($_); R=([W]::Rect($_) -join ',') } }) }
function MainH { (Top $script:p | ?{$_.C -eq 'TMainForm'}).H }
function Start-App($deck=$null) {
  if($deck){ $script:p = Start-Process -FilePath $script:Exe -ArgumentList ('"'+$deck+'"') -WorkingDirectory (Split-Path $script:Exe) -PassThru }
  else { $script:p = Start-Process -FilePath $script:Exe -WorkingDirectory (Split-Path $script:Exe) -PassThru }
  for($i=0;$i -lt 80;$i++){ Start-Sleep -Milliseconds 500; if((Top $script:p|?{$_.C -eq 'TMainForm'})){ Start-Sleep 3; return } }
  throw 'main window did not appear' }
function Attach-App { # attach to the running COPY (never the repo's instance)
  $q = Get-Process mtgstudio_s -ErrorAction SilentlyContinue | select -first 1
  if($q){ $script:p = $q } else { Start-App } }
function Ensure-App { if($script:p.HasExited -or -not [W]::Alive((MainH))){ "  app dead/hung, restarting"; try{$script:p.Kill()}catch{}; Start-Sleep 1; Start-App } }
function Restart-App { try{$script:p.Kill()}catch{}; Start-Sleep 1; Start-App }

function Pt($x,$y){ [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF)) }
function Msg($h,$m,$w=0,$l=0){ [void][W]::PostMessage($h,[uint32]$m,[IntPtr]$w,[IntPtr]$l) }
# --- pointer messages to a specific window at its CLIENT coordinates
function MoveC($h,$x,$y,$w=0){ Msg $h 0x200 $w (Pt $x $y) }
function DownC($h,$x,$y){ Msg $h 0x201 1 (Pt $x $y) }
function UpC($h,$x,$y){ Msg $h 0x202 0 (Pt $x $y) }
function ClickC($h,$x,$y){ MoveC $h $x $y; DownC $h $x $y; UpC $h $x $y }
# --- the same by IMAGE coordinates of a top-level window (window-rect relative, as in the PNGs): finds the deepest child there
function Under($top,$px,$py){ $r=[W]::Rect($top); $d=[W]::Deep($top,$r[0]+$px,$r[1]+$py); [pscustomobject]@{H=[IntPtr]$d[0];X=[int]$d[1];Y=[int]$d[2];Cls=[W]::Cls([IntPtr]$d[0])} }
function PMove($top,$px,$py){ $u=Under $top $px $py; MoveC $u.H $u.X $u.Y; $u }
function PDown($top,$px,$py){ $u=Under $top $px $py; MoveC $u.H $u.X $u.Y; DownC $u.H $u.X $u.Y; $u }
function PUp($top,$px,$py){ $u=Under $top $px $py; UpC $u.H $u.X $u.Y; $u }
function PClick($top,$px,$py){ $u=Under $top $px $py; ClickC $u.H $u.X $u.Y; $u }
# hover: first a move well away (so the control sees a fresh enter), then onto the target, then wait
function Hover($top,$px,$py,$wait=350,$away=@(2,2)){ [void](PMove $top $away[0] $away[1]); Start-Sleep -Milliseconds 120; $u=PMove $top $px $py; Start-Sleep -Milliseconds $wait; $u }
function Leave($top){ $u=Under $top 2 2; MoveC $u.H $u.X $u.Y; Msg $u.H 0x2A3 0 0; Start-Sleep -Milliseconds 200 } # WM_MOUSELEAVE to what is at 2,2
function Key($h,$vk,$ext=0){ Msg $h 0x100 $vk (1 -bor ($ext -shl 24)); Msg $h 0x101 $vk (0xC0000001 -bor ($ext -shl 24)) }
function KeyDown($h,$vk){ Msg $h 0x100 $vk 1 }
function KeyUp($h,$vk){ Msg $h 0x101 $vk 0xC0000001 }
function Esc($h){ Key $h 0x1B }
function CloseWin($h){ Msg $h 0x10 }
function Focus($h){ [void][W]::FocusOn($h) }

function Grab($h,$f){ $r=[W]::Rect($h); $bmp=New-Object System.Drawing.Bitmap ([int]$r[2]),([int]$r[3]); $g=[System.Drawing.Graphics]::FromImage($bmp); $dc=$g.GetHdc(); [void][W]::PrintWindow($h,$dc,2); $g.ReleaseHdc($dc); $g.Dispose(); New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; $bmp.Save($f); $bmp.Dispose() }
function Controls($h){ $r=[W]::Rect($h); $o=@(); foreach($c in [W]::Children($h)){ $cr=[W]::Rect($c); $o+=[pscustomobject]@{class=[W]::Cls($c);text=[W]::Text($c);visible=[W]::IsWindowVisible($c);enabled=[W]::IsWindowEnabled($c);x=$cr[0]-$r[0];y=$cr[1]-$r[1];w=$cr[2];h=$cr[3];id=[W]::GetDlgCtrlID($c);hwnd=$c.ToInt64()} }; $o }
function Popups { Top $script:p | ?{$_.C -like 'TdxBar*Sub*' -or $_.C -like 'Tcx*Popup*' -or $_.C -like '*DropDown*' -or $_.C -like 'TdxHint*' -or $_.C -like 'TcxHint*' -or $_.C -like 'TdxScreenTip*'} }
function Others { Top $script:p | ?{ $_.C -notin 'TMainForm','TApplication' -and $_.C -notlike 'TdxBar*Sub*' } }
# every top-level window of the process, for diagnosing what class a hint / drop-down has
function Dump-Top { Top $script:p | %{ "{0,-28} '{1}' {2}" -f $_.C,$_.T,$_.R } }

# Save a window as states/<name>@1x.png and append a manifest row
function Shot($h,$name,$control,$state,$how,$notes='',[switch]$Json){
  if(-not [W]::IsWindow($h)){ "  !! $name : window gone"; return }
  Grab $h (Join-Path $script:Out "$name@1x.png")
  $r=[W]::Rect($h)
  if($Json){ [ordered]@{name=$name;control=$control;state=$state;how=$how;class=[W]::Cls($h);title=[W]::Text($h);width=$r[2];height=$r[3];dpi='100 % (v3 is DPI unaware)';controls=@(Controls $h)} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:Out "$name.controls.json") -Encoding UTF8 }
  [void]$script:Rows.Add([pscustomobject]@{File="$name@1x.png";Control=$control;State=$state;How=$how;Class=[W]::Cls($h);Size="$($r[2])x$($r[3])";Notes=$notes})
  "  shot $name ($($r[2])x$($r[3]))"
}
function Close-Win($h){ CloseWin $h; for($i=0;$i -lt 8;$i++){ Start-Sleep -Milliseconds 400; if(-not [W]::IsWindow($h) -or -not [W]::IsWindowVisible($h)){return $true} }
  Msg $h 0x111 2 0; Start-Sleep 1; if(-not [W]::IsWindow($h) -or -not [W]::IsWindowVisible($h)){return $true}; Esc $h; Start-Sleep 1; (-not [W]::IsWindow($h)) -or (-not [W]::IsWindowVisible($h)) }
function Close-Popups { for($i=0;$i -lt 4;$i++){ $pp=Popups; if(-not $pp){return}; foreach($x in $pp){Esc $x.H}; Start-Sleep -Milliseconds 600 } }
function MenuBar { [W]::Children((MainH)) | ? {[W]::Cls($_) -eq 'TdxBarControl' -and [W]::Text($_) -eq 'Main Menu'} | select -first 1 }
function Open-Menu($title){ Close-Popups; ClickC (MenuBar) $script:MenuX[$title] 13; for($i=0;$i -lt 10;$i++){ Start-Sleep -Milliseconds 300; $pp=Popups; if($pp){ return $pp[0].H } }; $null }
function Open-Dialog($menu,$y,$timeout=20){ Close-Popups; $pop=Open-Menu $menu; if(-not $pop){ return $null }; ClickC $pop 60 $y
  for($i=0;$i -lt $timeout*2;$i++){ Start-Sleep -Milliseconds 500; $w = Others | select -first 1; if($w){ Start-Sleep 1.5; return $w.H } }; $null }

# ---- activation / lookup helpers
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);' -Name FG -Namespace X -ErrorAction SilentlyContinue
# makes h the foreground window by attaching input queues for a moment (no input is simulated); needed for "active" paint states and drop-downs that close when the owner is inactive
function Activate($h){ $fg=[W]::GetForegroundWindow(); $ft=[W]::Tid($fg); $me=[W]::GetCurrentThreadId(); $mt=[W]::Tid($h)
  [void][W]::AttachThreadInput($me,$ft,$true); [void][W]::AttachThreadInput($me,$mt,$true); [void][X.FG]::SetForegroundWindow($h); [void][W]::AttachThreadInput($me,$ft,$false); [void][W]::AttachThreadInput($me,$mt,$false); Start-Sleep -Milliseconds 300 }
# find a visible child by class and (optional) text / nearby position; hwnds change whenever a page is rebuilt, so always look them up fresh
function Find-Ctl($top,$class,$text=$null,$x=$null,$y=$null){
  $r=[W]::Rect($top); foreach($c in [W]::Children($top)){ if(-not [W]::IsWindowVisible($c)){continue}; if([W]::Cls($c) -ne $class){continue}
    if($text -and [W]::Text($c) -notlike $text){continue}
    $cr=[W]::Rect($c); if($x -ne $null -and ([math]::Abs($cr[0]-$r[0]-$x) -gt 3 -or [math]::Abs($cr[1]-$r[1]-$y) -gt 3)){continue}
    return $c } }
function Options-Page($d,$n){ $cat=[W]::Children($d)|?{[W]::Cls($_) -eq 'TCategoryButtons'}|select -first 1; ClickC $cat 100 (23+36*($n-1)); Start-Sleep -Milliseconds 1300 }
function Poll-New($known,$ms=1500){ for($i=0;$i -lt $ms/50;$i++){ $n=Top $script:p | ?{ $_.H -notin $known }; if($n){ return $n }; Start-Sleep -Milliseconds 50 } }

# The patched copy names its own collection file mtgstudio_s.collection (empty at first, which disables Missing Set Cards, Combos... in Reports).
# Give it a COPY of the maintainer's collection, and a COPY of a deck file to open from the command line (read only; the Desktop original is never opened).
function Prepare-Data {
  $dir = Join-Path $env:APPDATA 'MTG Studio'
  try { Copy-Item (Join-Path $dir 'mtgstudio.collection') (Join-Path $dir 'mtgstudio_s.collection') -Force } catch { "  collection copy failed: $_" }
  $src = Join-Path $env:USERPROFILE 'Desktop\New Deck.deck'
  if(Test-Path $src){ Copy-Item $src 'D:\Temp\claude\v3run\Probe Deck.deck' -Force }
}
function Start-With-Deck { try{$script:p.Kill()}catch{}; Start-Sleep 2; Start-App 'D:\Temp\claude\v3run\Probe Deck.deck' }
