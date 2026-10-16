// The scroll bar in every state under every look: docs/ui/looks/<look>/scroll_bar.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

// The scrolled content: a white box `extent` long along the axis, 40 across.
fn content(a: *mem.Arena, t: *const control.Theme, vertical: bool, extent: f32) -> ([]widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var s = style.defaults()
    s.background = paint.Brush { Solid: style.hex(16777215u32) }
    // Neper dark: the page's own surface instead of white (the light pictures keep white)
    if t.tokens.palette == .Dark && t.tokens.profile == .Neper { s.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) } }
    s.width = style.Length { Px: 40.0 }
    s.height = style.Length { Px: extent }
    if !vertical {
        s.width = style.Length { Px: extent }
        s.height = style.Length { Px: 40.0 }
    }
    nodes[0usize] = widget.box(0u64, s, zero)
    ret (nodes, ok)
}

// Eight cells: the vertical bar at rest, hovered, pressed, scrolled half way, with content that
// fits (no thumb); the horizontal bar at rest, hovered and scrolled to the end. The harness
// points at a cell's centre, so a spacer beside the control puts the centre on the bar.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Rest", "Hover", "Pressed", "Scrolled", "Fits", "Horizontal", "H hover", "H scrolled" }
    var gap: f32 = 28.0
    if t.tokens.profile == .Windows { gap = 40.0 }
    var i = 0usize
    while i < 8usize {
        let vertical = i < 5usize
        var offset: f32 = 0.0
        var extent: f32 = 400.0
        if i == 3usize { offset = 150.0 }
        if i == 4usize { extent = 90.0 }
        if i == 7usize { offset = 280.0 }
        var width: f32 = 40.0
        var height: f32 = 100.0
        var axis: ui_layout.Axis = .Vertical
        var direction: ui_layout.Axis = .Horizontal
        if t.tokens.profile == .Windows {
            if vertical { width = 56.0 } else { height = 56.0 }
        }
        if !vertical {
            axis = .Horizontal
            direction = .Vertical
            if t.tokens.profile != .Windows { height = 40.0 }
            width = 120.0
        }
        let (kids, kids_error) = content(a, t, vertical, extent)
        if kids_error != ok { ret (0usize, kids_error) }
        let (bar, bar_error) = control.scroll_area(a, u64(10000usize * (i + 1usize)), t, axis, width, height, offset, extent, kids[0usize..1usize])
        if bar_error != ok { ret (0usize, bar_error) }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (0usize, pair_error) }
        pair[0usize] = bar
        pair[1usize] = widget.spacer(0u64, gap)
        var holder = style.defaults()
        holder.width = style.Length { Px: width + gap }
        holder.height = style.Length { Px: height }
        if !vertical {
            holder.width = style.Length { Px: width }
            holder.height = style.Length { Px: height + gap }
        }
        let node = widget.flex(0u64, ui_layout.Flex { axis: direction, main: .Start, cross: .Start, gap: 0.0 }, holder, pair[0usize..2usize])
        var drive: looks.Drive = .None
        if i == 1usize || i == 6usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

// The two bars as the live capture of the v3 main window shows them (ref/windows/scroll_bar_live*.png),
// at rest: the grid's vertical bar (16 wide, the thumb 2 wide) and a horizontal bar (a 9 thick block).
fn build_live(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var i = 0usize
    while i < 2usize {
        let vertical = i == 0usize
        var axis: ui_layout.Axis = .Vertical
        var direction: ui_layout.Axis = .Horizontal
        var width: f32 = 40.0
        var height: f32 = 150.0
        if !vertical {
            axis = .Horizontal
            direction = .Vertical
            width = 150.0
            height = 40.0
        }
        let (kids, kids_error) = content(a, t, vertical, 300.0)
        if kids_error != ok { ret (0usize, kids_error) }
        let (bar, bar_error) = control.scroll_area(a, u64(10000usize * (i + 1usize)), t, axis, width, height, 0.0, 300.0, kids[0usize..1usize])
        if bar_error != ok { ret (0usize, bar_error) }
        var holder = style.defaults()
        holder.width = style.Length { Px: width }
        holder.height = style.Length { Px: height }
        let node = widget.flex(0u64, ui_layout.Flex { axis: direction, main: .Start, cross: .Start, gap: 0.0 }, holder, mem_one(a, bar))
        var caption = "Vertical"
        if !vertical { caption = "Horizontal" }
        cells[i] = looks.Cell { caption: caption, node: node, drive: .None }
        i += 1usize
    }
    ret (2usize, ok)
}

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret zero }
    nodes[0usize] = node
    ret nodes[0usize..1usize]
}

// ---- sheet 3: scroll_bar_states, the bars of the live captures at rest and with the thumb pressed ----------------
// states/scroll-bar-thumb-pressed-main-vertical (the grid's bar: a 2 px thumb, a 6 px pill pressed) and
// ...-main-horizontal (the navigator's: an 8 px block in a rim, 12 px with rounded ends pressed), each against its rest.
// The harness presses the centre of a cell, which is on the bar.
fn build_states(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [4]str{ "Vertical", "Vertical pressed", "Horizontal", "Horizontal pressed" }
    var i = 0usize
    while i < 4usize {
        let vertical = i < 2usize
        var length: f32 = 100.0
        let (bar, bar_error) = control.windows_scroll_bar(a, u64(7000usize + i), t, vertical, length, length, 400.0, 0.0)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 3usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 2usize {
        let states = looks.Sheet { name: "scroll_bar_states", cells: 4usize, columns: 4usize, cell_w: 130.0, cell_h: 130.0, ctx: zero, build: build_states }
        ret looks.run_all(a, &states)
    }
    if args.len > 1usize {
        let live = looks.Sheet { name: "scroll_bar_live", cells: 2usize, columns: 2usize, cell_w: 200.0, cell_h: 190.0, ctx: zero, build: build_live }
        ret looks.run_all(a, &live)
    }
    let sheet = looks.Sheet { name: "scroll_bar", cells: 8usize, columns: 4usize, cell_w: 140.0, cell_h: 120.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
