# e.text.layout — 15 of 15 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/text/layout.e` |
| plan row | layer 2, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/text/layout.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.text.shape` | partial | `lib/e/text/shape.e` | 2 |
| `e.text.unicode` | partial | `lib/e/text/unicode.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Align = enum u8 { Start, End, Center, Justify }
type Wrap = enum u8 { None, Word, Character }
type FontChoice = struct { font: shape.Font, size: f32 }
type Style = struct { fonts: []const FontChoice, language: str, line_height: f32 }
type GlyphRun = struct { run: shape.Run, origin: geometry.Point, size: f32 }
type Line = struct { runs: []const GlyphRun, bounds: geometry.Rect, baseline: f32, start: usize, end: usize }
type Layout = struct { source: str, lines: []const Line, bounds: geometry.Rect }
type Options = struct { width: f32, max_lines: u32, align: Align, wrap: Wrap, ellipsis: str }
error MissingGlyph
error Invalid
error TooLarge

fn layout(a: *mem.Arena, source: str, style: Style, options: Options) -> (Layout, err)
fn hit_test(value: *const Layout, point: geometry.Point) -> usize
fn caret(value: *const Layout, byte_offset: usize) -> geometry.Rect
fn selection(a: *mem.Arena, value: *const Layout, start: usize, end: usize) -> ([]geometry.Rect, err)
```

The module performs Unicode bidi resolution, line breaking, fallback and visual
placement. Byte offsets always identify UTF-8 boundaries in `source`.

## Missing declarations

- [ ] `Align`
- [ ] `Wrap`
- [ ] `FontChoice`
- [ ] `Style`
- [ ] `GlyphRun`
- [ ] `Line`
- [ ] `Layout`
- [ ] `Options`
- [ ] `MissingGlyph`
- [ ] `Invalid`
- [ ] `TooLarge`
- [ ] `layout`
- [ ] `hit_test`
- [ ] `caret`
- [ ] `selection`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/text/collate.e`
- `lib/e/text/encoding.e`
- `lib/e/text/io.e`
- `lib/e/text/locale.e`
- `lib/e/text/normalize.e`‡
- `lib/e/text/regex.e`
- `lib/e/text/shape.e`
- `lib/e/text/template.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/text/layout.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/text_layout/src/main.e` that prints one fixed line on success, registered in both runners.
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
