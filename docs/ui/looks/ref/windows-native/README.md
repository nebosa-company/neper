# Windows 11 native control references (light and dark)

Real captures of the standard Win32 / comctl32 v6 controls on Windows 11 (build 26300), made by `scripts/winnative/gallery.c` with `PrintWindow` (see `scripts/winnative/README.md`). Independent of v3. `<theme>/<control>-<state>@<scale>.png`, 191 captures per theme per scale: light and dark at `@1x` (DPI-unaware, 100 %, like v3) and `@1.5x` (per-monitor-v2 on the 144 dpi primary monitor, native 150 % rendering, not a resample). **No `@2x`**: no 192 dpi display here and the display scale is a system setting.

`manifest.csv`: file, theme, scale, control, state, size, Neper control id, `status.json` id, notes. `controls.json`: per image the rectangles (`class`, `text`, `x`, `y`, `w`, `h`, pixels in that image) of every control, plus the popup/dropdown windows captured with it.

Re-run: `pwsh -File scripts\winnative\run.ps1` (about 6 minutes; the gallery window flashes on screen, no input is used).

## Real vs not

Real: every pixel is drawn by Windows (uxtheme/comctl32/DWM); the only app-chosen things are the dark dialog colour `#202020` with white text (`WM_CTLCOLOR*`), the list/tree view colours in dark (`LVM_SETBKCOLOR`...) and the alternating row colours of `listview-alternating-notify-customdraw` (`NM_CUSTOMDRAW`, not owner draw). Not real: nothing is composited by hand except that popups (drop lists, menus, tooltips, calendar) are `PrintWindow` copies placed at their screen offset on one canvas. Text has ClearType fringes (colour edges).

## Dark mode: what engaged

Dark natively: push/split button, check box, radio, edit/combo (CFD), spin, trackbar, scroll bars, list view and header, tree view, popup menus (+ submenus), tooltips (and balloon), window and plain dialog captions, toolbar (partly: text is dim, hot/checked looks stay light).

**Native control has no dark theme** (stays light in dark mode, best available kept): tab control, status bar, date-time picker and its drop-down calendar, month calendar (`MCM_SETCOLOR` is ignored under visual styles), the menu bar (white), message box and task dialog (client and caption stay light), disabled list view (light fill), group box frame, progress bar (default green on a light track; `DarkMode_Explorer` paints a white fill). List box and the combo drop list: left unthemed because under any `DarkMode_*` theme their selection is white on white; they therefore have light scroll bars.

## Not captured / weak

- Caption button pressed (min/max/close): `WM_NCLBUTTONDOWN` starts a tracking loop on the real button state and hangs; hot caption buttons are captured but are pixel-identical to rest (DWM tracks the real pointer).
- Hover (hot) looks that are `PIXEL-IDENTICAL to ...-rest` in the manifest (15 per theme: button, check box, radio, check list, edit, combo, date picker, link, tab hot, ...): the fake pointer did not make the control hot. Hover did engage for scroll-bar/spin parts, toolbar (via `TB_SETHOTITEM`), tree, list view rows and header, trackbar. Treat the others as unavailable, not as proof that Windows has no hover look.
- Popup menus: only keyboard selection works (outline cue); the mouse-hover grey fill appears only for the first item of `menubar-open`.
- Edit caret: the caret is a system overlay, not in `PrintWindow` (focus/selected states show selection, caret may be missing).
- Marquee progress is a moment of an animation; task dialog is one configuration (command links, verification, footer).
- Hover for the split button's arrow part and `window-caption-*-hot` need no further caveat beyond the above.

## Mapping to `docs/ui/looks/status.json`

| capture prefix | Neper control | status.json id |
|---|---|---|
| `button-*` | control.button | button |
| `checkbox-*` | control.checkbox | checkbox |
| `radio-*` | control.radio_group | radio, radio_group |
| `groupbox-*` | control.group_box | group_box |
| `edit-*` | control.text_field / control.text_area | text_edit, memo |
| `label-*`, `syslink-*` | control.text | label |
| `spin-*` | control.spin_box | spin_edit |
| `combo-*` | control.combo_box | combo_box, image_combo_box |
| `datepicker-*`, `monthcal-*` | control.picker | date_edit |
| `listbox-*` | control.list_box | list_box |
| `checklist-*` | control.multi_select_list | check_list_box |
| `tab-*` | control.tabs | page_control |
| `progress-*` | control.progress_bar | progress_bar |
| `vscroll-*`, `hscroll-*` | widget.scrollbar | scroll_bar |
| `statusbar-*` | navigation.status_bar | status_bar |
| `toolbar-*` | control.glyph_button | toolbar_button |
| `menubar-*` / `menu-popup-*` | navigation.menu_bar / overlay.menu | menu_bar / popup_menu |
| `tooltip-*` | overlay.tooltip | hint |
| `tree-*` | tree_adapter | tree_list |
| `listview-*` | datagrid (header, rows, sort arrow) | data_grid |
| `window-*`, `dialog-*`, `messagebox-*`, `taskdialog-*` | overlay.dialog | dialog |
| `trackbar-*` | (no Neper control yet) | none |

## Round 15 additions (100 % only, no @1.5x yet)

`edit-multiline-rest`, `-focus`, `-selected`, `-readonly`, `-disabled` (the multi-line edit without a bar: 168 x 90, three lines; the focus capture shows the caret, the selected one the first line selected with the caret at its end) and `edit-multiline-explorer` (the six-line edit with `DarkMode_Explorer` on the control, which themes the scroll bar: a 17 wide #171717 column with a 2 wide #959595 thumb; the frame is then the Explorer theme's white one, so only the inside of the frame is a reference). `edit-multiline-vscroll` (the `DarkMode_CFD` theme) keeps the light unthemed scroll column: it is what a CFD edit gets, and no dark app ships it. Captured with `gallery.exe <out> <theme> 100 edit-multiline` and merged by hand into manifest.csv and controls.json (finish.py rewrites both from one run).
