# e.gfx.image — 13 of 13 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gfx/image.e` |
| plan row | layer 2, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gfx/image.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Stable pure images and codecs:** deliver extended `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.image`, `e.fmt.png`, `e.fmt.jpeg` and `e.fmt.webp` as one compatibility cohort under `image-codec-conformance` (D84). Test independent decoders, pixel/stride/alpha contracts and hostile inputs. This wave requires no GPU/window or GP-15 UI gate.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.gfx.paint` | partial | `lib/e/gfx/paint.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Format = enum u8 { R8, Rgba8, Bgra8, Rgba16Float }
type Alpha = enum u8 { Opaque, Straight, Premultiplied }
type Info = struct { width: u32, height: u32, format: Format, alpha: Alpha, frames: u32 }
type Image = struct { pixels: []u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha }
type ConstImage = struct { pixels: []const u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha }
error Invalid
error TooLarge

fn required_bytes(width: u32, height: u32, format: Format, stride: usize) -> (usize, err)
fn make(pixels: []u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha) -> (Image, err)
fn make_const(pixels: []const u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha) -> (ConstImage, err)
fn allocate(a: *mem.Arena, width: u32, height: u32, format: Format, alpha: Alpha) -> (Image, err)
fn clear(image: Image, color: paint.Color)
fn copy(dst: Image, src: ConstImage, dst_origin: geometry.Point) -> err
```

Images are pixel views, not codecs or GPU resources. Encoders and decoders belong in
`e.fmt.*`; upload and caching belong in `e.gfx.scene`.

## Missing declarations

- [ ] `Format`
- [ ] `Alpha`
- [ ] `Info`
- [ ] `Image`
- [ ] `ConstImage`
- [ ] `Invalid`
- [ ] `TooLarge`
- [ ] `required_bytes`
- [ ] `make`
- [ ] `make_const`
- [ ] `allocate`
- [ ] `clear`
- [ ] `copy`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/stdlib-hardening.md:407` Promote `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` to extended alongside existing
- `docs/ui-framework.md:277` The pure `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` dependency closure is instead

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gfx/image.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gfx_image/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 13.

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
