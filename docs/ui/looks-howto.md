# Adding a control to the looks

Plan: `docs/ui/looks-plan.md`. Decision: D5108. Progress page: `docs/ui/looks-progress.html`
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
   build/windows/neper-self.exe emit-executable examples/looks/<control>.e D:/repos/neper x64 windows <out>.exe --arena 512m
   <out>.exe
   ```

   It prints `executable written`; the run writes `docs/ui/looks/{neper,windows}/<control>.png` and
   `<control>@1.5x.png`, and `docs/ui/looks/windows/<control>-vs-ref[@1.5x].png` (reference left,
   ours right) when `docs/ui/looks/ref/windows/<control>[@1.5x].png` exists. `check-file` gives
   better diagnostics than `emit-executable` when it says only `E-TYPE-9999`: bisect the file.
5. **Compare.** View the PNGs with the Read tool. Crop the same control from the v3 capture and
   from ours (`@1.5x`), paste them one above the other at 3x with PIL, and compare size, border,
   face, label position and ink width. Iterate until they match; then check the 1.0 render too.
6. **Record.** Do NOT edit `status.json` (parallel workers would conflict). Write your own overlay `docs/ui/looks/status.d/<group>.json` = `{"<control id>": {"looks": {"windows": {...}}}}` (a look entry replaces the base one wholesale; copy the base entry first and change it). In the entry set `status`
   (`planned`, `started`, `review` = renders but not within tolerance or unmeasured states,
   `ready` = matches the reference at 100 % and 150 %), `screenshot` (relative to
   `docs/ui/looks/`), `notes` and `gaps` (every guessed colour, every state without a capture,
   every part not drawn). Then `python scripts/render_looks.py`. A control with no Neper
   equivalent gets `"neper": null` and a `gap`.
7. **Commit only your paths:** the control and style edits, the app, the PNGs, `status.json`,
   `looks-progress.html`. If the queue item L165 changes, follow AGENTS.md (the render scripts
   rewrite unrelated files: `git checkout -- docs/tasks` and keep only what you caused).

## Traps

- A local may not be named `target`, `text`, `width`, `str` (or any module-scope function or `use`
  qualifier). `use e.str` clashes with the type `str`: `use e.str as strs`.
- `const` takes integers only: no `f32` or `str` constants; use a one-line `fn`.
- `ret f(...)` of a tuple-returning call is refused (`E-TYPE-0003`): bind, then `ret (a, b)`.
- `widget.Key` is `u64`: write `u64(i)`, not `widget.Key(i)`.
- A button's root node needs an explicit size; labels need a registered font (the rig registers
  Segoe UI as 7 and Tahoma as 8; Segoe leads the theme's fallback chain).
- `testing.pump` renders at the harness scale since D5108; before that a scale of 1.5 drew at 1.
- Windows palette is Light only; Dark and HighContrast keep Neper colours with Windows metrics.

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
- `examples/looks/scale_tiles.e` (`scale_button`, `scale_marks`, `scale_edits`, one per process) puts the controls
  on fractional positions: review its `@1.5x` PNGs by eye after touching a tile painter.
