# e.ui.winedit — 2 of 2 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ui/winedit.e` |
| plan row | layer 6, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ui/winedit.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.gfx.paint` | partial | `lib/e/gfx/paint.e` | 2 |
| `e.gfx.scene` | partial | `lib/e/gfx/scene.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.ui.layout` | partial | `lib/e/ui/layout.e` | 2 |
| `e.ui.style` | partial | `lib/e/ui/style.e` | 2 |
| `e.ui.widget` | partial | `lib/e/ui/widget.e` | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Chrome = struct { kind: u32, state: u32, width: f32, height: f32, window_y: f32, dim: u32 }
fn chrome(a: *mem.Arena, kind: u32, state: u32, width: f32, height: f32, window_y: f32, dim: u32) -> (widget.Node, err)
```

The Windows look's edit chrome: `chrome` is the frame, ellipsis button or spin buttons of v3's TcxMaskEdit, TcxTextEdit, TcxSpinEdit and TcxButtonEdit as one custom node laid over the edit's white face, from baked pixel tiles (`scripts/looks_winedit_gen.py`); `window_y` is the control's y in the dialog, which the top and foot rows drift with. Baked at 96 DPI, so 1.5x resamples. Read by `e.ui.control` under the Windows look.

## Missing declarations

- [ ] `Chrome`
- [ ] `chrome`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/ui/accessibility.e`†
- `lib/e/ui/adwicon_l2.e`
- `lib/e/ui/animation.e`
- `lib/e/ui/app.e`†
- `lib/e/ui/asset.e`
- `lib/e/ui/audit.e`
- `lib/e/ui/code_editor.e`‡
- `lib/e/ui/collection.e`‡

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ui/winedit.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ui_winedit/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 2.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
