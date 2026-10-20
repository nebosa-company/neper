<#
.SYNOPSIS  Capture reference screenshots of the real MTG Studio v3 dialogs, menus and windows.
.DESCRIPTION
  Launches a COPY of mtgstudio.exe (never the repo or installed one) and drives it WITHOUT physical input:
  menu titles and items are opened by posting WM_MOUSEMOVE/WM_LBUTTONDOWN/WM_LBUTTONUP to the dxBar windows,
  Options pages by clicking its TCategoryButtons the same way, dialogs are closed with WM_CLOSE (fallback
  WM_COMMAND IDCANCEL, Esc). Each window is saved with Win32 PrintWindow(flag 2) plus a controls JSON.
  This process is deliberately DPI UNAWARE (as v3 is), so rects/pixels are 100 % regardless of desktop scale.
  dxBar exposes no usable MSAA/UIA children (every child id answers with the parent), so item positions are a
  hand-measured table (menu popup client y) taken from the menu-*@1x.png captures; re-measure if menus change.
  Only information/settings items are listed; anything that edits, deletes, imports, prints or goes online is
  skipped (see $Skipped, written to the README).
.EXAMPLE   pwsh -File scripts\grab_v3_dialogs.ps1
#>
param(
  [string]$Exe = 'D:\Temp\claude\v3run\mtgstudio.exe',   # a COPY with its own mtgstudio.db3
  [string]$Out = (Join-Path $PSScriptRoot '..\docs\ui\looks\ref\windows-1to1\dialogs'),
  [int]$OpenTimeoutSec = 20
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'v3_grab11.ps1')
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
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint c);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static string Text(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static int[] Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return new[]{r.L, r.T, r.R-r.L, r.B-r.T}; }
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
}
'@

function Start-V3($exe) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru }
function Top($p) { @([W]::ForPid($p.Id) | % { [pscustomobject]@{H=$_; C=[W]::Cls($_); T=[W]::Text($_); R=([W]::Rect($_) -join ',') } }) }
function Wait-Main($p, $sec=40) { for($i=0;$i -lt $sec*2;$i++){ Start-Sleep -Milliseconds 500; $m = Top $p | ? {$_.C -eq 'TMainForm'}; if($m){ Start-Sleep 3; return $m.H } } }
$script:MenuX=[ordered]@{File=25;Cards=60;Search=105;View=149;'Card Art'=197;Online=249;Reports=299;Tools=347;Admin=390;Help=431}
function Grab($h,$f){ Grab11 $h $f }
function Click($h,$x,$y){ $l=[IntPtr](($y -shl 16) -bor ($x -band 0xFFFF)); [void][W]::PostMessage($h,0x200,[IntPtr]0,$l); [void][W]::PostMessage($h,0x201,[IntPtr]1,$l); [void][W]::PostMessage($h,0x202,[IntPtr]0,$l) }
function Esc($h){ [void][W]::PostMessage($h,0x100,[IntPtr]0x1B,[IntPtr]0); [void][W]::PostMessage($h,0x101,[IntPtr]0x1B,[IntPtr]0xC0000001) }
function Popups($p){ Top $p | ?{$_.C -like 'TdxBar*Sub*'} }
function Close-Popups($p){ for($i=0;$i -lt 4;$i++){ $pp=Popups $p; if(-not $pp){return}; foreach($x in $pp){Esc $x.H}; Start-Sleep -Milliseconds 600 } }
function MainH($p){ (Top $p|?{$_.C -eq 'TMainForm'}).H }
function MenuBar($p){ [W]::Children((MainH $p)) | ? {[W]::Cls($_) -eq 'TdxBarControl' -and [W]::Text($_) -eq 'Main Menu'} | select -first 1 }
function Open-Menu($p,$title){ Close-Popups $p; Click (MenuBar $p) $script:MenuX[$title] 13; for($i=0;$i -lt 10;$i++){ Start-Sleep -Milliseconds 300; $pp=Popups $p; if($pp){ return $pp[0].H } }; $null }
# windows that are not main/app/popup
function Others($p){ Top $p | ?{ $_.C -notin 'TMainForm','TApplication' -and $_.C -notlike 'TdxBar*Sub*' } }
function Controls($h){ $r=[W]::Rect($h); $o=@(); foreach($c in [W]::Children($h)){ $cr=[W]::Rect($c); $o+=[pscustomobject]@{class=[W]::Cls($c);text=[W]::Text($c);visible=[W]::IsWindowVisible($c);x=$cr[0]-$r[0];y=$cr[1]-$r[1];w=$cr[2];h=$cr[3];id=[W]::GetDlgCtrlID($c);hwnd=$c.ToInt64()} }; $o }
function Close-Win($p,$h){ [void][W]::PostMessage($h,0x10,[IntPtr]0,[IntPtr]0); for($i=0;$i -lt 8;$i++){ Start-Sleep -Milliseconds 400; if(-not [W]::IsWindow($h) -or -not [W]::IsWindowVisible($h)){return $true} }
  [void][W]::PostMessage($h,0x111,[IntPtr]2,[IntPtr]0); Start-Sleep 1; if(-not [W]::IsWindow($h) -or -not [W]::IsWindowVisible($h)){return $true}; Esc $h; Start-Sleep 1; (-not [W]::IsWindow($h)) -or (-not [W]::IsWindowVisible($h)) }

# ---- targets: name, menu title, item y in the popup (100 % client px), form-notes ----
$Targets = @(
  @('search-filter-top','Search',13),@('search-filter-bottom','Search',33),@('search-advanced-filter','Search',53),
  @('search-search','Search',221),
  @('view-sort','View',75),@('view-legality','View',263),@('view-card-rules','View',283),
  @('view-show-columns','View',303),@('view-conditional-formatting','View',483),
  @('cardart-preview','Card Art',33),
  @('reports-missing-set-cards','Reports',103),@('reports-combos-from-collection','Reports',123),
  @('reports-edition-availability','Reports',143),@('reports-card-quantities','Reports',163),@('reports-scorepad','Reports',193),
  @('tools-locate-my-collection','Tools',13),@('tools-options','Tools',153),
  @('help-game-rules','Help',53),@('help-version-history','Help',73),@('help-report-missing-card','Help',183),@('help-about','Help',203)
)
$DeckTargets = @(
  @('deck-properties','File',213),@('deck-legality','File',233),@('deck-statistics','File',253)
)
$Skipped = [ordered]@{
 'File > New/Open/Reopen/Save/Save As/Save All/Close/Close All/Delete Deck' = 'edit or delete data (and disabled in this mode)'
 'File > Print Proxies' = 'prints'
 'File > Import / Update Prices' = 'imports data / goes online'
 'File > Mode items, Full Screen, Minimize, Stay on Top' = 'change app state, not dialogs'
 'File > Exit' = 'exits'
 'Cards > Add/Remove/Quantity/Batch Update/Delete All/Cut/Copy/Paste' = 'edit data'
 'Cards > Print, Export, Copy as Text' = 'print/export (submenus)'
 'Cards > Lock Collection, Next/Previous Deck' = 'state change'
 'Search > Reset All Filters, General Filter toggles, Next/Previous/Cancel, Go to, Bookmarks' = 'state change / navigation, no dialog'
 'View > Sort Order/Group By/Show* toggles, Toolbars, Status Bar' = 'toggles change layout, no dialog'
 'Card Art > Export, Open Containing Folder, Copy to Clipboard, sizes, align, Download All Art' = 'export / explorer / clipboard / network / toggles'
 'Online > Gatherer, Boardgames Rules, eBay Sales, Google Images' = 'go online (disabled)'
 'Reports > Deck Registration Sheets, Deck Availability, Deck Combos' = 'deck-only (disabled in Collection from Pool mode)'
 'Tools > Check Collection Integrity, Backup Collection, Open Installation/Configuration/My Decks Folder' = 'maintenance / writes / launches Explorer'
 'Admin > Debug' = 'admin'
 'Help > MTG Studio Help, Discord, Homepage, Bug Report, Request a Feature' = 'launch external viewer/browser'
 'Help > Check for Update' = 'goes online'
}
function Start-App { $script:p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru
  for($i=0;$i -lt 240;$i++){ Start-Sleep -Milliseconds 500; if((Top $script:p|?{$_.C -eq 'TMainForm'})){ Start-Sleep 3; return } }; throw 'main window did not appear' }
function Ensure-App { if($script:p.HasExited -or -not [W]::Alive((MainH $script:p))){ "  app dead/hung, restarting"; try{$script:p.Kill()}catch{}; Start-App } }
function Save-Win($h,$name,$how,$extra=@{}){
  Grab $h (Join-Path $Out "$name@1x.png")
  $r=[W]::Rect($h)
  $o=[ordered]@{name=$name;how=$how;class=[W]::Cls($h);title=[W]::Text($h);width=$r[2];height=$r[3];dpi='100 % (v3 is DPI unaware)';controls=@(Controls $h)}
  foreach($k in $extra.Keys){$o[$k]=$extra[$k]}
  $o | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Out "$name.controls.json") -Encoding UTF8
  [pscustomobject]@{File="$name@1x.png";How=$how;Class=$o.class;Title=$o.title;Size="$($r[2])x$($r[3])"}
}
$Manifest = New-Object System.Collections.ArrayList
New-Item -ItemType Directory -Force $Out | Out-Null
Start-App
[void]$Manifest.Add((Save-Win (MainH $script:p) 'main-window' 'launch'))
# 1. menus
foreach($t in $script:MenuX.Keys){
  Ensure-App
  $pop = Open-Menu $script:p $t
  if($pop){ [void]$Manifest.Add((Save-Win $pop ("menu-" + ($t -replace ' ','')) "click '$t' on the Main Menu bar")) } else { "menu $t did not open" }
  Close-Popups $script:p
}
# 2. dialogs
function Do-Target($t){
  $name,$menu,$y = $t
  Ensure-App; Close-Popups $script:p
  "== $name"
  $pop = Open-Menu $script:p $menu
  if(-not $pop){ "  menu failed"; return }
  Click $pop 60 $y
  $win=$null; for($i=0;$i -lt $OpenTimeoutSec*2 -and -not $win;$i++){ Start-Sleep -Milliseconds 500; $win = Others $script:p | select -first 1 }
  if(-not $win){ "  no new window; main window state saved"; [void]$Manifest.Add([pscustomobject]@{File="$name-main@1x.png";How="$menu item y=$y : NO NEW WINDOW";Class='TMainForm';Title='(main window after the click)';Size=''}); Grab (MainH $script:p) (Join-Path $Out "$name-main@1x.png"); Close-Popups $script:p; return }
  Start-Sleep 1.5
  $how = "$menu menu, item at popup y=$y"
  if($name -eq 'tools-options'){
    [void]$Manifest.Add((Save-Win $win.H 'options-01-interface' "$how (page 1)"))
    $cat = [W]::Children($win.H) | ?{[W]::Cls($_) -eq 'TCategoryButtons'} | select -first 1
    $pages='decks','shortcuts','passwords','internet-authentication','rules','prices','grids','defaults','card-art','morph'
    for($i=0;$i -lt $pages.Count;$i++){
      Click $cat 100 (23 + 36*($i+1)); Start-Sleep 1.2
      [void]$Manifest.Add((Save-Win $win.H ('options-{0:D2}-{1}' -f ($i+2),$pages[$i]) "$how, then click page $($i+2) in the left category list"))
    }
  } else { [void]$Manifest.Add((Save-Win $win.H $name $how)) }
  $closed = Close-Win $script:p $win.H
  "  captured $($win.C) '$($win.T)' closed=$closed"
}
foreach($t in $Targets){ Do-Target $t }
# 2b. deck-mode dialogs: switch the (copy of the) app to Deck from Card Pool first; File > Mode item at popup y=317
try{$script:p.Kill()}catch{}; Start-App
$pop = Open-Menu $script:p 'File'; Click $pop 60 317; Start-Sleep 3
[void]$Manifest.Add((Save-Win (MainH $script:p) 'main-window-deck-mode' 'File > Mode > Deck from Card Pool (y=317)'))
foreach($t in $DeckTargets){ Do-Target $t }
# 3. back to rest: main grab at the end for comparison
Ensure-App
[void]$Manifest.Add((Save-Win (MainH $script:p) 'main-window-end' 'after all dialogs closed'))
# leave the copy in its normal mode (File > Mode > Collection from Card Pool, y=337): the mode is persisted and Deck mode would make the next launch start in it
Close-Popups $script:p; $pop = Open-Menu $script:p 'File'; Click $pop 60 337; Start-Sleep 3
try{$script:p.Kill()}catch{}
$Manifest | Export-Csv (Join-Path $Out 'manifest.csv') -NoTypeInformation
$Skipped.GetEnumerator() | %{ "SKIPPED: $($_.Key) -- $($_.Value)" }
$Manifest | ft -auto | out-string -width 220
