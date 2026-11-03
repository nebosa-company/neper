// The Markdown viewer (e.ui.markdown_view), docs/ui/looks/<look>/markdown_view.png in all ten looks. The viewer itself is a
// model (a laid-out list of words, markers, rules, quote bars, code backs and table cells); this host is the minimal widget
// tree that draws it: each text leaf as a control.paragraph of the model's rich spans (so the words, bold, italic, code and
// link kinds, and the pressable link states, come from the shared control), a list marker and a quote bar beside it, a code
// block as a mono box, a table as rows of bordered cells, a rule as a divider. The model's own grid positions are used only
// for the left offsets; the paragraphs wrap by their own shaped text, so line breaks differ from the grid. Derived from the
// shared tokens; no platform renders Markdown natively, so there is nothing to compare.

use e.fmt.markdown
use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_x63
use e.ui.markdown_view as mv
use e.ui.style
use e.ui.widget

fn on_link(ctx: *void) -> err { ret ok }

fn spacer(w: f32) -> widget.Node {
    ret widget.box(0u64, control.sized_style(w, 1.0), zero)
}

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

fn quote_cross(bar: bool) -> ui_layout.CrossAlign {
    if bar { ret .Stretch }
    ret .Start
}

fn leaf_role(nd: mv.Node) -> style.TextRole {
    if nd.role == .Heading {
        if nd.level == 1u32 { ret .TitleLarge }
        if nd.level == 2u32 { ret .TitleMedium }
        ret .TitleSmall
    }
    ret .BodyMedium
}

fn text_leaf(a: *mem.Arena, t: *const control.Theme, v: *const mv.View, n: usize, key: u64, width: f32, action: widget.Submit) -> (widget.Node, err) {
    let nd = v.nodes[n]
    var x0 = width
    var marker_x: f32 = 0.0
    var marker: str = ""
    var has_marker = false
    var bar_x: f32 = 0.0
    var bar_w: f32 = 0.0
    var has_bar = false
    var i = nd.first
    while i < nd.first + nd.count {
        let it = v.items[i]
        if it.kind == .Word && it.x < x0 { x0 = it.x }
        if it.kind == .Marker && !has_marker {
            has_marker = true
            marker_x = it.x
            marker = v.store[it.start..it.start + it.len]
        }
        if it.kind == .QuoteBar && !has_bar {
            has_bar = true
            bar_x = it.x
            bar_w = it.w
        }
        i += 1usize
    }
    if x0 >= width { x0 = 0.0 }
    let (spans, spans_error) = mem.alloc[control.RichSpan](a, nd.count + 1usize)
    if spans_error != ok { ret (zero, spans_error) }
    let (used, used_error) = mv.rich_spans(v, n, spans, action)
    if used_error != ok { ret (zero, used_error) }
    var options = control.rich_options(t)
    options.role = leaf_role(nd)
    options.width = width - x0
    let (para, para_error) = control.paragraph(a, key, t, spans[0usize..used], options)
    if para_error != ok { ret (zero, para_error) }
    let (kids, kids_error) = mem.alloc[widget.Node](a, 4usize)
    if kids_error != ok { ret (zero, kids_error) }
    var k = 0usize
    if has_bar {
        kids[k] = spacer(bar_x)
        k += 1usize
        var bar = control.sized_style(bar_w, 1.0)
        bar.background = paint.Brush { Solid: style.color(t.tokens, .Outline) }
        kids[k] = widget.box(0u64, bar, zero)
        k += 1usize
        kids[k] = spacer(x0 - bar_x - bar_w)
        k += 1usize
    } else if has_marker {
        kids[k] = spacer(marker_x)
        k += 1usize
        var mark_options = control.text_options()
        mark_options.wrap = .None
        let (mark, mark_error) = control.text(a, 0u64, marker, t, mark_options)
        if mark_error != ok { ret (zero, mark_error) }
        kids[k] = widget.box(0u64, control.sized_style(x0 - marker_x, 18.0), mem_one(a, mark))
        k += 1usize
    } else {
        kids[k] = spacer(x0)
        k += 1usize
    }
    kids[k] = para
    k += 1usize
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: quote_cross(has_bar), gap: 0.0 }, style.defaults(), kids[0usize..k]), ok)
}

fn code_leaf(a: *mem.Arena, t: *const control.Theme, v: *const mv.View, n: usize, width: f32) -> (widget.Node, err) {
    let nd = v.nodes[n]
    let (lines, lines_error) = mem.alloc[widget.Node](a, nd.count + 1usize)
    if lines_error != ok { ret (zero, lines_error) }
    var count = 0usize
    var x0: f32 = 0.0
    var i = nd.first
    while i < nd.first + nd.count {
        let it = v.items[i]
        if it.kind == .CodeBack { x0 = it.x }
        if it.kind == .CodeLine {
            var options = control.text_options()
            options.wrap = .None
            options.mono = true
            let (line, line_error) = control.text(a, 0u64, v.store[it.start..it.start + it.len], t, options)
            if line_error != ok { ret (zero, line_error) }
            lines[count] = line
            count += 1usize
        }
        i += 1usize
    }
    var box = style.defaults()
    box.width = style.Length { Px: width - x0 }
    box.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    box.radius = t.tokens.radii.sm
    let pad = style.Length { Px: 8.0 }
    box.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, box, lines[0usize..count])
    let (kids, kids_error) = mem.alloc[widget.Node](a, 2usize)
    if kids_error != ok { ret (zero, kids_error) }
    kids[0usize] = spacer(x0)
    kids[1usize] = column
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), kids[0usize..2usize]), ok)
}

fn table_row(a: *mem.Arena, t: *const control.Theme, v: *const mv.View, first: usize, last: usize, columns: usize, width: f32, key: u64, action: widget.Submit) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, last - first + 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    let w = width / f32(columns)
    var k = first
    while k < last {
        let nd = v.nodes[k]
        let (spans, spans_error) = mem.alloc[control.RichSpan](a, nd.count + 1usize)
        if spans_error != ok { ret (zero, spans_error) }
        let (used, used_error) = mv.rich_spans(v, k, spans, action)
        if used_error != ok { ret (zero, used_error) }
        var options = control.rich_options(t)
        options.width = w - 16.0
        if nd.role == .HeaderCell {
            var j = 0usize
            while j < used {
                if spans[j].kind == .Plain { spans[j].kind = .Strong }
                j += 1usize
            }
        }
        let (para, para_error) = control.paragraph(a, key + u64(k) * 1000u64, t, spans[0usize..used], options)
        if para_error != ok { ret (zero, para_error) }
        var cell = style.defaults()
        cell.width = style.Length { Px: w }
        cell.border = style.Border { width: 1.0, color: style.color(t.tokens, .OutlineVariant) }
        if nd.role == .HeaderCell { cell.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) } }
        let pad = style.Length { Px: 7.0 }
        cell.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
        cells[k - first] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, cell, mem_one(a, para))
        k += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), cells[0usize..last - first]), ok)
}

fn is_cell(nd: mv.Node) -> bool {
    ret nd.role == .Cell || nd.role == .HeaderCell
}

fn document(a: *mem.Arena, t: *const control.Theme, src: str, width: f32, base: u64, policy: mv.LinkPolicy) -> (widget.Node, err) {
    let (items, e1) = mem.alloc[mv.Item](a, 400usize)
    if e1 != ok { ret (zero, e1) }
    let (nodes, e2) = mem.alloc[mv.Node](a, 64usize)
    if e2 != ok { ret (zero, e2) }
    let (links, e3) = mem.alloc[mv.Link](a, 16usize)
    if e3 != ok { ret (zero, e3) }
    let (store, e4) = mem.alloc[u8](a, 4096usize)
    if e4 != ok { ret (zero, e4) }
    let (scratch, e5) = mem.alloc[u8](a, 2048usize)
    if e5 != ok { ret (zero, e5) }
    let (blocks, e6) = mem.alloc[markdown.Block](a, 160usize)
    if e6 != ok { ret (zero, e6) }
    let (inlines, e7) = mem.alloc[markdown.Inline](a, 160usize)
    if e7 != ok { ret (zero, e7) }
    let (words, e8) = mem.alloc[mv.Word](a, 160usize)
    if e8 != ok { ret (zero, e8) }
    let st = mv.Storage { items: items, nodes: nodes, links: links, store: store, scratch: scratch, blocks: blocks, inlines: inlines, words: words }
    let m = mv.Metrics { width: width, char_w: 6.5, line_h: 18.0, gap: 8.0, indent: 20.0, pad: 8.0, bar: 3.0 }
    let (vs, vs_error) = mem.alloc[mv.View](a, 1usize)
    if vs_error != ok { ret (zero, vs_error) }
    let (built, built_error) = mv.build(src, st, m, policy)
    if built_error != ok { ret (zero, built_error) }
    vs[0usize] = built
    let v = &vs[0usize]
    let action = widget.Submit { ctx: nil, invoke: on_link }
    let (blocks_out, blocks_error) = mem.alloc[widget.Node](a, v.node_count + 1usize)
    if blocks_error != ok { ret (zero, blocks_error) }
    var count = 0usize
    var n = 0usize
    while n < v.node_count {
        let nd = v.nodes[n]
        if nd.role == .Heading || nd.role == .Paragraph {
            let (node, node_error) = text_leaf(a, t, v, n, base + u64(n) * 1000u64, width, action)
            if node_error != ok { ret (zero, node_error) }
            blocks_out[count] = node
            count += 1usize
        } else if nd.role == .Code {
            let (node, node_error) = code_leaf(a, t, v, n, width)
            if node_error != ok { ret (zero, node_error) }
            blocks_out[count] = node
            count += 1usize
        } else if nd.role == .Separator {
            let (node, node_error) = control.divider(a, 0u64, t, .Horizontal, width)
            if node_error != ok { ret (zero, node_error) }
            blocks_out[count] = node
            count += 1usize
        } else if nd.role == .Table {
            // the rows: runs of cells that share a row number, in the node order after the table
            var columns = usize(nd.level)
            if columns == 0usize { columns = 1usize }
            let (rows, rows_error) = mem.alloc[widget.Node](a, v.node_count + 1usize)
            if rows_error != ok { ret (zero, rows_error) }
            var row_count = 0usize
            var k = n + 1usize
            while k < v.node_count {
                if v.nodes[k].role == .Row {
                    k += 1usize
                    continue
                }
                if !is_cell(v.nodes[k]) { break }
                var stop = k
                while stop < v.node_count && is_cell(v.nodes[stop]) && v.nodes[stop].row == v.nodes[k].row { stop += 1usize }
                let (row, row_error) = table_row(a, t, v, k, stop, columns, width, base + u64(k) * 1000u64, action)
                if row_error != ok { ret (zero, row_error) }
                rows[row_count] = row
                row_count += 1usize
                k = stop
            }
            blocks_out[count] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..row_count])
            count += 1usize
            n = k - 1usize
        }
        n += 1usize
    }
    var page = style.defaults()
    page.width = style.Length { Px: width }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, page, blocks_out[0usize..count]), ok)
}

fn full_source() -> str {
    ret "# Release notes\n\nThe **deck editor** now has *live prices*, a `bulk.prices` fallback and a [full changelog](https://example.org/changes).\n\n## Changes\n\n- Prices update **hourly**\n- Missing files no longer raise an error\n  1. Retry once\n  2. Then show the cached value\n\n> Prices are a guide, not an offer.\n\n```\nprice = cache.get(card)\n```\n\n| Control | State |\n|---|---|\n| Button | Done |\n| Slider | Review |\n\n---\n\nEnd of the notes."
}

fn build(ctx: *void, a: *mem.Arena, theme: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Android: the rig has no Roboto Mono, so the sheet adds Cascadia Mono for the code block and the inline code.
    var t = theme
    if theme.tokens.profile == .MaterialLike {
        let (mono, mono_error) = looks_x63.mono_theme(a, theme)
        if mono_error != ok { ret (0usize, mono_error) }
        t = mono
    }
    let names = [2]str{ "document", "narrow" }
    var i = 0usize
    while i < 2usize {
        var width: f32 = 380.0
        if i == 1usize { width = 230.0 }
        let (node, node_error) = document(a, t, full_source(), width, u64(i + 1usize) * 10000000u64, .HostActivated)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (2usize, ok)
}

// The pressable link states of a host-activated viewer, and the same words display-only.
fn build_links(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "link hover", "link focus", "link pressed", "display-only link" }
    var i = 0usize
    while i < 4usize {
        var policy: mv.LinkPolicy = .HostActivated
        var drive: looks.Drive = .None
        if i == 0usize { drive = .Hover }
        if i == 1usize { drive = .Focus }
        if i == 2usize { drive = .Press }
        if i == 3usize { policy = .DisplayOnly }
        let (node, node_error) = document(a, t, "See the [release notes](https://example.org/notes) for more.", 300.0, u64(i + 1usize) * 10000000u64, policy)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        if i < 3usize { looks.aim(i, -70.0, 0.0) }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "markdown_view", cells: 2usize, columns: 2usize, cell_w: 400.0, cell_h: 440.0, ctx: zero, build: build }
    let links = looks.Sheet { name: "markdown_view_links", cells: 4usize, columns: 2usize, cell_w: 320.0, cell_h: 60.0, ctx: zero, build: build_links }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_all(a, &links)
    try looks.run_linux(a, &links)
    try looks.run_cupertino(a, &links)
    ret looks.run_material(a, &links)
}
