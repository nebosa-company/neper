<#
.SYNOPSIS  Capture the HOVER (mouse-over) looks of the real MTG Studio v3 controls, from a hooked COPY of v3.
.DESCRIPTION
  VCL / DevExpress read the real pointer (GetCursorPos, WindowFromPoint, GetKeyState, TrackMouseEvent), which posted messages cannot fake. This script
  launches the COPY (D:\Temp\claude\v3run\mtgstudio_s.exe), injects scripts\v3_hook\v3hook.dll into that one process (build it with
  scripts\v3_hook\build.ps1) so those calls answer from a shared block, moves the FAKE pointer there, posts the ordinary WM_MOUSEMOVE to the window under
  it, waits, and grabs with PrintWindow. The real cursor is never moved and no SendInput / mouse_event / keybd_event / SetCursorPos is used.
  Each dialog is opened fresh and its hover-<dialog>-rest grab is taken first; every hover PNG is hashed against it and the manifest note says when a
  control draws no distinct hover look. Output: docs\ui\looks\ref\windows\states\hover-<control>-<what>@1x.png, manifest.csv rows and the hover
  section of states\README.md. Nothing is saved, applied, deleted, run or released: a pressed look is a button-down with WM_CANCELMODE afterwards.
.PARAMETER Only  sections to run: main, menus, options, dialogs, deck, grid (default all). Each run re-launches the copy and kills it at the end.
.EXAMPLE   pwsh -File scripts\grab_v3_hover.ps1 -Only main
#>
param([string[]]$Only = @('main','menus','options','dialogs','deck','grid'))
. (Join-Path $PSScriptRoot 'v3_hover_lib.ps1')
. (Join-Path $PSScriptRoot 'v3_states_options.ps1')   # OptDlg, Done
. (Join-Path $PSScriptRoot 'v3_states_dialogs.ps1')   # Dlg
New-Item -ItemType Directory -Force $script:Out | Out-Null
$script:Notes = New-Object System.Collections.ArrayList
function NotReached($control,$state,$why){ [void]$script:Notes.Add([pscustomobject]@{Control=$control;State=$state;Why=$why}); "  -- not reached: $control $state ($why)" }
function Sleepms($n){ Start-Sleep -Milliseconds $n }
function Guard-Main { $m=MainH; if(-not $m){return}; $r=[W]::Rect($m); if($r[0] -le -30000){ Msg $m 0x112 0xF120 0; Sleep 1 } }
function Fresh { Ensure-App; Close-Popups; foreach($o in (Others)){ [void](Close-Win $o.H) }; Guard-Main; Activate (MainH) }
function Cancel-Press($h){ Msg $h 0x1F; Msg $h 0x215 0 0; FakeButton 0; Sleepms 300 }
function D1($x){ @($x)[-1] }
function Fhash($n){ (Get-FileHash (Join-Path $script:Out "$n@1x.png") -Algorithm MD5).Hash }

# ---- rest + hover primitives. $script:RestName / RestHash hold the rest grab of the window being worked on.
function RestShot($d,$name,$control,$where){
  Msg $d 0x86 1 0; Sleepms 250   # WM_NCACTIVATE(TRUE): the first grab after a launch can otherwise show the greyed (inactive) caption
  Shot $d "hover-$name-rest" $control 'rest (pointer away)' "dialog / window just opened, fake pointer parked off screen ($where)"
  $script:RestName="hover-$name-rest"; }
# the pre-hover grab (same window, taken just before the pointer moves in, never saved) is what a hover is compared with: the rest PNG can differ by
# unrelated content (caret, clock, selection) after a long run
function Pre($d){ $f='D:/Temp/claude/v3run/pre.png'; Grab $d $f; $script:RestHash=(Get-FileHash $f -Algorithm MD5).Hash }
function Mark-Same($file){ if((Fhash $file) -eq $script:RestHash){ $script:Rows[-1].Notes = (($script:Rows[-1].Notes + ' PIXEL-IDENTICAL to rest: no distinct hover look').Trim()) } }
# hover a point of top-level $d (image coords), grab $d (or $grab if given), move away
function Hv($d,$name,$control,$state,$px,$py,$where,$wait=450,$grab=$null){
  Pre $d; $u=HoverAt $d $px $py $wait; $g= if($grab){$grab}else{$d}
  Shot $g "hover-$name" $control $state "fake pointer + WM_MOUSEMOVE ($where)"; Mark-Same "hover-$name"; Unhover $u }
# same but the button is DOWN (pressed look): fake pointer + fake VK_LBUTTON + WM_LBUTTONDOWN, no up, then WM_CANCELMODE
function HvDown($d,$name,$control,$state,$px,$py,$where){
  Pre $d; $u=HoverAt $d $px $py 300; FakeButton 1; DownC $u.H $u.X $u.Y; Sleepms 450
  Shot $d "hover-$name" $control $state "fake pointer + fake left button, WM_LBUTTONDOWN, no up, then WM_CANCELMODE ($where)"; Mark-Same "hover-$name"
  Cancel-Press $u.H; Unhover $u }
# hint window: hold the hover until a new top-level window appears (cxHint / THintWindow), grab it and the owner
function HvHint($d,$name,$control,$px,$py,$where,$waitMs=3000){
  $hint=$null; for($try=0;$try -lt 2 -and -not $hint;$try++){
  FakeAway; Sleepms 1500; $known=@((Top $script:p).H); $u=HoverAt $d $px $py 200
  for($i=0;$i -lt $waitMs/100 -and -not $hint;$i++){ Sleepms 100; $hint=Top $script:p | ?{ $_.H -notin $known -and $_.C -like '*Hint*' } | select -first 1 }
  if(-not $hint){ Unhover $u } }
  if($hint){ Sleepms 400; Shot $hint.H "hover-hint-$name" "$control hint window" "visible after the fake pointer rested on it" "fake pointer + WM_MOUSEMOVE, held; window class $($hint.C) ($where)"
             Shot $d "hover-hint-$name-context" $control "hint showing (owner window)" "same, grab of the owner window ($where)" }
  else { NotReached "$control hint" 'hint window' "no new top-level window within $waitMs ms ($where)" }
  Unhover $u; Sleepms 400 }
# window-caption button hover through WM_NCMOUSEMOVE (hit-test code in wParam, screen point in lParam)
function HvCaption($d,$name,$control,$ht,$px,$py,$where){
  Pre $d; $r=[W]::Rect($d); $sx=$r[0]+$px; $sy=$r[1]+$py; FakeAway; Sleepms 80; FakeAt $sx $sy
  Msg $d 0xA0 $ht ([IntPtr](($sy -shl 16) -bor ($sx -band 0xFFFF))); Sleepms 500
  Shot $d "hover-$name" $control 'hover' "fake pointer + WM_NCMOUSEMOVE hit-test $ht ($where)"; Mark-Same "hover-$name"
  Msg $d 0xA0 0 ([IntPtr](((5) -shl 16) -bor 5)); FakeAway; Sleepms 200 }

# ===================================================================== main window
function Section-Main {
  "== main window"
  Fresh; $m=MainH; Sleepms 800
  RestShot $m 'main' 'main window' 'launch, window active'
  # menu bar titles (no menu open)
  $titles=[ordered]@{file=33;cards=68;search=113;view=157;cardart=205;online=257;reports=307;tools=355;admin=398;help=439}
  foreach($t in $titles.Keys){ Hv $m "menubar-title-$t" 'menu bar' "hot title ($t), no menu open" $titles[$t] 44 'Main Menu bar' }
  # toolbars: enabled (hot), disabled (hover over a greyed button), combos
  $tb=@(@('cards-expand',395,'Cards bar, blue double arrow'),@('cards-f',418,'Cards bar, F button'),@('search-filter',477,'Search bar, filter funnel'),@('search-filter-plus',500,'Search bar, funnel plus'),
        @('search-binoculars',522,'Search bar, binoculars'),@('search-pencil',548,'Search bar'),@('search-4',570,'Search bar'),@('search-5',593,'Search bar'),
        @('help-home',628,'Help bar, home'),@('help-discord',653,'Help bar, discord'),
        @('standard-1',28,'Standard bar, first (greyed)'),@('standard-2',53,'Standard bar (greyed)'),@('standard-3',78,'Standard bar (greyed)'),@('standard-8',208,'Standard bar, last (greyed)'),
        @('cards-1',244,'Cards bar, first (greyed)'),@('cards-plus',343,'Cards bar, plus'),@('cards-minus',366,'Cards bar, minus'))
  foreach($b in $tb){ Hv $m "toolbar-button-$($b[0])" 'toolbar button' 'hot (hover)' $b[1] 96 $b[2] }
  Hv $m 'toolbar-combo-card-edit' 'toolbar combo (card name)' 'hover over the edit' 90 70 'Standard bar combo'
  Hv $m 'toolbar-combo-card-drop' 'toolbar combo (card name)' 'hover over the drop button' 158 70 'Standard bar combo'
  Hv $m 'toolbar-combo-mode' 'toolbar combo (Mode)' 'hover over the combo' 700 70 'mode combo'
  # hint windows
  foreach($b in @(@('search-filter',477),@('search-binoculars',522),@('help-home',628),@('cards-expand',395),@('cards-f',418))){ HvHint $m "toolbar-$($b[0])" 'toolbar button' $b[1] 96 "toolbar $($b[0])" }
  # pressed toolbar buttons (down, no up)
  HvDown $m 'toolbar-button-search-filter-pressed' 'toolbar button' 'pressed (button down)' 477 96 'Search bar funnel'
  HvDown $m 'toolbar-button-search-binoculars-pressed' 'toolbar button' 'pressed (button down)' 522 96 'Search bar binoculars'
  # grid: hot column headers, rows, navigator, scroll bars
  foreach($h in @(@('name',300),@('edition',466),@('color',520),@('type',600),@('rarity',727))){ Hv $m "grid-header-$($h[0])" 'data grid header' 'hot column header' $h[1] 121 'top grid' }
  Hv $m 'grid-star-header' 'data grid header' 'hot (indicator / star column)' 241 121 'top grid, star'
  Hv $m 'grid-row-top' 'data grid row' 'hover over a row (cell)' 400 180 'top grid'
  Hv $m 'grid-row-top-selected' 'data grid row' 'hover over the selected row' 400 142 'top grid'
  Hv $m 'grid-row-bottom' 'data grid row' 'hover over a row (cell)' 420 398 'bottom grid'
  Hv $m 'grid-header-bottom-name' 'data grid header' 'hot column header' 290 341 'bottom grid'
  foreach($n in @(@('first',227),@('prior',249),@('next',364),@('last',386),@('filter',429))){ Hv $m "grid-navigator-$($n[0])" 'grid navigator' "hover over '$($n[0])' button" $n[1] 309 'top grid navigator' }
  foreach($n in @(@('first',227),@('next',335),@('filter',417))){ Hv $m "grid-navigator-bottom-$($n[0])" 'grid navigator' "hover over '$($n[0])' button (bottom grid)" $n[1] 559 'bottom grid navigator' }
  Hv $m 'scroll-bar-vertical-thumb' 'scroll bar (vertical, top grid)' 'hover over the thumb' 783 135 'top grid'
  Hv $m 'scroll-bar-vertical-track' 'scroll bar (vertical, top grid)' 'hover over the track below the thumb' 783 230 'top grid'
  Hv $m 'scroll-bar-vertical-arrow-down' 'scroll bar (vertical, top grid)' 'hover over the lower arrow' 783 295 'top grid'
  Hv $m 'scroll-bar-vertical-arrow-up' 'scroll bar (vertical, top grid)' 'hover over the upper arrow' 783 112 'top grid'
  Hv $m 'scroll-bar-horizontal-thumb' 'scroll bar (horizontal, in the navigator)' 'hover over the thumb' 540 309 'top grid navigator'
  # splitters, tab strip, status bar
  Hv $m 'splitter-vertical' 'splitter (vertical, left)' 'hover' 212 300 '8 px strip'
  Hv $m 'splitter-horizontal' 'splitter (horizontal, between grids)' 'hover' 500 326 '8 px strip'
  Hv $m 'tab-left-first' 'tab control (left, bottom tabs)' 'hover over the selected first tab' 28 558 'left tabs'
  Hv $m 'tab-left-second' 'tab control (left, bottom tabs)' 'hover over the second tab' 62 558 'left tabs'
  foreach($s in @(@('panel-1',60),@('panel-2',200),@('panel-3',320),@('panel-4',480))){ Hv $m "status-bar-$($s[0])" 'status bar panel' 'hover' $s[1] 582 'status bar' }
  HvHint $m 'grid-header-name' 'data grid header' 300 121 'top grid Name header'
  HvHint $m 'status-bar-panel-3' 'status bar panel' 320 582 'status bar'
  # window caption buttons (main window): hit-test codes MIN 8, MAX 9, CLOSE 20
  HvCaption $m 'caption-minimize-main' 'caption button' 8 680 16 'main window'
  HvCaption $m 'caption-maximize-main' 'caption button' 9 721 16 'main window'
  HvCaption $m 'caption-close-main' 'caption button' 20 763 16 'main window'
  # inactive caption for contrast
  Msg $m 0x86 0 0; Sleepms 500; Shot $m 'hover-caption-inactive-main' 'title bar' 'inactive window' 'WM_NCACTIVATE with wParam 0'; Msg $m 0x86 1 0; Sleepms 300
}

# ===================================================================== menus
function Section-Menus {
  "== menus"
  $plan=[ordered]@{File=@(13,213,317,337,377,427,477,497,537,567);Cards=@(13,103,123,343,373,393,433);Search=@(13,53,105,157,221,325,385,455);View=@(75,135,195,303,483,553);Reports=@(103,123,143,163);Tools=@(33,93,153);Help=@(23,83,143,203);'Card Art'=@(33,93,153);Online=@(23,43)}
  foreach($t in $plan.Keys){
    Fresh; $m=MainH; $pop=Open-Menu $t; if(-not $pop){ NotReached "menu $t" 'hot row' 'menu did not open'; continue }
    Activate $pop; Sleepms 300
    $slug=($t -replace ' ','').ToLower()
    $script:RestName=$null; $script:RestHash='-'
    Shot $pop "hover-menu-$slug-rest" 'menu popup' 'open, pointer away' "click on the '$t' title, fake pointer parked"
    $script:RestHash=Fhash "hover-menu-$slug-rest"
    $i=0; foreach($y in $plan[$t]){ $i++; Hv $pop "menu-$slug-row$i" 'menu popup' "mouse-hot row at y=$y" 60 $y "$t menu" 350 }
    Close-Popups
  }
  # sub-menu parent rows: the pointer rests on 'Print' / 'Toolbars'; the sub-menu popup opens by itself, grab every popup of the process
  foreach($sm in @(@('Cards',373,'cards-print'),@('View',553,'view-toolbars'),@('View',463,'view-grid-lines'))){
    Fresh; $pop=Open-Menu $sm[0]; if(-not $pop){ continue }; Activate $pop; Sleepms 300
    $u=HoverAt $pop 60 $sm[1] 1500; $k=0
    foreach($p in (Popups)){ $k++; Shot $p.H "hover-menu-submenu-$($sm[2])-popup$k" 'menu popup' "sub-menu parent row '$($sm[2])' hovered, popup $k of the open chain" 'fake pointer rests on the parent row; the sub-menu opens after the menu delay' }
    Unhover $u; Close-Popups }
  # menu switching: a menu is open and the pointer rests on another title; hot title with open menu
  foreach($pair in @(@('File','Search',113),@('File','View',157),@('Search','Reports',307),@('View','Tools',355),@('Help','File',33))){
    Fresh; $m=MainH; $pop=Open-Menu $pair[0]; if(-not $pop){ continue }; Activate $pop; Sleepms 300
    $script:RestHash='-'; $u=HoverAt $m $pair[2] 44 600
    Shot $m "hover-menu-switch-$($pair[0].ToLower())-to-$($pair[1].ToLower())" 'menu bar' "menu '$($pair[0])' open, pointer on the '$($pair[1])' title" 'fake pointer + WM_MOUSEMOVE to the bar while a menu is open'
    $pi=0; foreach($p in (Popups | select -first 2)){ $pi++; Shot $p.H "hover-menu-switch-$($pair[0].ToLower())-to-$($pair[1].ToLower())-popup$pi" 'menu popup' 'popup showing while hovering the other title' 'same' }
    Unhover $u; Close-Popups
  }
}

# ===================================================================== Options
function Combo-Hot($d,$px,$py,$name,$where){
  $known=(Top $script:p).H; $u=PClick $d $px $py
  $n=Poll-New $known 2500 | ?{ $_.C -like '*Popup*' } | select -first 1
  if(-not $n){ NotReached "combo box ($where)" 'open list hot row' 'no popup'; return }
  Sleepms 300; $r=[W]::Rect($n.H); $h=$r[3]; $script:RestHash='-'
  Shot $n.H "hover-combo-list-$name-open" 'combo box drop-down list' 'open, pointer away' "click on the drop button ($where)"; $script:RestHash=Fhash "hover-combo-list-$name-open"
  $k=0; foreach($y in @(8,[int]($h/2),($h-8)) | select -Unique){ $k++; Hv $n.H "combo-list-$name-row$k" 'combo box drop-down list' "mouse-hot row at y=$y" 30 $y $where 350 }
  Close-Popups; Msg $d 0x1F; Sleepms 200 }
function Section-Options {
  "== options"
  # page 1 Interface
  $d=D1 (OptDlg 1); RestShot $d 'options-interface' 'dialog (Options, Interface page)' 'Options, page 1'
  Hv $d 'button-options-ok' 'button (default)' 'hover (OK, default button)' 505 $script:BtnY 'Options'
  Hv $d 'button-options-cancel' 'button' 'hover (Cancel)' 589 $script:BtnY 'Options'
  Hv $d 'button-options-apply' 'button' 'hover (Apply)' 673 $script:BtnY 'Options'
  HvDown $d 'button-options-cancel-pressed' 'button' 'hover and pressed (Cancel)' 589 $script:BtnY 'Options'
  Hv $d 'checkbox-options-hide-splash' 'check box' 'hover (unchecked box)' 224 84 'Options > Interface'
  Hv $d 'checkbox-options-hide-splash-label' 'check box' 'hover over the caption (unchecked)' 300 84 'Options > Interface'
  Hv $d 'checkbox-options-show-tooltips' 'check box' 'hover (checked box)' 224 165 'Options > Interface'
  Hv $d 'checkbox-options-card-preview-label' 'check box' 'hover over the caption (checked)' 300 138 'Options > Interface'
  Hv $d 'category-list-options-decks' 'category list (TCategoryButtons)' 'hover over an unselected item' 100 90 'Options, left list'
  Hv $d 'category-list-options-selected' 'category list (TCategoryButtons)' 'hover over the selected item' 100 54 'Options, left list'
  Hv $d 'panel-options-header' 'page header' 'hover' 300 48 'Options page header'
  HvHint $d 'options-checkbox-tooltips' 'check box' 224 165 'Options'
  HvCaption $d 'caption-close-options' 'caption button (close X)' 20 704 16 'Options dialog'
  Msg $d 0x86 0 0; Sleepms 400; Shot $d 'hover-caption-inactive-options' 'title bar' 'inactive dialog' 'WM_NCACTIVATE with wParam 0'; Msg $d 0x86 1 0; Sleepms 300
  Done $d
  # page 2 Decks
  $d=D1 (OptDlg 2); RestShot $d 'options-decks' 'dialog (Options, Decks page)' 'Options, page 2'
  Hv $d 'edit-options-deck-path' 'button edit (path)' 'hover over the edit' 400 104 'Options > Decks'
  Hv $d 'edit-button-ellipsis-options-deck-path' 'button edit ellipsis' 'hover over the ... button' 700 104 'Options > Decks'
  Hv $d 'spin-edit-options-max-same-cards' 'spin edit' 'hover over the edit' 250 169 'Options > Decks'
  Hv $d 'spin-edit-arrow-up-options-max-same-cards' 'spin edit' 'hover over the up arrow' 312 165 'Options > Decks'
  Hv $d 'spin-edit-arrow-down-options-max-same-cards' 'spin edit' 'hover over the down arrow' 312 174 'Options > Decks'
  Hv $d 'spin-edit-arrow-left-options-max-same-cards' 'spin edit' 'hover over the left (decrease) button' 296 169 'Options > Decks'
  Hv $d 'spin-edit-arrow-right-options-max-same-cards' 'spin edit' 'hover over the right (increase) button' 326 169 'Options > Decks'
  Done $d
  # page 3 Shortcuts
  $d=D1 (OptDlg 3); RestShot $d 'options-shortcuts' 'dialog (Options, Shortcuts page)' 'Options, page 3'
  Hv $d 'grid-header-options-shortcuts-command' 'data grid header' 'hot column header (Command)' 400 82 'Options > Shortcuts'
  Hv $d 'grid-header-options-shortcuts-key' 'data grid header' 'hot column header (Shortcut)' 600 82 'Options > Shortcuts'
  Hv $d 'grid-row-options-shortcuts' 'data grid row' 'hover over a row' 380 118 'Options > Shortcuts'
  Hv $d 'scroll-bar-thumb-options-shortcuts' 'scroll bar (grid)' 'hover over the thumb' 701 112 'Options > Shortcuts'
  Hv $d 'scroll-bar-track-options-shortcuts' 'scroll bar (grid)' 'hover over the track' 701 300 'Options > Shortcuts'
  Hv $d 'scroll-bar-arrow-up-options-shortcuts' 'scroll bar (grid)' 'hover over the upper arrow' 701 97 'Options > Shortcuts'
  Hv $d 'scroll-bar-arrow-down-options-shortcuts' 'scroll bar (grid)' 'hover over the lower arrow' 701 392 'Options > Shortcuts'
  Hv $d 'edit-options-shortcut-hotkey' 'hot key edit' 'hover' 450 424 'Options > Shortcuts'
  Hv $d 'button-options-shortcut-set' 'button' 'hover (Set)' 588 424 'Options > Shortcuts'
  Hv $d 'button-options-shortcut-reset' 'button' 'hover (Reset)' 672 424 'Options > Shortcuts'
  Done $d
  # page 4 Passwords
  $d=D1 (OptDlg 4); RestShot $d 'options-passwords' 'dialog (Options, Passwords page)' 'Options, page 4'
  Hv $d 'edit-options-old-password' 'text edit (password)' 'hover' 450 100 'Options > Passwords'
  Hv $d 'button-options-password-change' 'button' 'hover (Change)' 252 244 'Options > Passwords'
  Done $d
  # page 5 Internet Authentication: combo
  $d=D1 (OptDlg 5); RestShot $d 'options-internet' 'dialog (Options, Internet page)' 'Options, page 5'
  Hv $d 'combo-box-edit-options-auth-type' 'combo box' 'hover over the edit' 300 82 'Options > Internet'
  Hv $d 'combo-box-drop-options-auth-type' 'combo box' 'hover over the drop button' 456 82 'Options > Internet'
  Combo-Hot $d 456 82 'options-auth-type' 'Options > Internet Authentication'
  Done $d
  # page 6 Rules: check list box
  $d=D1 (OptDlg 6); RestShot $d 'options-rules' 'dialog (Options, Rules page)' 'Options, page 6'
  Hv $d 'check-list-box-row-options-rules' 'check list box' 'hover over a row text' 330 119 'Options > Rules'
  Hv $d 'check-list-box-checkbox-options-rules' 'check list box' 'hover over a row check box' 226 134 'Options > Rules'
  Hv $d 'check-list-box-empty-options-rules' 'check list box' 'hover over the empty area' 330 300 'Options > Rules'
  Done $d
  # page 7 Prices
  $d=D1 (OptDlg 7); RestShot $d 'options-prices' 'dialog (Options, Prices page)' 'Options, page 7'
  Hv $d 'check-list-box-row-options-prices' 'check list box' 'hover over a row text' 330 134 'Options > Prices'
  Done $d
  # page 8 Grids
  $d=D1 (OptDlg 8); RestShot $d 'options-grids' 'dialog (Options, Grids page)' 'Options, page 8'
  Hv $d 'combo-box-edit-options-row-color' 'combo box' 'hover over the edit' 450 82 'Options > Grids'
  Hv $d 'combo-box-drop-options-row-color' 'combo box' 'hover over the drop button' 703 82 'Options > Grids'
  Hv $d 'checkbox-options-show-foil' 'check box' 'hover (checked box)' 234 113 'Options > Grids'
  Hv $d 'checkbox-options-show-filter-row' 'check box' 'hover (unchecked box)' 234 143 'Options > Grids'
  Hv $d 'radio-options-search-from-start' 'radio button' 'hover (selected)' 238 233 'Options > Grids'
  Hv $d 'radio-options-search-within' 'radio button' 'hover (unselected)' 238 275 'Options > Grids'
  Hv $d 'radio-options-move-next-row' 'radio button' 'hover (unselected)' 238 386 'Options > Grids'
  Hv $d 'radio-options-search-within-label' 'radio button' 'hover over the caption' 300 275 'Options > Grids'
  Combo-Hot $d 703 82 'options-row-color' 'Options > Grids, Row Color'
  Combo-Hot $d 703 170 'options-font-size' 'Options > Grids, Font Size'
  Done $d
  # page 9 Defaults
  $d=D1 (OptDlg 9); RestShot $d 'options-defaults' 'dialog (Options, Defaults page)' 'Options, page 9'
  Hv $d 'combo-box-drop-options-condition' 'combo box' 'hover over the drop button' 697 110 'Options > Defaults'
  Combo-Hot $d 697 110 'options-condition' 'Options > Defaults, Condition'
  Done $d
  # page 10 Card Art
  $d=D1 (OptDlg 10); RestShot $d 'options-cardart' 'dialog (Options, Card Art page)' 'Options, page 10'
  Hv $d 'check-list-box-row-options-cardart' 'check list box' 'hover over a row' 400 100 'Options > Card Art'
  Hv $d 'button-options-cardart-validate' 'button' 'hover (Validate)' 495 428 'Options > Card Art'
  Hv $d 'button-image-options-cardart-move-up' 'speed button (image)' 'hover over the up arrow' 698 597 'Options > Card Art'
  Hv $d 'edit-button-ellipsis-options-cardart' 'button edit ellipsis' 'hover over the ... button' 669 395 'Options > Card Art'
  Done $d
  # page 11 Morph
  $d=D1 (OptDlg 11); RestShot $d 'options-morph' 'dialog (Options, Morph page)' 'Options, page 11'
  Hv $d 'spin-edit-options-morph-speed' 'spin edit' 'hover over the edit' 420 115 'Options > Morph'
  Hv $d 'spin-edit-arrow-up-options-morph-speed' 'spin edit (stacked arrows)' 'hover over the up arrow' 441 110 'Options > Morph'
  Hv $d 'spin-edit-arrow-down-options-morph-speed' 'spin edit (stacked arrows)' 'hover over the down arrow' 441 119 'Options > Morph'
  Hv $d 'checkbox-options-morph-use' 'check box' 'hover (checked)' 226 83 'Options > Morph'
  Hv $d 'combo-box-drop-options-card-art-position' 'combo box' 'hover over the drop button' 548 289 'Options > Morph'
  Combo-Hot $d 548 289 'options-card-art-position' 'Options > Morph, Card Art Position'
  Done $d
}

# ===================================================================== other dialogs
function Section-Dialogs {
  "== dialogs"
  # Filter
  $d=D1 (Dlg 'Search' 13 'filter'); RestShot $d 'filter' 'dialog (Filter Card Pool)' 'Search > Filter Card Pool'
  Hv $d 'tab-filter-blocks-selected' 'tab control (top tabs)' 'hover over the selected tab' 78 41 'Filter'
  Hv $d 'tab-filter-cards' 'tab control (top tabs)' 'hover over an unselected tab (Cards)' 167 43 'Filter'
  Hv $d 'tab-filter-options' 'tab control (top tabs)' 'hover over an unselected tab (Options)' 213 43 'Filter'
  Hv $d 'tree-list-row-filter' 'tree list' 'hover over a row' 150 133 'Filter > Blocks tree'
  Hv $d 'tree-list-checkbox-filter' 'tree list check box' 'hover over a node check box' 44 133 'Filter > Blocks tree'
  Hv $d 'tree-list-expander-filter' 'tree list expander (+)' 'hover over the expand button' 28 133 'Filter > Blocks tree'
  Hv $d 'radio-filter-formats' 'radio button' 'hover (unselected Formats)' 115 74 'Filter'
  Hv $d 'radio-filter-blocks' 'radio button' 'hover (selected Blocks)' 27 74 'Filter'
  Hv $d 'button-filter-all' 'button' 'hover (All)' 65 424 'Filter'
  Hv $d 'button-filter-invert' 'button' 'hover (Invert)' 232 424 'Filter'
  Hv $d 'button-filter-clear' 'button' 'hover (Clear)' 60 466 'Filter'
  Hv $d 'button-filter-ok' 'button (default)' 'hover (OK)' 488 466 'Filter'
  Hv $d 'splitter-filter' 'splitter (dialog)' 'hover' 336 250 'Filter, between tree and web view'
  Hv $d 'scroll-bar-thumb-filter-tree' 'scroll bar (tree)' 'hover over the thumb' 317 120 'Filter, Blocks tree'
  Hv $d 'scroll-bar-track-filter-tree' 'scroll bar (tree)' 'hover over the track' 317 300 'Filter, Blocks tree'
  Done $d
  # Advanced Filter
  $d=D1 (Dlg 'Search' 53 'advanced filter'); RestShot $d 'advanced-filter' 'dialog (Advanced Filter)' 'Search > Advanced Filter'
  Hv $d 'filter-control-advanced-filter-root' 'filter control' 'hover over the root condition' 200 80 'Advanced Filter'
  Hv $d 'button-advanced-filter-open' 'button' 'hover (Open...)' 52 326 'Advanced Filter'
  Hv $d 'button-advanced-filter-ok' 'button (default)' 'hover (OK)' 346 326 'Advanced Filter'
  Done $d
  # Search
  $d=D1 (Dlg 'Search' 221 'search'); RestShot $d 'search' 'dialog (Search for Card)' 'Search > Search'
  Hv $d 'combo-box-edit-search' 'combo box (editable)' 'hover over the edit' 150 80 'Search for Card'
  Hv $d 'combo-box-drop-search' 'combo box' 'hover over the drop button' 300 80 'Search for Card'
  Hv $d 'radio-search-collection' 'radio button' 'hover (unselected Collection)' 36 183 'Search for Card'
  Hv $d 'radio-search-cards' 'radio button' 'hover (selected Cards)' 36 141 'Search for Card'
  Hv $d 'button-search-ok' 'button (default)' 'hover (OK)' 120 226 'Search for Card'
  Hv $d 'button-search-cancel' 'button' 'hover (Cancel)' 204 226 'Search for Card'
  HvDown $d 'button-search-ok-pressed' 'button (default)' 'hover and pressed (OK)' 120 226 'Search for Card'
  Done $d
  # Sort
  $d=D1 (Dlg 'View' 75 'sort'); RestShot $d 'sort' 'dialog (Sort)' 'View > Sort...'
  Hv $d 'grid-row-sort' 'data grid row' 'hover over a row' 100 108 'Sort'
  Hv $d 'grid-header-sort-order' 'data grid header' 'hot column header (Sort Order)' 260 52 'Sort'
  Hv $d 'grid-header-sort-column' 'data grid header' 'hot column header (Column)' 100 52 'Sort'
  Hv $d 'grid-cell-sort-order' 'data grid cell (image combo)' 'hover over the Sort Order cell' 250 108 'Sort'
  Hv $d 'button-sort-clear' 'button' 'hover (Clear)' 55 321 'Sort'
  Hv $d 'button-sort-ok' 'button (default)' 'hover (OK)' 230 321 'Sort'
  Hv $d 'scroll-bar-thumb-sort' 'scroll bar (grid)' 'hover over the thumb' 341 100 'Sort'
  Done $d
  # Customization
  $d=D1 (Dlg 'View' 303 'customization'); RestShot $d 'customization' 'dialog (Customization)' 'View > Show Columns...'
  Hv $d 'list-box-row-customization' 'list box (column chooser)' 'hover over a row' 80 80 'Customization'
  Hv $d 'list-box-row2-customization' 'list box (column chooser)' 'hover over a second row' 80 110 'Customization'
  Hv $d 'tab-customization-columns' 'tab control (single tab)' 'hover over the tab' 40 45 'Customization'
  Done $d
  # Conditional Formatting
  $d=D1 (Dlg 'View' 483 'conditional formatting'); RestShot $d 'conditional-formatting' 'dialog (Conditional Formatting)' 'View > Conditional Formatting...'
  Hv $d 'tree-list-conditional-formatting' 'tree list' 'hover over the rule list' 250 130 'Conditional Formatting'
  Hv $d 'button-conditional-formatting-new-rule' 'button' 'hover (New Rule...)' 80 96 'Conditional Formatting'
  Hv $d 'button-conditional-formatting-edit-rule-disabled' 'button' 'hover over a DISABLED button (Edit Rule...)' 211 96 'Conditional Formatting'
  Hv $d 'button-conditional-formatting-ok' 'button' 'hover (OK)' 457 390 'Conditional Formatting'
  Hv $d 'button-conditional-formatting-apply' 'button' 'hover (Apply)' 640 390 'Conditional Formatting'
  Hv $d 'combo-box-drop-conditional-formatting-show' 'combo box' 'hover over the drop button' 285 52 'Conditional Formatting'
  Combo-Hot $d 285 52 'conditional-formatting-show' 'Conditional Formatting, Show rules for'
  Done $d
  # Missing Set Cards
  $d=D1 (Dlg 'Reports' 103 'missing set cards'); RestShot $d 'missing-set-cards' 'dialog (Missing Set Cards)' 'Reports > Missing Set Cards'
  Hv $d 'grid-row-missing-set-cards' 'data grid row' 'hover over a row' 100 110 'Missing Set Cards'
  Hv $d 'radio-missing-set-cards-available' 'radio button' 'hover (unselected)' 32 404 'Missing Set Cards'
  Hv $d 'radio-missing-set-cards-missing' 'radio button' 'hover over the caption' 60 380 'Missing Set Cards'
  Hv $d 'button-missing-set-cards-ok' 'button (default)' 'hover (OK)' 130 477 'Missing Set Cards'
  Done $d
  # About
  $d=D1 (Dlg 'Help' 203 'about'); RestShot $d 'about' 'dialog (About)' 'Help > About'
  Hv $d 'button-about-ok' 'button (default)' 'hover (OK)' 397 345 'About'
  Hv $d 'label-link-about-support' 'link label' 'hover (Send email to Support)' 300 288 'About'
  Done $d
}
function Section-Deck {
  "== deck-mode dialogs"
  Start-Hooked 'D:\Temp\claude\v3run\Probe Deck.deck'; Sleepms 2000; Fresh; $pop=Open-Menu 'File'; ClickC $pop 60 317; Sleepms 3500; Activate (MainH)
  $d=D1 (Dlg 'File' 213 'deck properties'); RestShot $d 'deck-properties' 'dialog (Deck Properties)' 'File > Properties (deck mode)'
  Hv $d 'vertical-grid-row-deck-properties-name' 'vertical grid' 'hover over the Name value cell' 260 112 'Deck Properties'
  Hv $d 'vertical-grid-caption-deck-properties-author' 'vertical grid' 'hover over a row caption' 80 131 'Deck Properties'
  Hv $d 'vertical-grid-row-deck-properties-description' 'vertical grid' 'hover over the Description value cell' 260 226 'Deck Properties'
  Hv $d 'vertical-grid-combo-deck-properties-archetype' 'vertical grid (combo)' 'hover over the Archetype value cell' 260 362 'Deck Properties'
  Hv $d 'vertical-grid-category-deck-properties-general' 'vertical grid category header' 'hover over the category (collapse button)' 340 91 'Deck Properties'
  Hv $d 'button-deck-properties-ok' 'button (default)' 'hover (OK)' 225 525 'Deck Properties'
  Done $d
  $d=D1 (Dlg 'File' 233 'deck legality'); RestShot $d 'deck-legality' 'dialog (Deck Legality)' 'File > Legality'
  Hv $d 'button-deck-legality-standard' 'button (format toggle)' 'hover (Standard)' 78 77 'Deck Legality'
  Hv $d 'button-deck-legality-modern' 'button (format toggle)' 'hover (Modern)' 159 77 'Deck Legality'
  Hv $d 'button-deck-legality-close' 'button (default)' 'hover (Close)' 497 459 'Deck Legality'
  Done $d
  $d=D1 (Dlg 'File' 253 'statistics'); RestShot $d 'statistics' 'dialog (Statistics)' 'File > Statistics'
  $k=0; foreach($tx in @(40,100,180,250,340,435,525,625,700,780,870)){ $k++; Hv $d "tab-statistics-$k" 'tab control (top tabs)' "hover over tab $k" $tx 44 'Statistics' 350 }
  Hv $d 'button-statistics-close' 'button' 'hover (Close)' 902 482 'Statistics'
  Done $d
}


# ===================================================================== main grid: group box and group rows (View > Show Group Box, View > Group by Edition; unsaved view changes of the copy)
function Section-Grid {
  "== main grid, group box"
  Fresh; $m=MainH; $pop=Open-Menu 'View'; Activate $pop; Sleepms 300; ClickC $pop 60 363; Sleepms 1200
  RestShot $m 'grid-groupbox' 'data grid (group box shown)' 'View > Show Group Box'
  Hv $m 'grid-groupbox-empty' 'grid group-by box' 'hover over the empty box area' 500 128 'top grid, group box'
  $pop=Open-Menu 'View'; Activate $pop; Sleepms 300; ClickC $pop 60 139; Sleepms 2500; Activate $m
  RestShot $m 'grid-grouped' 'data grid (grouped by Edition)' 'View > Group by Edition'
  Hv $m 'grid-groupbox-chip' 'grid group-by box' 'hover over the Edition group chip' 245 128 'top grid, group box chip'
  Hv $m 'grid-group-row' 'data grid group row' 'hover over a group row' 400 194 'top grid, grouped'
  Hv $m 'grid-group-row-text' 'data grid group row' 'hover over a group row caption' 280 212 'top grid, grouped'
  Hv $m 'grid-group-row-expand' 'data grid group row' 'hover over the expand button' 237 176 'top grid, grouped'
  Hv $m 'grid-group-header-name' 'data grid header' 'hot column header while grouped (Name)' 330 156 'top grid, grouped'
  Hv $m 'grid-group-header-edition' 'data grid header' 'hot grouped column header (Edition)' 463 156 'top grid, grouped'
  HvDown $m 'grid-group-chip-pressed' 'grid group-by box' 'hover and pressed (Edition chip)' 245 128 'top grid, group box chip'
}

# ===================================================================== README / manifest
function Write-HoverDocs {
  $mf=Join-Path $script:Out 'manifest.csv'
  $old=@(); if(Test-Path $mf){ $old=@(Import-Csv $mf) }
  $mine=@($script:Rows | ?{ $_.File -like 'hover-*' })
  $mineNames=@($mine|%{$_.File}); $keep=@($old | ?{ $_.File -notin $mineNames -and (Test-Path (Join-Path $script:Out $_.File)) })
  $all=@($keep + $mine) | Sort-Object File -Unique
  $all | Export-Csv $mf -NoTypeInformation -Encoding UTF8
  $nf=Join-Path $script:Out 'hover-notes.csv'
  $nold=@(); if(Test-Path $nf){ $nold=@(Import-Csv $nf) }
  $hn=@($script:Notes|%{"$($_.Control)|$($_.State)"})
  $nall=@($nold | ?{ "$($_.Control)|$($_.State)" -notin $hn }) + @($script:Notes)
  $nall | Export-Csv $nf -NoTypeInformation -Encoding UTF8
}

function Run-Hover {
  Get-Process mtgstudio_s -ErrorAction SilentlyContinue | Stop-Process -Force
  Prepare-Data
  try {
    Start-Hooked
    foreach($s in @($Only -split ",")){ try{ switch($s){ 'main'{Section-Main} 'menus'{Section-Menus} 'options'{Section-Options} 'dialogs'{Section-Dialogs} 'deck'{Section-Deck} 'grid'{Section-Grid} } }catch{ "SECTION $s FAILED: $_"; NotReached "section $s" 'whole section' "$_" } }
  } finally { Write-HoverDocs; Get-Process mtgstudio_s -ErrorAction SilentlyContinue | Stop-Process -Force; FakeAway }
}
if($MyInvocation.InvocationName -ne '.'){ Run-Hover }
