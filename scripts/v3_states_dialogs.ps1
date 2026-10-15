# Section 4 of grab_v3_states.ps1: states of the other dialogs (Filter, Search, Sort, Customization, Conditional Formatting, Missing Set Cards, About,
# Deck Properties, Deck Legality, Statistics, report previews). Dot-sourced by it; uses its helpers (Press, FocusOn, Rest, Combo-Open, Done ...).
function Dlg($menu,$y,$tag){ Fresh; $d=Open-Dialog $menu $y; if(-not $d){ throw "dialog $tag did not open" }; Activate $d; Sleepms 500; $d }
function Section-Dialogs {
  "== dialogs"
  # ---- Filter Card Pool (TFilterForm): page control, tree list, radios, buttons
  $d=Dlg 'Search' 13 'filter'; Rest $d 'dialog-filter-rest' 'dialog (Filter Card Pool)' 'Search > Filter Card Pool' $true
  [void](PClick $d 167 43); Sleepms 800; Shot $d 'tab-selected-filter-cards' 'tab control (page control, top tabs)' 'second tab (Cards) selected, first deselected' 'WM_LBUTTONDOWN+UP on the Cards tab' '' -Json
  [void](PClick $d 213 43); Sleepms 800; Shot $d 'tab-selected-filter-options' 'tab control (page control, top tabs)' 'third tab (Options) selected' 'click on the Options tab'
  [void](PClick $d 78 41); Sleepms 800
  [void](PClick $d 150 133); Sleepms 500
  Shot $d 'tree-list-row-selected-focused-filter' 'tree list' 'selected row (Core Sets), tree focused' 'click on a row of the Blocks tree'
  $t=Under $d 150 133; Msg $t.H 0x8 0 0; Sleepms 500
  Shot $d 'tree-list-row-selected-unfocused-filter' 'tree list' 'selected row, tree not focused' 'WM_KILLFOCUS to the tree site'
  [void](Press $d 'tree-list-checkbox-pressed-filter' 'tree list check box' 'pressed node check box' 44 133 'Filter > Blocks tree, Core Sets')
  [void](Press $d 'tree-list-expander-pressed-filter' 'tree list expander (+)' 'pressed expand button' 28 133 'Filter > Blocks tree')
  [void](Press $d 'radio-pressed-filter-formats' 'radio button' 'pressed (unselected Formats)' 115 74 'Filter > Blocks/Formats/Editions')
  [void](Press $d 'radio-pressed-filter-blocks' 'radio button' 'pressed (selected Blocks)' 27 74 'Filter > Blocks/Formats/Editions')
  [void](FocusOn $d 'radio-focused-filter-blocks' 'radio button' 'focused (selected)' 50 74 'Filter')
  [void](Press $d 'button-pressed-filter-all' 'button' 'pressed (All)' 65 424 'Filter')
  [void](FocusOn $d 'button-focused-filter-invert' 'button' 'focused non-default (Invert)' 232 424 'Filter')
  [void](Press $d 'button-pressed-filter-clear' 'button' 'pressed (Clear)' 60 466 'Filter')
  [void](Press $d 'button-pressed-filter-ok' 'button (default)' 'pressed (OK)' 488 466 'Filter')
  [void](Press $d 'splitter-pressed-filter' 'splitter (dialog)' 'pressed (no drag)' 336 250 'Filter, between tree and web view')
  [void](Press $d 'scroll-bar-thumb-pressed-filter-tree' 'scroll bar (tree)' 'pressed thumb' 317 120 'Filter, Blocks tree')
  Rest $d 'dialog-filter-after' 'dialog' 'Filter after the states, for the diff'; Done $d

  # ---- Advanced Filter (filter control)
  $d=Dlg 'Search' 53 'advanced filter'; Rest $d 'dialog-advanced-filter-rest' 'dialog (Advanced Filter)' 'Search > Advanced Filter' $true
  [void](PClick $d 200 80); Sleepms 600; Shot $d 'filter-control-focused-advanced-filter' 'filter control' 'clicked on the root condition' 'click on the root row'
  [void](Press $d 'button-pressed-advanced-filter-open' 'button' 'pressed (Open...)' 52 326 'Advanced Filter')
  [void](Press $d 'button-pressed-advanced-filter-ok' 'button (default)' 'pressed (OK)' 346 326 'Advanced Filter')
  Done $d

  # ---- Search for Card: combo (editable), radio group, buttons
  $d=Dlg 'Search' 221 'search'; Rest $d 'dialog-search-rest' 'dialog (Search for Card)' 'Search > Search' $true
  [void](PClick $d 150 80); Sleepms 500; Shot $d 'combo-box-edit-focused-search' 'combo box (editable)' 'focused with caret' 'click into the text area'
  [void](Press $d 'combo-box-drop-button-pressed-search' 'combo box' 'drop button pressed' 300 80 'Search for Card')
  [void](Press $d 'radio-pressed-search-collection' 'radio button' 'pressed (unselected Collection)' 36 183 'Search for Card')
  [void](Press $d 'radio-pressed-search-cards' 'radio button' 'pressed (selected Cards)' 36 141 'Search for Card')
  [void](FocusOn $d 'radio-focused-search-cards' 'radio button' 'focused (selected)' 60 141 'Search for Card')
  [void](FocusOn $d 'radio-focused-search-collection' 'radio button' 'focused (unselected)' 60 183 'Search for Card')
  [void](Press $d 'button-pressed-search-ok' 'button (default)' 'pressed (OK)' 120 226 'Search for Card')
  [void](Press $d 'button-pressed-search-cancel' 'button' 'pressed (Cancel)' 204 226 'Search for Card')
  Done $d
  $d=Dlg 'Search' 221 'search'; Combo-Open $d 300 80 'search-card' 'Search for Card, Card combo (history; may be empty)' 1; Done $d

  # ---- Sort dialog: grid with in-place image combo
  $d=Dlg 'View' 75 'sort'; Rest $d 'dialog-sort-rest' 'dialog (Sort)' 'View > Sort...' $true
  [void](PClick $d 100 108); Sleepms 500; Shot $d 'grid-row-selected-focused-sort' 'data grid (sort columns)' 'selected row (Name), focused' 'click a row'
  $g=Under $d 100 108; Msg $g.H 0x8 0 0; Sleepms 500; Shot $d 'grid-row-selected-unfocused-sort' 'data grid (sort columns)' 'selected row, grid not focused' 'WM_KILLFOCUS'
  [void](Press $d 'grid-header-pressed-sort' 'data grid header' 'pressed header (Sort Order)' 260 52 'Sort')
  [void](PClick $d 250 108); Sleepms 700; Shot $d 'image-combo-box-cell-editor-sort' 'image combo box (in-place cell editor)' 'editor active in the Sort Order cell' 'click the Sort Order cell of the Name row (no value changed)'
  $known=(Top $script:p).H; [void](PClick $d 322 108); $n=Poll-New $known 2000 | ?{ $_.C -like '*Popup*' } | select -first 1
  if($n){ Shot $d 'image-combo-box-open-dialog-sort' 'image combo box' 'drop-down open (dialog side)' 'click on the cell editor drop button'; Shot $n.H 'image-combo-box-open-list-sort' 'image combo box drop-down list' 'open list with images, current item selected' "popup $($n.C)" }
  else { NotReached 'image combo box (Sort Order cell)' 'open list' 'no popup after clicking the cell editor drop button' }
  Done $d
  $d=Dlg 'View' 75 'sort'
  [void](Press $d 'button-pressed-sort-clear' 'button' 'pressed (Clear)' 55 321 'Sort')
  [void](Press $d 'button-pressed-sort-ok' 'button (default)' 'pressed (OK)' 230 321 'Sort')
  [void](Press $d 'scroll-bar-thumb-pressed-sort' 'scroll bar (grid)' 'pressed thumb' 341 100 'Sort')
  Done $d

  # ---- Customization (grid columns list)
  $d=Dlg 'View' 303 'customization'; Rest $d 'dialog-customization-rest' 'dialog (Customization)' 'View > Show Columns...' $true
  [void](PClick $d 80 80); Sleepms 500; Shot $d 'list-box-row-selected-focused-customization' 'list box (column chooser)' 'selected row, list focused' 'click a row'
  $l=Under $d 80 80; Msg $l.H 0x8 0 0; Sleepms 500; Shot $d 'list-box-row-selected-unfocused-customization' 'list box (column chooser)' 'selected row, list not focused' 'WM_KILLFOCUS'
  [void](Press $d 'tab-pressed-customization-columns' 'tab control (single tab)' 'pressed tab' 40 45 'Customization')
  Done $d

  # ---- Conditional Formatting Rules Manager: tree list, combo, buttons
  $d=Dlg 'View' 483 'conditional formatting'; Rest $d 'dialog-conditional-formatting-rest' 'dialog (Conditional Formatting)' 'View > Conditional Formatting...' $true
  [void](PClick $d 250 130); Sleepms 500; Shot $d 'tree-list-focused-conditional-formatting' 'tree list' 'clicked in the (empty?) rule list' 'click'
  [void](Press $d 'button-pressed-conditional-formatting-new-rule' 'button' 'pressed (New Rule...)' 80 96 'Conditional Formatting')
  [void](Press $d 'button-disabled-conditional-formatting-edit-rule' 'button' 'pressed / disabled (Edit Rule...)' 211 96 'Conditional Formatting' 'a disabled button ignores the press: this shows its disabled look')
  [void](Press $d 'button-pressed-conditional-formatting-ok' 'button' 'pressed (OK)' 457 390 'Conditional Formatting')
  [void](FocusOn $d 'button-focused-conditional-formatting-apply' 'button' 'focused (Apply)' 640 390 'Conditional Formatting')
  Done $d
  $d=Dlg 'View' 483 'conditional formatting'; Combo-Open $d 285 52 'conditional-formatting-show' 'Conditional Formatting, Show rules for combo' 1; Done $d

}
function Part0 { # Missing Set Cards: grid + radios in a group box
  $d=Dlg 'Reports' 103 'missing set cards'; Rest $d 'dialog-missing-set-cards-rest' 'dialog (Missing Set Cards)' 'Reports > Missing Set Cards' $true
  [void](PClick $d 100 110); Sleepms 500; Shot $d 'grid-row-selected-focused-missing-set-cards' 'data grid (editions)' 'selected row, focused' 'click a row'
  [void](Press $d 'radio-pressed-missing-set-cards-available' 'radio button' 'pressed (unselected)' 32 404 'Missing Set Cards, Available Only')
  [void](FocusOn $d 'radio-focused-missing-set-cards-missing' 'radio button' 'focused' 60 380 'Missing Set Cards, Missing Only')
  [void](Press $d 'button-pressed-missing-set-cards-ok' 'button (default)' 'pressed (OK)' 130 477 'Missing Set Cards')
  Done $d

}
function Part1 { # About: page control, buttons, link labels
  $d=Dlg 'Help' 203 'about'; Rest $d 'dialog-about-rest' 'dialog (About)' 'Help > About' $true
  [void](Press $d 'button-pressed-about-ok' 'button (default)' 'pressed (OK)' 397 345 'About')
  [void](Press $d 'label-link-pressed-about-support' 'link label' 'pressed (Send email to Support)' 300 288 'About' 'down only: the up would start a mail client')
  Done $d

}
function Part2 { # Reports > Combos from Collection: try to catch the progress bar while it computes
  Fresh; $known=(Top $script:p).H; $pop=Open-Menu 'Reports'; if($pop -and [W]::Rect($pop)[2] -eq 228){ ClickC $pop 60 123
    $got=0; for($i=0;$i -lt 40;$i++){ Sleepms 120; $o=Others | select -first 1; if($o){ if($got -lt 3){ Shot $o.H "progress-while-computing-combos-$got" 'report preview / progress' "frame $got right after the click" "Reports > Combos from Collection, grabbed every 120 ms"; $got++ } else { break } } }
    if($got -eq 0){ NotReached 'progress bar' 'visible' 'no window appeared within 4.8 s to grab' }
    Start-Sleep 3; foreach($o in (Others)){ [void](Close-Win $o.H) } }

}
function Part3 { # deck-mode dialogs
  Start-With-Deck; Sleepms 2000; Fresh; $pop=Open-Menu 'File'; ClickC $pop 60 317; Sleepms 3500; Activate (MainH)   # File > Mode > Deck from Card Pool
  $d=Dlg 'File' 213 'deck properties'; Rest $d 'dialog-deck-properties-rest' 'dialog (Deck Properties)' 'File > Properties (deck mode)' $true
  [void](PClick $d 260 226); Sleepms 700; Shot $d 'vertical-grid-editor-open-deck-properties-description' 'vertical grid' 'in-place text editor open on Description' 'click on the value cell; nothing typed'
  [void](PClick $d 260 112); Sleepms 700; Shot $d 'vertical-grid-row-focused-deck-properties-name' 'vertical grid' 'focused row Name with editor' 'click on the value cell of Name; nothing typed'
  [void](PClick $d 80 131); Sleepms 600; Shot $d 'vertical-grid-row-selected-deck-properties-author' 'vertical grid' 'focused row Author (label click)' 'click on the row caption'
  [void](PClick $d 260 362); Sleepms 700; Shot $d 'vertical-grid-editor-combo-deck-properties-archetype' 'vertical grid (combo editor)' 'in-place combo editor active on Archetype' 'click on the value cell'
  $known=(Top $script:p).H; [void](PClick $d 335 362); $n=Poll-New $known 2000 | ?{ $_.C -like '*Popup*' } | select -first 1
  if($n){ Shot $n.H 'vertical-grid-combo-list-deck-properties-archetype' 'vertical grid combo drop-down' 'list open' "popup $($n.C)"; Shot $d 'vertical-grid-combo-open-dialog-deck-properties' 'vertical grid' 'combo open (dialog side)' 'click the editor drop button' } else { NotReached 'vertical grid combo' 'open list' 'no popup after clicking the editor drop button' }
  Done $d
  $d=Dlg 'File' 213 'deck properties'
  [void](Press $d 'vertical-grid-category-pressed-deck-properties-general' 'vertical grid category header' 'pressed (collapse button)' 340 91 'Deck Properties')
  [void](Press $d 'button-pressed-deck-properties-ok' 'button (default)' 'pressed (OK)' 225 525 'Deck Properties')
  Done $d

  $d=Dlg 'File' 233 'deck legality'; Rest $d 'dialog-deck-legality-rest' 'dialog (Deck Legality)' 'File > Legality' $true
  [void](Press $d 'button-pressed-deck-legality-standard' 'button (format toggle)' 'pressed (Standard)' 78 77 'Deck Legality')
  [void](FocusOn $d 'button-focused-deck-legality-modern' 'button' 'focused non-default (Modern)' 159 77 'Deck Legality')
  [void](Press $d 'button-pressed-deck-legality-close' 'button (default)' 'pressed (Close)' 497 459 'Deck Legality')
  Done $d

  $d=Dlg 'File' 253 'statistics'; Rest $d 'dialog-statistics-rest' 'dialog (Statistics)' 'File > Statistics' $true
  $tabs=@(40,100,180,250,340,435,525,625,700,780,870)
  $k=0; foreach($tx in $tabs){ $k++; [void](PClick $d $tx 44); Sleepms 900; Shot $d "tab-selected-statistics-$k" 'tab control (page control, top tabs)' "tab at x=$tx clicked (tab $k)" 'WM_LBUTTONDOWN+UP on the tab strip' '11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced' }
  [void](Press $d 'button-pressed-statistics-close' 'button' 'pressed (Close)' 902 482 'Statistics')
  Done $d

}
function Part4 { # Deck Registration Sheet: a report dialog, deck mode only
  Fresh; $pop=Open-Menu 'Reports'; if($pop){ Activate $pop; Shot $pop 'menu-reports-deck-mode' 'menu popup' 'Reports menu in deck mode (deck items enabled)' 'File > Mode > Deck from Card Pool, then Reports' }
  Close-Popups
  NotReached 'date edit' 'any state' 'no v3 dialog reached with posted messages contains a date edit: Deck Registration Sheets and Deck Availability would print/generate documents, so they were not opened'
}
function Section-Dialogs2 {
  "== dialogs 2"
  try{ Part0 }catch{ NotReached 'Missing Set Cards: grid + radios in a group box' 'whole block' "$_" }
  try{ Part1 }catch{ NotReached 'About: page control, buttons, link labels' 'whole block' "$_" }
  try{ Part2 }catch{ NotReached 'Reports > Combos from Collection: try to catch the progress ' 'whole block' "$_" }
  try{ Part3 }catch{ NotReached 'deck-mode dialogs' 'whole block' "$_" }
  try{ Part4 }catch{ NotReached 'Deck Registration Sheet: a report dialog, deck mode only' 'whole block' "$_" }
}
