// Text out of Office Open XML packages (C123, C142): the paragraphs of a Word document (`.docx`) and the slides of
// a PowerPoint deck (`.pptx`), read over e.fmt.zip and e.fmt.xml from a byte slice. It is a reader for what a
// viewer shows -- the text of each paragraph in order, a paragraph's style name (`Heading1`, `ListParagraph`) and
// whether it is a list item, tabs and line breaks as the characters they are -- not a layout engine: runs,
// tables, images and shapes are not drawn, and the text of a table cell or a slide shape is a paragraph like
// any other, in document order. Namespace prefixes are ignored (`w:p` and `p` are the same element).
//
// Memory: every result lives in the arena passed in.
use e.mem
use e.io
use e.os
use e.str
use e.fmt.zip as zip
use e.fmt.xml as xml

error NotAPackage
error NoMainPart

type Source = struct { data: []const u8, off: usize }

type Paragraph = struct { text: str, style: str, list: bool }

type Slide = struct { paragraphs: []const str }

const LIMIT_ENTRIES: usize = 512usize
const LIMIT_NAME: usize = 256usize
const LIMIT_ENTRY: u64 = 8388608u64
const LIMIT_TOTAL: u64 = 33554432u64

fn source_read(ctx: *void, dst: []u8) -> (usize, err) {
    var s = mem.cast[*Source](ctx)
    if s.off >= s.data.len { ret (0usize, io.End) }
    var take = dst.len
    if s.data.len - s.off < take { take = s.data.len - s.off }
    mem.copy[u8](dst[..take], s.data[s.off..s.off + take])
    s.off += take
    ret (take, ok)
}

fn source_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err) {
    var s = mem.cast[*Source](ctx)
    var base = 0i64
    if whence == .Current { base = i64(s.off) }
    if whence == .End { base = i64(s.data.len) }
    let target_at = base + off
    if target_at < 0i64 || target_at > i64(s.data.len) { ret (0u64, io.End) }
    s.off = usize(target_at)
    ret (u64(target_at), ok)
}

// The part of `name` after its namespace prefix: `w:p` is `p`.
fn local(name: str) -> str {
    var i = name.len
    while i > 0usize {
        if name[i - 1usize] == 58u8 { ret name[i..name.len] }
        i -= 1usize
    }
    ret name
}

fn open_package(a: *mem.Arena, data: []const u8) -> (zip.Archive, err) {
    let (cell, cell_error) = mem.alloc[Source](a, 1usize)
    if cell_error != ok { ret (zero, cell_error) }
    cell[0usize] = Source { data: data, off: 0usize }
    let reader = io.Reader { ctx: mem.cast[*void](&cell[0usize]), read: source_read }
    let seeker = io.Seeker { ctx: mem.cast[*void](&cell[0usize]), seek: source_seek }
    var limits: zip.Limits = zero
    limits.entries = LIMIT_ENTRIES
    limits.name_bytes = LIMIT_NAME
    limits.entry_bytes = LIMIT_ENTRY
    limits.total_bytes = LIMIT_TOTAL
    let (archive, open_error) = zip.open(a, reader, seeker, limits)
    if open_error != ok { ret (archive, NotAPackage) }
    ret (archive, ok)
}

// The index of the entry called `name`, and whether there is one.
fn find(archive: *zip.Archive, name: str) -> (usize, bool) {
    let listed = zip.entries(archive)
    var i = 0usize
    while i < listed.len {
        if str.eq(listed[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// The text of the elements called `leaf` (`t`) under the paragraph elements called `para` (`p`) of an XML part,
// one string per paragraph, in order. `style_attr` pulls a paragraph's style name when the part has one.
type Collected = struct { texts: []str, styles: []str, lists: []bool }

fn collect(a: *mem.Arena, part: []const u8) -> (Collected, err) {
    let (found, found_error) = collect_of(a, part, "p")
    ret (found, found_error)
}

// `collect` for any paragraph-like element: `si` for the shared strings of a workbook.
fn collect_of(a: *mem.Arena, part: []const u8, para: str) -> (Collected, err) {
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    // Paragraph element indexes, in document order.
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), para) { count += 1usize }
        i += 1usize
    }
    let (starts, starts_error) = mem.alloc[usize](a, count + 1usize)
    if starts_error != ok { ret (zero, starts_error) }
    var k = 0usize
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), para) {
            starts[k] = i
            k += 1usize
        }
        i += 1usize
    }
    starts[count] = nodes.len
    let (texts, texts_error) = mem.alloc[str](a, count)
    if texts_error != ok { ret (zero, texts_error) }
    let (styles, styles_error) = mem.alloc[str](a, count)
    if styles_error != ok { ret (zero, styles_error) }
    let (lists, lists_error) = mem.alloc[bool](a, count)
    if lists_error != ok { ret (zero, lists_error) }
    var p = 0usize
    while p < count {
        // The bytes of this paragraph's text: `t` text nodes, a tab for `tab`, a newline for `br`.
        var size = 0usize
        var n = starts[p]
        while n < starts[p + 1usize] {
            if nodes[n].kind == .Text && usize(nodes[n].parent) < nodes.len && str.eq(local(nodes[usize(nodes[n].parent)].name), "t") { size += nodes[n].value.len }
            if nodes[n].kind == .Element && (str.eq(local(nodes[n].name), "tab") || str.eq(local(nodes[n].name), "br")) { size += 1usize }
            n += 1usize
        }
        let (buffer, buffer_error) = mem.alloc[u8](a, size + 1usize)
        if buffer_error != ok { ret (zero, buffer_error) }
        var at = 0usize
        var style = ""
        var is_list = false
        n = starts[p]
        while n < starts[p + 1usize] {
            if nodes[n].kind == .Text && usize(nodes[n].parent) < nodes.len && str.eq(local(nodes[usize(nodes[n].parent)].name), "t") {
                var j = 0usize
                while j < nodes[n].value.len {
                    buffer[at] = nodes[n].value[j]
                    at += 1usize
                    j += 1usize
                }
            }
            if nodes[n].kind == .Element {
                let name = local(nodes[n].name)
                if str.eq(name, "tab") {
                    buffer[at] = 9u8
                    at += 1usize
                }
                if str.eq(name, "br") {
                    buffer[at] = 10u8
                    at += 1usize
                }
                if str.eq(name, "pStyle") {
                    let (value, has_value) = xml.attribute(&nodes[n], "w:val")
                    if has_value { style = value }
                }
                if str.eq(name, "numPr") { is_list = true }
            }
            n += 1usize
        }
        texts[p] = buffer[0usize..at]
        styles[p] = style
        lists[p] = is_list
        p += 1usize
    }
    ret (Collected { texts: texts, styles: styles, lists: lists }, ok)
}

// The paragraphs of a `.docx` held in `data`: its main part `word/document.xml`.
fn paragraphs(a: *mem.Arena, data: []const u8) -> ([]Paragraph, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = find(&ar, "word/document.xml")
    if !found { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    let (c, collect_error) = collect(a, part)
    if collect_error != ok { ret (zero, collect_error) }
    let (out, out_error) = mem.alloc[Paragraph](a, c.texts.len)
    if out_error != ok { ret (zero, out_error) }
    var i = 0usize
    while i < c.texts.len {
        out[i] = Paragraph { text: c.texts[i], style: c.styles[i], list: c.lists[i] }
        i += 1usize
    }
    ret (out, ok)
}

// The number in `ppt/slides/slide<N>.xml`, or 0 when `name` is not a slide part.
fn slide_number(name: str) -> usize {
    let prefix = "ppt/slides/slide"
    let suffix = ".xml"
    if name.len <= prefix.len + suffix.len { ret 0usize }
    var i = 0usize
    while i < prefix.len {
        if name[i] != prefix[i] { ret 0usize }
        i += 1usize
    }
    var n = 0usize
    var at = prefix.len
    while at < name.len - suffix.len {
        if name[at] < 48u8 || name[at] > 57u8 { ret 0usize }
        n = n * 10usize + usize(name[at] - 48u8)
        at += 1usize
    }
    i = 0usize
    while i < suffix.len {
        if name[name.len - suffix.len + i] != suffix[i] { ret 0usize }
        i += 1usize
    }
    ret n
}

// The slides of a `.pptx` held in `data`, in slide-number order; each slide's text paragraphs.
fn slides(a: *mem.Arena, data: []const u8) -> ([]Slide, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let listed = zip.entries(&ar)
    var total = 0usize
    var i = 0usize
    while i < listed.len {
        if slide_number(listed[i].name) > 0usize { total += 1usize }
        i += 1usize
    }
    if total == 0usize { ret (zero, NoMainPart) }
    let (out, out_error) = mem.alloc[Slide](a, total)
    if out_error != ok { ret (zero, out_error) }
    // Slide k, for k = 1 upward, is the part whose number is k; a missing number is skipped.
    var written = 0usize
    var want = 1usize
    while written < total && want < 10000usize {
        var j = 0usize
        while j < listed.len {
            if slide_number(listed[j].name) == want {
                let (part, extract_error) = zip.extract(a, &ar, j)
                if extract_error != ok { ret (zero, extract_error) }
                let (c, collect_error) = collect(a, part)
                if collect_error != ok { ret (zero, collect_error) }
                out[written] = Slide { paragraphs: c.texts }
                written += 1usize
            }
            j += 1usize
        }
        want += 1usize
    }
    ret (out[0usize..written], ok)
}

// A worksheet as a grid (C172): `cells[row * columns + column]` is the cell's text, "" where the sheet has none.
// A number is its stored text, a boolean `TRUE` or `FALSE`, a shared or inline string its characters; a date is its
// serial number (no number-format reading).
type Grid = struct { rows: usize, columns: usize, cells: []str }

const LIMIT_GRID_ROWS: usize = 2000usize
const LIMIT_GRID_COLUMNS: usize = 64usize

// The column and row (both from 0) of a cell reference such as `C12`; false when it is not one.
fn cell_at(reference: str) -> (usize, usize, bool) {
    var column = 0usize
    var i = 0usize
    while i < reference.len && reference[i] >= 65u8 && reference[i] <= 90u8 {
        column = column * 26usize + usize(reference[i] - 64u8)
        if column > 16384usize { ret (0usize, 0usize, false) }
        i += 1usize
    }
    if i == 0usize || i == reference.len { ret (0usize, 0usize, false) }
    var row = 0usize
    while i < reference.len {
        if reference[i] < 48u8 || reference[i] > 57u8 { ret (0usize, 0usize, false) }
        row = row * 10usize + usize(reference[i] - 48u8)
        if row > 1048576usize { ret (0usize, 0usize, false) }
        i += 1usize
    }
    if row == 0usize { ret (0usize, 0usize, false) }
    ret (column - 1usize, row - 1usize, true)
}

// The names of the workbook's sheets in order (`xl/workbook.xml`).
fn sheet_names(a: *mem.Arena, data: []const u8) -> ([]str, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = find(&ar, "xl/workbook.xml")
    if !found { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "sheet") { count += 1usize }
        i += 1usize
    }
    let (names, names_error) = mem.alloc[str](a, count + 1usize)
    if names_error != ok { ret (zero, names_error) }
    var k = 0usize
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "sheet") {
            let (value, has_value) = xml.attribute(&nodes[i], "name")
            names[k] = value
            k += 1usize
        }
        i += 1usize
    }
    ret (names[0usize..count], ok)
}

// Sheet `number` (from 1: `xl/worksheets/sheet<number>.xml`) of an `.xlsx` held in `data`, as a grid at most
// LIMIT_GRID_ROWS by LIMIT_GRID_COLUMNS (cells beyond are dropped). A cell with no `r` reference is skipped.
fn sheet_grid(a: *mem.Arena, data: []const u8, number: usize) -> (Grid, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    var shared_texts: []str = zero
    let (shared_index, has_shared) = find(&ar, "xl/sharedStrings.xml")
    if has_shared {
        let (shared_part, shared_error) = zip.extract(a, &ar, shared_index)
        if shared_error != ok { ret (zero, shared_error) }
        let (items, items_error) = collect_of(a, shared_part, "si")
        if items_error != ok { ret (zero, items_error) }
        shared_texts = items.texts
    }
    let (name_builder, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret (zero, builder_error) }
    var nb = name_builder
    let pushed_prefix = str.push(&nb, "xl/worksheets/sheet")
    let pushed_number = str.push_usize(&nb, number)
    let pushed_suffix = str.push(&nb, ".xml")
    let (part_index, has_part) = find(&ar, str.done(&nb))
    if !has_part { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, part_index)
    if extract_error != ok { ret (zero, extract_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    // The extent: the largest cell reference, within the limits.
    var rows = 0usize
    var columns = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "c") {
            let (reference, has_reference) = xml.attribute(&nodes[i], "r")
            let (col, row, valid) = cell_at(reference)
            if has_reference && valid && col < LIMIT_GRID_COLUMNS && row < LIMIT_GRID_ROWS {
                if col + 1usize > columns { columns = col + 1usize }
                if row + 1usize > rows { rows = row + 1usize }
            }
        }
        i += 1usize
    }
    let (cells, cells_error) = mem.alloc[str](a, rows * columns + 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    var c = 0usize
    while c < rows * columns {
        cells[c] = ""
        c += 1usize
    }
    // The values: each `v` (or inline `t`) text belongs to the nearest cell element before it.
    var at = 0usize
    var live = false
    var kind_byte = 0u8
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "c") {
            let (reference, has_reference) = xml.attribute(&nodes[i], "r")
            let (col, row, valid) = cell_at(reference)
            live = has_reference && valid && col < LIMIT_GRID_COLUMNS && row < LIMIT_GRID_ROWS
            at = row * columns + col
            let (kind_text, has_kind) = xml.attribute(&nodes[i], "t")
            kind_byte = 0u8
            if has_kind && kind_text.len == 1usize { kind_byte = kind_text[0usize] }
        }
        if live && nodes[i].kind == .Text && usize(nodes[i].parent) < nodes.len {
            let owner = local(nodes[usize(nodes[i].parent)].name)
            if str.eq(owner, "v") || str.eq(owner, "t") {
                var shown = nodes[i].value
                if kind_byte == 115u8 && str.eq(owner, "v") {
                    let (position, position_error) = str.parse_u64(shown)
                    if position_error == ok && usize(position) < shared_texts.len { shown = shared_texts[usize(position)] }
                }
                if kind_byte == 98u8 {
                    if str.eq(shown, "1") { shown = "TRUE" } else { shown = "FALSE" }
                }
                cells[at] = shown
            }
        }
        i += 1usize
    }
    ret (Grid { rows: rows, columns: columns, cells: cells }, ok)
}
