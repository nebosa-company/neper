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
type Grid = struct { rows: usize, columns: usize, cells: []str, after: usize }

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
    ret (Grid { rows: rows, columns: columns, cells: cells, after: 0usize }, ok)
}

// The tables of a `.docx` in document order (C152, C172), each as a Grid of its cells' text (the paragraphs of a cell
// joined by a space, runs by nothing). A table nested in a cell is not a table of its own: its text joins the cell's.
// At most LIMIT_GRID_ROWS by LIMIT_GRID_COLUMNS each; a short row is padded with empty cells.
fn tables(a: *mem.Arena, data: []const u8) -> ([]Grid, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = find(&ar, "word/document.xml")
    if !found { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    // Pass 1: the shape of each top-level table: rows, and the most cells in a row.
    var table_count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "tbl") && !inside_cell(nodes, i) { table_count += 1usize }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[Grid](a, table_count + 1usize)
    if out_error != ok { ret (zero, out_error) }
    let (row_counts, rc_error) = mem.alloc[usize](a, table_count + 1usize)
    if rc_error != ok { ret (zero, rc_error) }
    let (column_counts, cc_error) = mem.alloc[usize](a, table_count + 1usize)
    if cc_error != ok { ret (zero, cc_error) }
    let (afters, afters_error) = mem.alloc[usize](a, table_count + 1usize)
    if afters_error != ok { ret (zero, afters_error) }
    var t = 0usize
    while t < table_count + 1usize {
        row_counts[t] = 0usize
        column_counts[t] = 0usize
        t += 1usize
    }
    var current = 0usize
    var seen = 0usize
    var row_cells = 0usize
    var body_paragraphs = 0usize
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element {
            let name = local(nodes[i].name)
            if str.eq(name, "p") && !inside_cell(nodes, i) { body_paragraphs += 1usize }
            if str.eq(name, "tbl") && !inside_cell(nodes, i) {
                current = seen
                afters[seen] = body_paragraphs
                seen += 1usize
                row_cells = 0usize
            } else if str.eq(name, "tr") && !inside_cell(nodes, i) && seen > 0usize {
                row_counts[current] += 1usize
                row_cells = 0usize
            } else if str.eq(name, "tc") && !inside_cell(nodes, i) && seen > 0usize {
                row_cells += 1usize
                if row_cells > column_counts[current] { column_counts[current] = row_cells }
            }
        }
        i += 1usize
    }
    t = 0usize
    while t < table_count {
        var rows = row_counts[t]
        var columns = column_counts[t]
        if rows > LIMIT_GRID_ROWS { rows = LIMIT_GRID_ROWS }
        if columns > LIMIT_GRID_COLUMNS { columns = LIMIT_GRID_COLUMNS }
        let (cells, cells_error) = mem.alloc[str](a, rows * columns + 1usize)
        if cells_error != ok { ret (zero, cells_error) }
        var c = 0usize
        while c < rows * columns {
            cells[c] = ""
            c += 1usize
        }
        out[t] = Grid { rows: rows, columns: columns, cells: cells, after: afters[t] }
        t += 1usize
    }
    // Pass 2: the text of each cell into its place.
    current = 0usize
    seen = 0usize
    var row = 0usize
    var column = 0usize
    var live = false
    var in_row = false
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element {
            let name = local(nodes[i].name)
            if str.eq(name, "tbl") && !inside_cell(nodes, i) {
                current = seen
                seen += 1usize
                row = 0usize
                column = 0usize
                in_row = false
                live = false
            } else if str.eq(name, "tr") && !inside_cell(nodes, i) && seen > 0usize {
                if in_row { row += 1usize }
                in_row = true
                column = 0usize
                live = false
            } else if str.eq(name, "tc") && !inside_cell(nodes, i) && seen > 0usize {
                live = row < out[current].rows && column < out[current].columns
                column += 1usize
            } else if str.eq(name, "p") && live && seen > 0usize && inside_cell(nodes, i) {
                let at_cell = row * out[current].columns + (column - 1usize)
                if out[current].cells[at_cell].len > 0usize {
                    let (joined, joined_error) = str.concat(a, out[current].cells[at_cell], " ")
                    if joined_error != ok { ret (zero, joined_error) }
                    out[current].cells[at_cell] = joined
                }
            }
        } else if nodes[i].kind == .Text && live && seen > 0usize && inside_cell(nodes, i) && usize(nodes[i].parent) < nodes.len && str.eq(local(nodes[usize(nodes[i].parent)].name), "t") && column > 0usize {
            let at_cell = row * out[current].columns + (column - 1usize)
            let (joined, joined_error) = str.concat(a, out[current].cells[at_cell], nodes[i].value)
            if joined_error != ok { ret (zero, joined_error) }
            out[current].cells[at_cell] = joined
        }
        i += 1usize
    }
    ret (out[0usize..table_count], ok)
}

// Whether node `i` has a `tc` element among its ancestors (a table nested in a cell).
fn inside_cell(nodes: []const xml.Node, i: usize) -> bool {
    var up = usize(nodes[i].parent)
    var steps = 0usize
    while up < nodes.len && steps < 64usize {
        if nodes[up].kind == .Element && str.eq(local(nodes[up].name), "tc") { ret true }
        up = usize(nodes[up].parent)
        steps += 1usize
    }
    ret false
}

// For each paragraph `paragraphs` gives (the same order), whether it sits in a table cell: a viewer that lays the
// `tables` out itself leaves those out of the text.
fn cell_flags(a: *mem.Arena, data: []const u8) -> ([]bool, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = find(&ar, "word/document.xml")
    if !found { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "p") { count += 1usize }
        i += 1usize
    }
    let (flags, flags_error) = mem.alloc[bool](a, count + 1usize)
    if flags_error != ok { ret (zero, flags_error) }
    var k = 0usize
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "p") {
            flags[k] = inside_cell(nodes, i)
            k += 1usize
        }
        i += 1usize
    }
    ret (flags[0usize..count], ok)
}

// ---- Pictures and shapes (D4802): the images of a Word document and the shapes of a slide.

// An image: the paragraph it sits in (an index into `paragraphs`; 0 for a slide's), the size it is drawn at in EMU
// (914400 to the inch; 0 when the part gives none), its part name and its bytes (a PNG or JPEG as stored).
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

// The part name `dest` stands for in a relationship of a part in directory `base` (`word/`, `ppt/slides/`): an
// absolute dest loses its slash, each `../` goes up a directory.
fn resolve_target(a: *mem.Arena, base: str, dest: str) -> str {
    if dest.len > 0usize && dest[0usize] == 47u8 { ret dest[1usize..dest.len] }
    var dir = base
    var rest = dest
    while rest.len >= 3usize && rest[0usize] == 46u8 && rest[1usize] == 46u8 && rest[2usize] == 47u8 {
        rest = rest[3usize..rest.len]
        // Drop the last directory of `dir` (which ends with a slash).
        var cut = dir.len
        if cut > 0usize { cut -= 1usize }
        while cut > 0usize && dir[cut - 1usize] != 47u8 { cut -= 1usize }
        dir = dir[0usize..cut]
    }
    var out = ""
    let (builder, builder_error) = str.builder(a, dir.len + rest.len + 1usize)
    if builder_error != ok { ret rest }
    var b = builder
    let first = str.push(&b, dir)
    let second = str.push(&b, rest)
    out = str.done(&b)
    ret out
}

// The dest of relationship `id` in the relationships part `rels_name`, resolved against `base`; "" when there is none.
fn related_part(a: *mem.Arena, ar: *zip.Archive, rels_name: str, base: str, id: str) -> str {
    let (index, found) = find(ar, rels_name)
    if !found { ret "" }
    let (part, extract_error) = zip.extract(a, ar, index)
    if extract_error != ok { ret "" }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret "" }
    let nodes = doc.nodes
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "Relationship") {
            let (rid, has_id) = xml.attribute(&nodes[i], "Id")
            let (dest, has_dest) = xml.attribute(&nodes[i], "Target")
            if has_id && has_dest && str.eq(rid, id) { ret resolve_target(a, base, dest) }
        }
        i += 1usize
    }
    ret ""
}

// The bytes of the part called `name`, empty when there is none or it is over LIMIT_PICTURE.
fn part_bytes(a: *mem.Arena, ar: *zip.Archive, name: str) -> []const u8 {
    let (index, found) = find(ar, name)
    if !found { ret "" }
    let listed = zip.entries(ar)
    if listed[index].size > LIMIT_PICTURE { ret "" }
    let (bytes, extract_error) = zip.extract(a, ar, index)
    if extract_error != ok { ret "" }
    ret bytes
}

fn number_attribute(node: *const xml.Node, name: str) -> usize {
    let (text, has) = xml.attribute(node, name)
    if !has { ret 0usize }
    let (value, parse_error) = str.parse_u64(text)
    if parse_error != ok { ret 0usize }
    ret usize(value)
}

// The pictures of a `.docx` (up to LIMIT_PICTURES, each at most 256 KB) with the paragraph each sits in and the
// size its `wp:extent` gives, read through `word/_rels/document.xml.rels`.
fn pictures(a: *mem.Arena, data: []const u8) -> ([]Picture, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = find(&ar, "word/document.xml")
    if !found { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    let (out, out_error) = mem.alloc[Picture](a, LIMIT_PICTURES)
    if out_error != ok { ret (zero, out_error) }
    var n = 0usize
    var paragraph = 0usize
    var seen_paragraphs = 0usize
    var cx = 0usize
    var cy = 0usize
    var i = 0usize
    while i < nodes.len && n < LIMIT_PICTURES {
        if nodes[i].kind == .Element {
            let name = local(nodes[i].name)
            if str.eq(name, "p") {
                paragraph = seen_paragraphs
                seen_paragraphs += 1usize
            }
            if str.eq(name, "extent") {
                cx = number_attribute(&nodes[i], "cx")
                cy = number_attribute(&nodes[i], "cy")
            }
            if str.eq(name, "blip") {
                let (rid, has_rid) = xml.attribute(&nodes[i], "r:embed")
                if has_rid {
                    let dest = related_part(a, &ar, "word/_rels/document.xml.rels", "word/", rid)
                    if dest.len > 0usize {
                        let bytes = part_bytes(a, &ar, dest)
                        if bytes.len > 0usize {
                            out[n] = Picture { paragraph: paragraph, cx: cx, cy: cy, name: dest, data: bytes }
                            n += 1usize
                        }
                    }
                }
            }
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// One shape of a slide: its kind, position and size in EMU, the fill (`NO_COLOR` for none), its text (paragraphs
// joined by a newline) and, for a picture, the index into `SlideLayout.pictures`.
type SlideShape = struct { kind: u8, x: usize, y: usize, cx: usize, cy: usize, fill: u32, text: str, picture: usize }
type SlideLayout = struct { width: usize, height: usize, shapes: []SlideShape, pictures: []Picture }

fn hex_digit(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c - 48u8) }
    if c >= 65u8 && c <= 70u8 { ret u32(c - 55u8) }
    if c >= 97u8 && c <= 102u8 { ret u32(c - 87u8) }
    ret 0u32
}

fn has_ancestor(nodes: []const xml.Node, n: usize, name: str) -> bool {
    var at = usize(nodes[n].parent)
    var guard = 0usize
    while at < nodes.len && guard < 64usize {
        if nodes[at].kind == .Element && str.eq(local(nodes[at].name), name) { ret true }
        if usize(nodes[at].parent) == at { ret false }
        at = usize(nodes[at].parent)
        guard += 1usize
    }
    ret false
}

// Whether node `n` is inside (a descendant of) element `root`.
fn within(nodes: []const xml.Node, n: usize, root: usize) -> bool {
    var at = n
    var guard = 0usize
    while at < nodes.len && guard < 64usize {
        if at == root { ret true }
        if usize(nodes[at].parent) == at { ret false }
        at = usize(nodes[at].parent)
        guard += 1usize
    }
    ret false
}

// The layout of slide `number` (from 1, in slide-number order) of a `.pptx`: the slide size from
// `ppt/presentation.xml` (default 9144000 by 6858000), and its `sp` shapes (a rectangle, ellipse or line by its
// `prstGeom`), `pic` pictures and `cxnSp` connectors with their offsets, extents, solid fills and text. Groups are not
// transformed: a shape in a group is placed as if the group were the slide.
fn slide_layout(a: *mem.Arena, data: []const u8, number: usize) -> (SlideLayout, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let listed = zip.entries(&ar)
    var part_index = 0usize
    var part_number = 0usize
    var seen = 0usize
    var want = 1usize
    var located = false
    while !located && want < 10000usize && seen < number {
        var j = 0usize
        while j < listed.len {
            if slide_number(listed[j].name) == want {
                seen += 1usize
                if seen == number {
                    part_index = j
                    part_number = want
                    located = true
                }
            }
            j += 1usize
        }
        want += 1usize
    }
    if !located { ret (zero, NoMainPart) }
    var width = 9144000usize
    var height = 6858000usize
    let (pres_index, has_pres) = find(&ar, "ppt/presentation.xml")
    if has_pres {
        let (pres, pres_error) = zip.extract(a, &ar, pres_index)
        if pres_error == ok {
            let (pdoc, pdoc_error) = xml.parse(a, pres)
            if pdoc_error == ok {
                var k = 0usize
                while k < pdoc.nodes.len {
                    if pdoc.nodes[k].kind == .Element && str.eq(local(pdoc.nodes[k].name), "sldSz") {
                        let w = number_attribute(&pdoc.nodes[k], "cx")
                        let h = number_attribute(&pdoc.nodes[k], "cy")
                        if w > 0usize && h > 0usize {
                            width = w
                            height = h
                        }
                    }
                    k += 1usize
                }
            }
        }
    }
    let (part, extract_error) = zip.extract(a, &ar, part_index)
    if extract_error != ok { ret (zero, extract_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    let (shapes, shapes_error) = mem.alloc[SlideShape](a, LIMIT_SHAPES)
    if shapes_error != ok { ret (zero, shapes_error) }
    let (pics, pics_error) = mem.alloc[Picture](a, LIMIT_PICTURES)
    if pics_error != ok { ret (zero, pics_error) }
    var shape_n = 0usize
    var pic_n = 0usize
    let (rels_builder, rels_builder_error) = str.builder(a, 64usize)
    if rels_builder_error != ok { ret (zero, rels_builder_error) }
    var rb = rels_builder
    let r1 = str.push(&rb, "ppt/slides/_rels/slide")
    let r2 = str.push_usize(&rb, part_number)
    let r3 = str.push(&rb, ".xml.rels")
    let rels_name = str.done(&rb)
    var i = 0usize
    while i < nodes.len && shape_n < LIMIT_SHAPES {
        if nodes[i].kind == .Element {
            let name = local(nodes[i].name)
            let is_sp = str.eq(name, "sp")
            let is_pic = str.eq(name, "pic")
            let is_line = str.eq(name, "cxnSp")
            if (is_sp || is_pic || is_line) && !has_ancestor(nodes, i, "sp") && !has_ancestor(nodes, i, "pic") {
                var shape = SlideShape { kind: SHAPE_RECT, x: 0usize, y: 0usize, cx: 0usize, cy: 0usize, fill: NO_COLOR, text: "", picture: NO_PICTURE }
                if is_pic { shape.kind = SHAPE_PICTURE }
                if is_line { shape.kind = SHAPE_LINE }
                var got_ext = false
                var got_fill = false
                var k = i + 1usize
                while k < nodes.len && within(nodes, k, i) {
                    if nodes[k].kind == .Element {
                        let inner = local(nodes[k].name)
                        if str.eq(inner, "off") && !got_ext {
                            shape.x = number_attribute(&nodes[k], "x")
                            shape.y = number_attribute(&nodes[k], "y")
                        }
                        if str.eq(inner, "ext") && !got_ext {
                            let w = number_attribute(&nodes[k], "cx")
                            let h = number_attribute(&nodes[k], "cy")
                            if w > 0usize || h > 0usize {
                                shape.cx = w
                                shape.cy = h
                                got_ext = true
                            }
                        }
                        if str.eq(inner, "prstGeom") {
                            let (prst, has_prst) = xml.attribute(&nodes[k], "prst")
                            if has_prst && str.eq(prst, "ellipse") { shape.kind = SHAPE_ELLIPSE }
                            if has_prst && str.eq(prst, "line") { shape.kind = SHAPE_LINE }
                        }
                        if str.eq(inner, "srgbClr") && !got_fill && has_ancestor(nodes, k, "spPr") && !has_ancestor(nodes, k, "ln") && !has_ancestor(nodes, k, "txBody") {
                            let (hex, has_hex) = xml.attribute(&nodes[k], "val")
                            if has_hex && hex.len == 6usize {
                                var v = 0u32
                                var d = 0usize
                                while d < 6usize {
                                    v = v * 16u32 + hex_digit(hex[d])
                                    d += 1usize
                                }
                                shape.fill = v
                                got_fill = true
                            }
                        }
                        if str.eq(inner, "blip") && is_pic && pic_n < LIMIT_PICTURES {
                            let (rid, has_rid) = xml.attribute(&nodes[k], "r:embed")
                            if has_rid {
                                let dest = related_part(a, &ar, rels_name, "ppt/slides/", rid)
                                if dest.len > 0usize {
                                    let bytes = part_bytes(a, &ar, dest)
                                    if bytes.len > 0usize {
                                        pics[pic_n] = Picture { paragraph: 0usize, cx: shape.cx, cy: shape.cy, name: dest, data: bytes }
                                        shape.picture = pic_n
                                        pic_n += 1usize
                                    }
                                }
                            }
                        }
                    }
                    k += 1usize
                }
                // The text: every `t` under a txBody, a newline between paragraphs.
                var size = 0usize
                k = i + 1usize
                while k < nodes.len && within(nodes, k, i) {
                    if nodes[k].kind == .Text && usize(nodes[k].parent) < nodes.len && str.eq(local(nodes[usize(nodes[k].parent)].name), "t") { size += nodes[k].value.len + 1usize }
                    k += 1usize
                }
                if size > 0usize {
                    let (buffer, buffer_error) = mem.alloc[u8](a, size)
                    if buffer_error != ok { ret (zero, buffer_error) }
                    var at = 0usize
                    var last_paragraph = 99999999usize
                    k = i + 1usize
                    while k < nodes.len && within(nodes, k, i) {
                        if nodes[k].kind == .Text && usize(nodes[k].parent) < nodes.len && str.eq(local(nodes[usize(nodes[k].parent)].name), "t") {
                            // The paragraph element above this run: a change of it is a newline.
                            var up = usize(nodes[k].parent)
                            var guard = 0usize
                            while up < nodes.len && guard < 8usize && !(nodes[up].kind == .Element && str.eq(local(nodes[up].name), "p")) {
                                up = usize(nodes[up].parent)
                                guard += 1usize
                            }
                            if last_paragraph != 99999999usize && up != last_paragraph && at < size {
                                buffer[at] = 10u8
                                at += 1usize
                            }
                            last_paragraph = up
                            var c = 0usize
                            while c < nodes[k].value.len && at < size {
                                buffer[at] = nodes[k].value[c]
                                at += 1usize
                                c += 1usize
                            }
                        }
                        k += 1usize
                    }
                    shape.text = buffer[0usize..at]
                }
                shapes[shape_n] = shape
                shape_n += 1usize
            }
        }
        i += 1usize
    }
    ret (SlideLayout { width: width, height: height, shapes: shapes[0usize..shape_n], pictures: pics[0usize..pic_n] }, ok)
}
