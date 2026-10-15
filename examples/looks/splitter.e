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
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize {
        let dialog = looks.Sheet { name: "splitter_dialog", cells: 1usize, columns: 1usize, cell_w: 24.0, cell_h: 387.0, ctx: zero, build: build_dialog }
        ret looks.run_all(a, &dialog)
    }
    if args.len > 1usize {
        let live = looks.Sheet { name: "splitter_live", cells: 2usize, columns: 2usize, cell_w: 497.0, cell_h: 463.0, ctx: zero, build: build_live }
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

fn build_live(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var i = 0usize
    while i < 2usize {
        var axis: ui_layout.Axis = .Horizontal
        if i == 1usize { axis = .Vertical }
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        // Strips of the captures' real lengths (463 upright, 497 lying: the hot zone is 0.3 of them).
        var live_w: f32 = 200.0
        var live_h: f32 = 463.0
        if i == 1usize {
            live_w = 497.0
            live_h = 200.0
        }
        let (node, node_error) = control.split_view(a, u64(1000usize * (i + 1usize)), t, axis, plain_pane(), plain_pane(), 96.0, 40.0, 40.0, change, live_w, live_h)
        if node_error != ok { ret (0usize, node_error) }
        var caption = "Upright"
        if i == 1usize { caption = "Lying" }
        cells[i] = looks.Cell { caption: caption, node: node, drive: .None }
        i += 1usize
    }
    ret (2usize, ok)
}
