# e.gfx.geometry — 29 of 29 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gfx/geometry.e` |
| plan row | layer 2, surface `planned`, milestone none, schedule `later` |
| blocked by | `image-codec-conformance` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gfx/geometry.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Stable pure images and codecs:** deliver extended `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.image`, `e.fmt.png`, `e.fmt.jpeg` and `e.fmt.webp` as one compatibility cohort under `image-codec-conformance` (D84). Test independent decoders, pixel/stride/alpha contracts and hostile inputs. This wave requires no GPU/window or GP-15 UI gate.

Blockers named in the plan must be resolved first; a blocked module is not eligible. Search `docs/roadmap.md` and `docs/decisions.md` for each blocker id.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.math` | partial | `lib/e/math.e` | 0 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Point = struct { x: f32, y: f32 }
type Size = struct { width: f32, height: f32 }
type Rect = struct { x: f32, y: f32, width: f32, height: f32 }
type Insets = struct { left: f32, top: f32, right: f32, bottom: f32 }
type Radius = struct { x: f32, y: f32 }
type RRect = struct { rect: Rect, top_left: Radius, top_right: Radius, bottom_right: Radius, bottom_left: Radius }
type Transform = struct { m00: f32, m01: f32, m02: f32, m10: f32, m11: f32, m12: f32 }
type PathVerb = enum u8 { Move, Line, Quad, Cubic, Close }
type Path = struct { verbs: []const PathVerb, points: []const Point }
type PathBuilder = struct { state: *void }
error Invalid
error TooLarge

fn rect(x: f32, y: f32, width: f32, height: f32) -> Rect
fn contains(r: Rect, p: Point) -> bool
fn intersect(a: Rect, b: Rect) -> Rect
fn union_rect(a: Rect, b: Rect) -> Rect
fn transform_identity() -> Transform
fn transform_translate(x: f32, y: f32) -> Transform
fn transform_scale(x: f32, y: f32) -> Transform
fn transform_rotate(radians: f32) -> Transform
fn transform_multiply(a: Transform, b: Transform) -> Transform
fn transform_point(t: Transform, p: Point) -> Point
fn path_builder(a: *mem.Arena, max_verbs: usize, max_points: usize) -> (PathBuilder, err)
fn move_to(b: *PathBuilder, p: Point) -> err
fn line_to(b: *PathBuilder, p: Point) -> err
fn quad_to(b: *PathBuilder, control: Point, end: Point) -> err
fn cubic_to(b: *PathBuilder, first: Point, second: Point, end: Point) -> err
fn close_path(b: *PathBuilder) -> err
fn finish(b: *PathBuilder) -> Path
```

Coordinates are logical pixels. Values must be finite; rectangles and sizes have
non-negative dimensions. Paths and transforms allocate nothing after builder
creation and are independent of any rendering backend.

## Missing declarations

- [ ] `Point`
- [ ] `Size`
- [ ] `Rect`
- [ ] `Insets`
- [ ] `Radius`
- [ ] `RRect`
- [ ] `Transform`
- [ ] `PathVerb`
- [ ] `Path`
- [ ] `PathBuilder`
- [ ] `Invalid`
- [ ] `TooLarge`
- [ ] `rect`
- [ ] `contains`
- [ ] `intersect`
- [ ] `union_rect`
- [ ] `transform_identity`
- [ ] `transform_translate`
- [ ] `transform_scale`
- [ ] `transform_rotate`
- [ ] `transform_multiply`
- [ ] `transform_point`
- [ ] `path_builder`
- [ ] `move_to`
- [ ] `line_to`
- [ ] `quad_to`
- [ ] `cubic_to`
- [ ] `close_path`
- [ ] `finish`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/stdlib-hardening.md:407` Promote `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` to extended alongside existing
- `docs/ui-framework.md:277` The pure `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` dependency closure is instead

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gfx/geometry.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gfx_geometry/src/main.e` that prints one fixed line on success, registered in both runners.
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
