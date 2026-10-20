# v3 interaction-state references

Captured by `scripts/grab_v3_states.ps1` (helpers in `scripts/v3_states_lib.ps1`, sections in `v3_states_options.ps1` and `v3_states_dialogs.ps1`) from a COPY of MTG Studio v3 3.235 with its own database copy, using only window messages: `WM_MOUSEMOVE`, `WM_LBUTTONDOWN` / `WM_LBUTTONUP`, `WM_KEYDOWN` / `WM_SYSKEYDOWN`, `WM_KILLFOCUS`, `WM_CANCELMODE`, `WM_NCACTIVATE`, `EM_SETSEL`, `WM_CLOSE`, plus programmatic `SetFocus` and `SetForegroundWindow` through `AttachThreadInput`. No `SendInput`, `mouse_event`, `keybd_event` or `SetCursorPos`; the real pointer and keyboard were never used. Every PNG is a `PrintWindow` (flag 2) of one window at 100 % (v3 and the script are DPI unaware), so pixels are true size. Windows are the dialog or main form itself, or the drop-down / menu popup window for open lists and menus. `manifest.csv` has the same table as below.

Each dialog is opened fresh, its `*-rest` grab is taken first, and the states follow in the same dialog, so any state diffs cleanly against the rest grab of its dialog (`dialog-options-<page>-rest`, `dialog-<name>-rest`, `main-window-rest`). Nothing was saved, applied, deleted, imported, exported, printed or run: a pressed state is a button-down with no button-up, then `WM_CANCELMODE`; every dialog was closed with `WM_CLOSE` (Cancel semantics). Some states do change an unsaved value inside the dialog that is then discarded: pressing a spin edit arrow auto-repeats and changes the number (the grabs show 5, 1, 11), and the Options Interface "after" grab can differ from "rest" for that reason; the real option values were never written.

## What is reachable and what is not

| Looks | Reachable with posted messages | How |
|---|---|---|
| pressed (buttons, check boxes, radios, spin arrows, ellipsis, scroll thumb, header, tab, category, link) | yes | `WM_LBUTTONDOWN` only, grab, `WM_CANCELMODE` |
| focus rectangle, focused button / default shift, caret, selection | yes | `SetFocus` on the child via `AttachThreadInput`; click inside an edit; `EM_SETSEL(0,-1)` to the inner edit |
| open drop-down list (combo, image combo, in-place combo) with the current row selected | yes, only while the dialog is the foreground window | `Activate` (SetForegroundWindow via AttachThreadInput), then a click on the drop button; the popup is a `TcxComboBoxPopupWindow` top-level window |
| the highlighted (hot-looking) row in a list or menu | yes, as a keyboard-selected row | `WM_KEYDOWN VK_DOWN` to the combo's inner edit or to the menu popup (blue row identical to the mouse row) |
| open menu title + open popup, sub-menu open | yes | click the title, `VK_DOWN` n times, `VK_RIGHT` for the sub-menu |
| selected focused / unfocused row (grid, tree, list, check list) | yes | click the row; `WM_KILLFOCUS` to the control for the unfocused look |
| inactive caption | main window only, approximately | `WM_NCACTIVATE 0` |
| hover (mouse over) of anything, toolbar buttons hot / pressed, hint windows, status bar / splitter / scroll bar / navigator hover, caption button hover, the mouse-hot row of menus and open lists | yes, with the pointer hook | `scripts/grab_v3_hover.ps1` on a copy whose `GetCursorPos` / `WindowFromPoint` / `GetKeyState(VK_LBUTTON)` are faked by `scripts/v3_hook` (section below); these are the `hover-*` files |
| caption button pressed | NO | `WM_NCLBUTTONDOWN` on the X returns at once and the grab shows the plain (not even hot) button: the system does not hold the pressed caption button without a real button; hover of the caption buttons IS captured (`hover-caption-*`) |
| progress bar | only if a window shows while computing | see the table: the report previews open in under 120 ms, the bar was never on screen when grabbed |
| date edit | not present | no dialog reachable without printing / generating a document has one |

Hover has its own section below. Without the hook it is not reachable: DevExpress / VCL read the real pointer.

## Hover (mouse-over) states

Captured by `scripts/grab_v3_hover.ps1` (helpers `scripts/v3_hover_lib.ps1`, hook source and build in `scripts/v3_hook/`, see its README). VCL and DevExpress decide "the mouse is over this control" from the real pointer (`GetCursorPos`, `WindowFromPoint`, `GetKeyState`, `TrackMouseEvent`), which posted messages cannot change. The copy (`mtgstudio_s.exe`, only that process) is therefore injected with `v3hook.dll`: those calls answer from a small shared memory block that the script writes (the fake pointer), the script then posts the ordinary `WM_MOUSEMOVE` to the window under that fake pointer, waits 350 to 600 ms and grabs with `PrintWindow`. The fake pointer is parked far off screen between grabs. The real cursor and keyboard are never used (no `SendInput`, `mouse_event`, `keybd_event`, `SetCursorPos`); the maintainer's v3, the installed program and `version-3` in the repo were not touched.

Naming: `hover-<control>-<what>@1x.png`. Every dialog or window gets a `hover-<dialog>-rest` grab first; each hover grab is also compared with a grab taken just before the pointer moved in, and the Notes column says `PIXEL-IDENTICAL to rest: no distinct hover look` where the control draws nothing different (disabled toolbar buttons, grid rows, group rows, status bar panels, the left tabs, Statistics tabs, list box rows ...). Those PNGs are kept as proof that the hover was tried. `hover-*-pressed` files are fake pointer + fake left button + `WM_LBUTTONDOWN`, never released (`WM_CANCELMODE` after). Hint windows are grabbed as their own top-level window (`hover-hint-*`, class `TdxBarHintWindow` / `TcxHintWindow`) plus the owner (`*-context`). Popup rows (`hover-menu-*-rowN`, `hover-combo-list-*-rowN`) are the true mouse-hot row, as opposed to the keyboard row of the other captures. Window-caption hover is a `WM_NCMOUSEMOVE` with the hit-test code (min, max, close are visibly hot).

Not captured: hint windows of the status bar panels (none appear) and of Options check boxes (none); a pressed caption button (see table); grid filter-row cells and date edits (no reachable screen: the filter row needs Options > Show Filter Row, which is a saved setting, and no dialog without printing has a date edit); a progress bar (Filter OK on the 120k pool finished in under 0.5 s and the status bar stayed on "Idle" in 20 frames). Hover on the deck-mode vertical grid, tree list rows, tabs, list boxes draws nothing different.

Traps specific to hover: the hook must be rebuilt for a new v3 build only if the exe stops importing those functions (it matches the resolved addresses in every module's import table, not names). `Start-Sleep 1500` is 1500 seconds. Hover state is per process: restarting the copy resets the hook, `Start-Hooked` re-injects. Hints appear only after a quiet 0.7 s and not at all after an unreleased dxBar button press, so the toolbar hints run before the pressed grabs. Posting `WM_MOUSEMOVE` repeatedly at the same spot restarts the hint timer. Native `Button` / `TcxButton` windows call `TrackMouseEvent(TME_LEAVE)`; with no real pointer over the window the system would send `WM_MOUSELEAVE` at once and un-hot the button, so the hook swallows those requests for button classes only (swallowing them for dxBar broke the toolbar hover). Re-run: `pwsh -File scripts\grab_v3_hover.ps1 [-Only main,menus,options,dialogs,deck,grid]`.

## Traps

- **v3 allows one instance per session** (named mutex `MtgStudioSetupRunPreventionMutex`). When the maintainer's own v3 is running, the plain copy only shows "MTG Studio is already started". `Make-PatchedCopy` writes `D:\Temp\claude\v3run\mtgstudio_s.exe`, the same bytes with the last character of that mutex name changed (`x` to `y`, one occurrence). The process is named `mtgstudio_s`; the maintainer's `mtgstudio` process is never touched.
- **Nothing visual happens in a background app**: drop-downs close at once and the open menu title stays flat when the window is not the foreground window. `Activate` first.
- **hwnds change** whenever an Options page is rebuilt (an `F4`-style shortcut jumps pages and rebuilds): look controls up by class and position (`Under` finds the deepest child at an image coordinate), never cache a handle across pages. A stale handle once toggled an unrelated check box.
- **A key posted to a control is first offered to the form's shortcuts**: `VK_F4` posted to a combo in Options jumped to the Shortcuts page instead of dropping the list. Use `Alt+Down` style keys or the drop button click.
- **Keys in an open menu only select, never press Enter**: the selection can sit on `Minimize`, `Stay on Top` or `Exit`. A stray posted key once left the copy minimised (rect at -32000): `Guard-Main` restores it with `SC_RESTORE`.
- **Never post VCL `CM_` messages** (`0xB013` CM_MOUSEENTER sent to a dxBar minimised the copy).
- `Escape` posted to a combo's inner edit closes the whole dialog (popup and form), so drop-down captures end with `WM_CLOSE` of the dialog.
- Posting `WM_LBUTTONUP` outside a pressed Cancel button still closed the dialog once; the scripts therefore never post the up of a press, only `WM_CANCELMODE`.
- Edit carets blink: a grab can land on the off phase (the focus look is the underline plus the caret when it shows).
- `Sleep 500` is 500 seconds in PowerShell; use `Start-Sleep -Milliseconds`.

## Re-run

```
pwsh -File scripts\grab_v3_states.ps1                 # everything: menus, main, options, dialogs (about 15 minutes), rewrites this README and manifest.csv
pwsh -File scripts\grab_v3_states.ps1 -Only options   # one section; README is rewritten from that section only, so run all to keep the full table
```

The script kills and relaunches the `mtgstudio_s` copy at the start. The copy runs on `D:\Temp\claude\v3run\mtgstudio.db3` (re-copy it from `D:\repos\mtg.studio.src\version-3\bin\` if damaged).

## Manifest

| File | Control | State | How reached | Window class | Size | Notes |
|---|---|---|---|---|---|---|
| button-disabled-conditional-formatting-edit-rule@1x.png | button | pressed / disabled (Edit Rule...) | a disabled button ignores the press: this shows its disabled look (Conditional Formatting) | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| button-focused-conditional-formatting-apply@1x.png | button | focused (Apply) | SetFocus via AttachThreadInput on the control (Conditional Formatting) | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| button-focused-deck-legality-modern@1x.png | button | focused non-default (Modern) | SetFocus via AttachThreadInput on the control (Deck Legality) | TDeckLegalityForm | 555x486 |  |
| button-focused-filter-invert@1x.png | button | focused non-default (Invert) | SetFocus via AttachThreadInput on the control (Filter) | TFilterForm | 708x493 |  |
| button-focused-options-apply@1x.png | button | focused non-default (Apply) | SetFocus via AttachThreadInput on the control (Options) | TOptionsForm | 728x494 |  |
| button-focused-options-cancel@1x.png | button | focused non-default (Cancel) | SetFocus via AttachThreadInput on the control (Options) | TOptionsForm | 728x494 |  |
| button-focused-options-password-change@1x.png | button | focused non-default (Change) | SetFocus via AttachThreadInput on the control (Options > Passwords) | TOptionsForm | 728x494 |  |
| button-image-pressed-options-cardart-move-up@1x.png | speed button (image) | pressed up arrow | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Card Art) | TOptionsForm | 728x494 |  |
| button-pressed-about-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (About) | TAboutForm | 452x372 |  |
| button-pressed-advanced-filter-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Advanced Filter) | TfmFilterControlDialog | 560x355 |  |
| button-pressed-advanced-filter-open@1x.png | button | pressed (Open...) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Advanced Filter) | TfmFilterControlDialog | 560x355 |  |
| button-pressed-conditional-formatting-new-rule@1x.png | button | pressed (New Rule...) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Conditional Formatting) | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| button-pressed-conditional-formatting-ok@1x.png | button | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Conditional Formatting) | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| button-pressed-deck-legality-close@1x.png | button (default) | pressed (Close) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Deck Legality) | TDeckLegalityForm | 555x486 |  |
| button-pressed-deck-legality-standard@1x.png | button (format toggle) | pressed (Standard) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Deck Legality) | TDeckLegalityForm | 555x486 |  |
| button-pressed-deck-properties-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Deck Properties) | TDeckPropertiesForm | 364x552 |  |
| button-pressed-filter-all@1x.png | button | pressed (All) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter) | TFilterForm | 708x493 |  |
| button-pressed-filter-clear@1x.png | button | pressed (Clear) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter) | TFilterForm | 708x493 |  |
| button-pressed-filter-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter) | TFilterForm | 708x493 |  |
| button-pressed-missing-set-cards-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Missing Set Cards) | TMissingSetCardsForm | 266x503 |  |
| button-pressed-options-apply@1x.png | button | pressed (Apply) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options) | TOptionsForm | 728x494 |  |
| button-pressed-options-cancel@1x.png | button | pressed (Cancel) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options) | TOptionsForm | 728x494 |  |
| button-pressed-options-cardart-validate@1x.png | button | pressed (Validate) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Card Art) | TOptionsForm | 728x494 |  |
| button-pressed-options-ok@1x.png | button (default) | pressed (OK, default button) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options) | TOptionsForm | 728x494 |  |
| button-pressed-options-password-change@1x.png | button | pressed (Change) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Passwords) | TOptionsForm | 728x494 |  |
| button-pressed-options-shortcut-reset@1x.png | button | pressed (Reset) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Shortcuts) | TOptionsForm | 728x494 |  |
| button-pressed-options-shortcut-set@1x.png | button | pressed (Set) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Shortcuts) | TOptionsForm | 728x494 |  |
| button-pressed-search-cancel@1x.png | button | pressed (Cancel) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Search for Card) | TSearchForm | 325x257 |  |
| button-pressed-search-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Search for Card) | TSearchForm | 325x257 |  |
| button-pressed-sort-clear@1x.png | button | pressed (Clear) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Sort) | TSortColumnsForm | 367x347 |  |
| button-pressed-sort-ok@1x.png | button (default) | pressed (OK) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Sort) | TSortColumnsForm | 367x347 |  |
| button-pressed-statistics-close@1x.png | button | pressed (Close) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Statistics) | TStatisticsForm | 957x509 |  |
| category-list-pressed-options-decks@1x.png | category list (TCategoryButtons) | pressed item | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options, left list, Decks entry) | TOptionsForm | 728x494 |  |
| check-list-box-checkbox-pressed-options-rules@1x.png | check list box | pressed check box in a row | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Rules, 2nd row) | TOptionsForm | 728x494 |  |
| check-list-box-focused-options-rules@1x.png | check list box | focused list | SetFocus via AttachThreadInput on the control (Options > Rules, empty area under the rows) | TOptionsForm | 728x494 |  |
| check-list-box-row-selected-focused-options-cardart@1x.png | check list box | selected 2nd row, list focused | click on the 2nd row text | TOptionsForm | 728x494 |  |
| check-list-box-row-selected-focused-options-prices@1x.png | check list box | selected row (3rd), list focused | click on the text of the 3rd row | TOptionsForm | 728x494 |  |
| check-list-box-row-selected-focused-options-rules@1x.png | check list box | selected row (2nd), list focused | click on the text of the 2nd row | TOptionsForm | 728x494 |  |
| check-list-box-row-selected-unfocused-options-rules@1x.png | check list box | selected row, list not focused | WM_KILLFOCUS to the list | TOptionsForm | 728x494 |  |
| checkbox-focused-options-hide-splash@1x.png | check box | focused | SetFocus via AttachThreadInput on the control (Options > Interface, Hide splash screen) | TOptionsForm | 728x494 |  |
| checkbox-focused-options-morph-use@1x.png | check box | focused | SetFocus via AttachThreadInput on the control (Options > Morph, Use Morph effect) | TOptionsForm | 728x494 |  |
| checkbox-focused-options-show-foil@1x.png | check box | focused | SetFocus via AttachThreadInput on the control (Options > Grids, Show Foil Symbol) | TOptionsForm | 728x494 |  |
| checkbox-focused-options-show-tooltips@1x.png | check box | focused (focus rectangle) | SetFocus via AttachThreadInput on the control (Options > Interface, Show tooltips) | TOptionsForm | 728x494 |  |
| checkbox-pressed-options-hide-splash@1x.png | check box | pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Interface, Hide splash screen) | TOptionsForm | 728x494 |  |
| checkbox-pressed-options-morph-use@1x.png | check box | pressed (checked) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Morph, Use Morph effect) | TOptionsForm | 728x494 |  |
| checkbox-pressed-options-show-filter-row@1x.png | check box | pressed (unchecked box) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Grids, Show Filter Row) | TOptionsForm | 728x494 |  |
| checkbox-pressed-options-show-foil@1x.png | check box | pressed (checked box) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Grids, Show Foil Symbol) | TOptionsForm | 728x494 |  |
| checkbox-pressed-options-show-tooltips@1x.png | check box | pressed (mouse down) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Interface, Show tooltips) | TOptionsForm | 728x494 |  |
| combo-box-drop-button-pressed-options-row-color@1x.png | combo box | drop button pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Grids, Row Color) | TOptionsForm | 728x494 |  |
| combo-box-drop-button-pressed-search@1x.png | combo box | drop button pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Search for Card) | TSearchForm | 325x257 |  |
| combo-box-edit-focused-search@1x.png | combo box (editable) | focused with caret | click into the text area | TSearchForm | 325x257 |  |
| combo-box-focused-options-row-color@1x.png | combo box | focused (no list) | SetFocus via AttachThreadInput on the control (Options > Grids, Row Color) | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-conditional-formatting-show-row2@1x.png | combo box | list open, highlight moved | same, dialog side | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| combo-box-open-dialog-conditional-formatting-show@1x.png | combo box | drop button pressed / list open (dialog side) | WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window (Conditional Formatting, Show rules for combo) | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| combo-box-open-dialog-options-auth-type-row2@1x.png | combo box | list open, highlight moved | same, dialog side | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-auth-type@1x.png | combo box | drop button pressed / list open (dialog side) | WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window (Options > Internet Authentication) | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-card-art-position-row2@1x.png | combo box | list open, highlight moved | same, dialog side | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-card-art-position@1x.png | combo box | drop button pressed / list open (dialog side) | WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window (Options > Morph, Card Art Position) | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-condition-row2@1x.png | combo box | list open, highlight moved | same, dialog side | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-condition@1x.png | combo box | drop button pressed / list open (dialog side) | WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window (Options > Defaults, Condition) | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-font-size-row2@1x.png | combo box | list open, highlight moved | same, dialog side | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-font-size@1x.png | combo box | drop button pressed / list open (dialog side) | WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window (Options > Grids, Font Size) | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-row-color-row2@1x.png | combo box | list open, highlight moved | same, dialog side | TOptionsForm | 728x494 |  |
| combo-box-open-dialog-options-row-color@1x.png | combo box | drop button pressed / list open (dialog side) | WM_LBUTTONDOWN+UP on the drop button while the dialog is the foreground window (Options > Grids, Row Color) | TOptionsForm | 728x494 |  |
| combo-box-open-list-conditional-formatting-show-row2@1x.png | combo box drop-down list | highlight moved down 1 rows (keyboard, stands in for the hovered row) | VK_DOWN x1 to the combo's inner edit (Conditional Formatting, Show rules for combo) | TcxComboBoxPopupWindow | 143x106 |  |
| combo-box-open-list-conditional-formatting-show@1x.png | combo box drop-down list | open, current item selected | popup window TcxComboBoxPopupWindow opened by the click (Conditional Formatting, Show rules for combo) | TcxComboBoxPopupWindow | 143x106 |  |
| combo-box-open-list-options-auth-type-row2@1x.png | combo box drop-down list | highlight moved down 2 rows (keyboard, stands in for the hovered row) | VK_DOWN x2 to the combo's inner edit (Options > Internet Authentication) | TcxComboBoxPopupWindow | 189x32 |  |
| combo-box-open-list-options-auth-type@1x.png | combo box drop-down list | open, current item selected | popup window TcxComboBoxPopupWindow opened by the click (Options > Internet Authentication) | TcxComboBoxPopupWindow | 189x32 |  |
| combo-box-open-list-options-card-art-position-row2@1x.png | combo box drop-down list | highlight moved down 2 rows (keyboard, stands in for the hovered row) | VK_DOWN x2 to the combo's inner edit (Options > Morph, Card Art Position) | TcxComboBoxPopupWindow | 151x47 |  |
| combo-box-open-list-options-card-art-position@1x.png | combo box drop-down list | open, current item selected | popup window TcxComboBoxPopupWindow opened by the click (Options > Morph, Card Art Position) | TcxComboBoxPopupWindow | 151x47 |  |
| combo-box-open-list-options-condition-row2@1x.png | combo box drop-down list | highlight moved down 3 rows (keyboard, stands in for the hovered row) | VK_DOWN x3 to the combo's inner edit (Options > Defaults, Condition) | TcxComboBoxPopupWindow | 335x227 |  |
| combo-box-open-list-options-condition@1x.png | combo box drop-down list | open, current item selected | popup window TcxComboBoxPopupWindow opened by the click (Options > Defaults, Condition) | TcxComboBoxPopupWindow | 335x227 |  |
| combo-box-open-list-options-font-size-row2@1x.png | combo box drop-down list | highlight moved down 3 rows (keyboard, stands in for the hovered row) | VK_DOWN x3 to the combo's inner edit (Options > Grids, Font Size) | TcxComboBoxPopupWindow | 389x54 |  |
| combo-box-open-list-options-font-size@1x.png | combo box drop-down list | open, current item selected | popup window TcxComboBoxPopupWindow opened by the click (Options > Grids, Font Size) | TcxComboBoxPopupWindow | 389x54 |  |
| combo-box-open-list-options-row-color-row2@1x.png | combo box drop-down list | highlight moved down 2 rows (keyboard, stands in for the hovered row) | VK_DOWN x2 to the combo's inner edit (Options > Grids, Row Color) | TcxComboBoxPopupWindow | 389x41 |  |
| combo-box-open-list-options-row-color@1x.png | combo box drop-down list | open, current item selected | popup window TcxComboBoxPopupWindow opened by the click (Options > Grids, Row Color) | TcxComboBoxPopupWindow | 389x41 |  |
| dialog-about-rest@1x.png | dialog (About) | rest | dialog just opened (Help > About) | TAboutForm | 452x372 |  |
| dialog-advanced-filter-rest@1x.png | dialog (Advanced Filter) | rest | dialog just opened (Search > Advanced Filter) | TfmFilterControlDialog | 560x355 |  |
| dialog-chrome-inactive-caption-main@1x.png | title bar | inactive window (caption greyed) | WM_NCACTIVATE with wParam 0 to the main form | TMainForm | 800x600 |  |
| dialog-conditional-formatting-rest@1x.png | dialog (Conditional Formatting) | rest | dialog just opened (View > Conditional Formatting...) | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| dialog-customization-rest@1x.png | dialog (Customization) | rest | dialog just opened (View > Show Columns...) | TcxGridBandedTableCustomizationForm | 180x300 |  |
| dialog-deck-legality-rest@1x.png | dialog (Deck Legality) | rest | dialog just opened (File > Legality) | TDeckLegalityForm | 555x486 |  |
| dialog-deck-properties-rest@1x.png | dialog (Deck Properties) | rest | dialog just opened (File > Properties (deck mode)) | TDeckPropertiesForm | 364x552 |  |
| dialog-filter-after@1x.png | dialog | rest | dialog just opened (Filter after the states, for the diff) | TFilterForm | 708x493 |  |
| dialog-filter-rest@1x.png | dialog (Filter Card Pool) | rest | dialog just opened (Search > Filter Card Pool) | TFilterForm | 708x493 |  |
| dialog-missing-set-cards-rest@1x.png | dialog (Missing Set Cards) | rest | dialog just opened (Reports > Missing Set Cards) | TMissingSetCardsForm | 266x503 |  |
| dialog-options-cardart-rest@1x.png | dialog (Options, Card Art page) | rest | dialog just opened (Options, page 10) | TOptionsForm | 728x494 |  |
| dialog-options-decks-rest@1x.png | dialog (Options, Decks page) | rest | dialog just opened (Options, page 2) | TOptionsForm | 728x494 |  |
| dialog-options-defaults-rest@1x.png | dialog (Options, Defaults page) | rest | dialog just opened (Options, page 9) | TOptionsForm | 728x494 |  |
| dialog-options-grids-after@1x.png | dialog | rest | dialog just opened (Options page 8 after the states, for the diff) | TOptionsForm | 728x494 |  |
| dialog-options-grids-rest@1x.png | dialog (Options, Grids page) | rest | dialog just opened (Options, page 8) | TOptionsForm | 728x494 |  |
| dialog-options-interface-after@1x.png | dialog | rest | dialog just opened (Options page 1 after the states, for the diff) | TOptionsForm | 728x494 |  |
| dialog-options-interface-rest@1x.png | dialog (Options, Interface page) | rest | dialog just opened (Options, page 1) | TOptionsForm | 728x494 |  |
| dialog-options-internet-rest@1x.png | dialog (Options, Internet Authentication page) | rest | dialog just opened (Options, page 5) | TOptionsForm | 728x494 |  |
| dialog-options-morph-rest@1x.png | dialog (Options, Morph page) | rest | dialog just opened (Options, page 11) | TOptionsForm | 728x494 |  |
| dialog-options-passwords-rest@1x.png | dialog (Options, Passwords page) | rest | dialog just opened (Options, page 4) | TOptionsForm | 728x494 |  |
| dialog-options-prices-rest@1x.png | dialog (Options, Prices page) | rest | dialog just opened (Options, page 7) | TOptionsForm | 728x494 |  |
| dialog-options-rules-rest@1x.png | dialog (Options, Rules page) | rest | dialog just opened (Options, page 6) | TOptionsForm | 728x494 |  |
| dialog-options-shortcuts-rest@1x.png | dialog (Options, Shortcuts page) | rest | dialog just opened (Options, page 3) | TOptionsForm | 728x494 |  |
| dialog-search-rest@1x.png | dialog (Search for Card) | rest | dialog just opened (Search > Search) | TSearchForm | 325x257 |  |
| dialog-sort-rest@1x.png | dialog (Sort) | rest | dialog just opened (View > Sort...) | TSortColumnsForm | 367x347 |  |
| dialog-statistics-rest@1x.png | dialog (Statistics) | rest | dialog just opened (File > Statistics) | TStatisticsForm | 957x509 |  |
| edit-button-ellipsis-pressed-options-cardart@1x.png | button edit ellipsis | pressed ellipsis | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Card Art path) | TOptionsForm | 728x494 |  |
| edit-button-ellipsis-pressed-options-deck-path@1x.png | button edit ellipsis | pressed ellipsis button | WM_LBUTTONDOWN on the ... button, no up (the up would open a folder dialog) (Options > Decks, path) | TOptionsForm | 728x494 |  |
| edit-focused-options-deck-path@1x.png | button edit (path) | focused with caret | WM_LBUTTONDOWN+UP inside the edit | TOptionsForm | 728x494 |  |
| edit-focused-options-new-password@1x.png | text edit (password) | focused with caret | click inside New Password | TOptionsForm | 728x494 |  |
| edit-focused-options-old-password@1x.png | text edit (password) | focused with caret | click inside Old Password | TOptionsForm | 728x494 |  |
| edit-focused-options-shortcut-hotkey@1x.png | hot key edit | focused | click inside the hot key edit | TOptionsForm | 728x494 |  |
| edit-selected-options-deck-path@1x.png | button edit (path) | text selected | EM_SETSEL(0,-1) posted to the inner edit | TOptionsForm | 728x494 |  |
| filter-control-focused-advanced-filter@1x.png | filter control | clicked on the root condition | click on the root row | TfmFilterControlDialog | 560x355 |  |
| grid-header-pressed-main@1x.png | data grid header | pressed column header (the hot filter glyph shows too) | WM_LBUTTONDOWN on the Type header, no WM_LBUTTONUP, then WM_CANCELMODE | TMainForm | 800x600 |  |
| grid-header-pressed-options-shortcuts@1x.png | data grid header | pressed header (Command) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Shortcuts) | TOptionsForm | 728x494 |  |
| grid-header-pressed-sort@1x.png | data grid header | pressed header (Sort Order) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Sort) | TSortColumnsForm | 367x347 |  |
| grid-navigator-first-pressed-main@1x.png | grid navigator | pressed 'first' button | WM_LBUTTONDOWN on the first record button of the top grid, no WM_LBUTTONUP, then WM_CANCELMODE | TMainForm | 800x600 |  |
| grid-navigator-last-pressed-main@1x.png | grid navigator | pressed 'last' button | WM_LBUTTONDOWN on the last record button of the top grid, no WM_LBUTTONUP, then WM_CANCELMODE | TMainForm | 800x600 |  |
| grid-navigator-next-pressed-main@1x.png | grid navigator | pressed 'next' button | WM_LBUTTONDOWN on the next record button of the top grid, no WM_LBUTTONUP, then WM_CANCELMODE | TMainForm | 800x600 |  |
| grid-navigator-rest-main@1x.png | grid navigator | rest | after the presses were cancelled | TMainForm | 800x600 |  |
| grid-row-selected-focused-main-bottom@1x.png | data grid (bottom, collection) | selected row, grid focused | click on a row of the bottom grid (empty collection copy: the click may only focus) | TMainForm | 800x600 |  |
| grid-row-selected-focused-main@1x.png | data grid (top) | selected row, grid focused | WM_LBUTTONDOWN+UP on a row of the top grid | TMainForm | 800x600 |  |
| grid-row-selected-focused-missing-set-cards@1x.png | data grid (editions) | selected row, focused | click a row | TMissingSetCardsForm | 266x503 |  |
| grid-row-selected-focused-options-shortcuts@1x.png | data grid (shortcuts) | selected row, grid focused | click on the Open row | TOptionsForm | 728x494 |  |
| grid-row-selected-focused-sort@1x.png | data grid (sort columns) | selected row (Name), focused | click a row | TSortColumnsForm | 367x347 |  |
| grid-row-selected-unfocused-main@1x.png | data grid (top) | selected row, grid not focused | same row, then WM_KILLFOCUS to the grid site | TMainForm | 800x600 |  |
| grid-row-selected-unfocused-options-shortcuts@1x.png | data grid (shortcuts) | selected row, grid not focused | WM_KILLFOCUS to the grid site | TOptionsForm | 728x494 |  |
| grid-row-selected-unfocused-sort@1x.png | data grid (sort columns) | selected row, grid not focused | WM_KILLFOCUS | TSortColumnsForm | 367x347 |  |
| image-combo-box-cell-editor-sort@1x.png | image combo box (in-place cell editor) | editor active in the Sort Order cell | click the Sort Order cell of the Name row (no value changed) | TSortColumnsForm | 367x347 |  |
| image-combo-box-open-dialog-sort@1x.png | image combo box | drop-down open (dialog side) | click on the cell editor drop button | TSortColumnsForm | 367x347 |  |
| image-combo-box-open-list-sort@1x.png | image combo box drop-down list | open list with images, current item selected | popup TcxComboBoxPopupWindow | TcxComboBoxPopupWindow | 153x56 |  |
| label-link-pressed-about-support@1x.png | link label | pressed (Send email to Support) | down only: the up would start a mail client (About) | TAboutForm | 452x372 |  |
| list-box-row-selected-focused-customization@1x.png | list box (column chooser) | selected row, list focused | click a row | TcxGridBandedTableCustomizationForm | 180x300 |  |
| list-box-row-selected-unfocused-customization@1x.png | list box (column chooser) | selected row, list not focused | WM_KILLFOCUS | TcxGridBandedTableCustomizationForm | 180x300 |  |
| main-window-rest@1x.png | main window | rest | launch, window active (the rest reference for every main-window state below) | TMainForm | 800x600 |  |
| menu-bar-open-title-cardart@1x.png | menu bar | open title (pressed) | click 'Card Art' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-cards@1x.png | menu bar | open title (pressed) | click 'Cards' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-file@1x.png | menu bar | open title (pressed) | click 'File' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-help@1x.png | menu bar | open title (pressed) | click 'Help' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-online@1x.png | menu bar | open title (pressed) | click 'Online' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-reports@1x.png | menu bar | open title (pressed) | click 'Reports' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-search@1x.png | menu bar | open title (pressed) | click 'Search' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-tools@1x.png | menu bar | open title (pressed) | click 'Tools' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-bar-open-title-view@1x.png | menu bar | open title (pressed) | click 'View' on the Main Menu bar; popup stays open | TMainForm | 800x600 |  |
| menu-item-selected-cardart-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Card Art', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 189x332 |  |
| menu-item-selected-cardart-3@1x.png | menu popup | selected row (keyboard focus row #3) | click 'Card Art', then 3 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 189x332 |  |
| menu-item-selected-cards-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Cards', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 217x496 |  |
| menu-item-selected-cards-4@1x.png | menu popup | selected row (keyboard focus row #4) | click 'Cards', then 4 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 217x496 |  |
| menu-item-selected-file-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'File', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 251x580 | disabled first row (New...) |
| menu-item-selected-file-24@1x.png | menu popup | selected row (keyboard focus row #24) | click 'File', then 24 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 251x580 | near the bottom (Stay on Top) |
| menu-item-selected-help-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Help', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 191x216 |  |
| menu-item-selected-help-4@1x.png | menu popup | selected row (keyboard focus row #4) | click 'Help', then 4 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 191x216 |  |
| menu-item-selected-online-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Online', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 162x86 |  |
| menu-item-selected-reports-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Reports', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 228x206 |  |
| menu-item-selected-search-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Search', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 227x488 |  |
| menu-item-selected-search-5@1x.png | menu popup | selected row (keyboard focus row #5) | click 'Search', then 5 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 227x488 |  |
| menu-item-selected-tools-1@1x.png | menu popup | selected row (keyboard focus row #1) | click 'Tools', then 1 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 255x166 |  |
| menu-item-selected-tools-3@1x.png | menu popup | selected row (keyboard focus row #3) | click 'Tools', then 3 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 255x166 |  |
| menu-item-selected-view-5@1x.png | menu popup | selected row (keyboard focus row #5) | click 'View', then 5 x WM_KEYDOWN VK_DOWN to the popup | TdxBarSubMenuControl | 214x626 |  |
| menu-reports-deck-mode@1x.png | menu popup | Reports menu in deck mode (deck items enabled) | File > Mode > Deck from Card Pool, then Reports | TdxBarSubMenuControl | 228x206 |  |
| menu-submenu-open-cards-export-0@1x.png | menu popup | sub-menu open, parent row selected | Cards menu, 18 x VK_DOWN then VK_RIGHT (popup #0 of 2, later ones are the sub-menu) | TdxBarSubMenuControl | 130x126 |  |
| menu-submenu-open-cards-export-1@1x.png | menu popup | sub-menu open, parent row selected | Cards menu, 18 x VK_DOWN then VK_RIGHT (popup #1 of 2, later ones are the sub-menu) | TdxBarSubMenuControl | 217x496 |  |
| progress-while-computing-combos-0@1x.png | report preview / progress | frame 0 right after the click | Reports > Combos from Collection, grabbed every 120 ms | TfrxPreviewForm | 1296x768 |  |
| progress-while-computing-combos-1@1x.png | report preview / progress | frame 1 right after the click | Reports > Combos from Collection, grabbed every 120 ms | TfrxPreviewForm | 1296x768 |  |
| progress-while-computing-combos-2@1x.png | report preview / progress | frame 2 right after the click | Reports > Combos from Collection, grabbed every 120 ms | TfrxPreviewForm | 1296x768 |  |
| radio-focused-filter-blocks@1x.png | radio button | focused (selected) | SetFocus via AttachThreadInput on the control (Filter) | TFilterForm | 708x493 |  |
| radio-focused-missing-set-cards-missing@1x.png | radio button | focused | SetFocus via AttachThreadInput on the control (Missing Set Cards, Missing Only) | TMissingSetCardsForm | 266x503 |  |
| radio-focused-options-search-from-start@1x.png | radio button | focused (selected) | SetFocus via AttachThreadInput on the control (Options > Grids, Incremental Search: from start) | TOptionsForm | 728x494 |  |
| radio-focused-options-search-within@1x.png | radio button | focused (unselected) | SetFocus via AttachThreadInput on the control (Options > Grids, Incremental Search: within) | TOptionsForm | 728x494 |  |
| radio-focused-search-cards@1x.png | radio button | focused (selected) | SetFocus via AttachThreadInput on the control (Search for Card) | TSearchForm | 325x257 |  |
| radio-focused-search-collection@1x.png | radio button | focused (unselected) | SetFocus via AttachThreadInput on the control (Search for Card) | TSearchForm | 325x257 |  |
| radio-pressed-filter-blocks@1x.png | radio button | pressed (selected Blocks) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter > Blocks/Formats/Editions) | TFilterForm | 708x493 |  |
| radio-pressed-filter-formats@1x.png | radio button | pressed (unselected Formats) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter > Blocks/Formats/Editions) | TFilterForm | 708x493 |  |
| radio-pressed-missing-set-cards-available@1x.png | radio button | pressed (unselected) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Missing Set Cards, Available Only) | TMissingSetCardsForm | 266x503 |  |
| radio-pressed-options-move-next-row@1x.png | radio button | pressed (unselected) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Grids, Enter key: next row) | TOptionsForm | 728x494 |  |
| radio-pressed-options-search-from-start@1x.png | radio button | pressed (selected) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Grids, Incremental Search: from start) | TOptionsForm | 728x494 |  |
| radio-pressed-options-search-within@1x.png | radio button | pressed (unselected) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Grids, Incremental Search: within) | TOptionsForm | 728x494 |  |
| radio-pressed-search-cards@1x.png | radio button | pressed (selected Cards) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Search for Card) | TSearchForm | 325x257 |  |
| radio-pressed-search-collection@1x.png | radio button | pressed (unselected Collection) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Search for Card) | TSearchForm | 325x257 |  |
| scroll-bar-arrow-pressed-main-vertical@1x.png | scroll bar (vertical, top grid) | pressed lower arrow / track | WM_LBUTTONDOWN near the bottom of the track, then WM_CANCELMODE | TMainForm | 800x600 |  |
| scroll-bar-thumb-pressed-filter-tree@1x.png | scroll bar (tree) | pressed thumb | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter, Blocks tree) | TFilterForm | 708x493 |  |
| scroll-bar-thumb-pressed-main-horizontal@1x.png | scroll bar (horizontal, in the navigator) | pressed thumb | WM_LBUTTONDOWN on the thumb, no WM_LBUTTONUP, then WM_CANCELMODE | TMainForm | 800x600 |  |
| scroll-bar-thumb-pressed-main-vertical@1x.png | scroll bar (vertical, top grid) | pressed thumb | WM_LBUTTONDOWN on the thumb, no WM_LBUTTONUP, then WM_CANCELMODE | TMainForm | 800x600 |  |
| scroll-bar-thumb-pressed-options-shortcuts@1x.png | scroll bar (grid) | pressed thumb | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Shortcuts) | TOptionsForm | 728x494 |  |
| scroll-bar-thumb-pressed-sort@1x.png | scroll bar (grid) | pressed thumb | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Sort) | TSortColumnsForm | 367x347 |  |
| spin-edit-arrow-down-pressed-options-max-same-cards@1x.png | spin edit | down arrow pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Decks, Max Same Cards) | TOptionsForm | 728x494 |  |
| spin-edit-arrow-down-pressed-options-morph-speed@1x.png | spin edit (stacked arrows) | down arrow pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Morph, Morph Speed) | TOptionsForm | 728x494 |  |
| spin-edit-arrow-left-pressed-options-max-same-cards@1x.png | spin edit | left (decrease) button pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Decks, Max Same Cards) | TOptionsForm | 728x494 |  |
| spin-edit-arrow-right-pressed-options-max-same-cards@1x.png | spin edit | right (increase) button pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Decks, Max Same Cards) | TOptionsForm | 728x494 |  |
| spin-edit-arrow-up-pressed-options-max-same-cards@1x.png | spin edit | up arrow pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Decks, Max Same Cards) | TOptionsForm | 728x494 |  |
| spin-edit-arrow-up-pressed-options-morph-speed@1x.png | spin edit (stacked arrows) | up arrow pressed | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Options > Morph, Morph Speed) | TOptionsForm | 728x494 |  |
| spin-edit-focused-options-max-same-cards@1x.png | spin edit | focused with caret | click inside the spin edit | TOptionsForm | 728x494 |  |
| spin-edit-focused-options-morph-speed@1x.png | spin edit | focused with caret | click inside Morph Speed | TOptionsForm | 728x494 |  |
| splitter-pressed-filter@1x.png | splitter (dialog) | pressed (no drag) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter, between tree and web view) | TFilterForm | 708x493 |  |
| splitter-pressed-main-horizontal@1x.png | splitter (horizontal, between grids) | pressed (no drag) | WM_LBUTTONDOWN on the 8 px strip, no move, then WM_CANCELMODE | TMainForm | 800x600 |  |
| splitter-pressed-main-vertical@1x.png | splitter (vertical, left) | pressed (no drag) | WM_LBUTTONDOWN on the 8 px strip, no move, then WM_CANCELMODE | TMainForm | 800x600 |  |
| tab-pressed-customization-columns@1x.png | tab control (single tab) | pressed tab | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Customization) | TcxGridBandedTableCustomizationForm | 180x300 |  |
| tab-selected-filter-cards@1x.png | tab control (page control, top tabs) | second tab (Cards) selected, first deselected | WM_LBUTTONDOWN+UP on the Cards tab | TFilterForm | 708x493 |  |
| tab-selected-filter-options@1x.png | tab control (page control, top tabs) | third tab (Options) selected | click on the Options tab | TFilterForm | 708x493 |  |
| tab-selected-second-main-left@1x.png | tab control (left, bottom tabs) | second tab selected | WM_LBUTTONDOWN+UP on the second tab | TMainForm | 800x600 |  |
| tab-selected-statistics-1@1x.png | tab control (page control, top tabs) | tab at x=40 clicked (tab 1) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-10@1x.png | tab control (page control, top tabs) | tab at x=780 clicked (tab 10) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-11@1x.png | tab control (page control, top tabs) | tab at x=870 clicked (tab 11) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-2@1x.png | tab control (page control, top tabs) | tab at x=100 clicked (tab 2) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-3@1x.png | tab control (page control, top tabs) | tab at x=180 clicked (tab 3) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-4@1x.png | tab control (page control, top tabs) | tab at x=250 clicked (tab 4) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-5@1x.png | tab control (page control, top tabs) | tab at x=340 clicked (tab 5) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-6@1x.png | tab control (page control, top tabs) | tab at x=435 clicked (tab 6) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-7@1x.png | tab control (page control, top tabs) | tab at x=525 clicked (tab 7) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-8@1x.png | tab control (page control, top tabs) | tab at x=625 clicked (tab 8) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tab-selected-statistics-9@1x.png | tab control (page control, top tabs) | tab at x=700 clicked (tab 9) | WM_LBUTTONDOWN+UP on the tab strip | TStatisticsForm | 957x509 | 11 tabs: Colors, Rarity, Card Type, Editions, Mana Analyser, Mana Product, Power Analyser, Probability, Mana Slots, Start Hand, Advanced |
| tree-list-checkbox-pressed-filter@1x.png | tree list check box | pressed node check box | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter > Blocks tree, Core Sets) | TFilterForm | 708x493 |  |
| tree-list-expander-pressed-filter@1x.png | tree list expander (+) | pressed expand button | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Filter > Blocks tree) | TFilterForm | 708x493 |  |
| tree-list-focused-conditional-formatting@1x.png | tree list | clicked in the (empty?) rule list | click | TfrmDataControllerConditionalFormattingRulesManagerDialog | 700x421 |  |
| tree-list-row-selected-focused-filter@1x.png | tree list | selected row (Core Sets), tree focused | click on a row of the Blocks tree | TFilterForm | 708x493 |  |
| tree-list-row-selected-unfocused-filter@1x.png | tree list | selected row, tree not focused | WM_KILLFOCUS to the tree site | TFilterForm | 708x493 |  |
| vertical-grid-category-pressed-deck-properties-general@1x.png | vertical grid category header | pressed (collapse button) | WM_LBUTTONDOWN on the control, no WM_LBUTTONUP, then WM_CANCELMODE (Deck Properties) | TDeckPropertiesForm | 364x552 |  |
| vertical-grid-editor-combo-deck-properties-archetype@1x.png | vertical grid (combo editor) | in-place combo editor active on Archetype | click on the value cell | TDeckPropertiesForm | 364x552 |  |
| vertical-grid-editor-open-deck-properties-description@1x.png | vertical grid | in-place text editor open on Description | click on the value cell; nothing typed | TDeckPropertiesForm | 364x552 |  |
| vertical-grid-row-focused-deck-properties-name@1x.png | vertical grid | focused row Name with editor | click on the value cell of Name; nothing typed | TDeckPropertiesForm | 364x552 |  |
| vertical-grid-row-selected-deck-properties-author@1x.png | vertical grid | focused row Author (label click) | click on the row caption | TDeckPropertiesForm | 364x552 |  |

## Not reached in this run

| Control | State | Why |
|---|---|---|
| menu Reports | open | popup did not appear |
| toolbar button | hot / pressed / checked | dxBar toolbars ignore posted mouse messages (a posted down+up on the Search-toolbar binoculars neither pressed nor opened the dialog); hit-test uses the real pointer |
| any control | hover (mouse over) | DevExpress reads the real pointer with GetCursorPos / its own mouse hook; a posted WM_MOUSEMOVE changes nothing visible (tried toolbar, menu popup, cxButton, grid header and rows, with and without app activation, with CM_MOUSEENTER and WM_MOUSEHOVER) |
| combo box (Search for Card, Card combo (history; may be empty)) | open drop-down list | no popup window appeared after a posted click on the drop button |
| vertical grid combo | open list | no popup after clicking the editor drop button |
| date edit | any state | no v3 dialog reached with posted messages contains a date edit: Deck Registration Sheets and Deck Availability would print/generate documents, so they were not opened |

