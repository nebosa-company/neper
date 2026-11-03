# e.fmt.pdf — 1 of 84 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/pdf.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/pdf.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.fmt.jpeg` | partial | `lib/e/fmt/jpeg.e` | 6 |
| `e.fmt.zlib` | partial | `lib/e/fmt/zlib.e` | 6 |
| `e.gfx.image` | partial | `lib/e/gfx/image.e` | 2 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error NotPdf
error NoPages
type Object = struct { number: usize, start: usize, end: usize }
const MAX_OBJECTS: usize = 4096usize
const MAX_PAGES: usize = 512usize
const MAX_STREAM: u64 = 8388608u64
fn is_space(c: u8) -> bool
fn is_delim(c: u8) -> bool
fn is_digit(c: u8) -> bool
fn at_word(data: []const u8, at: usize, word: str) -> bool
fn find(data: []const u8, word: str, from: usize, until: usize) -> usize
fn number_at(data: []const u8, from: usize, until: usize) -> (usize, usize, bool)
fn objects(a: *mem.Arena, data: []const u8) -> ([]Object, usize, err)
fn object_span(table: []const Object, count: usize, number: usize) -> (usize, usize, bool)
fn has_pair(data: []const u8, from: usize, until: usize, key: str, value: str) -> bool
fn ref_after(data: []const u8, from: usize, until: usize, key: str) -> (usize, bool)
fn refs_in_array(data: []const u8, from: usize, until: usize, key: str, out: []usize) -> usize
fn walk(a: *mem.Arena, data: []const u8, table: []const Object, count: usize, root: usize, found_pages: []usize) -> (usize, err)
fn ascii85(a: *mem.Arena, raw: []const u8) -> ([]const u8, err)
fn stream_of(a: *mem.Arena, data: []const u8, s: usize, e: usize) -> ([]const u8, err)
fn stream_capped(a: *mem.Arena, data: []const u8, s: usize, e: usize, cap: usize) -> ([]const u8, err)
type Mem = struct { data: []const u8, off: usize }
fn mem_read(ctx: *void, dst: []u8) -> (usize, err)
fn put_latin1(out: []u8, at: usize, c: u8) -> usize
fn put_raw(out: []u8, at: usize, c: u8) -> usize
fn newline(out: []u8, at: usize) -> usize
fn text_of(a: *mem.Arena, content: []const u8) -> (str, err)
fn put_code(out: []u8, at: usize, p: *Painter, c: u8, half: *usize) -> usize
fn text_run(a: *mem.Arena, content: []const u8, p: *Painter) -> (str, err)
type Tree = struct { table: []Object, count: usize, page_objects: []usize, page_count: usize }
fn page_tree(a: *mem.Arena, data: []const u8) -> (Tree, err)
fn pages(a: *mem.Arena, data: []const u8) -> ([]str, err)
type Shape = struct { kind: u8, x0: f64, y0: f64, x1: f64, y1: f64, width: f64, red: f64, green: f64, blue: f64, size: f64, text: str }
type Image = struct { width: u32, height: u32, pixels: []u8 }
type Painting = struct { width: f64, height: f64, shapes: []Shape, images: []Image }
type FontInfo = struct { object: usize, first: usize, widths: []u16, codes: []u16, unis: []u32, mapped: usize, two_byte: bool, default_width: usize }
type Segment = struct { x0: f64, y0: f64, x1: f64, y1: f64 }
const SHAPE_FILL: u8 = 0u8
const SHAPE_LINE: u8 = 1u8
const SHAPE_TEXT: u8 = 2u8
const SHAPE_IMAGE: u8 = 3u8
const MAX_IMAGES: usize = 6usize
const MAX_IMAGE_PIXELS: usize = 1048576usize
const MAX_FONTS: usize = 8usize
const MAX_CMAP: usize = 1024usize
const MAX_WIDTHS: usize = 4096usize
const MAX_SHAPES: usize = 4000usize
const MAX_SEGMENTS: usize = 256usize
const STATE_DEPTH: usize = 8usize
type Painter = struct { out: []Shape, n: usize, fill_r: f64, fill_g: f64, fill_b: f64, stroke_r: f64, stroke_g: f64, stroke_b: f64, line_width: f64, scale_x: f64, scale_y: f64, shift_x: f64, shift_y: f64, saved: [88]f64, depth: usize, segs: [256]Segment, seg_n: usize, rects: [64]Segment, rect_n: usize, cur_x: f64, cur_y: f64, start_x: f64, start_y: f64, tm_x: f64, tm_y: f64, line_x: f64, line_y: f64, leading: f64, font_size: f64, text_scale: f64, data: []const u8, table: []Object, count: usize, res_s: usize, res_e: usize, images: []Image, image_n: usize, image_objs: [6]usize, fonts: [8]FontInfo, font_n: usize, cur_font: usize, form_depth: usize }
fn paint_start(out: []Shape) -> Painter
fn paint_push(p: *Painter, kind: u8, x0: f64, y0: f64, x1: f64, y1: f64, width: f64, red: f64, green: f64, blue: f64, size: f64, text: str)
fn paint_path(p: *Painter, fill: bool, stroke: bool)
fn paint_line_to(p: *Painter, x: f64, y: f64)
fn paint_text(p: *Painter, text: str)
fn put_utf8(out: []u8, at: usize, cp: u32) -> usize
fn font_unicode(f: *const FontInfo, code: usize) -> u32
fn font_width(f: *const FontInfo, code: usize) -> usize
fn paint_run(a: *mem.Arena, p: *Painter, raw: []const u8)
fn paint_move_text(p: *Painter, tx: f64, ty: f64)
fn operand_number(text: str) -> f64
fn dict_end(data: []const u8, k: usize, until: usize) -> usize
fn region_after(data: []const u8, table: []const Object, count: usize, from: usize, until: usize, key: str) -> (usize, usize, bool)
fn resources_span(data: []const u8, table: []const Object, count: usize, ps: usize, pe: usize) -> (usize, usize, bool)
fn named_ref(data: []const u8, table: []const Object, count: usize, rs: usize, re: usize, group: str, name: str) -> (usize, bool)
fn int_after(data: []const u8, from: usize, until: usize, key: str, fallback: usize) -> usize
fn array_after(data: []const u8, table: []const Object, count: usize, from: usize, until: usize, key: str) -> (usize, usize, bool)
fn array_token(data: []const u8, at: usize, until: usize) -> (u8, f64, usize)
fn read_widths(data: []const u8, s: usize, e: usize, out: []u16) -> usize
fn read_cid_widths(data: []const u8, s: usize, e: usize, out: []u16) -> usize
fn hex_value(data: []const u8, at: usize, until: usize) -> (u32, usize, usize, bool)
fn read_cmap(data: []const u8, f: *FontInfo, codes: []u16, unis: []u32) -> usize
fn load_font(a: *mem.Arena, p: *Painter, object: usize) -> usize
fn unpredict(raw: []u8, row_bytes: usize, bpp: usize) -> usize
fn decode_image(a: *mem.Arena, p: *Painter, s: usize, e: usize) -> (Image, bool)
fn paint_xobject(a: *mem.Arena, p: *Painter, name: []const u8)
fn paint_content(a: *mem.Arena, p: *Painter, content: []const u8) -> err
fn media_box(data: []const u8, from: usize, until: usize) -> (f64, f64, bool)
fn page_painting(a: *mem.Arena, data: []const u8, page: usize) -> (Painting, err)
type OutlineItem = struct { title: str, page: usize, level: usize }
const MAX_OUTLINE: usize = 64usize
const NO_PAGE: usize = 4294967295usize
fn string_after(a: *mem.Arena, data: []const u8, s: usize, e: usize, key: str) -> str
fn outline(a: *mem.Arena, data: []const u8) -> ([]OutlineItem, err)
```

A page painted (C152, C172, D3801): `page_painting` runs page N's content streams and gives the page's size (its MediaBox, or the first MediaBox of any page tree node, else 612 by 792) and the shapes in paint order: `SHAPE_FILL` (a rectangle filled by `re` then `f`, `F`, `f*`, `B`), `SHAPE_LINE` (a segment of `m`/`l`/`h`/`re` stroked by `S`, `s`, `B`, with the line width and the stroke colour) and `SHAPE_TEXT` (a `Tj`/`TJ`/`'`/`"` string at the text position, with the font size scaled by `Tm`), in user space (origin bottom left) after the `cm` scale and offset; colours from `g`, `rg`, `k` and their stroke forms, `q`/`Q` nest eight deep. Not a renderer: a `cm` rotation or shear is not followed, a curve is its chord, a filled path that is not a rectangle is not filled, clipping and images (`Do`) are ignored, and text is placed with no glyph metrics (half its size a character). Checked on a hand-written page with a red fill, a blue 3-unit line, text after `Td`, a `cm` scale and offset undone by `Q`, and a CMYK black kerned `TJ` (`reference_paint.py`).

The text of a PDF held in a byte slice (C123): `pages` gives each page's text in page-tree order. The objects are found by scanning for `N G obj` (a file with its objects in object streams, or with an xref stream, is `NoPages`), the page order is the catalog's tree, a page's content streams are joined and `/FlateDecode` is undone through `e.fmt.zlib`, and the text operators `Tj`, `TJ` (a kern of -200 or more is a word space), `'`, `"`, `T*`, `Td`, `TD`, `Tm` and `ET` give the lines; literal strings keep their escapes and octal codes, hex strings are read, Latin-1 bytes are written as UTF-8. Not a renderer and not a font reader: an embedded font with its own encoding gives its codes. Checked against PDFs written by the fixture's generator.


Images, fonts and the outline (D4800): `Do` for an image XObject is a `SHAPE_IMAGE` over the unit square under the matrix (`x0`,`y0` to `x1`,`y1`; `size` is the index into `Painting.images`, -1 when it was not decoded), a form XObject's content is run in place (two deep). `Image` is RGBA: `/DCTDecode` through `e.fmt.jpeg` (up to `MAX_IMAGE_PIXELS`, 1,048,576), `/FlateDecode` samples of 8-bit gray, RGB or CMYK (the component count guessed from the sample count when the colour space is an ICC or calibrated one) with the PNG predictors 10 to 15 undone, 1-bit gray and `/ImageMask` stencils (black where the sample is 0, transparent elsewhere); an Indexed colour space, 16 bits a sample and soft masks are not read (an image with a soft mask is drawn opaque). Fonts: `Tf` selects the font resource (`/Font` in the page's, else the first page tree node's, `/Resources`, direct or indirect); a string's codes are read through its `/ToUnicode` CMap (`bfchar` and `bfrange`, up to 1024 entries, two-byte codes for a Type0 font) and each code advances the position by `/Widths` (from `/FirstChar`) or a CID font's `/W` (else `/DW`, else 500), so a text shape's `x1` is its end; `pages` reads strings through the same fonts, so the text lines and Find agree with what is painted. Without font resources a string is Latin-1 at half the size a character, as before. `outline` gives the bookmarks in order with their depth and the page index of a `/Dest [page ...]` or `/A << /D [page ...] >>` (`NO_PAGE` for a named destination). Not here: Type0 fonts whose codes are glyph indices without a `/ToUnicode` (the text is the codes), embedded glyph outlines (text is drawn in the viewer's face), `/Differences` encodings, kerning inside a `TJ` (the run is one shape), clipping and shading, an `/SMask`, named destinations, and a ToUnicode CMap over 1024 entries (CJK).

## Missing declarations

- [ ] `MAX_STREAM`

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/pdf.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_pdf/src/main.e` that prints one fixed line on success, registered in both runners.
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
