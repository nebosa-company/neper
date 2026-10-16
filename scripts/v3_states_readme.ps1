# Writes states\README.md and states\manifest.csv from $script:Rows / $script:Notes (dot-sourced by grab_v3_states.ps1)
function Write-Readme {
  # merge with what earlier partial runs (-Only ...) already recorded, so the table always covers the whole folder
  $mf=Join-Path $script:Out 'manifest.csv'; $nf=Join-Path $script:Out 'notes.csv'
  $all=@($script:Rows); if(Test-Path $mf){ $have=@($script:Rows|%{$_.File}); $all += @(Import-Csv $mf | ?{ $_.File -notin $have -and (Test-Path (Join-Path $script:Out $_.File)) }) }
  $rows = $all | Sort-Object File -Unique
  $notes=@($script:Notes); if(Test-Path $nf){ $hv=@($script:Notes|%{ "$($_.Control)|$($_.State)" }); $notes += @(Import-Csv $nf | ?{ "$($_.Control)|$($_.State)" -notin $hv }) }
  $script:Notes = New-Object System.Collections.ArrayList; foreach($n in $notes){ if(-not ($script:Notes | ?{ $_.Control -eq $n.Control -and $_.State -eq $n.State })){ [void]$script:Notes.Add($n) } }
  $script:Notes | Export-Csv $nf -NoTypeInformation -Encoding UTF8
  $rows | Export-Csv (Join-Path $script:Out 'manifest.csv') -NoTypeInformation -Encoding UTF8
  $sb = New-Object System.Text.StringBuilder
  $head = @'
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
'@
  [void]$sb.AppendLine($head)
  foreach($r in $rows){ [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $r.File,$r.Control,$r.State,($r.How -replace '\|','/'),$r.Class,$r.Size,($r.Notes -replace '\|','/'))) }
  [void]$sb.AppendLine("`n## Not reached in this run`n`n| Control | State | Why |`n|---|---|---|")
  $hnf=Join-Path $script:Out 'hover-notes.csv'
  $allNotes=@($script:Notes); if(Test-Path $hnf){ $allNotes += @(Import-Csv $hnf) }
  foreach($n in $allNotes){ [void]$sb.AppendLine("| $($n.Control) | $($n.State) | $($n.Why -replace '\|','/') |") }
  Set-Content (Join-Path $script:Out 'README.md') $sb.ToString() -Encoding UTF8
}
