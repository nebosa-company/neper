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
    if t.tokens.profile == .Windows {
        // round 13: the two bars at rest exactly as the live main window draws them: the grid's vertical one (16 x 186, an 88 px thumb)
        // and the navigator's horizontal one (196 x 16, a 163 px thumb after the 17 px slot), each at its cell's corner
        var k = 0usize
        while k < 2usize {
            var length: f32 = 186.0
            var view: f32 = 88.0
            var live_content: f32 = 154.0
            if k == 1usize {
                length = 196.0
                view = 163.0
                live_content = 164.0
            }
            let (live_bar, live_error) = control.windows_scroll_bar(a, u64(23000usize + k), t, k == 0usize, length, view, live_content, 0.0)
            if live_error != ok { ret (0usize, live_error) }
            let corner = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(200.0, 190.0), mem_one(a, live_bar))
            var live_caption = "Vertical"
            if k == 1usize { live_caption = "Horizontal" }
            cells[k] = looks.Cell { caption: live_caption, node: corner, drive: .None }
            k += 1usize
        }
        ret (2usize, ok)
    }
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


// ---- round 13: the grid bar of the live main window in every captured state (ref/windows/states/*scroll-bar*) ----------------------
// scripts/looks_bars.py cuts the capture crops (track x 775 to 790, y 111 to 296 of the 800 x 600 grabs) and compares them with the cells
// of this sheet at whole pixels. A cell is the bar alone, 16 x 186. The pointer goes where the capture's pointer was.
// cell: 0 rest (the long thumb of main-window@1x), 1 hover thumb, 2 hover upper arrow, 3 hover lower arrow, 4 hover track,
// 5 pressed thumb, 6 pressed lower arrow
fn build_main_bar(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [7]str{ "Rest", "Hover thumb", "Hover up", "Hover down", "Hover track", "Pressed thumb", "Pressed down" }
    var i = 0usize
    while i < 7usize {
        var view: f32 = 17.0
        if i == 0usize { view = 88.0 }
        let (bar, bar_error) = control.windows_scroll_bar(a, u64(20000usize + i), t, true, 186.0, view, 154.0, 0.0)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        var dy: f32 = 0.0
        if i == 1usize { drive = .Hover
            dy = 0.0 - 69.0 }
        if i == 2usize { drive = .Hover
            dy = 0.0 - 85.0 }
        if i == 3usize { drive = .Hover
            dy = 84.0 }
        if i == 4usize { drive = .Hover
            dy = 7.0 }
        if i == 5usize { drive = .Press
            dy = 0.0 - 69.0 }
        if i == 6usize { drive = .Press
            dy = 85.0 }
        looks.aim(i, 0.0, dy)
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

// The horizontal bar of the main window's navigator: rest, pointer on the thumb, thumb held (a 163 px thumb after a 17 px slot, 16 thick).
fn build_main_h(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [3]str{ "Rest", "Hover thumb", "Pressed thumb" }
    var i = 0usize
    while i < 3usize {
        let (bar, bar_error) = control.windows_scroll_bar(a, u64(21000usize + i), t, false, 196.0, 163.0, 164.0, 0.0)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        looks.aim(i, 0.0, 0.0 - 1.0)
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

// The states v3 never showed, from the native Windows 11 light captures (ref/windows-native/light): the disabled bars (vertical 17 x 170,
// horizontal 178 x 17) and the upper arrow held down (only the arrow is compared: the native thumb is its own look, v3's stays).
fn build_native_bar(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [3]str{ "Disabled", "Disabled H", "Pressed up" }
    var i = 0usize
    while i < 3usize {
        control.set_scroll_bar_disabled(i < 2usize)
        var vertical = i != 1usize
        var length: f32 = 170.0
        if i == 1usize { length = 178.0 }
        let (bar, bar_error) = control.windows_scroll_bar(a, u64(22000usize + i), t, vertical, length, 40.0, 154.0, 0.0)
        control.set_scroll_bar_disabled(false)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        if i == 2usize {
            drive = .Press
            looks.aim(i, 0.0 - 81.0, 0.0 - 77.0)
        }
        // the bar at the cell's corner (the harness centres a smaller node)
        let holder = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, looks.size_style(178.0, 170.0), mem_one(a, bar))
        cells[i] = looks.Cell { caption: captions[i], node: holder, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize && args[1usize].len > 1usize && args[1usize][0usize] == 109u8 && args[1usize][1usize] == 104u8 {
        let main_h = looks.Sheet { name: "scroll_bar_main_h", cells: 3usize, columns: 1usize, cell_w: 196.0, cell_h: 16.0, ctx: zero, build: build_main_h }
        ret looks.run_all(a, &main_h)
    }
    if args.len > 1usize && args[1usize].len > 0usize && args[1usize][0usize] == 110u8 {
        let native_bar = looks.Sheet { name: "scroll_bar_native", cells: 3usize, columns: 3usize, cell_w: 178.0, cell_h: 170.0, ctx: zero, build: build_native_bar }
        ret looks.run_all(a, &native_bar)
    }
    if args.len > 1usize && args[1usize].len > 0usize && args[1usize][0usize] == 109u8 {
        let main_bar = looks.Sheet { name: "scroll_bar_main", cells: 7usize, columns: 7usize, cell_w: 16.0, cell_h: 186.0, ctx: zero, build: build_main_bar }
        ret looks.run_all(a, &main_bar)
    }
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
