# e.ui.asset — 15 of 15 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ui/asset.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ui/asset.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.asset` | source | `lib/e/asset.e` | 5 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.gfx.image` | partial | `lib/e/gfx/image.e` | 2 |
| `e.gfx.scene` | partial | `lib/e/gfx/scene.e` | 6 |
| `e.text.shape` | partial | `lib/e/text/shape.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Theme = enum u8 { Any, Light, Dark }
type Request = struct { scale: f32, locale: str, theme: Theme }
type ImageDecoder = struct { ctx: *void, decode: fn(*void, *mem.Arena, []const u8) -> (image.Image, err) }
type Cache = struct { state: *void }
error Missing
error InvalidVariant
error Decode
error Full

fn select(base: str, request: Request) -> (asset.Asset, err)
fn font(base: str, request: Request, face_index: u32) -> (shape.Font, err)
fn cache(a: *mem.Arena, renderer: *scene.Renderer, capacity: usize) -> (Cache, err)
fn texture(texture_cache: *Cache, scratch: *mem.Arena, base: str, request: Request, decoder: ImageDecoder) -> (scene.TextureId, err)
fn evict(texture_cache: *Cache, renderer: *scene.Renderer, base: str) -> err
fn clear(texture_cache: *Cache, renderer: *scene.Renderer) -> err
fn close(texture_cache: *Cache, renderer: *scene.Renderer) -> err
```

Variants share a manifest `base` attribute. Selection first filters by base, then
chooses exact locale (falling back by removing subtags and finally to
an empty locale), exact theme before `Any`, and the smallest scale not below the
request or otherwise the largest scale. UTF-8 asset name breaks any remaining tie.
The algorithm reads only `e.asset` metadata and is deterministic on every host.

`font` returns executable-backed OpenType bytes without copying. `texture` invokes
the caller-supplied decoder into `scratch`, uploads before returning, and keys the
bounded cache by selected asset SHA-256 plus decoder identity. The cache owns its
texture entries but not the renderer; eviction and closure explicitly release them.
No image codec, filesystem lookup or unbounded global cache is hidden here.

## Missing declarations

- [ ] `Theme`
- [ ] `Request`
- [ ] `ImageDecoder`
- [ ] `Cache`
- [ ] `Missing`
- [ ] `InvalidVariant`
- [ ] `Decode`
- [ ] `Full`
- [ ] `select`
- [ ] `font`
- [ ] `cache`
- [ ] `texture`
- [ ] `evict`
- [ ] `clear`
- [ ] `close`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/ui-framework.md:76` `e.ui.asset` groups physical entries by their `base` attribute and deterministically

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/ui/layout.e`
- `lib/e/ui/style.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ui/asset.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ui_asset/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 15.

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
