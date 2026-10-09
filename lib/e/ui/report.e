// A banded report engine (D2282, L089): the layout half of QuickReport and FastReport. A `Report` is a page, a list of
// bands (report header, page header, group headers, detail, group footers, report footer, page footer) holding elements
// (text, line, rectangle) at positions relative to their band, a list of grouping fields, and a `Source` of rows. `layout`
// answers the pages: each a list of positioned primitives (`Item`s) in page coordinates, ready for a renderer or a print
// job. The engine owns what a report needs and a renderer does not: sorting rows into groups, expanding a text template
// (`[Field]`, `[Field:2]`, `[SUM(Field)]`, `[AVG(..)]`, `[MIN(..)]`, `[MAX(..)]`, `[COUNT()]`, `[ROW]`, `[PAGE]`, `[PAGES]`,
// `[[` for a bracket), wrapping text in its box and growing the band to hold it, and pagination: page header and footer on
// every page, a group's header kept with its first detail, a group kept together on one page when it fits on one,
// a page break before a group, group headers repeated when a group runs onto a new page, `[PAGES]` settled by laying out
// again until the count holds still. Text is measured through a `Measure`, so a real font can stand behind it; `fixed_pitch`
// is a stand-in with a fixed character width. Lines are `size * 1.25` tall. Left out: images, sub-reports, columns of
// detail, page-number formats, and printing and PDF (a page list is what a print job takes).

use e.mem

type Cell = struct { text: str, number: f64, numeric: bool }
type Source = struct { columns: []const str, cells: []const Cell, rows: usize }
type Align = enum u8 { Left, Center, Right }
type ElementKind = enum u8 { Text, Line, Rect }
type Element = struct { kind: ElementKind, x: f32, y: f32, width: f32, height: f32, text: str, size: f32, bold: bool, align: Align, border: bool, grow: bool }
type BandKind = enum u8 { ReportHeader, PageHeader, GroupHeader, Detail, GroupFooter, ReportFooter, PageFooter }
type Band = struct { kind: BandKind, height: f32, elements: []const Element, level: usize, page_break_before: bool }
type Group = struct { field: str, keep_together: bool, repeat_header: bool }
type Report = struct {
    page_width: f32, page_height: f32, margin_left: f32, margin_top: f32, margin_right: f32, margin_bottom: f32,
    bands: []const Band, groups: []const Group, source: Source, sort: bool,
}
type Item = struct { kind: ElementKind, x: f32, y: f32, width: f32, height: f32, text: str, size: f32, bold: bool, align: Align }
type Page = struct { number: usize, items: []const Item }
type Layout = struct { pages: []const Page }
type Measure = struct { ctx: *void, wrap: fn(*void, str, f32, f32, bool, []str) -> usize }
type FixedPitch = struct { em: f32 }

error Invalid
error TooLarge

const MAX_LINES: usize = 64usize
const MAX_LEVELS: usize = 4usize

// ---- text measurement ----------------------------------------------------------------------------------

fn fixed_wrap(ctx: *void, text: str, size: f32, width: f32, bold: bool, out: []str) -> usize {
    let pitch = mem.cast[*FixedPitch](ctx)
    let cw = pitch.em * size
    var per_line = usize(width / cw)
    if per_line == 0usize { per_line = 1usize }
    var n = 0usize
    var p = 0usize
    while true {
        var q = p
        while q < text.len && text[q] != 10u8 { q += 1usize }
        n = wrap_paragraph(text[p..q], per_line, out, n)
        if q >= text.len { break }
        p = q + 1usize
    }
    ret n
}

fn emit_line(out: []str, n: usize, line: str) -> usize {
    if n < out.len && n < MAX_LINES { out[n] = line }
    ret n + 1usize
}

fn wrap_paragraph(para: str, per_line: usize, out: []str, start: usize) -> usize {
    var n = start
    if para.len == 0usize { ret emit_line(out, n, "") }
    var i = 0usize
    var line_start = para.len
    var has_line = false
    var line_end = 0usize
    var emitted = false
    while i < para.len {
        while i < para.len && para[i] == 32u8 { i += 1usize }
        if i >= para.len { break }
        var w_start = i
        while i < para.len && para[i] != 32u8 { i += 1usize }
        let w_end = i
        var wl = w_end - w_start
        while wl > per_line {
            if has_line {
                n = emit_line(out, n, para[line_start..line_end])
                emitted = true
                has_line = false
            }
            n = emit_line(out, n, para[w_start..w_start + per_line])
            emitted = true
            w_start += per_line
            wl -= per_line
        }
        if !has_line {
            line_start = w_start
            line_end = w_end
            has_line = true
        } else if w_end - line_start <= per_line {
            line_end = w_end
        } else {
            n = emit_line(out, n, para[line_start..line_end])
            emitted = true
            line_start = w_start
            line_end = w_end
        }
    }
    if has_line {
        n = emit_line(out, n, para[line_start..line_end])
        emitted = true
    }
    if !emitted { n = emit_line(out, n, "") }
    ret n
}

// A measure with a fixed character width of `em` times the size, wrapping words greedily and breaking a word longer
// than the line; the pitch outlives the measure.
fn fixed_pitch(pitch: *const FixedPitch) -> Measure {
    ret Measure { ctx: mem.cast[*void](pitch), wrap: fixed_wrap }
}

// ---- numbers and templates ------------------------------------------------------------------------------

fn pow10(d: usize) -> f64 {
    var v: f64 = 1.0
    var i = 0usize
    while i < d {
        v = v * 10.0
        i += 1usize
    }
    ret v
}

// `v` with `decimals` digits after the point, rounded half away from zero, no minus on a zero.
fn format_fixed(a: *mem.Arena, v: f64, decimals: usize) -> (str, err) {
    var negative = false
    var magnitude = v
    if magnitude < 0.0 {
        negative = true
        magnitude = 0.0 - magnitude
    }
    let scale = pow10(decimals)
    let scaled = u64(magnitude * scale + 0.5)
    if scaled == 0u64 { negative = false }
    var whole = scaled
    var fraction = 0u64
    if decimals > 0usize {
        whole = scaled / u64(scale)
        fraction = scaled % u64(scale)
    }
    let (buf, alloc_error) = mem.alloc[u8](a, 48usize)
    if alloc_error != ok { ret ("", TooLarge) }
    var digits: [24]u8 = zero
    var count = 0usize
    var rest = whole
    if rest == 0u64 {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0u64 {
        digits[count] = u8(48u64 + rest % 10u64)
        rest = rest / 10u64
        count += 1usize
    }
    var at = 0usize
    if negative {
        buf[at] = 45u8
        at += 1usize
    }
    while count > 0usize {
        count -= 1usize
        buf[at] = digits[count]
        at += 1usize
    }
    if decimals > 0usize {
        buf[at] = 46u8
        at += 1usize
        var k = decimals
        var frac_digits: [24]u8 = zero
        var f = fraction
        while k > 0usize {
            k -= 1usize
            frac_digits[k] = u8(48u64 + f % 10u64)
            f = f / 10u64
        }
        var j = 0usize
        while j < decimals {
            buf[at] = frac_digits[j]
            at += 1usize
            j += 1usize
        }
    }
    ret (buf[..at], ok)
}

fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn column_of(source: Source, name: str) -> (usize, bool) {
    var i = 0usize
    while i < source.columns.len {
        if same_text(source.columns[i], name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// What a template can see: the rows (in report order), the range an aggregate runs over, the row a plain field reads,
// the running row number, and the page numbers.
type Scope = struct { order: []const usize, lo: usize, hi: usize, row: usize, row_number: usize, page: usize, pages: usize }

fn cell_at(source: Source, order: []const usize, r: usize, column: usize) -> Cell {
    ret source.cells[order[r] * source.columns.len + column]
}

fn starts(text: str, prefix: str) -> bool {
    if text.len < prefix.len { ret false }
    ret same_text(text[..prefix.len], prefix)
}

fn parse_decimals(text: str, fallback: usize) -> usize {
    if text.len == 0usize { ret fallback }
    var v = 0usize
    var i = 0usize
    while i < text.len && text[i] >= 48u8 && text[i] <= 57u8 {
        v = v * 10usize + usize(text[i] - 48u8)
        i += 1usize
    }
    ret v
}

// One `[..]` expression's text.
fn expression(a: *mem.Arena, source: Source, scope: Scope, body: str) -> (str, err) {
    if same_text(body, "PAGE") {
        let (fixed_text, fixed_error) = format_fixed(a, f64(scope.page), 0usize)
        ret (fixed_text, fixed_error)
    }
    if same_text(body, "PAGES") {
        let (fixed_text, fixed_error) = format_fixed(a, f64(scope.pages), 0usize)
        ret (fixed_text, fixed_error)
    }
    if same_text(body, "ROW") {
        let (fixed_text, fixed_error) = format_fixed(a, f64(scope.row_number), 0usize)
        ret (fixed_text, fixed_error)
    }
    var function = ""
    var inner_from = 0usize
    var inner_to = 0usize
    var tail = ""
    if starts(body, "SUM(") { function = "SUM" } else if starts(body, "AVG(") { function = "AVG" } else if starts(body, "MIN(") { function = "MIN" } else if starts(body, "MAX(") { function = "MAX" } else if starts(body, "COUNT(") { function = "COUNT" }
    if function.len > 0usize {
        inner_from = function.len + 1usize
        inner_to = inner_from
        while inner_to < body.len && body[inner_to] != 41u8 { inner_to += 1usize }
        if inner_to < body.len && inner_to + 1usize < body.len && body[inner_to + 1usize] == 58u8 { tail = body[inner_to + 2usize..] }
        let field = body[inner_from..inner_to]
        let decimals = parse_decimals(tail, 2usize)
        if same_text(function, "COUNT") {
            if field.len == 0usize {
                let (fixed_text, fixed_error) = format_fixed(a, f64(scope.hi - scope.lo), 0usize)
                ret (fixed_text, fixed_error)
            }
            let (column, found) = column_of(source, field)
            var seen = 0usize
            if found {
                var r = scope.lo
                while r < scope.hi {
                    if cell_at(source, scope.order, r, column).text.len > 0usize { seen += 1usize }
                    r += 1usize
                }
            }
            let (fixed_text, fixed_error) = format_fixed(a, f64(seen), 0usize)
            ret (fixed_text, fixed_error)
        }
        let (column, found) = column_of(source, field)
        var total: f64 = 0.0
        var count = 0usize
        var low: f64 = 0.0
        var high: f64 = 0.0
        if found {
            var r = scope.lo
            while r < scope.hi {
                let cell = cell_at(source, scope.order, r, column)
                if cell.numeric {
                    if count == 0usize {
                        low = cell.number
                        high = cell.number
                    }
                    if cell.number < low { low = cell.number }
                    if cell.number > high { high = cell.number }
                    total = total + cell.number
                    count += 1usize
                }
                r += 1usize
            }
        }
        var value = total
        if same_text(function, "AVG") {
            value = 0.0
            if count > 0usize { value = total / f64(count) }
        }
        if same_text(function, "MIN") { value = low }
        if same_text(function, "MAX") { value = high }
        let (fixed_text, fixed_error) = format_fixed(a, value, decimals)
        ret (fixed_text, fixed_error)
    }
    // a field, with an optional `:decimals`
    var name = body
    var spec = ""
    var colon = 0usize
    while colon < body.len && body[colon] != 58u8 { colon += 1usize }
    if colon < body.len {
        name = body[..colon]
        spec = body[colon + 1usize..]
    }
    let (column, found) = column_of(source, name)
    if !found || scope.row >= scope.order.len { ret ("", ok) }
    let cell = cell_at(source, scope.order, scope.row, column)
    if cell.numeric && spec.len > 0usize {
        let (fixed_text, fixed_error) = format_fixed(a, cell.number, parse_decimals(spec, 2usize))
        ret (fixed_text, fixed_error)
    }
    ret (cell.text, ok)
}

fn expand(a: *mem.Arena, source: Source, scope: Scope, template: str) -> (str, err) {
    var has_bracket = false
    var i = 0usize
    while i < template.len {
        if template[i] == 91u8 { has_bracket = true }
        i += 1usize
    }
    if !has_bracket { ret (template, ok) }
    var out: []u8 = zero
    var used = 0usize
    var p = 0usize
    while p < template.len {
        if template[p] == 91u8 && p + 1usize < template.len && template[p + 1usize] == 91u8 {
            let (grown, grow_error) = grow_for(a, out, used, 1usize)
            if grow_error != ok { ret ("", grow_error) }
            out = grown
            out[used] = 91u8
            used += 1usize
            p += 2usize
            continue
        }
        if template[p] == 91u8 {
            var q = p + 1usize
            while q < template.len && template[q] != 93u8 { q += 1usize }
            if q >= template.len { ret ("", Invalid) }
            let (text, text_error) = expression(a, source, scope, template[p + 1usize..q])
            if text_error != ok { ret ("", text_error) }
            let (grown, grow_error) = grow_for(a, out, used, text.len)
            if grow_error != ok { ret ("", grow_error) }
            out = grown
            mem.copy[u8](out[used..], text)
            used += text.len
            p = q + 1usize
            continue
        }
        let (grown, grow_error) = grow_for(a, out, used, 1usize)
        if grow_error != ok { ret ("", grow_error) }
        out = grown
        out[used] = template[p]
        used += 1usize
        p += 1usize
    }
    ret (out[..used], ok)
}

fn grow_for(a: *mem.Arena, buf: []u8, used: usize, extra: usize) -> ([]u8, err) {
    if used + extra <= buf.len { ret (buf, ok) }
    var size = buf.len * 2usize
    if size < 64usize { size = 64usize }
    while size < used + extra { size *= 2usize }
    let (bigger, alloc_error) = mem.alloc[u8](a, size)
    if alloc_error != ok { ret (buf, TooLarge) }
    mem.copy[u8](bigger, buf[..used])
    ret (bigger, ok)
}

// ---- the layout -----------------------------------------------------------------------------------------

type Run = struct {
    a: *mem.Arena, r: *const Report, measure: Measure, order: []usize, pages_total: usize,
    pages: []Page, page_count: usize, items: []Item, item_count: usize, page_no: usize,
    y: f32, content_top: f32, bottom: f32, page_header: usize, page_footer: usize, has_header: bool, has_footer: bool,
    cur_row: usize, open_levels: usize, row_number: usize, starts: []usize, ends: []usize, stride: usize, key_columns: [4]usize, reserved: f32,
}

// Stable merge sort of `order[lo..hi]` by the group key columns, comparing the key texts level by level.
fn sort_rows(r: *const Report, order: []usize, scratch: []usize, columns: [4]usize, lo: usize, hi: usize) {
    if hi - lo < 2usize { ret }
    let mid = lo + (hi - lo) / 2usize
    sort_rows(r, order, scratch, columns, lo, mid)
    sort_rows(r, order, scratch, columns, mid, hi)
    var i = lo
    var j = mid
    var k = lo
    while i < mid && j < hi {
        if row_before(r, order[j], order[i], columns) {
            scratch[k] = order[j]
            j += 1usize
        } else {
            scratch[k] = order[i]
            i += 1usize
        }
        k += 1usize
    }
    while i < mid {
        scratch[k] = order[i]
        i += 1usize
        k += 1usize
    }
    while j < hi {
        scratch[k] = order[j]
        j += 1usize
        k += 1usize
    }
    var m = lo
    while m < hi {
        order[m] = scratch[m]
        m += 1usize
    }
}

fn text_before(x: str, y: str) -> bool {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] { ret x[i] < y[i] }
        i += 1usize
    }
    ret x.len < y.len
}

// Whether source row `p` sorts before source row `q`.
fn row_before(r: *const Report, p: usize, q: usize, columns: [4]usize) -> bool {
    var level = 0usize
    while level < r.groups.len {
        let x = r.source.cells[p * r.source.columns.len + columns[level]].text
        let y = r.source.cells[q * r.source.columns.len + columns[level]].text
        if !same_text(x, y) { ret text_before(x, y) }
        level += 1usize
    }
    ret false
}

type Placed = struct { height: f32, count: usize }

// Materialise a band: expand and wrap its elements for `scope`, answer its height, and, when `into` is set, append the
// items at (`left`, `top`) in page coordinates.
fn materialise(run: *Run, band: *const Band, scope: Scope, left: f32, top: f32, into: bool) -> (f32, err) {
    var height = band.height
    var e = 0usize
    while e < band.elements.len {
        let el = &band.elements[e]
        if el.kind == .Text {
            let (text, text_error) = expand(run.a, run.r.source, scope, el.text)
            if text_error != ok { ret (0.0, text_error) }
            var lines: [64]str = zero
            let count = run.measure.wrap(run.measure.ctx, text, el.size, el.width, el.bold, lines[0usize..64usize])
            var shown = count
            if shown > MAX_LINES { shown = MAX_LINES }
            let line_height = el.size * 1.25
            if !el.grow {
                var fits = usize(el.height / line_height)
                if fits == 0usize { fits = 1usize }
                if shown > fits { shown = fits }
            } else {
                let needed = el.y + f32(shown) * line_height
                if needed > height { height = needed }
            }
            if into {
                if el.border {
                    var box_height = el.height
                    if el.grow {
                        let grown = f32(shown) * line_height
                        if grown > box_height { box_height = grown }
                    }
                    try push_item(run, Item { kind: .Rect, x: left + el.x, y: top + el.y, width: el.width, height: box_height, text: "", size: 0.0, bold: false, align: .Left })
                }
                var l = 0usize
                while l < shown {
                    try push_item(run, Item { kind: .Text, x: left + el.x, y: top + el.y + f32(l) * line_height, width: el.width, height: line_height, text: lines[l], size: el.size, bold: el.bold, align: el.align })
                    l += 1usize
                }
            }
        } else if into {
            try push_item(run, Item { kind: el.kind, x: left + el.x, y: top + el.y, width: el.width, height: el.height, text: "", size: 0.0, bold: false, align: .Left })
        }
        e += 1usize
    }
    ret (height, ok)
}

fn push_item(run: *Run, item: Item) -> err {
    if run.item_count >= run.items.len {
        var size = run.items.len * 2usize
        if size < 64usize { size = 64usize }
        let (bigger, alloc_error) = mem.alloc[Item](run.a, size)
        if alloc_error != ok { ret TooLarge }
        var k = 0usize
        while k < run.item_count {
            bigger[k] = run.items[k]
            k += 1usize
        }
        run.items = bigger
    }
    run.items[run.item_count] = item
    run.item_count += 1usize
    ret ok
}

fn scope_all(run: *Run) -> Scope {
    ret Scope { order: run.order, lo: 0usize, hi: run.order.len, row: run.cur_row, row_number: run.row_number, page: run.page_no, pages: run.pages_total }
}

// The scope of a band of `kind` at `level` for row `row`: a group band reads its group's rows, a detail band its one row,
// the rest read every row.
fn scope_for(run: *Run, kind: BandKind, level: usize, row: usize) -> Scope {
    var s = scope_all(run)
    s.row = row
    if kind == .GroupHeader || kind == .GroupFooter {
        s.lo = run.starts[level * run.stride + row]
        s.hi = run.ends[level * run.stride + row]
    }
    if kind == .Detail {
        s.lo = row
        s.hi = row + 1usize
    }
    ret s
}

fn page_left(run: *Run) -> f32 { ret run.r.margin_left }

fn begin_page(run: *Run) -> err {
    run.page_no += 1usize
    run.item_count = 0usize
    run.content_top = run.r.margin_top
    run.bottom = run.r.page_height - run.r.margin_bottom
    if run.has_footer { run.bottom -= run.r.bands[run.page_footer].height }
    if run.has_header {
        let band = &run.r.bands[run.page_header]
        let (h, h_error) = materialise(run, band, scope_for(run, .PageHeader, 0usize, run.cur_row), page_left(run), run.r.margin_top, true)
        if h_error != ok { ret h_error }
        run.content_top += band.height
    }
    run.y = run.content_top
    ret ok
}

fn end_page(run: *Run) -> err {
    if run.has_footer {
        let band = &run.r.bands[run.page_footer]
        let top = run.r.page_height - run.r.margin_bottom - band.height
        let (h, h_error) = materialise(run, band, scope_for(run, .PageFooter, 0usize, run.cur_row), page_left(run), top, true)
        if h_error != ok { ret h_error }
    }
    let (kept, alloc_error) = mem.alloc[Item](run.a, run.item_count + 1usize)
    if alloc_error != ok { ret TooLarge }
    mem.copy[Item](kept, run.items[..run.item_count])
    if run.page_count >= run.pages.len {
        var size = run.pages.len * 2usize
        if size < 8usize { size = 8usize }
        let (bigger, pages_error) = mem.alloc[Page](run.a, size)
        if pages_error != ok { ret TooLarge }
        var k = 0usize
        while k < run.page_count {
            bigger[k] = run.pages[k]
            k += 1usize
        }
        run.pages = bigger
    }
    run.pages[run.page_count] = Page { number: run.page_no, items: kept[..run.item_count] }
    run.page_count += 1usize
    ret ok
}

// The group-header bands of `level`, in order, are emitted again at the top of a continued page.
fn repeat_headers(run: *Run) -> err {
    var level = 0usize
    while level < run.open_levels && level < run.r.groups.len {
        if run.r.groups[level].repeat_header {
            var b = 0usize
            while b < run.r.bands.len {
                let band = &run.r.bands[b]
                if band.kind == .GroupHeader && band.level == level {
                    let (h, h_error) = materialise(run, band, scope_for(run, .GroupHeader, level, run.cur_row), page_left(run), run.y, true)
                    if h_error != ok { ret h_error }
                    run.y += h
                }
                b += 1usize
            }
        }
        level += 1usize
    }
    ret ok
}

// Start a new page; with `repeat` the open groups' repeating headers follow the page header.
fn break_page(run: *Run, repeat: bool) -> err {
    try end_page(run)
    try begin_page(run)
    if repeat { try repeat_headers(run) }
    ret ok
}

// Place one band instance, breaking the page first when it does not fit and the page is not empty.
fn place(run: *Run, band: *const Band, scope: Scope, repeat: bool) -> err {
    let (h, h_error) = materialise(run, band, scope, page_left(run), run.y, false)
    if h_error != ok { ret h_error }
    if run.y + h > run.bottom && run.y > run.content_top { try break_page(run, repeat) }
    let (placed, placed_error) = materialise(run, band, scope, page_left(run), run.y, true)
    if placed_error != ok { ret placed_error }
    run.y += placed
    ret ok
}

fn bands_height(run: *Run, kind: BandKind, level: usize, row: usize) -> (f32, err) {
    var total: f32 = 0.0
    var b = 0usize
    while b < run.r.bands.len {
        let band = &run.r.bands[b]
        if band.kind == kind && (kind == .Detail || band.level == level) {
            let (h, h_error) = materialise(run, band, scope_for(run, kind, level, row), 0.0, 0.0, false)
            if h_error != ok { ret (0.0, h_error) }
            total += h
        }
        b += 1usize
    }
    ret (total, ok)
}

// The height of the group of `level` that starts at `row`: its header bands, its body, its footer bands.
fn group_height(run: *Run, level: usize, row: usize) -> (f32, err) {
    let (head, head_error) = bands_height(run, .GroupHeader, level, row)
    if head_error != ok { ret (0.0, head_error) }
    var total = head
    let end = run.ends[level * run.stride + row]
    var r = row
    if level + 1usize >= run.r.groups.len {
        while r < end {
            let (h, h_error) = bands_height(run, .Detail, 0usize, r)
            if h_error != ok { ret (0.0, h_error) }
            total += h
            r += 1usize
        }
    } else {
        while r < end {
            let (inner, inner_error) = group_height(run, level + 1usize, r)
            if inner_error != ok { ret (0.0, inner_error) }
            total += inner
            r = run.ends[(level + 1usize) * run.stride + r]
        }
    }
    let (foot, foot_error) = bands_height(run, .GroupFooter, level, end - 1usize)
    if foot_error != ok { ret (0.0, foot_error) }
    ret (total + foot, ok)
}

fn emit_kind(run: *Run, kind: BandKind, level: usize, row: usize, repeat: bool) -> err {
    var b = 0usize
    while b < run.r.bands.len {
        let band = &run.r.bands[b]
        if band.kind == kind && (kind == .Detail || kind == .ReportHeader || kind == .ReportFooter || band.level == level) {
            run.cur_row = row
            try place(run, band, scope_for(run, kind, level, row), repeat)
        }
        b += 1usize
    }
    ret ok
}

fn run_once(run: *Run) -> err {
    let r = run.r
    let n = run.order.len
    let g = r.groups.len
    run.page_no = 0usize
    run.page_count = 0usize
    run.item_count = 0usize
    run.open_levels = 0usize
    run.row_number = 0usize
    run.cur_row = 0usize
    try begin_page(run)
    try emit_kind(run, .ReportHeader, 0usize, 0usize, false)
    var i = 0usize
    while i < n {
        run.cur_row = i
        var level = 0usize
        if i > 0usize {
            level = g
            var l = 0usize
            while l < g {
                if !same_text(cell_at(r.source, run.order, i, run.key_columns[l]).text, cell_at(r.source, run.order, i - 1usize, run.key_columns[l]).text) {
                    level = l
                    break
                }
                l += 1usize
            }
        }
        if i > 0usize && level < g {
            var close = g
            while close > level {
                close -= 1usize
                try emit_kind(run, .GroupFooter, close, i - 1usize, true)
                run.open_levels = close
            }
        }
        if level < g {
            // page breaks asked for before the new groups, and keeping each with its first detail or all together
            var lvl = level
            while lvl < g {
                var wants_break = false
                var b = 0usize
                while b < r.bands.len {
                    if r.bands[b].kind == .GroupHeader && r.bands[b].level == lvl && r.bands[b].page_break_before { wants_break = true }
                    b += 1usize
                }
                if wants_break && run.y > run.content_top {
                    try break_page(run, false)
                }
                lvl += 1usize
            }
            // keep the new headers with the first detail
            var head_total: f32 = 0.0
            lvl = level
            while lvl < g {
                let (h, h_error) = bands_height(run, .GroupHeader, lvl, i)
                if h_error != ok { ret h_error }
                head_total += h
                lvl += 1usize
            }
            let (first, first_error) = bands_height(run, .Detail, 0usize, i)
            if first_error != ok { ret first_error }
            if run.y + head_total + first > run.bottom && run.y > run.content_top { try break_page(run, false) }
            // keep a group together when it fits on a page of its own
            lvl = level
            while lvl < g {
                if r.groups[lvl].keep_together {
                    let (whole, whole_error) = group_height(run, lvl, i)
                    if whole_error != ok { ret whole_error }
                    let page_room = run.r.page_height - run.r.margin_bottom - run.r.margin_top - run.reserved
                    if run.y + whole > run.bottom && whole <= page_room && run.y > run.content_top {
                        try break_page(run, false)
                        break
                    }
                }
                lvl += 1usize
            }
            lvl = level
            while lvl < g {
                try emit_kind(run, .GroupHeader, lvl, i, true)
                run.open_levels = lvl + 1usize
                lvl += 1usize
            }
        }
        run.row_number += 1usize
        try emit_kind(run, .Detail, 0usize, i, true)
        i += 1usize
    }
    if n > 0usize {
        var close = g
        while close > 0usize {
            close -= 1usize
            try emit_kind(run, .GroupFooter, close, n - 1usize, true)
            run.open_levels = close
        }
    }
    var last = 0usize
    if n > 0usize { last = n - 1usize }
    try emit_kind(run, .ReportFooter, 0usize, last, true)
    ret end_page(run)
}

// The pages of `report`, text measured by `measure`. Rows are sorted by the group fields first when `report.sort` is set (a
// stable sort, key texts compared byte by byte, group by group); otherwise they must already be in group order. A band
// whose `level` is not a group, more than four groups, an unknown group field or an empty page is `Invalid`.
fn layout(a: *mem.Arena, report: *const Report, measure: Measure) -> (Layout, err) {
    var none = Layout { pages: zero }
    if report.page_width <= 0.0 || report.page_height <= 0.0 || report.groups.len > MAX_LEVELS { ret (none, Invalid) }
    if report.margin_left + report.margin_right >= report.page_width || report.margin_top + report.margin_bottom >= report.page_height { ret (none, Invalid) }
    if report.source.cells.len != report.source.rows * report.source.columns.len { ret (none, Invalid) }
    var columns: [4]usize = zero
    var level = 0usize
    while level < report.groups.len {
        let (column, found) = column_of(report.source, report.groups[level].field)
        if !found { ret (none, Invalid) }
        columns[level] = column
        level += 1usize
    }
    var page_header = 0usize
    var page_footer = 0usize
    var has_header = false
    var has_footer = false
    var b = 0usize
    while b < report.bands.len {
        let band = &report.bands[b]
        if (band.kind == .GroupHeader || band.kind == .GroupFooter) && band.level >= report.groups.len { ret (none, Invalid) }
        if band.kind == .PageHeader && !has_header {
            page_header = b
            has_header = true
        }
        if band.kind == .PageFooter && !has_footer {
            page_footer = b
            has_footer = true
        }
        b += 1usize
    }
    let n = report.source.rows
    let (order, order_error) = mem.alloc[usize](a, n + 1usize)
    if order_error != ok { ret (none, TooLarge) }
    var r = 0usize
    while r < n {
        order[r] = r
        r += 1usize
    }
    if report.sort && report.groups.len > 0usize {
        let (scratch, scratch_error) = mem.alloc[usize](a, n + 1usize)
        if scratch_error != ok { ret (none, TooLarge) }
        sort_rows(report, order[..n], scratch, columns, 0usize, n)
    }
    var run = Run {
        a: a, r: report, measure: measure, order: order[..n], pages_total: 0usize, pages: zero, page_count: 0usize, items: zero, item_count: 0usize,
        page_no: 0usize, y: 0.0, content_top: 0.0, bottom: 0.0, page_header: page_header, page_footer: page_footer, has_header: has_header,
        has_footer: has_footer, cur_row: 0usize, open_levels: 0usize, row_number: 0usize, starts: zero, ends: zero, stride: n + 1usize, key_columns: columns, reserved: 0.0,
    }
    if has_header { run.reserved += report.bands[page_header].height }
    if has_footer { run.reserved += report.bands[page_footer].height }
    // each row's group at each level: where it starts and where it ends
    let (all_starts, all_starts_error) = mem.alloc[usize](a, (report.groups.len + 1usize) * (n + 1usize))
    if all_starts_error != ok { ret (none, TooLarge) }
    let (all_ends, all_ends_error) = mem.alloc[usize](a, (report.groups.len + 1usize) * (n + 1usize))
    if all_ends_error != ok { ret (none, TooLarge) }
    run.starts = all_starts
    run.ends = all_ends
    level = 0usize
    while level < report.groups.len {
        var i = 0usize
        var begin = 0usize
        while i < n {
            var boundary = i == 0usize
            if !boundary {
                var k = 0usize
                while k <= level {
                    if !same_text(cell_at(report.source, run.order, i, columns[k]).text, cell_at(report.source, run.order, i - 1usize, columns[k]).text) { boundary = true }
                    k += 1usize
                }
            }
            if boundary { begin = i }
            run.starts[level * run.stride + i] = begin
            i += 1usize
        }
        var stop = n
        i = n
        while i > 0usize {
            i -= 1usize
            var boundary_after = i + 1usize == n
            if !boundary_after {
                var k = 0usize
                while k <= level {
                    if !same_text(cell_at(report.source, run.order, i + 1usize, columns[k]).text, cell_at(report.source, run.order, i, columns[k]).text) { boundary_after = true }
                    k += 1usize
                }
            }
            if boundary_after { stop = i + 1usize }
            run.ends[level * run.stride + i] = stop
        }
        level += 1usize
    }
    // lay out again while the page count (read by [PAGES]) is still changing
    var pass = 0usize
    while pass < 4usize {
        let mark = mem.mark(a)
        var no_pages: []Page = zero
        var no_items: []Item = zero
        run.pages = no_pages
        run.items = no_items
        let status = run_once(&run)
        if status != ok { ret (none, status) }
        if run.page_count == run.pages_total || pass == 3usize { break }
        run.pages_total = run.page_count
        mem.reset(a, mark)
        pass += 1usize
    }
    ret (Layout { pages: run.pages[..run.page_count] }, ok)
}
