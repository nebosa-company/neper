// The label in its looks: docs/ui/looks/<look>/label.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.text.layout
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn box_style(w: f32, h: f32, color: paint.Color) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    s.background = paint.Brush { Solid: color }
    ret s
}

fn plain(a: *mem.Arena, key: u64, t: *const control.Theme, value: str, role: style.TextRole, size: f32, weight: u32, color: paint.Color, wrap: layout.Wrap) -> (widget.Node, err) {
    var options = control.text_options()
    options.role = role
    options.wrap = wrap
    options.weight = weight
    options.size = size
    let (node, node_error) = control.colored_text(a, key, value, t, options, color)
    ret (node, node_error)
}

// Ten cells: v3's TcxLabel styles. Normal (the dialog's text), bold (section titles), a
// 13 px one, clGray hints, disabled, the hot-link style (#336CCC, underlined), the same
// label on a clWhite and a clBtnFace Style.Color (not transparent), word wrap in a 120 unit box,
// and a long label clipped by its box (AutoSize = False).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let ink = style.color(t.tokens, .Text)
    let names = [10]str{ "Normal", "Bold", "Font height -13", "Gray (clGray)", "Disabled", "Hot-link", "On clWhite", "On clBtnFace", "Word wrap, 120", "Long, clipped at 120" }
    var i = 0usize
    while i < 10usize {
        var node: widget.Node = zero
        var node_error: err = ok
        if i == 0usize {
            let (n, e) = plain(a, 1u64, t, "Row Color:", .Body, 0.0, 0u32, ink, .None)
            node = n
            node_error = e
        }
        if i == 1usize {
            let (n, e) = plain(a, 2u64, t, "Interface (F2)", .Body, 0.0, 700u32, ink, .None)
            node = n
            node_error = e
        }
        if i == 2usize {
            let (n, e) = plain(a, 3u64, t, "Deck Name", .Body, 13.2, 0u32, ink, .None)
            node = n
            node_error = e
        }
        if i == 3usize {
            let (n, e) = plain(a, 4u64, t, "Sample file is available.", .Body, 0.0, 0u32, style.hex(8421504u32), .None)
            node = n
            node_error = e
        }
        if i == 4usize {
            let (n, e) = plain(a, 5u64, t, "Font Size:", .Body, 0.0, 0u32, style.color(t.tokens, .TextMuted), .None)
            node = n
            node_error = e
        }
        if i == 5usize {
            let (words, words_error) = plain(a, 6u64, t, "Send email to Support", .Body, 0.0, 0u32, style.hex(3370188u32), .None)
            if words_error != ok { ret (0usize, words_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
            if parts_error != ok { ret (0usize, parts_error) }
            parts[0usize] = words
            parts[1usize] = widget.box(0u64, box_style(112.0, 1.0, style.hex(3370188u32)), zero)
            node = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
        }
        if i == 6usize || i == 7usize {
            var ground = style.hex(16777215u32)
            if i == 7usize { ground = style.color(t.tokens, .Background) }
            let (words, words_error) = plain(a, u64(i + 1usize), t, "Import card prices", .Body, 0.0, 0u32, ink, .None)
            if words_error != ok { ret (0usize, words_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
            if parts_error != ok { ret (0usize, parts_error) }
            parts[0usize] = words
            var holder = box_style(130.0, 17.0, ground)
            holder.border = style.Border { width: 1.0, color: style.color(t.tokens, .Border) }
            node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, holder, parts[0usize..1usize])
        }
        if i == 8usize {
            let (words, words_error) = plain(a, 9u64, t, "Import your collection of cards from various file formats.", .Body, 0.0, 0u32, ink, .Word)
            if words_error != ok { ret (0usize, words_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
            if parts_error != ok { ret (0usize, parts_error) }
            parts[0usize] = words
            var holder = style.defaults()
            holder.width = style.Length { Px: 120.0 }
            node = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, holder, parts[0usize..1usize])
        }
        if i == 9usize {
            var options = control.text_options()
            options.role = .Body
            options.wrap = .None
            options.max_lines = 1u32
            options.ellipsis = "..."
            let (words, words_error) = control.colored_text(a, 10u64, "Search from start (typing War would not find Fog of War)", t, options, ink)
            if words_error != ok { ret (0usize, words_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
            if parts_error != ok { ret (0usize, parts_error) }
            parts[0usize] = words
            var holder = style.defaults()
            holder.width = style.Length { Px: 120.0 }
            holder.overflow = .Clip
            node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, parts[0usize..1usize])
        }
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "label", cells: 10usize, columns: 4usize, cell_w: 170.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
