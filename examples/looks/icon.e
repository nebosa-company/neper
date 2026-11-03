// Round 62 c: the icon in all ten looks: the shared glyph set (three rows), the size steps 16 to 36, the colour roles, the
// disabled tint, the filled form and a picture icon (the sample landscape of looks_c, standing in for a bitmap icon). The
// glyphs are the vector set every look shares; no look has its own icon font here. Derived, no platform capture. Run from
// the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_c
use e.ui.style
use e.ui.widget
use e.ui.looks_y87

fn glyph_row(a: *mem.Arena, t: *const control.Theme, base: u64, kinds: []const control.GlyphKind) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, kinds.len)
    if parts_error != ok { ret (zero, parts_error) }
    var i = 0usize
    while i < kinds.len {
        var options: control.IconOptions = zero
        options.size = 24.0
        options.color = .OnSurfaceVariant
        options.enabled = true
        options.label = "icon"
        let (node, node_error) = control.icon_of(a, base + u64(i), t, kinds[i], options)
        if node_error != ok { ret (zero, node_error) }
        parts[i] = node
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 10.0 }, style.defaults(), parts[0usize..kinds.len]), ok)
}

// Cupertino only: the roles this sheet draws with take tones that hold 4.5:1 (any other look is passed through unchanged).
fn build(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [1]looks_y87.RoleTone{ looks_y87.orange_tone(.Tertiary) }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..1usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [9]str{ "Set, 1 to 12", "Set, 13 to 24", "Set, 25 to 35", "Sizes 16 20 24 36", "Colour roles", "Disabled", "Filled", "Filled, primary", "Picture icon 24" }
    let first = [12]control.GlyphKind{ .Check, .Dash, .Cross, .ChevronDown, .ChevronUp, .ChevronLeft, .ChevronRight, .Calendar, .Clock, .Search, .Person, .Picture }
    let second = [12]control.GlyphKind{ .Alert, .DragHandle, .DockLeft, .Maximize, .MoreHoriz, .ArrowBack, .ArrowForward, .Info, .CheckCircle, .Warning, .MoreVert, .Menu }
    let third = [11]control.GlyphKind{ .ArrowUp, .ArrowDown, .Refresh, .Add, .Visibility, .VisibilityOff, .Edit, .Settings, .Filter, .Table, .Sigma }
    var i = 0usize
    while i < 9usize {
        let key = u64((i + 1usize) * 64usize)
        var node: widget.Node = zero
        var node_error = ok
        if i == 0usize {
            let (made, made_error) = glyph_row(a, t, key, first[0usize..12usize])
            node = made
            node_error = made_error
        }
        if i == 1usize {
            let (made, made_error) = glyph_row(a, t, key, second[0usize..12usize])
            node = made
            node_error = made_error
        }
        if i == 2usize {
            let (made, made_error) = glyph_row(a, t, key, third[0usize..11usize])
            node = made
            node_error = made_error
        }
        if i >= 3usize && i <= 7usize {
            let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
            if parts_error != ok { ret (0usize, parts_error) }
            var n = 0usize
            while n < 4usize {
                var options: control.IconOptions = zero
                options.size = 24.0
                options.color = .OnSurfaceVariant
                options.enabled = true
                options.label = "icon"
                var kind: control.GlyphKind = .Search
                if i == 3usize {
                    let steps = [4]f32{ 16.0, 20.0, 24.0, 36.0 }
                    options.size = steps[n]
                }
                if i == 4usize {
                    let roles = [4]style.ColorRole{ .OnSurface, .Primary, .Error, .Tertiary }
                    options.color = roles[n]
                    kind = .Info
                }
                if i == 5usize {
                    options.enabled = n != 0usize && n != 2usize
                    kind = .Edit
                }
                if i == 6usize || i == 7usize {
                    let filled_kinds = [4]control.GlyphKind{ .CheckCircle, .Info, .Warning, .Person }
                    kind = filled_kinds[n]
                    options.filled = true
                    options.ground = .Surface
                    if i == 7usize { options.color = .Primary }
                }
                let (made, made_error) = control.icon_of(a, key + u64(n), t, kind, options)
                if made_error != ok { ret (0usize, made_error) }
                parts[n] = made
                n += 1usize
            }
            node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 14.0 }, style.defaults(), parts[0usize..4usize])
        }
        if i == 8usize {
            let (made, made_error) = control.icon(a, key, looks_c.picture, 24.0, "Picture")
            node = made
            node_error = made_error
        }
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (9usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "icon", cells: 9usize, columns: 3usize, cell_w: 360.0, cell_h: 80.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
