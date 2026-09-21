# e.ui.control — 12 of 12 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ui/control.e` |
| plan row | layer 6, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ui/control.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.gfx.paint` | partial | `lib/e/gfx/paint.e` | 2 |
| `e.gfx.scene` | partial | `lib/e/gfx/scene.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.text.layout` | partial | `lib/e/text/layout.e` | 2 |
| `e.text.shape` | partial | `lib/e/text/shape.e` | 2 |
| `e.ui.accessibility` | partial | `lib/e/ui/accessibility.e` | 6 |
| `e.ui.layout` | partial | `lib/e/ui/layout.e` | 2 |
| `e.ui.style` | partial | `lib/e/ui/style.e` | 2 |
| `e.ui.widget` | partial | `lib/e/ui/widget.e` | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Theme = struct { tokens: *const style.ThemeTokens, fonts: []const shape.Font, language: str }
type TextOptions = struct { role: style.TextRole, color: style.ColorRole, align: layout.Align, wrap: layout.Wrap, max_lines: u32, ellipsis: str }
type Span = struct { value: str, role: style.TextRole, color: style.ColorRole, link: widget.Submit }
error TooLarge

fn text_options() -> TextOptions
fn text_style(a: *mem.Arena, t: *const Theme, role: style.TextRole) -> (layout.Style, err)
fn text(a: *mem.Arena, key: widget.Key, value: str, t: *const Theme, options: TextOptions) -> (widget.Node, err)
fn selectable_text(a: *mem.Arena, key: widget.Key, buffer: []u8, len: usize, t: *const Theme, options: TextOptions) -> (widget.Node, err)
fn rich_text(a: *mem.Arena, key: widget.Key, spans: []const Span, t: *const Theme) -> (widget.Node, err)
fn icon(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, size: f32, label: str) -> (widget.Node, err)
fn image(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, width: f32, height: f32, fit: widget.Fit, label: str) -> (widget.Node, err)
fn canvas(a: *mem.Arena, key: widget.Key, custom: widget.Custom, label: str) -> (widget.Node, err)
```

The catalogue's controls (D813, widget plan phase 1) are functions that return node
subtrees into the caller's frame arena under a `Theme` -- the tokens, the fonts in
preference order and the language a page is set in. A control is `e.ui.widget`'s
primitives composed with the looks `e.ui.style` resolves, its internals keyed
positionally under the caller's key, and its semantics said through a `Semantics`
node; nothing here is a new primitive. Section 3.1, content (P1-01): `text` in a
text role with the layout's alignment, wrapping, line budget and ellipsis;
`selectable_text` is a read-only editor over the caller's buffer, so selection and
copy are the editor's; `rich_text` lays its spans side by side, a linked span a tap
region with the link role whose `Submit` the caller's spans must keep alive (spans
sit on one line until a span-aware layout wraps them); `icon` and `image` carry a
semantic label, an unlabelled image leaving the tree; `canvas` is the caller's
custom paint with a label. An icon is not tinted until the renderer has an image
brush.

## Missing declarations

- [ ] `Theme`
- [ ] `TextOptions`
- [ ] `Span`
- [ ] `TooLarge`
- [ ] `text_options`
- [ ] `text_style`
- [ ] `text`
- [ ] `selectable_text`
- [ ] `rich_text`
- [ ] `icon`
- [ ] `image`
- [ ] `canvas`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/ui/accessibility.e`
- `lib/e/ui/animation.e`
- `lib/e/ui/app.e`
- `lib/e/ui/asset.e`
- `lib/e/ui/input.e`
- `lib/e/ui/layout.e`
- `lib/e/ui/style.e`
- `lib/e/ui/testing.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ui/control.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ui_control/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 12.

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
