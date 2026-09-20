# e.gfx.scene — 29 of 29 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gfx/scene.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | `gpu-presentation-api` |
| unmet dependencies | `e.gpu` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gfx/scene.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

Blockers named in the plan must be resolved first; a blocked module is not eligible. Search `docs/roadmap.md` and `docs/decisions.md` for each blocker id.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.gpu` | spec | missing | 5 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.gfx.image` | partial | `lib/e/gfx/image.e` | 2 |
| `e.gfx.paint` | partial | `lib/e/gfx/paint.e` | 2 |
| `e.text.layout` | partial | `lib/e/text/layout.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type TextureId = struct { slot: u32, generation: u32 }
type SceneId = struct { slot: u32, generation: u32 }
type Clip = union enum u8 { Rect: geometry.Rect, Rounded: geometry.RRect, Path: geometry.Path }
type Command = union enum u8 { Save, Restore, Transform: geometry.Transform, Clip: Clip, FillRect: FillRect, FillPath: FillPath, StrokePath: StrokePath, Image: DrawImage, Text: DrawText, OpacityLayer: OpacityLayer }
type FillRect = struct { rect: geometry.Rect, brush: paint.Brush }
type FillPath = struct { path: geometry.Path, brush: paint.Brush }
type StrokePath = struct { path: geometry.Path, brush: paint.Brush, stroke: paint.Stroke }
type DrawImage = struct { texture: TextureId, source: geometry.Rect, destination: geometry.Rect, opacity: f32 }
type DrawText = struct { layout: *const layout.Layout, origin: geometry.Point, brush: paint.Brush }
type OpacityLayer = struct { bounds: geometry.Rect, opacity: f32 }
type DisplayList = struct { commands: []const Command }
type Builder = struct { state: *void }
type Renderer = struct { state: *void }
type Target = struct { state: *void }
error Invalid
error TooLarge
error OutOfMemory
error Lost

fn builder(a: *mem.Arena, max_commands: usize) -> (Builder, err)
fn push(b: *Builder, command: Command) -> err
fn finish(b: *Builder) -> DisplayList
fn renderer(a: *mem.Arena, device: *gpu.Device, queue: *gpu.Queue, max_scenes: u32, max_textures: u32) -> (Renderer, err)
fn upload_image(r: *Renderer, image_view: image.ConstImage) -> (TextureId, err)
fn update_image(r: *Renderer, texture: TextureId, image_view: image.ConstImage) -> err
fn release_image(r: *Renderer, texture: TextureId) -> err
fn compile(r: *Renderer, list: DisplayList) -> (SceneId, err)
fn render(r: *Renderer, scene: SceneId, render_target: Target, size: geometry.Size) -> err
fn release_scene(r: *Renderer, scene: SceneId) -> err
fn close(r: *Renderer) -> err
```

Display lists borrow their paths, gradients and text layouts until `compile`
returns. A renderer owns bounded generation-checked GPU caches. Compilation may
retain tessellation and glyph data but never application widget pointers. Rendering
is explicit queue work followed by presentation through the target surface.

## Missing declarations

- [ ] `TextureId`
- [ ] `SceneId`
- [ ] `Clip`
- [ ] `Command`
- [ ] `FillRect`
- [ ] `FillPath`
- [ ] `StrokePath`
- [ ] `DrawImage`
- [ ] `DrawText`
- [ ] `OpacityLayer`
- [ ] `DisplayList`
- [ ] `Builder`
- [ ] `Renderer`
- [ ] `Target`
- [ ] `Invalid`
- [ ] `TooLarge`
- [ ] `OutOfMemory`
- [ ] `Lost`
- [ ] `builder`
- [ ] `push`
- [ ] `finish`
- [ ] `renderer`
- [ ] `upload_image`
- [ ] `update_image`
- [ ] `release_image`
- [ ] `compile`
- [ ] `render`
- [ ] `release_scene`
- [ ] `close`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/ui-framework.md:187` clips; malformed nesting is `Invalid`. `e.gfx.scene` validates the whole list before

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gfx/scene.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gfx_scene/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 29.

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
