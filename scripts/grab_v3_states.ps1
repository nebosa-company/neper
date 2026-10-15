<#
.SYNOPSIS  Capture INTERACTION STATES (pressed, focused, selected, open drop-downs, open menus, ...) of the real MTG Studio v3 controls.
.DESCRIPTION
  Drives a COPY of v3 (see scripts\v3_states_lib.ps1; it patches the single-instance mutex of the copy so it can run beside the maintainer's own
  v3) with posted/sent WINDOW MESSAGES only: WM_MOUSEMOVE / WM_LBUTTONDOWN / WM_LBUTTONUP / WM_KEYDOWN to a specific window, WM_KILLFOCUS, WM_CANCELMODE,
  programmatic SetFocus through AttachThreadInput, SetForegroundWindow via AttachThreadInput. NO SendInput, mouse_event, keybd_event or SetCursorPos.
  Window grabs are PrintWindow(flag 2); output goes to docs\ui\looks\ref\windows\states\<control>-<state>[-<where>]@1x.png + states\README.md.
  Each section opens a fresh dialog, grabs the REST state first, then the state, so pairs diff cleanly. Nothing is saved, applied, deleted or run:
  a pressed state is a WM_LBUTTONDOWN without its WM_LBUTTONUP and is cancelled with WM_CANCELMODE or by closing the dialog (Cancel semantics).
  Hover (the mouse-over look) is NOT reachable this way: dxBar/cxButton/cxGrid read the real pointer with GetCursorPos, see README.
.PARAMETER Only   run just these sections (menus, main, options, dialogs); default all
.EXAMPLE   pwsh -File scripts\grab_v3_states.ps1
.EXAMPLE   pwsh -File scripts\grab_v3_states.ps1 -Only options
#>
param([string[]]$Only = @('menus','main','options','dialogs'))
. (Join-Path $PSScriptRoot 'v3_states_lib.ps1')
New-Item -ItemType Directory -Force $script:Out | Out-Null
$script:Notes = New-Object System.Collections.ArrayList   # things that did not work
function NotReached($control,$state,$why){ [void]$script:Notes.Add([pscustomobject]@{Control=$control;State=$state;Why=$why}); "  -- not reached: $control $state ($why)" }
function Sleepms($n){ Start-Sleep -Milliseconds $n }
function Guard-Main { # the app minimised itself once after a stray key; put it back
  $m=MainH; if(-not $m){return}; $r=[W]::Rect($m); if($r[0] -le -30000){ Msg $m 0x112 0xF120 0; Sleep 1 } }
function Fresh { Ensure-App; Close-Popups; foreach($o in (Others)){ [void](Close-Win $o.H) }; Guard-Main; Activate (MainH) }
function Cancel-Press($h){ Msg $h 0x1F; Msg $h 0x215 0 0; Sleepms 300 }                    # WM_CANCELMODE + WM_CAPTURECHANGED: drops the pressed state, fires nothing
# generic tools on a dialog $d, image coordinates $px,$py
function Press($d,$name,$control,$state,$px,$py,$where,$how='WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE',$notes=''){
  $u=PDown $d $px $py; Sleepms 450; Shot $d "$name" $control $state "$how ($where)" $notes; Cancel-Press $u.H; $u }
function FocusOn($d,$name,$control,$state,$px,$py,$where,$notes=''){
  $u=Under $d $px $py; Focus $u.H; Sleepms 450; Shot $d "$name" $control $state "SetFocus via AttachThreadInput on the control ($where)" $notes; $u }
function Rest($d,$name,$control,$where,$json=$false){ if($json){ Shot $d $name $control 'rest' "dialog just opened ($where)" '' -Json } else { Shot $d $name $control 'rest' "dialog just opened ($where)" } }

# ===================================================================== 1. menus
function Section-Menus {
  "== menus"
  # item steps: how many VK_DOWN presses select an interesting enabled / disabled row (dxBar menu mode follows keys when the app is active)
  $plan = @(
    @('File',1,'disabled first row (New...)'),@('File',24,'near the bottom (Stay on Top)'),
    @('Cards',1,''),@('Cards',4,''),@('Search',1,''),@('Search',5,''),@('View',1,''),@('View',5,''),
    @('Card Art',1,''),@('Card Art',3,''),@('Online',1,''),@('Reports',1,''),@('Reports',4,''),@('Tools',1,''),@('Tools',3,''),@('Help',1,''),@('Help',4,'')
  )
  foreach($t in $plan){
    $title,$n,$note = $t; Fresh
    $pop = Open-Menu $title; if(-not $pop){ NotReached "menu $title" "open" 'popup did not appear'; continue }
    Activate $pop
    $tn = ($title -replace ' ','').ToLower()
    if($n -eq 1){ Shot (MainH) "menu-bar-open-title-$tn" 'menu bar' 'open title (pressed)' "click '$title' on the Main Menu bar; popup stays open" }
    for($i=0;$i -lt $n;$i++){ Key $pop 0x28; Sleepms 90 }; Sleepms 400
    Shot $pop "menu-item-selected-$tn-$n" 'menu popup' "selected row (keyboard focus row #$n)" "click '$title', then $n x WM_KEYDOWN VK_DOWN to the popup" $note
    Close-Popups; Guard-Main
  }
  # sub-menus: VK_DOWN to a row with an arrow, then VK_RIGHT (counts include disabled rows, headers are skipped)
  foreach($sm in @(@('Cards',17,'print'),@('Cards',18,'export'),@('View',20,'show-grid-lines'),@('View',24,'toolbars'))){
    $title,$n,$nm=$sm; Fresh; $pop=Open-Menu $title; if(-not $pop){ continue }; Activate $pop
    1..$n|%{ Key $pop 0x28; Sleepms 80 }; Key $pop 0x27; Sleepms 800
    $pp=@(Popups); $i=0; foreach($x in $pp){ Shot $x.H "menu-submenu-open-$($title.ToLower() -replace ' ','')-$nm-$i" 'menu popup' 'sub-menu open, parent row selected' "$title menu, $n x VK_DOWN then VK_RIGHT (popup #$i of $($pp.Count), later ones are the sub-menu)"; $i++ }
    Close-Popups; Guard-Main }
}

# ===================================================================== 2. main window
function Section-Main {
  "== main window"
  Fresh; $m=MainH
  Shot $m 'main-window-rest' 'main window' 'rest' 'launch, window active (the rest reference for every main-window state below)' -Json
  # --- grid rows: selected + focused, selected + unfocused (WM_KILLFOCUS to the grid site)
  $u=PClick $m 400 190; Sleepms 500
  Shot $m 'grid-row-selected-focused-main' 'data grid (top)' 'selected row, grid focused' 'WM_LBUTTONDOWN+UP on a row of the top grid'
  Msg $u.H 0x8 0 0; Sleepms 500
  Shot $m 'grid-row-selected-unfocused-main' 'data grid (top)' 'selected row, grid not focused' 'same row, then WM_KILLFOCUS to the grid site'
  $b=PClick $m 420 400; Sleepms 500
  Shot $m 'grid-row-selected-focused-main-bottom' 'data grid (bottom, collection)' 'selected row, grid focused' 'click on a row of the bottom grid (empty collection copy: the click may only focus)'
  # --- column header pressed (down, no up) then cancelled
  [void](PClick $m 400 190)
  $h=PDown $m 400 121; Sleepms 450
  Shot $m 'grid-header-pressed-main' 'data grid header' 'pressed column header (the hot filter glyph shows too)' 'WM_LBUTTONDOWN on the Type header, no WM_LBUTTONUP, then WM_CANCELMODE'
  Cancel-Press $h.H; Sleepms 300
  # --- navigator buttons
  foreach($nb in @(@('next',364),@('last',408),@('first',227))){
    $n=PDown $m $nb[1] 309; Sleepms 450
    Shot $m "grid-navigator-$($nb[0])-pressed-main" 'grid navigator' "pressed '$($nb[0])' button" "WM_LBUTTONDOWN on the $($nb[0]) record button of the top grid, no WM_LBUTTONUP, then WM_CANCELMODE"
    Cancel-Press $n.H }
  Shot $m 'grid-navigator-rest-main' 'grid navigator' 'rest' 'after the presses were cancelled'
  # --- scroll bars: pressed thumb
  $v=PDown $m 783 135; Sleepms 450
  Shot $m 'scroll-bar-thumb-pressed-main-vertical' 'scroll bar (vertical, top grid)' 'pressed thumb' 'WM_LBUTTONDOWN on the thumb, no WM_LBUTTONUP, then WM_CANCELMODE'
  Cancel-Press $v.H
  $hs=PDown $m 540 309; Sleepms 450
  Shot $m 'scroll-bar-thumb-pressed-main-horizontal' 'scroll bar (horizontal, in the navigator)' 'pressed thumb' 'WM_LBUTTONDOWN on the thumb, no WM_LBUTTONUP, then WM_CANCELMODE'
  Cancel-Press $hs.H
  $va=PDown $m 783 295; Sleepms 450
  Shot $m 'scroll-bar-arrow-pressed-main-vertical' 'scroll bar (vertical, top grid)' 'pressed lower arrow / track' 'WM_LBUTTONDOWN near the bottom of the track, then WM_CANCELMODE'
  Cancel-Press $va.H
  # --- splitters pressed (no move, so no drag)
  $sp=PDown $m 212 300; Sleepms 400
  Shot $m 'splitter-pressed-main-vertical' 'splitter (vertical, left)' 'pressed (no drag)' 'WM_LBUTTONDOWN on the 8 px strip, no move, then WM_CANCELMODE'
  Cancel-Press $sp.H
  $sp2=PDown $m 500 326; Sleepms 400
  Shot $m 'splitter-pressed-main-horizontal' 'splitter (horizontal, between grids)' 'pressed (no drag)' 'WM_LBUTTONDOWN on the 8 px strip, no move, then WM_CANCELMODE'
  Cancel-Press $sp2.H
  # --- tab strip under the card preview: select the second tab, then back
  $t=PClick $m 62 558; Sleepms 700
  Shot $m 'tab-selected-second-main-left' 'tab control (left, bottom tabs)' 'second tab selected' 'WM_LBUTTONDOWN+UP on the second tab'
  [void](PClick $m 28 558); Sleepms 500
  # --- window chrome: inactive caption
  Msg $m 0x86 0 0; Sleepms 500
  Shot $m 'dialog-chrome-inactive-caption-main' 'title bar' 'inactive window (caption greyed)' 'WM_NCACTIVATE with wParam 0 to the main form'
  Msg $m 0x86 1 0; Sleepms 300
  # --- failed on purpose, recorded
  NotReached 'toolbar button' 'hot / pressed / checked' 'dxBar toolbars ignore posted mouse messages (a posted down+up on the Search-toolbar binoculars neither pressed nor opened the dialog); hit-test uses the real pointer'
  NotReached 'any control' 'hover (mouse over)' 'DevExpress reads the real pointer with GetCursorPos / its own mouse hook; a posted WM_MOUSEMOVE changes nothing visible (tried toolbar, menu popup, cxButton, grid header and rows, with and without app activation, with CM_MOUSEENTER and WM_MOUSEHOVER)'
}

. (Join-Path $PSScriptRoot 'v3_states_options.ps1')
. (Join-Path $PSScriptRoot 'v3_states_dialogs.ps1')
. (Join-Path $PSScriptRoot 'v3_states_readme.ps1')
function Attach-App-Fresh { Get-Process mtgstudio_s -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; Prepare-Data; Start-App }
# ===================================================================== driver (skipped when dot-sourced for probing)
function Run-States {
  Attach-App-Fresh
  foreach($s in $Only){ try{ switch($s){ 'menus'{Section-Menus} 'main'{Section-Main} 'options'{Section-Options} 'dialogs'{Section-Dialogs; Section-Dialogs2} } }catch{ "SECTION $s FAILED: $_" } }
  Write-Readme
}
if($MyInvocation.InvocationName -ne '.'){ Run-States }
