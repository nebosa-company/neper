// The splitter (TcxSplitter) in every state under every look: docs/ui/looks/<look>/splitter.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

// A pane: a white box with a grey frame, standing for the panels v3 splits.
fn pane() -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Percent: 100.0 }
    s.height = style.Length { Percent: 100.0 }
    s.background = paint.Brush { Solid: style.hex(16777215u32) }
    s.border = style.Border { width: 1.0, color: style.hex(8554384u32) }
    ret widget.box(0u64, s, zero)
}

// Eight cells, a split of 200 x 120: the sash standing upright (panes side by side) at rest,
// hovered, dragged and keyboard-focused, then the same four lying down (panes above and below).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Rest", "Hover", "Dragged", "Focus", "Rest", "Hover", "Dragged", "Focus" }
    var i = 0usize
    while i < 8usize {
        var axis: ui_layout.Axis = .Horizontal
        var position: f32 = 96.0
        if i >= 4usize {
            axis = .Vertical
            position = 56.0
        }
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        let (node, node_error) = control.split_view(a, u64(1000usize * (i + 1usize)), t, axis, pane(), pane(), position, 40.0, 40.0, change, 200.0, 120.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        let step = i % 4usize
        if step == 1usize { drive = .Hover }
        if step == 2usize { drive = .Press }
        if step == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

// The splitter of v3's Filter window (ref/windows/dialogs/search-filter-top: TcxSplitter, simple hot
// zone, 387 long between two f9f9f9 panels) at its real length: a 16 x 387 split, the strip 8 wide at
// x 4. `splitter.exe dialog` writes splitter_dialog.png, which compares pixel for pixel with
// ref/windows/splitter_dialog.png (scripts/looks_refs_d.py).
fn page_pane() -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Percent: 100.0 }
    s.height = style.Length { Percent: 100.0 }
    s.background = paint.Brush { Solid: style.hex(16382457u32) }
    ret widget.box(0u64, s, zero)
}

fn small_pane(w: f32) -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Percent: 100.0 }
    s.background = paint.Brush { Solid: style.hex(16382457u32) }
    ret widget.box(0u64, s, zero)
}

fn build_dialog(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
    let (node, node_error) = control.split_view(a, 1000u64, t, .Horizontal, page_pane(), small_pane(4.0), 12.0, 2.0, 2.0, change, 24.0, 387.0)
    if node_error != ok { ret (0usize, node_error) }
    // The left edge of the capture crosses the neighbouring panel's frame: a #F0F0F0 band (6 wide, rows 34 to 351,
    // #F3F3F3 and #F6F6F6 at its ends) in the page's colour.
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = node
    parts[1usize] = band(34.0, 318.0, 15790320u32)
    parts[2usize] = band(33.0, 1.0, 15987699u32)
    parts[3usize] = band(352.0, 1.0, 16185078u32)
    cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, looks.size_style(24.0, 387.0), parts[0usize..4usize]), drive: .None }
    ret (1usize, ok)
}

fn band(y: f32, h: f32, rgb: u32) -> widget.Node {
    var s = looks.size_style(6.0, h)
    s.background = paint.Brush { Solid: style.hex(rgb) }
    ret widget.positioned(0u64, 0.0, y, s, zero)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && args[1usize][0usize] == 100u8 {
        let dialog = looks.Sheet { name: "splitter_dialog", cells: 1usize, columns: 1usize, cell_w: 24.0, cell_h: 387.0, ctx: zero, build: build_dialog }
        ret looks.run_all(a, &dialog)
    }
    if args.len == 2usize && args[1usize][0usize] == 104u8 {
        // `h`: the three held strips of ref/windows/states (the Filter window's, then `v` and `w` the main window's).
        let held = looks.Sheet { name: "splitter_dialog_held", cells: 1usize, columns: 1usize, cell_w: 24.0, cell_h: 387.0, ctx: zero, build: build_dialog_held }
        ret looks.run_all(a, &held)
    }
    if args.len == 2usize && args[1usize][0usize] == 120u8 {
        // `x` and `y`: the main window's strips under the pointer (hover-splitter-vertical, ...-horizontal).
        let hover = looks.Sheet { name: "splitter_live_hover", cells: 1usize, columns: 1usize, cell_w: 8.0, cell_h: 463.0, ctx: zero, build: build_live_hover }
        ret looks.run_all(a, &hover)
    }
    if args.len == 2usize && args[1usize][0usize] == 121u8 {
        let hover = looks.Sheet { name: "splitter_live_across_hover", cells: 1usize, columns: 1usize, cell_w: 574.0, cell_h: 8.0, ctx: zero, build: build_lying_hover }
        ret looks.run_all(a, &hover)
    }
    if args.len == 2usize && args[1usize][0usize] == 118u8 {
        let held = looks.Sheet { name: "splitter_live_held", cells: 1usize, columns: 1usize, cell_w: 8.0, cell_h: 463.0, ctx: zero, build: build_live_held }
        ret looks.run_all(a, &held)
    }
    if args.len == 2usize && args[1usize][0usize] == 119u8 {
        let held = looks.Sheet { name: "splitter_live_across_held", cells: 1usize, columns: 1usize, cell_w: 574.0, cell_h: 8.0, ctx: zero, build: build_lying_held }
        ret looks.run_all(a, &held)
    }
    if args.len > 1usize && args[1usize][0usize] == 108u8 {
        let lying = looks.Sheet { name: "splitter_live_across", cells: 1usize, columns: 1usize, cell_w: 497.0, cell_h: 8.0, ctx: zero, build: build_lying }
        ret looks.run_all(a, &lying)
    }
    if args.len > 1usize {
        let live = looks.Sheet { name: "splitter_live", cells: 1usize, columns: 1usize, cell_w: 8.0, cell_h: 463.0, ctx: zero, build: build_live }
        ret looks.run_all(a, &live)
    }
    let sheet = looks.Sheet { name: "splitter", cells: 8usize, columns: 4usize, cell_w: 200.0, cell_h: 120.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// The two splitters of the v3 main window at their real length (live capture
// ref/windows/splitter_live*.png): the upright one between the card panel and the grids, the
// lying one between the two grids; each in a split big enough for its hot zone.
fn plain_pane() -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Percent: 100.0 }
    s.height = style.Length { Percent: 100.0 }
    s.background = paint.Brush { Solid: style.hex(16777215u32) }
    ret widget.box(0u64, s, zero)
}

// `build_live`: the upright splitter of the main window, its whole 8 x 463 strip (the hot zone 140 long at 162),
// as ref/windows/main-window@1x shows it at (287, 109); `build_lying`: the lying one, 497 x 8 at (295, 322).
fn build_clipped(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, lying: bool, drive: looks.Drive, length: f32) -> (usize, err) {
    let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
    var axis: ui_layout.Axis = .Horizontal
    var w: f32 = 8.0
    var h: f32 = 463.0
    if lying {
        axis = .Vertical
        w = length
        h = 8.0
    }
    let (node, node_error) = control.split_view(a, 1000u64, t, axis, widget.box(0u64, looks.size_style(0.0, 0.0), zero), widget.box(0u64, looks.size_style(0.0, 0.0), zero), 0.0, 0.0, 0.0, change, w, h)
    if node_error != ok { ret (0usize, node_error) }
    if lying && drive == .None {
        // The first row of the strip is the grid frame above it (#B8BBBF) outside the hot zone.
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (0usize, parts_error) }
        parts[0usize] = node
        parts[1usize] = edge_row(0.0, 174.0)
        parts[2usize] = edge_row(325.0, 172.0)
        cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, looks.size_style(497.0, 8.0), parts[0usize..3usize]), drive: drive }
        ret (1usize, ok)
    }
    if drive != .None {
        // The held strips of the main window: the neighbouring panel's edge as in the rest strips.
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (0usize, parts_error) }
        parts[0usize] = node
        if lying {
            parts[1usize] = edge_row(0.0, 200.0)
            parts[2usize] = edge_row(374.0, 200.0)
            cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, looks.size_style(length, 8.0), parts[0usize..3usize]), drive: drive }
            ret (1usize, ok)
        }
        var left = looks.size_style(1.0, 158.0)
        left.background = paint.Brush { Solid: style.hex(14079445u32) }
        parts[1usize] = widget.positioned(0u64, 0.0, 3.0, left, zero)
        cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, looks.size_style(8.0, 463.0), parts[0usize..2usize]), drive: drive }
        ret (1usize, ok)
    }
    // The strip's first column below the hot zone is the neighbouring grid's edge (#F3F3F3, rows 309 to 462).
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = node
    var edge = looks.size_style(1.0, 154.0)
    edge.background = paint.Brush { Solid: style.hex(15987699u32) }
    parts[1usize] = widget.positioned(0u64, 0.0, 309.0, edge, zero)
    cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, looks.size_style(8.0, 463.0), parts[0usize..2usize]), drive: .None }
    ret (1usize, ok)
}

fn edge_row(x: f32, w: f32) -> widget.Node {
    var s = looks.size_style(w, 1.0)
    s.background = paint.Brush { Solid: style.hex(12106687u32) }
    ret widget.positioned(0u64, x, 0.0, s, zero)
}

fn build_live(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_clipped(a, t, cells, false, .None, 463.0)
    ret (m, e)
}

fn build_lying(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_clipped(a, t, cells, true, .None, 497.0)
    ret (m, e)
}

fn build_live_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_clipped(a, t, cells, false, .Hover, 463.0)
    ret (m, e)
}

fn build_lying_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_clipped(a, t, cells, true, .Hover, 574.0)
    ret (m, e)
}

fn build_live_held(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_clipped(a, t, cells, false, .Press, 463.0)
    ret (m, e)
}

fn build_lying_held(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_clipped(a, t, cells, true, .Press, 574.0)
    ret (m, e)
}

fn build_dialog_held(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
    let (node, node_error) = control.split_view(a, 1000u64, t, .Horizontal, page_pane(), small_pane(4.0), 12.0, 2.0, 2.0, change, 24.0, 387.0)
    if node_error != ok { ret (0usize, node_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = node
    parts[1usize] = band(34.0, 318.0, 15790320u32)
    parts[2usize] = band(33.0, 1.0, 15987699u32)
    parts[3usize] = band(352.0, 1.0, 16185078u32)
    cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, looks.size_style(24.0, 387.0), parts[0usize..4usize]), drive: .Press }
    ret (1usize, ok)
}
