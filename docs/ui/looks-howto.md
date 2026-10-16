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
`--arena 4g`, runs it, then runs `scripts/render_looks.py`. It runs `popup_menu` once per sheet name. Run
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

- About 12 rigs per process: a sheet app with more cells or sheets must be split into several apps.
- Several popup menus in one process fail with `TooLarge` (GPU memory): one menu sheet per process, as
  `render_looks_all.sh` does.
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
- Windows palette is Light only; Dark and HighContrast keep Neper colours with Windows metrics.
