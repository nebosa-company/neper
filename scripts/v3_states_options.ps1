# Section 3 of grab_v3_states.ps1: the Options dialog (11 pages). Dot-sourced by it; uses its helpers (Press, FocusOn, Rest, Combo-Open ...).
function OptDlg($page){ Fresh; $d=Open-Dialog 'Tools' 153; if(-not $d){ throw 'options did not open' }; if($page -gt 1){ Options-Page $d $page }; Activate $d; Sleepms 400; $d }
function Done($d){ [void](Close-Win $d); Sleepms 500 }
$script:BtnY=467
function Combo-Open($d,$pxDrop,$py,$name,$where,$downs=2){
  $known=(Top $script:p).H
  $u=PClick $d $pxDrop $py
  $n=Poll-New $known 2500 | ?{ $_.C -like '*Popup*' } | select -first 1
  if(-not $n){ NotReached "combo box ($where)" 'open drop-down list' 'no popup window appeared after a posted click on the drop button'; return }
  Sleepms 300
  Shot $d "combo-box-open-dialog-$name" 'combo box' 'drop button pressed / list open (dialog side)' "WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window ($where)"
  Shot $n.H "combo-box-open-list-$name" 'combo box drop-down list' 'open, current item selected' "popup window $($n.C) opened by the click ($where)"
  $r0=[W]::Rect($d)
  $inner=[W]::Children($d) | ?{ [W]::Cls($_) -like '*InnerEdit*' -and [W]::IsWindowVisible($_) } | ?{ $r=[W]::Rect($_); [math]::Abs(($r[1]-$r0[1])-($py-9)) -lt 12 } | select -first 1
  if($inner){ 1..$downs|%{ Key $inner 0x28; Sleepms 150 }; Sleepms 300
    Shot $n.H "combo-box-open-list-$name-row2" 'combo box drop-down list' "highlight moved down $downs rows (keyboard, stands in for the hovered row)" "VK_DOWN x$downs to the combo's inner edit ($where)"
    Shot $d "combo-box-open-dialog-$name-row2" 'combo box' 'list open, highlight moved' "same, dialog side" }
}
function Section-Options {
  "== options"
  # ---- page 1 Interface: buttons, check boxes, category list
  $d=OptDlg 1; Rest $d 'dialog-options-interface-rest' 'dialog (Options, Interface page)' 'Options, page 1' $true
  [void](Press $d 'button-pressed-options-cancel' 'button' 'pressed (Cancel)' 589 $script:BtnY 'Options')
  [void](Press $d 'button-pressed-options-ok' 'button (default)' 'pressed (OK, default button)' 505 $script:BtnY 'Options')
  [void](Press $d 'button-pressed-options-apply' 'button' 'pressed (Apply)' 673 $script:BtnY 'Options')
  [void](FocusOn $d 'button-focused-options-apply' 'button' 'focused non-default (Apply)' 673 $script:BtnY 'Options')
  [void](FocusOn $d 'button-focused-options-cancel' 'button' 'focused non-default (Cancel)' 589 $script:BtnY 'Options')
  [void](Press $d 'checkbox-pressed-options-show-tooltips' 'check box' 'pressed (mouse down)' 224 165 'Options > Interface, Show tooltips')
  [void](Press $d 'checkbox-pressed-options-hide-splash' 'check box' 'pressed' 224 84 'Options > Interface, Hide splash screen')
  [void](FocusOn $d 'checkbox-focused-options-show-tooltips' 'check box' 'focused (focus rectangle)' 260 165 'Options > Interface, Show tooltips')
  [void](FocusOn $d 'checkbox-focused-options-hide-splash' 'check box' 'focused' 260 84 'Options > Interface, Hide splash screen')
  [void](Press $d 'category-list-pressed-options-decks' 'category list (TCategoryButtons)' 'pressed item' 100 90 'Options, left list, Decks entry')
  Rest $d 'dialog-options-interface-after' 'dialog' 'Options page 1 after the states, for the diff'
  Done $d

  # ---- page 2 Decks: button edit (ellipsis), spin edit
  $d=OptDlg 2; Rest $d 'dialog-options-decks-rest' 'dialog (Options, Decks page)' 'Options, page 2' $true
  [void](PClick $d 400 104); Sleepms 500
  Shot $d 'edit-focused-options-deck-path' 'button edit (path)' 'focused with caret' 'WM_LBUTTONDOWN+UP inside the edit'
  $ie=Under $d 400 104; Msg $ie.H 0xB1 0 -1; Sleepms 400
  Shot $d 'edit-selected-options-deck-path' 'button edit (path)' 'text selected' 'EM_SETSEL(0,-1) posted to the inner edit'
  [void](Press $d 'edit-button-ellipsis-pressed-options-deck-path' 'button edit ellipsis' 'pressed ellipsis button' 700 104 'Options > Decks, path' 'WM_LBUTTONDOWN on the ... button, no up (the up would open a folder dialog)')
  [void](PClick $d 250 169); Sleepms 500
  Shot $d 'spin-edit-focused-options-max-same-cards' 'spin edit' 'focused with caret' 'click inside the spin edit'
  [void](Press $d 'spin-edit-arrow-up-pressed-options-max-same-cards' 'spin edit' 'up arrow pressed' 312 165 'Options > Decks, Max Same Cards')
  [void](Press $d 'spin-edit-arrow-down-pressed-options-max-same-cards' 'spin edit' 'down arrow pressed' 312 174 'Options > Decks, Max Same Cards')
  [void](Press $d 'spin-edit-arrow-left-pressed-options-max-same-cards' 'spin edit' 'left (decrease) button pressed' 296 169 'Options > Decks, Max Same Cards')
  [void](Press $d 'spin-edit-arrow-right-pressed-options-max-same-cards' 'spin edit' 'right (increase) button pressed' 326 169 'Options > Decks, Max Same Cards')
  Done $d

  # ---- page 3 Shortcuts: grid + hot key edit + buttons
  $d=OptDlg 3; Rest $d 'dialog-options-shortcuts-rest' 'dialog (Options, Shortcuts page)' 'Options, page 3' $true
  [void](PClick $d 380 118); Sleepms 500
  Shot $d 'grid-row-selected-focused-options-shortcuts' 'data grid (shortcuts)' 'selected row, grid focused' 'click on the Open row'
  $g=Under $d 380 118; Msg $g.H 0x8 0 0; Sleepms 500
  Shot $d 'grid-row-selected-unfocused-options-shortcuts' 'data grid (shortcuts)' 'selected row, grid not focused' 'WM_KILLFOCUS to the grid site'
  [void](Press $d 'grid-header-pressed-options-shortcuts' 'data grid header' 'pressed header (Command)' 400 82 'Options > Shortcuts')
  [void](PClick $d 450 424); Sleepms 500
  Shot $d 'edit-focused-options-shortcut-hotkey' 'hot key edit' 'focused' 'click inside the hot key edit'
  [void](Press $d 'button-pressed-options-shortcut-set' 'button' 'pressed (Set)' 588 424 'Options > Shortcuts')
  [void](Press $d 'button-pressed-options-shortcut-reset' 'button' 'pressed (Reset)' 672 424 'Options > Shortcuts')
  [void](Press $d 'scroll-bar-thumb-pressed-options-shortcuts' 'scroll bar (grid)' 'pressed thumb' 701 112 'Options > Shortcuts')
  Done $d

  # ---- page 4 Passwords: edits, button
  $d=OptDlg 4; Rest $d 'dialog-options-passwords-rest' 'dialog (Options, Passwords page)' 'Options, page 4' $true
  [void](PClick $d 450 100); Sleepms 500
  Shot $d 'edit-focused-options-old-password' 'text edit (password)' 'focused with caret' 'click inside Old Password'
  [void](PClick $d 450 153); Sleepms 500
  Shot $d 'edit-focused-options-new-password' 'text edit (password)' 'focused with caret' 'click inside New Password'
  [void](Press $d 'button-pressed-options-password-change' 'button' 'pressed (Change)' 252 244 'Options > Passwords')
  [void](FocusOn $d 'button-focused-options-password-change' 'button' 'focused non-default (Change)' 252 244 'Options > Passwords')
  Done $d

  # ---- page 5 Internet Authentication: combo
  $d=OptDlg 5; Rest $d 'dialog-options-internet-rest' 'dialog (Options, Internet Authentication page)' 'Options, page 5' $true
  Combo-Open $d 456 82 'options-auth-type' 'Options > Internet Authentication'
  Done $d

  # ---- page 6 Rules: check list box
  $d=OptDlg 6; Rest $d 'dialog-options-rules-rest' 'dialog (Options, Rules page)' 'Options, page 6' $true
  [void](PClick $d 330 119); Sleepms 500
  Shot $d 'check-list-box-row-selected-focused-options-rules' 'check list box' 'selected row (2nd), list focused' 'click on the text of the 2nd row'
  $l=Under $d 330 119; Msg $l.H 0x8 0 0; Sleepms 500
  Shot $d 'check-list-box-row-selected-unfocused-options-rules' 'check list box' 'selected row, list not focused' 'WM_KILLFOCUS to the list'
  Done $d
  $d=OptDlg 6
  [void](Press $d 'check-list-box-checkbox-pressed-options-rules' 'check list box' 'pressed check box in a row' 226 134 'Options > Rules, 2nd row')
  [void](FocusOn $d 'check-list-box-focused-options-rules' 'check list box' 'focused list' 330 300 'Options > Rules, empty area under the rows')
  Done $d

  # ---- page 7 Prices: check list box
  $d=OptDlg 7; Rest $d 'dialog-options-prices-rest' 'dialog (Options, Prices page)' 'Options, page 7' $true
  [void](PClick $d 330 134); Sleepms 500
  Shot $d 'check-list-box-row-selected-focused-options-prices' 'check list box' 'selected row (3rd), list focused' 'click on the text of the 3rd row'
  Done $d

  # ---- page 8 Grids: combos, check boxes, radio groups
  $d=OptDlg 8; Rest $d 'dialog-options-grids-rest' 'dialog (Options, Grids page)' 'Options, page 8' $true
  [void](FocusOn $d 'combo-box-focused-options-row-color' 'combo box' 'focused (no list)' 450 82 'Options > Grids, Row Color')
  [void](Press $d 'combo-box-drop-button-pressed-options-row-color' 'combo box' 'drop button pressed' 703 82 'Options > Grids, Row Color')
  [void](Press $d 'checkbox-pressed-options-show-foil' 'check box' 'pressed (checked box)' 234 113 'Options > Grids, Show Foil Symbol')
  [void](Press $d 'checkbox-pressed-options-show-filter-row' 'check box' 'pressed (unchecked box)' 234 143 'Options > Grids, Show Filter Row')
  [void](FocusOn $d 'checkbox-focused-options-show-foil' 'check box' 'focused' 270 113 'Options > Grids, Show Foil Symbol')
  [void](Press $d 'radio-pressed-options-search-within' 'radio button' 'pressed (unselected)' 238 275 'Options > Grids, Incremental Search: within')
  [void](Press $d 'radio-pressed-options-search-from-start' 'radio button' 'pressed (selected)' 238 233 'Options > Grids, Incremental Search: from start')
  [void](FocusOn $d 'radio-focused-options-search-from-start' 'radio button' 'focused (selected)' 300 233 'Options > Grids, Incremental Search: from start')
  [void](FocusOn $d 'radio-focused-options-search-within' 'radio button' 'focused (unselected)' 300 275 'Options > Grids, Incremental Search: within')
  [void](Press $d 'radio-pressed-options-move-next-row' 'radio button' 'pressed (unselected)' 238 386 'Options > Grids, Enter key: next row')
  Rest $d 'dialog-options-grids-after' 'dialog' 'Options page 8 after the states, for the diff'
  Done $d
  $d=OptDlg 8; Combo-Open $d 703 82 'options-row-color' 'Options > Grids, Row Color'; Done $d
  $d=OptDlg 8; Combo-Open $d 703 170 'options-font-size' 'Options > Grids, Font Size' 3; Done $d

  # ---- page 9 Defaults: combo
  $d=OptDlg 9; Rest $d 'dialog-options-defaults-rest' 'dialog (Options, Defaults page)' 'Options, page 9' $true
  Combo-Open $d 697 110 'options-condition' 'Options > Defaults, Condition' 3
  Done $d

  # ---- page 10 Card Art: check list, arrows, buttons
  $d=OptDlg 10; Rest $d 'dialog-options-cardart-rest' 'dialog (Options, Card Art page)' 'Options, page 10' $true
  [void](PClick $d 400 100); Sleepms 500
  Shot $d 'check-list-box-row-selected-focused-options-cardart' 'check list box' 'selected 2nd row, list focused' 'click on the 2nd row text'
  [void](Press $d 'button-pressed-options-cardart-validate' 'button' 'pressed (Validate)' 495 428 'Options > Card Art')
  [void](Press $d 'button-image-pressed-options-cardart-move-up' 'speed button (image)' 'pressed up arrow' 698 597 'Options > Card Art')
  [void](Press $d 'edit-button-ellipsis-pressed-options-cardart' 'button edit ellipsis' 'pressed ellipsis' 669 395 'Options > Card Art path')
  Done $d

  # ---- page 11 Morph: spin edits, check boxes, combo
  $d=OptDlg 11; Rest $d 'dialog-options-morph-rest' 'dialog (Options, Morph page)' 'Options, page 11' $true
  [void](PClick $d 420 115); Sleepms 500
  Shot $d 'spin-edit-focused-options-morph-speed' 'spin edit' 'focused with caret' 'click inside Morph Speed'
  [void](Press $d 'spin-edit-arrow-up-pressed-options-morph-speed' 'spin edit (stacked arrows)' 'up arrow pressed' 441 110 'Options > Morph, Morph Speed')
  [void](Press $d 'spin-edit-arrow-down-pressed-options-morph-speed' 'spin edit (stacked arrows)' 'down arrow pressed' 441 119 'Options > Morph, Morph Speed')
  [void](Press $d 'checkbox-pressed-options-morph-use' 'check box' 'pressed (checked)' 226 83 'Options > Morph, Use Morph effect')
  [void](FocusOn $d 'checkbox-focused-options-morph-use' 'check box' 'focused' 300 83 'Options > Morph, Use Morph effect')
  Done $d
  $d=OptDlg 11; Combo-Open $d 548 289 'options-card-art-position' 'Options > Morph, Card Art Position' 2; Done $d
}
