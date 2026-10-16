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

Eight looks (`looks.Look`), folders `docs/ui/looks/{neper,neper-dark,windows,windows-dark,cupertino,cupertino-dark,material,material-dark}/<sheet>[@1.5x].png`.
`looks.run_all` renders Neper, Windows and Windows dark (and Neper dark where the app's harness version does) at 1.0
and 1.5; `looks.run_cupertino` and `looks.run_material` render the Light and Dark of the platform looks. Dark has no live
reference (v3 has no dark mode, nor do Apple and Android): its evidence is the platform's published dark palette, so its
status is at most `started`, never `matched`.

`docs/ui/looks-progress.html` shows four flavor columns (Neper, Windows, macOS / iOS, Android), each cell holding the Light
and the Dark thumbnail side by side with their own status chip, notes and gaps; the eight summary boxes are one per look
(`status.json` `looks`: `neper`, `neper_dark`, `windows`, `windows_dark`, `cupertino`, `cupertino_dark`, `material`,
`material_dark`). Overlay look ids are those ids; screenshot paths use the hyphenated folders (`windows-dark/button.png`).

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

## Scales (1.25, 1.5, 2.0)

- A baked tile (check and radio marks, button ring, edit chrome, focus dots, glyph pixels, the menu's dither) is
  painted with `e.ui.winpx.fill`, never a bare 1 px `FillRect`: it moves each edge to a whole device pixel, so the
  tile is a nearest-neighbour scaled block with no seams. At scale 1 it is the plain rectangle, so the 100 %
  PNGs do not change. The scale comes from `scene.builder_scale(b)`, set from the runtime's snap, which the
  application sets from the window (`widget.set_snap`) and `looks.open` sets for a rig of scale other than 1.
- `NEPER_LOOKS_SCALE=1.25|1.5|2` makes a sheet app render that one scale, and `NEPER_LOOKS_OUT=<dir>` writes
  under `<dir>` instead of `docs/ui/looks` (scale files are `@1.25x`, `@1.5x`, `@2x`); `NEPER_LOOKS_NOTEXT=1`
  leaves text out. `python scripts/looks_scale_check.py` renders the Windows sheets at 1.0 and 2.0 this way and fails
  when a run of pixels of the 1.0 render is not twice as long in the 2.0 render.
- `examples/looks/scale_tiles.e` (`scale_button`, `scale_marks`, `scale_edits`) puts the controls
  on fractional positions: review its `@1.5x` PNGs by eye after touching a tile painter.
