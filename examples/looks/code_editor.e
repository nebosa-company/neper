// The code editor (e.ui.code_editor), docs/ui/looks/<look>/code_editor.png in all ten looks. e.ui.code_editor is a model (a
// gap-buffer document, selections, a tokenizer per language, search); there is no widget builder yet. This host is the minimal
// widget tree that draws the model: a gutter of line numbers, each visible line as runs of text coloured by the model's tokens
// (keyword, type, number, string, comment) through the theme's roles, the model's selections as filled runs and its carets as
// bars, the current line tinted, find matches marked, and one error line in the error container. The host has no scrolling,
// folding, wrapping or diagnostics layer, and the mono face is whatever the harness registers (the runs flow at their own
// widths). Derived from the shared tokens; no platform editor was compared.

use e.gfx.paint
use e.mem
use e.ui.code_editor as ce
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_x63
use e.ui.style
use e.ui.widget

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

fn spacer(w: f32, h: f32) -> widget.Node {
    ret widget.box(0u64, control.sized_style(w, h), zero)
}

fn source() -> str {
    ret "// cache one price per card\nfn price_of(card: str, cache: *Cache) -> f64 {\n    let hit = cache.get(card)\n    if hit != nil { ret hit.value }\n    var total = 0\n    while total < 10 { total += 1 }\n    let note = \"fetched from bulk.prices\"\n    ret fetch(card, 4.25) + f64(total)\n}\n"
}

fn token_role(kind: u32) -> style.ColorRole {
    if kind == ce.TOK_KEYWORD { ret .Primary }
    if kind == ce.TOK_TYPE { ret .Tertiary }
    if kind == ce.TOK_NUMBER { ret .Secondary }
    if kind == ce.TOK_STRING { ret .Success }
    if kind == ce.TOK_COMMENT { ret .OnSurfaceVariant }
    ret .OnSurface
}

type Marks = struct { carets: [8]usize, caret_n: usize, matches: [16]usize, match_n: usize, match_len: usize, error_line: usize, has_error: bool, current: usize }

fn in_selection(e: *ce.Editor, p: usize) -> bool {
    var i = 0usize
    while i < ce.selection_count(e) {
        let r = ce.selection_at(e, i)
        if p >= ce.range_from(r) && p < ce.range_to(r) { ret true }
        i += 1usize
    }
    ret false
}

fn in_match(m: *const Marks, p: usize) -> bool {
    var i = 0usize
    while i < m.match_n {
        if p >= m.matches[i] && p < m.matches[i] + m.match_len { ret true }
        i += 1usize
    }
    ret false
}

fn is_caret(m: *const Marks, p: usize) -> bool {
    var i = 0usize
    while i < m.caret_n {
        if m.carets[i] == p { ret true }
        i += 1usize
    }
    ret false
}

fn kind_at(toks: []const ce.Token, n: usize, p: usize) -> u32 {
    var i = 0usize
    while i < n {
        if p >= toks[i].start && p < toks[i].end { ret toks[i].kind }
        i += 1usize
    }
    ret 0u32
}

fn run_node(a: *mem.Arena, t: *const control.Theme, text: str, kind: u32, selected: bool, matched: bool) -> (widget.Node, err) {
    if text[0usize] == 32u8 {
        // a run of spaces: the text shaper drops them, so the run is a gap of the same width, filled when selected
        var gap = control.sized_style(f32(text.len) * 4.4, 18.0)
        if selected { gap.background = paint.Brush { Solid: style.color(t.tokens, .TextSelection) } }
        ret (widget.box(0u64, gap, zero), ok)
    }
    var options = control.text_options()
    options.wrap = .None
    options.mono = true
    let (node, node_error) = control.colored_text(a, 0u64, text, t, options, style.color(t.tokens, token_role(kind)))
    if node_error != ok { ret (zero, node_error) }
    if !selected && !matched { ret (node, ok) }
    var back = style.defaults()
    var role: style.ColorRole = .WarningContainer
    if selected { role = .TextSelection }
    back.background = paint.Brush { Solid: style.color(t.tokens, role) }
    ret (widget.box(0u64, back, mem_one(a, node)), ok)
}

fn line_row(a: *mem.Arena, t: *const control.Theme, e: *ce.Editor, ln: usize, m: *const Marks, width: f32) -> (widget.Node, err) {
    let ls = ce.line_start(e, ln)
    let le = ce.line_end(e, ln)
    let (bytes, bytes_error) = mem.alloc[u8](a, le - ls + 1usize)
    if bytes_error != ok { ret (zero, bytes_error) }
    let got = ce.copy_text(e, ls, le, bytes)
    var toks: [64]ce.Token = zero
    let tn = ce.tokens(e, ln, toks[0..])
    let (kids, kids_error) = mem.alloc[widget.Node](a, (le - ls) + 8usize)
    if kids_error != ok { ret (zero, kids_error) }
    // the gutter: the line number, right aligned
    var number_text: [4]u8 = zero
    let number = ln + 1usize
    number_text[0usize] = 48u8 + u8((number / 10usize) % 10usize)
    number_text[1usize] = 48u8 + u8(number % 10usize)
    var shown = number_text[0usize..2usize]
    if number < 10usize { shown = number_text[1usize..2usize] }
    let (digits, digits_error) = mem.alloc[u8](a, 2usize)
    if digits_error != ok { ret (zero, digits_error) }
    var d = 0usize
    while d < shown.len {
        digits[d] = shown[d]
        d += 1usize
    }
    var number_options = control.text_options()
    number_options.wrap = .None
    number_options.mono = true
    let (digit_node, digit_error) = control.colored_text(a, 0u64, digits[0usize..shown.len], t, number_options, style.color(t.tokens, .OnSurfaceVariant))
    if digit_error != ok { ret (zero, digit_error) }
    var gutter = control.sized_style(40.0, 20.0)
    gutter.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    gutter.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 0.0 } }
    kids[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 0.0 }, gutter, mem_one(a, digit_node))
    kids[1usize] = spacer(10.0, 20.0)
    var k = 2usize
    var run_start = 0usize
    var run_kind = kind_at(toks[0..], tn, ls)
    var run_sel = in_selection(e, ls)
    var run_match = in_match(m, ls)
    var p = 0usize
    while p <= got {
        var cut = p == got
        var kind: u32 = 0u32
        var sel = false
        var matched = false
        if p < got {
            kind = kind_at(toks[0..], tn, ls + p)
            sel = in_selection(e, ls + p)
            matched = in_match(m, ls + p)
            if kind != run_kind || sel != run_sel || matched != run_match { cut = true }
            if (bytes[p] == 32u8) != (bytes[run_start] == 32u8) { cut = true }
            if is_caret(m, ls + p) { cut = true }
        }
        if cut {
            if p > run_start {
                let (run, run_error) = run_node(a, t, bytes[run_start..p], run_kind, run_sel, run_match)
                if run_error != ok { ret (zero, run_error) }
                kids[k] = run
                k += 1usize
            }
            if is_caret(m, ls + p) {
                var bar = control.sized_style(2.0, 16.0)
                bar.background = paint.Brush { Solid: style.color(t.tokens, .OnSurface) }
                kids[k] = widget.box(0u64, bar, zero)
                k += 1usize
            }
            run_start = p
            run_kind = kind
            run_sel = sel
            run_match = matched
        }
        p += 1usize
    }
    var row = control.sized_style(width - 2.0, 20.0)
    row.overflow = .Clip
    var current = false
    var c = 0usize
    while c < m.caret_n {
        if ce.line_of(e, m.carets[c]) == ln { current = true }
        c += 1usize
    }
    if m.has_error && m.error_line == ln {
        var tint = style.color(t.tokens, .ErrorContainer)
        tint.alpha = 0.7
        row.background = paint.Brush { Solid: tint }
    } else if current {
        var tint = style.color(t.tokens, .Primary)
        tint.alpha = 0.07
        row.background = paint.Brush { Solid: tint }
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, row, kids[0usize..k]), ok)
}

fn editor_view(a: *mem.Arena, t: *const control.Theme, e: *ce.Editor, m: *const Marks, width: f32, disabled: bool) -> (widget.Node, err) {
    let count = ce.line_count(e)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count + 1usize)
    if rows_error != ok { ret (zero, rows_error) }
    var n = 0usize
    var ln = 0usize
    while ln < count {
        // the document ends in a newline: no row for the empty last line
        if ln + 1usize == count && ce.line_start(e, ln) == ce.line_end(e, ln) { break }
        let (row, row_error) = line_row(a, t, e, ln, m, width)
        if row_error != ok { ret (zero, row_error) }
        rows[n] = row
        n += 1usize
        ln += 1usize
    }
    var frame = control.sized_style(width, f32(n) * 20.0 + 2.0)
    frame.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
    frame.border = style.Border { width: 1.0, color: style.color(t.tokens, .OutlineVariant) }
    frame.radius = t.tokens.radii.sm
    frame.overflow = .Clip
    if disabled { frame.opacity = t.tokens.states.disabled_content }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, rows[0usize..n]), ok)
}

fn at(e: *ce.Editor, ln: usize, col: usize) -> usize {
    ret ce.line_start(e, ln) + col
}

fn build(ctx: *void, a: *mem.Arena, theme: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Android: the rig has no Roboto Mono, so the sheet adds Cascadia Mono (the Cupertino sheets keep their face).
    var t = theme
    if theme.tokens.profile == .MaterialLike {
        let (mono, mono_error) = looks_x63.mono_theme(a, theme)
        if mono_error != ok { ret (0usize, mono_error) }
        t = mono
    }
    let names = [6]str{ "rest, caret on line 3", "selection across lines", "three carets", "find matches", "error line", "disabled" }
    let e = mem.cast[*ce.Editor](ctx)
    var i = 0usize
    while i < 6usize {
        var m: Marks = zero
        var ranges: [4]ce.Range = zero
        var count = 1usize
        ranges[0usize] = ce.caret(at(e, 2usize, 15usize))
        if i == 1usize {
            ranges[0usize] = ce.Range { anchor: at(e, 2usize, 8usize), head: at(e, 4usize, 9usize), goal: ce.NO_GOAL }
        }
        if i == 2usize {
            ranges[0usize] = ce.caret(at(e, 2usize, 8usize))
            ranges[1usize] = ce.caret(at(e, 4usize, 9usize))
            ranges[2usize] = ce.caret(at(e, 7usize, 20usize))
            count = 3usize
        }
        if i == 3usize {
            ranges[0usize] = ce.Range { anchor: at(e, 5usize, 8usize), head: at(e, 5usize, 13usize), goal: ce.NO_GOAL }
            var from = 0usize
            while m.match_n < 16usize {
                let (found, hit) = ce.find(e, "total", from, true, ce.SearchOpts { case_sensitive: true, whole_word: false })
                if !hit || found < from { break }
                m.matches[m.match_n] = found
                m.match_n += 1usize
                from = found + 5usize
            }
            m.match_len = 5usize
        }
        if i == 4usize {
            m.has_error = true
            m.error_line = 3usize
        }
        if ce.set_selection(e, ranges[0usize..count], 0usize) != ok { ret (0usize, Invalid) }
        var s = 0usize
        while s < count {
            m.carets[s] = ranges[s].head
            s += 1usize
        }
        m.caret_n = count
        // Android (round 86): a disabled editor shows no caret and no current-line tint.
        if i == 5usize && t.tokens.profile == .MaterialLike { m.caret_n = 0usize }
        let (node, node_error) = editor_view(a, t, e, &m, 520.0, i == 5usize)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

error Invalid

fn main(a: *mem.Arena, args: []str) -> err {
    let (opened, open_error) = ce.open(a, 4096usize, 64usize, 8usize, 16usize, 64usize, 1024usize)
    if open_error != ok { ret open_error }
    let (eds, eds_error) = mem.alloc[ce.Editor](a, 1usize)
    if eds_error != ok { ret eds_error }
    eds[0usize] = opened
    ce.set_language(&eds[0usize], ce.lang_neper())
    try ce.load(&eds[0usize], source())
    let sheet = looks.Sheet { name: "code_editor", cells: 6usize, columns: 2usize, cell_w: 540.0, cell_h: 200.0, ctx: mem.cast[*void](&eds[0usize]), build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_material(a, &sheet)
}
