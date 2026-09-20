# e.gfx.paint — 14 of 14 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gfx/paint.e` |
| plan row | layer 2, surface `planned`, milestone none, schedule `later` |
| blocked by | `image-codec-conformance` |
| unmet dependencies | `e.gfx.geometry` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gfx/paint.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Stable pure images and codecs:** deliver extended `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.image`, `e.fmt.png`, `e.fmt.jpeg` and `e.fmt.webp` as one compatibility cohort under `image-codec-conformance` (D84). Test independent decoders, pixel/stride/alpha contracts and hostile inputs. This wave requires no GPU/window or GP-15 UI gate.

Blockers named in the plan must be resolved first; a blocked module is not eligible. Search `docs/roadmap.md` and `docs/decisions.md` for each blocker id.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.gfx.geometry` | planned | missing | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Color = struct { red: f32, green: f32, blue: f32, alpha: f32 }
type Blend = enum u8 { SourceOver, Source, DestinationOver, Multiply, Screen, Overlay, Darken, Lighten }
type StrokeCap = enum u8 { Butt, Round, Square }
type StrokeJoin = enum u8 { Miter, Round, Bevel }
type Stroke = struct { width: f32, cap: StrokeCap, join: StrokeJoin, miter_limit: f32 }
type Stop = struct { offset: f32, color: Color }
type Brush = union enum u8 { Solid: Color, Linear: LinearGradient, Radial: RadialGradient }
type LinearGradient = struct { start: geometry.Point, end: geometry.Point, stops: []const Stop }
type RadialGradient = struct { center: geometry.Point, radius: f32, stops: []const Stop }
error Invalid

fn rgba(red: f32, green: f32, blue: f32, alpha: f32) -> Color
fn srgb8(red: u8, green: u8, blue: u8, alpha: u8) -> Color
fn premultiply(color: Color) -> Color
fn validate(brush: *const Brush) -> err
```

Colors are linear-light floating-point RGBA; `srgb8` performs the defined sRGB
transfer. Gradient stops are borrowed, ordered and bounded to `0..1`.

## Missing declarations

- [ ] `Color`
- [ ] `Blend`
- [ ] `StrokeCap`
- [ ] `StrokeJoin`
- [ ] `Stroke`
- [ ] `Stop`
- [ ] `Brush`
- [ ] `LinearGradient`
- [ ] `RadialGradient`
- [ ] `Invalid`
- [ ] `rgba`
- [ ] `srgb8`
- [ ] `premultiply`
- [ ] `validate`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/stdlib-hardening.md:407` Promote `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` to extended alongside existing
- `docs/ui-framework.md:277` The pure `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` dependency closure is instead

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gfx/paint.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gfx_paint/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 14.

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
