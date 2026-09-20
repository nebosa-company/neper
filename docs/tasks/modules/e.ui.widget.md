# e.ui.widget — 35 of 35 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ui/widget.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `e.gfx.scene`, `e.ui.input`, `e.ui.window` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ui/widget.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.data.slot_map` | partial | `lib/e/data/slot_map.e` | 2 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.gfx.paint` | partial | `lib/e/gfx/paint.e` | 2 |
| `e.gfx.scene` | planned | missing | 6 |
| `e.text.layout` | partial | `lib/e/text/layout.e` | 2 |
| `e.ui.input` | planned | missing | 6 |
| `e.ui.layout` | partial | `lib/e/ui/layout.e` | 2 |
| `e.ui.style` | partial | `lib/e/ui/style.e` | 2 |
| `e.ui.window` | planned | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Key = u64
type ElementId = struct { slot: u32, generation: u32 }
type StateId = struct { slot: u32, generation: u32 }
type Action = struct { ctx: *void, invoke: fn(*void, input.Event) -> err }
type Text = struct { value: str, style: layout.Style, color: paint.Color }
type Button = struct { action: Action, enabled: bool }
type Image = struct { texture: scene.TextureId, fit: Fit }
type Scroll = struct { axis: ui_layout.Axis, offset: f32 }
type Custom = struct { ctx: *void, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, paint: fn(*void, *scene.Builder, geometry.Rect) -> err }
type Kind = union enum u8 { Box, Flex: ui_layout.Flex, Grid: ui_layout.Grid, Stack, Text: Text, Button: Button, Image: Image, Scroll: Scroll, Custom: Custom }
type Node = struct { key: Key, kind: Kind, style: style.Style, children: []const Node }
type Fit = enum u8 { Fill, Contain, Cover, None }
type BuildContext = struct { runtime: *Runtime, element: ElementId, frame: u64 }
type Runtime = struct { state: *void }
type Limits = struct { max_elements: usize, max_states: usize, state_bytes: usize, state_classes: u16, max_depth: u16, max_commands: usize }
error DuplicateKey
error InvalidTree
error TooDeep
error TooLarge
error StateType

fn runtime(a: *mem.Arena, renderer: *scene.Renderer, limits: Limits) -> (Runtime, err)
fn box(key: Key, value_style: style.Style, children: []const Node) -> Node
fn flex(key: Key, spec: ui_layout.Flex, value_style: style.Style, children: []const Node) -> Node
fn grid(key: Key, spec: ui_layout.Grid, value_style: style.Style, children: []const Node) -> Node
fn stack(key: Key, value_style: style.Style, children: []const Node) -> Node
fn text(key: Key, value: Text, value_style: style.Style) -> Node
fn button(key: Key, value: Button, value_style: style.Style, children: []const Node) -> Node
fn image(key: Key, value: Image, value_style: style.Style) -> Node
fn scroll(key: Key, value: Scroll, value_style: style.Style, children: []const Node) -> Node
fn state[T: type](ctx: *BuildContext, key: Key, initial: T) -> (*T, StateId, err)
fn invalidate(widget_runtime: *Runtime, element: ElementId)
fn reconcile(widget_runtime: *Runtime, frame_arena: *mem.Arena, root: Node, constraints: ui_layout.Constraints) -> (scene.SceneId, err)
fn dispatch(widget_runtime: *Runtime, event: input.Event) -> err
fn focus(widget_runtime: *Runtime, element: ElementId) -> err
fn close(widget_runtime: *Runtime) -> err
```

`Node` is the declarative syntax: ordinary literals and the allocation-free convenience
constructors create
an immutable tree in a resettable frame arena. Reconciliation matches siblings by
nonzero key and kind, otherwise by position and kind. Persistent elements and typed
state occupy bounded generation-checked slots owned by `Runtime`; widgets themselves
are never retained. Removed state is destroyed logically at the reconciliation
boundary and its size/alignment cell enters a bounded runtime free list. A reused
`Action.ctx` must outlive the element that retains it; passing frame-arena context is
`InvalidTree` in debug validation and undefined in release.

## Missing declarations

- [ ] `Key`
- [ ] `ElementId`
- [ ] `StateId`
- [ ] `Action`
- [ ] `Text`
- [ ] `Button`
- [ ] `Image`
- [ ] `Scroll`
- [ ] `Custom`
- [ ] `Kind`
- [ ] `Node`
- [ ] `Fit`
- [ ] `BuildContext`
- [ ] `Runtime`
- [ ] `Limits`
- [ ] `DuplicateKey`
- [ ] `InvalidTree`
- [ ] `TooDeep`
- [ ] `TooLarge`
- [ ] `StateType`
- [ ] `runtime`
- [ ] `box`
- [ ] `flex`
- [ ] `grid`
- [ ] `stack`
- [ ] `text`
- [ ] `button`
- [ ] `image`
- [ ] `scroll`
- [ ] `state`
- [ ] `invalidate`
- [ ] `reconcile`
- [ ] `dispatch`
- [ ] `focus`
- [ ] `close`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ui/widget.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ui_widget/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 35.

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
