// Text out of OpenDocument packages (C142): the paragraphs of a text document (`.odt`) and the slides of a
// presentation (`.odp`), read over e.fmt.zip and e.fmt.xml from a byte slice, the way e.fmt.ooxml reads Office
// Open XML. A reader for what a viewer shows: the text of each `text:p` and `text:h` in order, the style name
// (a heading is `Heading<level>`), whether it sits in a list item, spaces (`text:s`), tabs and line breaks as the
// characters they are. Tables, frames and images are not laid out: the text inside them is a paragraph like any
// other, in document order. Namespace prefixes are ignored.
//
// Memory: every result lives in the arena passed in.
use e.mem
use e.str
use e.fmt.zip as zip
use e.fmt.xml as xml
use e.fmt.ooxml as ooxml

error NoContent

const NO_OWNER: usize = 4294967295usize
const MAX_SPACES: usize = 64usize

type Parsed = struct { texts: []str, styles: []str, lists: []bool, pages: []usize }

// The node's parent as an index into the node list, or NO_OWNER for the root.
fn parent_of(nodes: []const xml.Node, n: usize) -> usize {
    let p = usize(nodes[n].parent)
    if p < nodes.len && p < n { ret p }
    ret NO_OWNER
}

fn collect(a: *mem.Arena, part: []const u8) -> (Parsed, err) {
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    let (owner, owner_error) = mem.alloc[usize](a, nodes.len + 1usize)
    if owner_error != ok { ret (zero, owner_error) }
    let (in_list, in_list_error) = mem.alloc[bool](a, nodes.len + 1usize)
    if in_list_error != ok { ret (zero, in_list_error) }
    let (page_of, page_error) = mem.alloc[usize](a, nodes.len + 1usize)
    if page_error != ok { ret (zero, page_error) }
    // First pass: which paragraph each node belongs to, whether it is in a list, and which page.
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        let p = parent_of(nodes, i)
        owner[i] = NO_OWNER
        in_list[i] = false
        page_of[i] = NO_OWNER
        if p != NO_OWNER {
            owner[i] = owner[p]
            in_list[i] = in_list[p]
            page_of[i] = page_of[p]
        }
        if nodes[i].kind == .Element {
            let name = ooxml.local(nodes[i].name)
            if str.eq(name, "list-item") { in_list[i] = true }
            if str.eq(name, "page") { page_of[i] = i }
            if str.eq(name, "p") || str.eq(name, "h") {
                owner[i] = count
                count += 1usize
            }
        }
        i += 1usize
    }
    let (texts, texts_error) = mem.alloc[str](a, count + 1usize)
    if texts_error != ok { ret (zero, texts_error) }
    let (styles, styles_error) = mem.alloc[str](a, count + 1usize)
    if styles_error != ok { ret (zero, styles_error) }
    let (lists, lists_error) = mem.alloc[bool](a, count + 1usize)
    if lists_error != ok { ret (zero, lists_error) }
    let (pages, pages_error) = mem.alloc[usize](a, count + 1usize)
    if pages_error != ok { ret (zero, pages_error) }
    // Second pass: the size of each paragraph's text, then the text.
    let (sizes, sizes_error) = mem.alloc[usize](a, count + 1usize)
    if sizes_error != ok { ret (zero, sizes_error) }
    let (fill, fill_error) = mem.alloc[usize](a, count + 1usize)
    if fill_error != ok { ret (zero, fill_error) }
    var p = 0usize
    while p < count {
        sizes[p] = 0usize
        fill[p] = 0usize
        p += 1usize
    }
    i = 0usize
    while i < nodes.len {
        let o = owner[i]
        if o != NO_OWNER {
            if nodes[i].kind == .Text { sizes[o] += nodes[i].value.len }
            if nodes[i].kind == .Element {
                let name = ooxml.local(nodes[i].name)
                if str.eq(name, "s") { sizes[o] += MAX_SPACES }
                if str.eq(name, "tab") || str.eq(name, "line-break") { sizes[o] += 1usize }
            }
        }
        i += 1usize
    }
    // One buffer for all the text, each paragraph owning a run of it.
    var total = 0usize
    p = 0usize
    while p < count {
        let at = total
        total += sizes[p]
        sizes[p] = at
        p += 1usize
    }
    let (all, all_error) = mem.alloc[u8](a, total + 1usize)
    if all_error != ok { ret (zero, all_error) }
    p = 0usize
    while p < count {
        styles[p] = ""
        lists[p] = false
        pages[p] = NO_OWNER
        p += 1usize
    }
    i = 0usize
    while i < nodes.len {
        let o = owner[i]
        if o != NO_OWNER {
            if nodes[i].kind == .Text {
                var j = 0usize
                while j < nodes[i].value.len {
                    all[sizes[o] + fill[o]] = nodes[i].value[j]
                    fill[o] += 1usize
                    j += 1usize
                }
            }
            if nodes[i].kind == .Element {
                let name = ooxml.local(nodes[i].name)
                if str.eq(name, "tab") {
                    all[sizes[o] + fill[o]] = 9u8
                    fill[o] += 1usize
                }
                if str.eq(name, "line-break") {
                    all[sizes[o] + fill[o]] = 10u8
                    fill[o] += 1usize
                }
                if str.eq(name, "s") {
                    var spaces = 1usize
                    let (c_text, has_c) = xml.attribute(&nodes[i], "text:c")
                    if has_c {
                        var c = 0usize
                        var k = 0usize
                        while k < c_text.len && c_text[k] >= 48u8 && c_text[k] <= 57u8 && c < 1000usize {
                            c = c * 10usize + usize(c_text[k] - 48u8)
                            k += 1usize
                        }
                        if c > 0usize { spaces = c }
                    }
                    if spaces > MAX_SPACES { spaces = MAX_SPACES }
                    var k2 = 0usize
                    while k2 < spaces {
                        all[sizes[o] + fill[o]] = 32u8
                        fill[o] += 1usize
                        k2 += 1usize
                    }
                }
                if str.eq(name, "p") || str.eq(name, "h") {
                    var style = ""
                    let (named, has_named) = xml.attribute(&nodes[i], "text:style-name")
                    if has_named { style = named }
                    if str.eq(name, "h") {
                        let (level, has_level) = xml.attribute(&nodes[i], "text:outline-level")
                        if has_level { style = join(a, "Heading", level) } else { style = "Heading" }
                    }
                    styles[o] = style
                    lists[o] = in_list[i]
                    pages[o] = page_of[i]
                }
            }
        }
        i += 1usize
    }
    p = 0usize
    while p < count {
        texts[p] = all[sizes[p]..sizes[p] + fill[p]]
        p += 1usize
    }
    ret (Parsed { texts: texts[0usize..count], styles: styles[0usize..count], lists: lists[0usize..count], pages: pages[0usize..count] }, ok)
}

fn join(a: *mem.Arena, first: str, second: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + 1usize)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

// The content part of the package in `data`, as bytes.
fn content(a: *mem.Arena, data: []const u8) -> ([]const u8, err) {
    let (archive, open_error) = ooxml.open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = ooxml.find(&ar, "content.xml")
    if !found { ret (zero, NoContent) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    ret (part, ok)
}

// The paragraphs of an `.odt` (or the text of any OpenDocument file) held in `data`, in document order.
fn paragraphs(a: *mem.Arena, data: []const u8) -> ([]ooxml.Paragraph, err) {
    let (part, part_error) = content(a, data)
    if part_error != ok { ret (zero, part_error) }
    let (c, collect_error) = collect(a, part)
    if collect_error != ok { ret (zero, collect_error) }
    let (out, out_error) = mem.alloc[ooxml.Paragraph](a, c.texts.len + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var i = 0usize
    while i < c.texts.len {
        out[i] = ooxml.Paragraph { text: c.texts[i], style: c.styles[i], list: c.lists[i] }
        i += 1usize
    }
    ret (out[0usize..c.texts.len], ok)
}

// The slides of an `.odp` held in `data`: one per `draw:page`, in order, each with the paragraphs inside it.
fn slides(a: *mem.Arena, data: []const u8) -> ([]ooxml.Slide, err) {
    let (part, part_error) = content(a, data)
    if part_error != ok { ret (zero, part_error) }
    let (c, collect_error) = collect(a, part)
    if collect_error != ok { ret (zero, collect_error) }
    // The distinct pages, in order of first appearance.
    var total = 0usize
    var i = 0usize
    while i < c.pages.len {
        if c.pages[i] != NO_OWNER && (i == 0usize || c.pages[i] != c.pages[i - 1usize]) { total += 1usize }
        i += 1usize
    }
    if total == 0usize { ret (zero, NoContent) }
    let (out, out_error) = mem.alloc[ooxml.Slide](a, total)
    if out_error != ok { ret (zero, out_error) }
    var written = 0usize
    i = 0usize
    while i < c.pages.len {
        if c.pages[i] != NO_OWNER && (i == 0usize || c.pages[i] != c.pages[i - 1usize]) {
            var end = i
            while end < c.pages.len && c.pages[end] == c.pages[i] { end += 1usize }
            out[written] = ooxml.Slide { paragraphs: c.texts[i..end] }
            written += 1usize
            i = end
        } else {
            i += 1usize
        }
    }
    ret (out[0usize..written], ok)
}

// ---- A spreadsheet's sheet as a grid (D4803).

const LIMIT_GRID_ROWS: usize = 2000usize
const LIMIT_GRID_COLUMNS: usize = 64usize

fn odf_local(name: str) -> str {
    var i = name.len
    while i > 0usize {
        if name[i - 1usize] == 58u8 { ret name[i..name.len] }
        i -= 1usize
    }
    ret name
}

fn repeat_of(node: *const xml.Node, attribute: str) -> usize {
    let (text, has) = xml.attribute(node, attribute)
    if !has { ret 1usize }
    let (value, parse_error) = str.parse_u64(text)
    if parse_error != ok || value == 0u64 { ret 1usize }
    if value > 100000u64 { ret 100000usize }
    ret usize(value)
}

// Whether node `n` is inside element `root` (a descendant of it).
fn odf_within(nodes: []const xml.Node, n: usize, root: usize) -> bool {
    var at = n
    var guard = 0usize
    while at < nodes.len && guard < 64usize {
        if at == root { ret true }
        let up = parent_of(nodes, at)
        if up == NO_OWNER { ret false }
        at = up
        guard += 1usize
    }
    ret false
}

// Record a finished cell: its text into `cells` (when filling) over the repeats of its column and row, and the extent.
fn emit_cell(fill: bool, cells: []str, columns: usize, row: usize, column: usize, cell_repeat: usize, row_repeat: usize, text: str, max_rows: *usize, max_columns: *usize) {
    if text.len == 0usize { ret }
    var r = 0usize
    while r < cell_repeat && column + r < LIMIT_GRID_COLUMNS {
        var q = 0usize
        while q < row_repeat && row + q < LIMIT_GRID_ROWS {
            if fill && column + r < columns { cells[(row + q) * columns + column + r] = text }
            if row + q + 1usize > *max_rows { *max_rows = row + q + 1usize }
            q += 1usize
        }
        if column + r + 1usize > *max_columns { *max_columns = column + r + 1usize }
        r += 1usize
    }
}

// The `p` element a text node sits in (an index), or NO_OWNER.
fn paragraph_of(nodes: []const xml.Node, n: usize) -> usize {
    var at = parent_of(nodes, n)
    var guard = 0usize
    while at != NO_OWNER && guard < 8usize {
        if nodes[at].kind == .Element && str.eq(odf_local(nodes[at].name), "p") { ret at }
        at = parent_of(nodes, at)
        guard += 1usize
    }
    ret NO_OWNER
}

// One walk over a sheet's rows and cells: with `fill` false it measures (rows, columns written to the pointers); with
// `fill` true it writes each non-empty cell's text into `cells[row * columns + column]`.
fn walk_sheet(a: *mem.Arena, nodes: []const xml.Node, table: usize, fill: bool, cells: []str, columns: usize, rows_out: *usize, columns_out: *usize) {
    var row = 0usize
    var column = 0usize
    var row_repeat = 1usize
    var started = false
    var cell_repeat = 1usize
    var cell_text = ""
    var in_cell = false
    var last_paragraph = NO_OWNER
    var max_rows = 0usize
    var max_columns = 0usize
    var i = table + 1usize
    while i < nodes.len && odf_within(nodes, i, table) {
        if nodes[i].kind == .Element {
            let name = odf_local(nodes[i].name)
            let is_row = str.eq(name, "table-row")
            let is_cell = str.eq(name, "table-cell") || str.eq(name, "covered-table-cell")
            if is_row || is_cell {
                // The cell before is finished.
                if in_cell {
                    emit_cell(fill, cells, columns, row, column, cell_repeat, row_repeat, cell_text, &max_rows, &max_columns)
                    column += cell_repeat
                    in_cell = false
                }
            }
            if is_row {
                if started { row += row_repeat }
                started = true
                row_repeat = repeat_of(&nodes[i], "table:number-rows-repeated")
                column = 0usize
            } else if is_cell {
                in_cell = true
                cell_repeat = repeat_of(&nodes[i], "table:number-columns-repeated")
                cell_text = ""
                last_paragraph = NO_OWNER
                // A number, date or boolean with no text paragraph shows its attribute.
                let (value, has_value) = xml.attribute(&nodes[i], "office:value")
                if has_value { cell_text = value }
                let (date, has_date) = xml.attribute(&nodes[i], "office:date-value")
                if has_date { cell_text = date }
                let (flag, has_flag) = xml.attribute(&nodes[i], "office:boolean-value")
                if has_flag {
                    if str.eq(flag, "true") { cell_text = "TRUE" } else { cell_text = "FALSE" }
                }
            }
        }
        if in_cell && nodes[i].kind == .Text {
            let owner = paragraph_of(nodes, i)
            if owner != NO_OWNER {
                if last_paragraph == NO_OWNER {
                    cell_text = nodes[i].value
                } else if owner == last_paragraph {
                    cell_text = join(a, cell_text, nodes[i].value)
                } else {
                    cell_text = join(a, join(a, cell_text, " "), nodes[i].value)
                }
                last_paragraph = owner
            }
        }
        i += 1usize
    }
    if in_cell { emit_cell(fill, cells, columns, row, column, cell_repeat, row_repeat, cell_text, &max_rows, &max_columns) }
    *rows_out = max_rows
    *columns_out = max_columns
}

// Sheet `number` (from 1) of an `.ods` held in `data` as a grid of cell texts (the cell's paragraphs joined by a
// space, else its `office:value`, date or boolean), repeated rows and columns expanded, at most LIMIT_GRID_ROWS by
// LIMIT_GRID_COLUMNS; trailing empty rows and columns are not part of it. `NoContent` for a package with no such sheet.
fn sheet_grid(a: *mem.Arena, data: []const u8, number: usize) -> (ooxml.Grid, err) {
    let (part, part_error) = content(a, data)
    if part_error != ok { ret (zero, part_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    var seen = 0usize
    var table = NO_OWNER
    var i = 0usize
    while i < nodes.len && table == NO_OWNER {
        if nodes[i].kind == .Element && str.eq(odf_local(nodes[i].name), "table") {
            seen += 1usize
            if seen == number { table = i }
        }
        i += 1usize
    }
    if table == NO_OWNER { ret (zero, NoContent) }
    var rows = 0usize
    var columns = 0usize
    var none: [1]str = zero
    walk_sheet(a, nodes, table, false, none[0usize..0usize], 0usize, &rows, &columns)
    let (cells, cells_error) = mem.alloc[str](a, rows * columns + 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    var c = 0usize
    while c < rows * columns + 1usize {
        cells[c] = ""
        c += 1usize
    }
    var rows_again = 0usize
    var columns_again = 0usize
    walk_sheet(a, nodes, table, true, cells, columns, &rows_again, &columns_again)
    ret (ooxml.Grid { rows: rows, columns: columns, cells: cells, after: 0usize }, ok)
}

// The names of the sheets of an `.ods`, in order.
fn sheet_names(a: *mem.Arena, data: []const u8) -> ([]str, err) {
    let (part, part_error) = content(a, data)
    if part_error != ok { ret (zero, part_error) }
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(odf_local(nodes[i].name), "table") { count += 1usize }
        i += 1usize
    }
    let (names, names_error) = mem.alloc[str](a, count + 1usize)
    if names_error != ok { ret (zero, names_error) }
    var n = 0usize
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(odf_local(nodes[i].name), "table") {
            let (title, has_title) = xml.attribute(&nodes[i], "table:name")
            names[n] = ""
            if has_title { names[n] = title }
            n += 1usize
        }
        i += 1usize
    }
    ret (names[0usize..n], ok)
}
