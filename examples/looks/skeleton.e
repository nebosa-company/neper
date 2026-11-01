// Round 62 c: the skeleton (loading placeholder) in all ten looks: text line, short line, circle, rectangle, pill, a block
// on the highest container, a list row (circle and two lines) and one block mid shimmer. The shimmer is a time effect: the
// sheet freezes it at one phase. Derived from the shared tokens, no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn block(a: *mem.Arena, key: u64, t: *const control.Theme, shape: control.SkeletonShape, w: f32, h: f32, highest: bool) -> (widget.Node, err) {
    var options = control.skeleton_options()
    options.shape = shape
    options.on_highest = highest
    if shape == .Rect { options.radius = t.tokens.radii.md }
    let (node, node_error) = control.skeleton_of(a, key, t, w, h, options)
    ret (node, node_error)
}

fn row(a: *mem.Arena, t: *const control.Theme, base: u64) -> (widget.Node, err) {
    let (circle, circle_error) = block(a, base + 1u64, t, .Circle, 40.0, 40.0, false)
    if circle_error != ok { ret (zero, circle_error) }
    let (first, first_error) = block(a, base + 2u64, t, .Line, 160.0, 12.0, false)
    if first_error != ok { ret (zero, first_error) }
    let (second, second_error) = block(a, base + 3u64, t, .Line, 100.0, 12.0, false)
    if second_error != ok { ret (zero, second_error) }
    let (lines, lines_error) = mem.alloc[widget.Node](a, 2usize)
    if lines_error != ok { ret (zero, lines_error) }
    lines[0usize] = first
    lines[1usize] = second
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = circle
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 8.0 }, style.defaults(), lines[0usize..2usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Text line", "Short line", "Circle", "Rectangle", "Pill", "On highest container", "List row", "Mid shimmer" }
    var i = 0usize
    while i < 8usize {
        let key = u64((i + 1usize) * 16usize)
        var node: widget.Node = zero
        var node_error = ok
        if i == 7usize {
            let (made, made_error) = control.skeleton(a, key, t, 200.0, 14.0, 0.5)
            node = made
            node_error = made_error
        }
        if i == 0usize {
            let (made, made_error) = block(a, key, t, .Line, 200.0, 14.0, false)
            node = made
            node_error = made_error
        }
        if i == 1usize {
            let (made, made_error) = block(a, key, t, .Line, 90.0, 14.0, false)
            node = made
            node_error = made_error
        }
        if i == 2usize {
            let (made, made_error) = block(a, key, t, .Circle, 48.0, 48.0, false)
            node = made
            node_error = made_error
        }
        if i == 3usize {
            let (made, made_error) = block(a, key, t, .Rect, 140.0, 80.0, false)
            node = made
            node_error = made_error
        }
        if i == 4usize {
            let (made, made_error) = block(a, key, t, .Pill, 100.0, 28.0, false)
            node = made
            node_error = made_error
        }
        if i == 5usize {
            let (inner, inner_error) = block(a, key, t, .Rect, 120.0, 56.0, true)
            if inner_error != ok { ret (0usize, inner_error) }
            let (kids, kids_error) = mem.alloc[widget.Node](a, 1usize)
            if kids_error != ok { ret (0usize, kids_error) }
            kids[0usize] = inner
            var options = control.surface_options(t)
            options.background = .SurfaceContainerHighest
            options.padding = 12.0
            options.radius = t.tokens.radii.md
            let (made, made_error) = control.surface(a, key + 8u64, t, options, kids[0usize..1usize])
            node = made
            node_error = made_error
        }
        if i == 6usize {
            let (made, made_error) = row(a, t, key)
            node = made
            node_error = made_error
        }
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "skeleton", cells: 8usize, columns: 4usize, cell_w: 240.0, cell_h: 120.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
