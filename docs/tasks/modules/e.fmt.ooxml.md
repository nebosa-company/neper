# e.fmt.ooxml — 1 of 50 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/ooxml.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/ooxml.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.fmt.xml` | partial | `lib/e/fmt/xml.e` | 6 |
| `e.fmt.zip` | partial | `lib/e/fmt/zip.e` | 6 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error NotAPackage
error NoMainPart
type Source = struct { data: []const u8, off: usize }
type Paragraph = struct { text: str, style: str, list: bool }
type Slide = struct { paragraphs: []const str }
const LIMIT_ENTRIES: usize = 512usize
const LIMIT_NAME: usize = 256usize
const LIMIT_ENTRY: u64 = 8388608u64
const LIMIT_TOTAL: u64 = 33554432u64
fn source_read(ctx: *void, dst: []u8) -> (usize, err)
fn source_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err)
fn local(name: str) -> str
fn open_package(a: *mem.Arena, data: []const u8) -> (zip.Archive, err)
fn find(archive: *zip.Archive, name: str) -> (usize, bool)
type Collected = struct { texts: []str, styles: []str, lists: []bool }
fn collect(a: *mem.Arena, part: []const u8) -> (Collected, err)
fn collect_of(a: *mem.Arena, part: []const u8, para: str) -> (Collected, err)
fn paragraphs(a: *mem.Arena, data: []const u8) -> ([]Paragraph, err)
fn slide_number(name: str) -> usize
fn slides(a: *mem.Arena, data: []const u8) -> ([]Slide, err)
type Grid = struct { rows: usize, columns: usize, cells: []str, after: usize }
const LIMIT_GRID_ROWS: usize = 2000usize
const LIMIT_GRID_COLUMNS: usize = 64usize
fn cell_at(reference: str) -> (usize, usize, bool)
fn sheet_names(a: *mem.Arena, data: []const u8) -> ([]str, err)
fn sheet_grid(a: *mem.Arena, data: []const u8, number: usize) -> (Grid, err)
fn tables(a: *mem.Arena, data: []const u8) -> ([]Grid, err)
fn inside_cell(nodes: []const xml.Node, i: usize) -> bool
fn cell_flags(a: *mem.Arena, data: []const u8) -> ([]bool, err)
type Picture = struct { paragraph: usize, cx: usize, cy: usize, name: str, data: []const u8 }
const LIMIT_PICTURES: usize = 8usize
const LIMIT_PICTURE: u64 = 262144u64
const LIMIT_SHAPES: usize = 64usize
const NO_COLOR: u32 = 16777216u32
const NO_PICTURE: usize = 4294967295usize
const SHAPE_RECT: u8 = 0u8
const SHAPE_ELLIPSE: u8 = 1u8
const SHAPE_PICTURE: u8 = 2u8
const SHAPE_LINE: u8 = 3u8
fn resolve_target(a: *mem.Arena, base: str, dest: str) -> str
fn related_part(a: *mem.Arena, ar: *zip.Archive, rels_name: str, base: str, id: str) -> str
fn part_bytes(a: *mem.Arena, ar: *zip.Archive, name: str) -> []const u8
fn number_attribute(node: *const xml.Node, name: str) -> usize
fn pictures(a: *mem.Arena, data: []const u8) -> ([]Picture, err)
type SlideShape = struct { kind: u8, x: usize, y: usize, cx: usize, cy: usize, fill: u32, text: str, picture: usize }
type SlideLayout = struct { width: usize, height: usize, shapes: []SlideShape, pictures: []Picture }
fn hex_digit(c: u8) -> u32
fn has_ancestor(nodes: []const xml.Node, n: usize, name: str) -> bool
fn within(nodes: []const xml.Node, n: usize, root: usize) -> bool
fn slide_layout(a: *mem.Arena, data: []const u8, number: usize) -> (SlideLayout, err)
```

Word tables (C152, D3809): `tables` reads a `.docx`'s tables in document order as `Grid`s (rows, columns, `cells[row * columns + column]`): the paragraphs of a cell joined by a space, a short row padded with empty cells, a table nested in a cell contributing its text to that cell rather than a grid of its own, at most 2000 by 64. `Grid.after` is the number of paragraphs outside any table before the table (0 for a sheet), and `cell_flags` says for each paragraph `paragraphs` gives whether it sits in a cell, so a viewer can leave those out of the text and set the grids in between. `paragraphs` is unchanged (a cell's paragraphs are still paragraphs in order). Checked on a package made with Python's zipfile (`reference_table.py`).

Spreadsheets (C172, D3800): `sheet_names` lists an `.xlsx`'s sheet names in workbook order and `sheet_grid` reads sheet N (`xl/worksheets/sheet<N>.xml`, assumed to follow workbook order) as a `Grid` of cell text (`cells[row * columns + column]`, `""` for an absent cell, at most 2000 rows by 64 columns): shared, inline and `str` strings as their characters, numbers as stored, booleans `TRUE`/`FALSE`, dates as serials (no number-format reading), a cell without an `r` reference skipped. Checked on a package made with Python's zipfile (`reference_xlsx.py`): a sparse sheet, column `AA`, an entity, a rich-text shared string, a second sheet and the refusals.

The text of an Office Open XML package, read over `e.fmt.zip` and `e.fmt.xml` from a byte slice (C123): `paragraphs` gives a `.docx`'s paragraphs in order (the text of each, its style name such as `Heading1`, whether it is a list item, tabs and breaks as characters, entities decoded), `slides` a `.pptx`'s slides in slide-number order with each slide's text paragraphs. Namespace prefixes are ignored; runs, tables, images and shapes are not laid out, and the text of a table cell or a shape is a paragraph like any other. A zip with no main part is `NoMainPart`, bytes that are not a zip `NotAPackage`. Checked against packages made with Python's zipfile.


Pictures and shapes (D4802): `pictures(data)` gives a `.docx`'s images (up to `LIMIT_PICTURES`, 8, each at most 256 KB): for each `a:blip r:embed` of `word/document.xml` the `Picture` has the index of its paragraph in `paragraphs` order (`w:p` in document order, table cells included), the `wp:extent` in EMU (the last extent seen before the blip), the part name resolved through `word/_rels/document.xml.rels` and the bytes as stored (a PNG or JPEG; nothing is decoded here). `slide_layout(data, n)` gives slide n (from 1 in slide-number order, as `slides`) of a `.pptx` as a `SlideLayout`: the size from `ppt/presentation.xml` `p:sldSz` (default 9144000 by 6858000) and, for each top-level `p:sp`, `p:pic` and `p:cxnSp`, a `SlideShape` with its `a:off` and `a:ext` (EMU), `SHAPE_RECT`, `SHAPE_ELLIPSE` or `SHAPE_LINE` from `a:prstGeom` (a picture is `SHAPE_PICTURE` with an index into `pictures`, resolved through `ppt/slides/_rels/slide<N>.xml.rels`), the fill (the first `a:srgbClr` under `p:spPr` that is not in the outline `a:ln` or a text run; `NO_COLOR` when the shape has none: a theme colour is not resolved) and its text (every `a:t`, a newline between paragraphs). Not here: group transforms (a shape in a group is placed as if the group were the slide), rotation, gradient and pattern fills, line width and colour, text size, bold, colour and alignment, charts and SmartArt, and word styles beyond the `pStyle` name `paragraphs` already gives. Checked in `fmt_ooxml` on packages written by `reference_pictures.py`.

## Missing declarations

- [ ] `related_part`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/fmt/arrow.e`
- `lib/e/fmt/asn1.e`
- `lib/e/fmt/avro.e`
- `lib/e/fmt/bincode.e`
- `lib/e/fmt/bmp.e`
- `lib/e/fmt/brotli.e`‡
- `lib/e/fmt/bson.e`
- `lib/e/fmt/bzip2.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/ooxml.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_ooxml/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

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
