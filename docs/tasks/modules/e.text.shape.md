# e.text.shape — 13 of 13 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/text/shape.e` |
| plan row | layer 2, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/text/shape.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.text.unicode` | partial | `lib/e/text/unicode.e` | 2 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type FontId = u32
type Direction = enum u8 { LeftToRight, RightToLeft }
type Font = struct { id: FontId, data: []const u8, face_index: u32 }
type Feature = struct { tag: u32, value: u32, start: usize, end: usize }
type Glyph = struct { id: u32, cluster: usize, advance_x: f32, advance_y: f32, offset_x: f32, offset_y: f32 }
type Run = struct { font: FontId, direction: Direction, script: u32, language: str, glyphs: []const Glyph }
type Options = struct { direction: Direction, script: u32, language: str, features: []const Feature }
error InvalidFont
error InvalidText
error Unsupported
error TooLarge

fn validate_font(font: Font) -> err
fn shape(a: *mem.Arena, font: Font, source: str, options: Options) -> (Run, err)
```

Shaping is deterministic over caller-provided OpenType font bytes and the toolchain's
pinned Unicode tables. It performs substitutions and positioning but no line
breaking, font discovery, fallback, rasterization or hidden file access.

## Missing declarations

- [ ] `FontId`
- [ ] `Direction`
- [ ] `Font`
- [ ] `Feature`
- [ ] `Glyph`
- [ ] `Run`
- [ ] `Options`
- [ ] `InvalidFont`
- [ ] `InvalidText`
- [ ] `Unsupported`
- [ ] `TooLarge`
- [ ] `validate_font`
- [ ] `shape`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/text/collate.e`
- `lib/e/text/encoding.e`
- `lib/e/text/io.e`
- `lib/e/text/normalize.e`‡
- `lib/e/text/template.e`
- `lib/e/text/unicode.e`‡
- `lib/e/text/utf8.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/text/shape.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/text_shape/src/main.e` that prints one fixed line on success, registered in both runners.
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
