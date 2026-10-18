# Adding a control to the looks

Plan: `docs/ui/looks-plan.md`. Decisions: D5108 to D5113. Audit: `docs/ui/looks/audit.md`. Progress page: `docs/ui/looks-progress.html`
(generated, never hand-edited). The pilot to copy is `examples/looks/button.e`.

## What exists

- `style.Profile.Windows` and `style.windows(palette)`: the MTG Studio v3 token set (Light palette
  only). Control faces read `SurfaceContainerLowest` (#FDFDFD), borders `Border` (#D2D2D2), accent
  `Primary`, dialog face `Background` (#F0F0F0). Metrics: control height 22, radius 4, 11.2 px body.
- `style.windows_resolve(tokens, variant, state)`: the Windows button's colours and box. A new
  control gets its own `windows_*` resolver next to it, or a few lines in its own function.
- `control.button` shows the branch: `if t.tokens.profile == .Windows { ... }`. Branch only where the
  shape differs; a colour or metric change belongs in the tokens.
- `e.ui.looks` (`lib/e/ui/looks.e`): the offscreen harness. `looks.run_all(a, &sheet)` renders the
  sheet under Neper and Windows at 1.0 and 1.5 and writes the PNGs.
- `ControlVariant.Default` is the Enter button (accent border under Windows, Filled elsewhere).

## Steps for one control

1. **Measure.** Open the v3 capture (`docs/grid-parity/tcxgrid/*-v3.png` are at 150 % DPI; logical
   px = physical / 1.5) or `docs/ui/looks/ref/windows/<control>[@1.5x].png`. Read sizes and colours
   with PIL (`.venv-docs-pdf/Scripts/python.exe`): scan a row and a column through the control and
   take the darkest border pixel, the face colour and the box extents. Look at a 3x crop with the
   Read tool. Write what you measured, and what you guessed, in the gaps list (step 6).
2. **Implement.** Add the Windows branch in the control (`lib/e/ui/control.e`; run
   `git diff --stat lib/e/ui/control.e` first, it is shared). Tokens go in `style.windows`.
3. **Write the app** `examples/looks/<control>.e`, copied from `button.e`:
   - `build(ctx, a, t, cells) -> (usize, err)` fills `cells[i] = looks.Cell { caption, node, drive }`
     for every state: rest, disabled and control-specific ones (checked, indeterminate, default,
     open, ...) are built with the control's own options; hover, pressed and keyboard focus are
     `drive: .Hover`, `.Press`, `.Focus` (the harness moves the pointer and keys, then rebuilds,
     because a control reads its interaction state when it is built).
   - Keys: unique, non-zero, the same on every call of `build` (it runs once per driven cell).
   - `main` makes `looks.Sheet { name, cells, columns, cell_w, cell_h, ctx, build }` and calls
     `looks.run_all(a, &sheet)`. Cell boxes centre the control; size them 10 px larger than it.
4. **Compile and run** from the repository root (the output paths are relative):

   ```
   build/windows/neper-self.exe emit-executable examples/looks/<control>.e D:/repos/neper x64 windows <out>.exe --arena 4g
   <out>.exe
   ```

   It prints `executable written`; the run writes `docs/ui/looks/{neper,windows}/<control>.png` and
   `<control>@1.5x.png`, and `docs/ui/looks/windows/<control>-vs-ref[@1.5x].png` (reference left,
   ours right) when `docs/ui/looks/ref/windows/<control>[@1.5x].png` exists. `check-file` gives
   better diagnostics than `emit-executable` when it says only `E-TYPE-9999`: bisect the file.
5. **Compare.** View the PNGs with the Read tool. Crop the same control from the v3 capture and
   from ours (`@1.5x`), paste them one above the other at 3x with PIL, and compare size, border,
   face, label position and ink width. Iterate until they match; then check the 1.0 render too.
6. **Record.** Do NOT edit `status.json` (parallel workers would conflict). Write your own overlay
   `docs/ui/looks/status.d/<group>.json` = `{"<control id>": {"looks": {"windows": {...}}}}`. Overlays apply in
   file-name order and a look entry replaces the earlier one wholesale (copy it first, change it); later
   names win, so `round9-audit` and `zzz-audit` override the rounds before them. Set `status`:
   `planned` nothing built; `started` renders, or v3 has nothing to compare; `review` renders but is outside
   tolerance, or captured states have no cell; `matched` every captured state has a cell within tolerance
   (2 levels per channel on structural pixels, text and icon artwork masked) at 100 %; `ready` matched at
   100 % and 150 %. Your status is a claim: the audit recomputes it independently and downgrades what fails
   (audit 2: 0 matched, 25 review, 5 started). Also set `screenshot` (relative to `docs/ui/looks/`), `notes`
   and `gaps` (every guessed colour, state without a capture, part not drawn). Then
   `python scripts/render_looks.py`. A control with no Neper equivalent gets `"neper": null` and a gap.
7. **Commit only your paths:** the control and style edits, the app, the PNGs, your overlay,
   `looks-progress.html`. If the queue item L165 changes, follow AGENTS.md (the render scripts
   rewrite unrelated files: `git checkout -- docs/tasks` and keep only what you caused).

## Rendering everything

`scripts/render_looks_all.sh [name ...]` (Git Bash, any directory) compiles each `examples/looks/*.e` with
`--arena 4g`, runs it, then runs `scripts/render_looks.py`. It still runs `popup_menu` and `scale_tiles` once per sheet
name (their sheets are big and the run is shorter that way), but nothing requires it any more. Run
sheets one at a time (no two processes sharing the output folder); render only the names you changed, then
check `git status` for PNGs you did not mean to change.

## Capturing the v3 reference

`scripts/grab_v3_windows.ps1` (main window), `grab_v3_dialogs.ps1` (menus, dialogs) and
`grab_v3_states.ps1` (pressed, focused, open lists; `-Only menus|main|options|dialogs`) launch a COPY of
mtgstudio.exe from `D:\Temp\claude3run` and grab it with PrintWindow. Safety rules: posted or sent window
messages only (no SendInput, mouse_event, SetCursorPos, no VCL `CM_` messages); a press is a button down
with no up, cancelled by WM_CANCELMODE; never save, apply, delete, import, print or go online; activate the
window first or drop-downs close at once; do not cache hwnds across Options pages; keep the copy beside the
maintainer's own v3 (patched mutex). Hover cannot be captured (v3 reads the real pointer). Details and traps:
`docs/ui/looks/ref/windows/states/README.md` and `dialogs/README.md`. `mtgstudio.db3` in the copy is a
throwaway; never point a script at the repo or installed exe.

## Harness limits

- A process runs any number of sheets: each rig (one per sheet x look x scale) closes its CPU gpu device when
  its render is done (`gpu.close` now frees the device's registry slot; a process has 16 slots) and gives its
  arena memory back (`looks.rig_scope`: the rigs live in one 768 MB scratch arena, zeroed before each rig; the
  font files and the 32 MB frame storage are read once and shared). An app's own state in the arena its `main`
  got is untouched. The old limits (about 12 rigs, `e.gpu.TooLarge`, `e.ui.widget.TooLarge`) are gone.
- Keep a sheet's rig under the scratch size (768 MB); `popup_menu`, `data_grid` with all sheets, and the
  `material_*` / `cup_*` apps are far below it.
- Compile with `--arena 4g`; 512m runs out on the big sheets.
- Baked tiles (`winbutton`, `winedit`, `winmark`) are 96 DPI: judge the 1.5x sheets separately (D5112).

## Traps

- A local may not be named `target`, `text`, `width`, `str` (or any module-scope function or `use`
  qualifier). `use e.str` clashes with the type `str`: `use e.str as strs`.
- `const` takes integers only: no `f32` or `str` constants; use a one-line `fn`.
- `ret f(...)` of a tuple-returning call is refused (`E-TYPE-0003`): bind, then `ret (a, b)`.
- `widget.Key` is `u64`: write `u64(i)`, not `widget.Key(i)`.
- A button's root node needs an explicit size; labels need a registered font (the rig registers
  Segoe UI as 7 and Tahoma as 8; Segoe leads the theme's fallback chain).
- `testing.pump` renders at the harness scale since D5108; before that a scale of 1.5 drew at 1.
- `style.windows(.Dark)` is the Windows dark look (`looks.Look.WindowsDark`); HighContrast keeps Neper colours with Windows metrics.

## Looks, Light and Dark

Ten looks (`looks.Look`), folders `docs/ui/looks/{neper,neper-dark,windows,windows-dark,linux,linux-dark,cupertino,cupertino-dark,material,material-dark}/<sheet>[@1.5x].png`.
`looks.run_all` renders Neper, Windows and Windows dark (and Neper dark where the app's harness version does) at 1.0
and 1.5; `looks.run_cupertino` and `looks.run_material` render the Light and Dark of the platform looks, `looks.run_linux` the Linux pair. Windows, Apple and
Android Dark have no live reference (v3 has no dark mode, nor are Apple and Android captured): their evidence is the platform's
published dark palette, so their status is at most `started`, never `matched`. Linux Dark has the real library's dark crops.

`docs/ui/looks-progress.html` shows five flavor columns in priority order (Windows, Linux, Neper, macOS / iOS, Android), each
cell holding the Light and the Dark thumbnail side by side with their own status chip, notes and gaps; the ten summary boxes are
one per look (`status.json` `looks`: `windows`, `windows_dark`, `linux`, `linux_dark`, `neper`, `neper_dark`, `cupertino`,
`cupertino_dark`, `material`, `material_dark`). Overlay look ids are those ids; screenshot paths use the hyphenated folders
(`linux-dark/button.png`).

- Auto entry: a control with no entry for a look gets `started` with the note "Rendered from the platform palette; not
  compared with a real screen." when `docs/ui/looks/<look dir>/<name>.png` exists, `<name>` being the control id, then its
  `app` sheet name, then its `sheet`. An overlay entry always wins, so write one only for more than that (notes, gaps, a
  different status or screenshot).
- Platform idiom controls: an overlay id that is not a `status.json` control becomes an extra row (switch, slider, stepper,
  segmented control, chip, fab, snackbar, app bar, date picker, navigation bar, ...) only when its entry has `"name"`:
  `{"switch": {"name": "Switch", "extra": true, "neper": "control.switch", "looks": {...}}}`. They are listed under
  "Platform idiom controls" below the 30 Delphi-equivalent rows with the Delphi column "(none)", and count in the summaries.
- The page inlines 150 px high base64 thumbnails (cached in the temp folder `neper-looks-thumbs` by mtime), so it opens
  from `file://` with no network and in viewers that do not resolve relative images.

## Cupertino sheets

`style.cupertino(palette)` (profile `CupertinoLike`) is `looks.Look.Cupertino` / `CupertinoDark`. The sheets are
`examples/looks/cup_<control>.e`; they call `looks.run_cupertino`, which writes `docs/ui/looks/cupertino[-dark]/<name>[@1.5x].png`.
`scripts/cup_run.sh [name[:arg] ...]` compiles and runs them one at a time (a modal overlay renders one per process:
`popup:open`, `menu:hover`, `alert:open`). Controls branch on `t.tokens.profile == .CupertinoLike`; the drawing helpers
(`cup_*`, `cupertino_*`) are appended at the end of `lib/e/ui/control.e`, a few in `overlay.e` and `navigation.e`.

## Linux sheets

`style.adwaita(palette)` (profile `Linux`) is `looks.Look.Linux` / `LinuxDark`. A sheet is `examples/looks/linux_<control>.e` that
calls `looks.run_linux` and names its sheet like the control (`button`, as the Cupertino and Android ones do), so the output is
`docs/ui/looks/linux[-dark]/<control>[@1.5x].png` and the auto entry finds it. Run it like any other, from the worktree root
(`neper-self.exe emit-executable examples/looks/linux_button.e <root> x64 windows <out>.exe --arena 4g`, then the exe).

- Controls branch on `t.tokens.profile == .Linux` (`control.button` calls `linux_button`; its helpers sit at the end of
  `control.e`). The button's colours are `style.adwaita_resolve`, mirroring `windows_resolve`. The runtime's focus ring is off
  (`metrics.focus_ring` 0): GTK draws the ring inside the control's edge (2 px, offset -2), so a control draws it as its border.
- The reference crops are composed into a sheet-shaped picture by `python -I scripts/linux/compose_ref.py [name]` (`SHEETS`
  there holds the cell order and geometry of each sheet; keep it in step with the app) into
  `docs/ui/looks/ref/linux/composite/{light,dark}/<name>.png`. `run_linux` finds it and writes
  `docs/ui/looks/linux[-dark]/<name>-vs-ref.png` (reference left, ours right) at 100 %; the library has no 1.5x crops.
  `python -I scripts/linux/compose_ref.py --diff <name>` prints, per cell, the pixels that are flat in the reference and outside
  its label or icon box (grown by 3 px; the 3 px around the control's box count, so a box one pixel too big shows) with the largest
  difference and how many are off by more than 2 levels, then the same over every pixel outside the label box (edges and rings
  included). The first number is the one for `matched`.
- Fonts: the Cantarell files in `docs/ui/looks/ref/linux/fonts` (OFL, `LICENSE.txt` beside them) are read by `run_linux` only, as
  font ids 13 (regular) and 14 (bold), ahead of the Windows faces. A control asks for a weight through its role (`Label` is bold
  here, the body regular): `control.text_style_faced_plain` honours the role's weight for Linux as it does for Android.
- Libadwaita specifics that matter: button labels are bold; a text button has 17 px sides, an icon button 9, an icon with a caption
  10; GTK lays a label out in whole pixels (Pango hinting), which `control.linux_label_width` approximates; flat buttons have no
  face until hovered; a disabled control is the whole control at 50 % opacity; the focus ring is the accent at 50 %.
- Corners use `widget.set_arc_corners` for Linux as for Android: true circular arcs make the 6 px corners and the 34 px circle
  match the library's antialiasing to 2 levels.

## Scales (1.25, 1.5, 2.0)

- A baked tile (check and radio marks, button ring, edit chrome, focus dots, glyph pixels, the menu's dither) is
  painted with `e.ui.winpx.fill`, never a bare 1 px `FillRect`: it moves each edge to a whole device pixel, so the
  tile is a nearest-neighbour scaled block with no seams. At scale 1 it is the plain rectangle, so the 100 %
  PNGs do not change. The scale comes from `scene.builder_scale(b)`, set from the runtime's snap, which the
  application sets from the window (`widget.set_snap`) and `looks.open` sets for a rig of scale other than 1.
- `NEPER_LOOKS_SCALE=1.25|1.5|2` makes a sheet app render that one scale, and `NEPER_LOOKS_OUT=<dir>` writes
  under `<dir>` instead of `docs/ui/looks` (scale files are `@1.25x`, `@1.5x`, `@2x`); `NEPER_LOOKS_NOTEXT=1`
  leaves text out; `NEPER_LOOKS_ONLY=windows` renders the Windows look alone; `NEPER_LOOKS_EXACT=1` turns the whole-pixel
  snapping on at scale 1 as well (the scale check's reference).
- Whole-pixel mode (round 9): with the Windows look (`scene.set_pixel_exact`, set by `looks.set_look`; an application sets
  it the same way when its theme is the Windows one) `widget.place` moves every plain box, border and shape of a node to whole
  device pixels at a scale other than 1 (`widget.snapped`), so a layout line (a menu rule, a frame, a selection bar) is never
  smeared over two device pixels; baked tiles put their origin there too (`winpx.origin`, the button ring and its focus dots).
  At scale 1 nothing moves, so the 100 % PNGs are unchanged.
- `python scripts/looks_scale_check.py [--scale S] [--report] [sheet ...]` renders every Windows sheet (the sheet to
  app and arguments table is `scripts/looks_scale_sheets.json`, rebuilt by `--discover [app ...]` when a sheet app is added)
  at 1.0 and at 1.25, 1.5 and 2.0 and fails when too few runs of pixels of the 1.0 render are a clean scaling in the other
  scales (see the header of the script); `--report` writes `docs/ui/looks/scale-report.md`. A full run compiles all sheet apps
  (`NEPER_SCALE_EXES=<dir>` keeps the built apps between runs) and takes about 45 minutes; give sheet names to run a few.
- `examples/looks/scale_tiles.e` (`scale_button`, `scale_marks`, `scale_edits`) puts the controls
  on fractional positions: review its `@1.5x` PNGs by eye after touching a tile painter.

## Native Windows 11 references (round 10)

`docs/ui/looks/ref/windows-native/{light,dark}/` holds real uxtheme captures of the Win32 controls (README there). The Windows Dark look is matched
to the dark ones; the light ones fill the states v3 never showed. Pixel tables read from them are baked by `python -I scripts/gen_winnative.py`
into `lib/e/ui/winnative.e` (do not edit): the dark button ring corners (`nring_*`, painted by `winbutton.ring_paint_native`), the check box and
radio marks (`nmark`, 13 x 13 ARGB, drawn by `e.ui.wintile`), the spin edit's up-down (`nspin`) and the combo chevron (`nchev`). The edit frame and the combos
are painted from measured lines (`winedit.native_chrome`, `winedit.native_combo`). A control picks them when `t.tokens.palette == .Dark`; light uses
the native tiles only for disabled and indeterminate marks. To compare, crop the native capture and the same state of the sheet, cut the same plain rows
the painter cuts (`nspin_row`) and diff outside the text.

`python -I scripts/looks_w1.py` (round 15) diffs every dark edit, spin, combo, open list, multi-line and picture-less image combo capture with the strict rule (more than 2 levels off; only pixels within 2 px of a glyph are set apart, never a selection fill, caret or scroll column) and prints per-capture counts: `native_dark` (cells in `native_dark.e`; the multi-line states are cells 55 to 59, the scroll bar cell 51), `native_dark_open<n>` (variants 4 and 5 are the image combo) and `native_dark_icb`. A native edit sets its glyphs one row above the line box that its selection and caret fill (`widget.place_edit`); the caret blinks, so a capture can lack it (`control.set_native_caret_off`).

## Text anti-aliasing: ClearType (round 19)

`scene.set_text_aa(.Grayscale | .ClearType)` picks how text is rasterised; `set_look` sets it, ClearType for the Windows profile and greyscale for every other, and `NEPER_TEXT_AA=grayscale` (or `cleartype`) overrides it at run time, which is the way back and how a sheet's grey twin is made. ClearType means the glyphs are hinted by the TrueType bytecode interpreter (`e.text.tthint`, run through `e.text.ttglyph`) with Windows' ClearType rules and rasterised by `e.gfx.cleartype` at GDI's five by six sampling, with GDI's gamma blend onto opaque pixels. The fonts (Segoe UI, Tahoma) are read from C:\Windows\Fonts at run time and never committed; a font without instructions, a non-solid brush, a non-uniform or rotated transform, a fractional pixel size or a translucent canvas falls back to the greyscale path for that text, so a sheet never loses text.

What is exact and what is not: points of Segoe UI 12 px hinted to GDI's are exact for about 55 % (Tahoma 11 px far fewer) and the rest differ by one to three 64ths; across the 77 dark captures the strict count (more than 2 levels, `LOOKS_GLYPHS=1 python -I scripts/looks_dark_native.py`) fell from 30800 to about 11500. Pen positions are GDI's: each glyph advances by its hinted whole-pixel advance, the pen is rounded to a pixel and the baseline is the next whole line (`scene.baseline_px`). Layout constants that were tuned to greyscale rounding may be one pixel off under ClearType (the dark popup menu's label x moved from 31 to 32). `choices_words` keeps Tahoma words at their whole size under ClearType instead of scaling them to the hinted width.

The v3 grabs under `ref/windows` were taken by PrintWindow and are softer than GDI ClearType, so against them ClearType text is about even with greyscale (combo_box_dialog's text region 676 to 669 strict pixels) rather than better; the native captures are the yardstick.
