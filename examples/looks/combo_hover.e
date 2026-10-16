// The combo boxes under the pointer, one cell per hover capture (docs/ui/looks/ref/windows/states/hover-combo-box-*): the
// list-style combo (Options Grids Row Color, Conditional Formatting Show) over its text and over its drop button, the three
// image combo boxes of Options (Internet Authentication, Defaults Condition, Morph Card Art Position) over their drop
// button, the editable combo of Search for Card over its drop button, and the two grabs that are PIXEL-IDENTICAL to the rest
// grab (Authentication and Search, "over the edit"): their cells are not driven, so the sheet asserts that the hover draws as
// rest there. Every control stands at the x and y it has in its dialog (the frame's drifting rows depend on them), and the cell
// (800 x 29, pointer at its centre) is placed so that the driven hover lands on the zone.
// scripts/looks_combo_hover_eval.py diffs the sheet against the captures (same order).
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

fn noop_submit(ctx: *void) -> err { ret ok }

fn pick_actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

// `node` `left` px from the side of a 800 x 29 cell, 4 px down.
fn placed(a: *mem.Arena, node: widget.Node, left: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, 4.0), zero)
    parts[1usize] = node
    var column = looks.size_style(800.0, 29.0)
    column.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), ok)
}

// A combo box (list style or editable) of DFM width `width` at (edge_x, edge_y) of its dialog.
fn plain(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: str, read_only: bool, width: f32, edge_x: f32, edge_y: f32) -> (widget.Node, err) {
    let colors = [4]str{ "Not Colored", "Against Card Color", "Against Card Rarity", "Frame" }
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let n = control.copy_text(buffer, value)
    let (picks, picks_error) = pick_actions(a, 4usize)
    if picks_error != ok { ret (zero, picks_error) }
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (zero, toggle_error) }
    var options = control.field_options()
    options.width = width
    options.read_only = read_only
    options.edge_x = edge_x
    options.edge_y = edge_y
    let (combo, combo_error) = control.combo_box(a, key, t, "Combo", buffer, n, zero, colors[0usize..4usize], 1usize, false, picks, zero, &toggle[0usize], options)
    ret (combo, combo_error)
}

// An image combo box (no picture in its head) as the Options pages draw it.
fn imaged(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: str, width: f32, edge_x: f32, edge_y: f32) -> (widget.Node, err) {
    let names = [2]str{ value, "Other" }
    let (picks, picks_error) = pick_actions(a, 2usize)
    if picks_error != ok { ret (zero, picks_error) }
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (zero, toggle_error) }
    var none: []const widget.Node = zero
    let (combo, combo_error) = control.image_select_at(a, key, t, "Image", names[0usize..2usize], none, 0usize, false, true, &toggle[0usize], picks, width, edge_y, edge_x)
    ret (combo, combo_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [9]str{ "Combo box, hover over the drop button (Options Grids, Row Color)", "Combo box, hover over the text (Options Grids, Row Color)", "Combo box, hover over the drop button (Conditional Formatting, Show, focused as in the dialog)", "Image combo box, hover over the drop button (Options Internet, Authentication)", "Image combo box, hover over the text: the capture is PIXEL-IDENTICAL to rest (Authentication)", "Image combo box, hover over the drop button (Options Defaults, Condition)", "Image combo box, hover over the drop button (Options Morph, Card Art Position)", "Editable combo box, hover over the drop button (Search for Card)", "Editable combo box, hover over the text: the capture is PIXEL-IDENTICAL to rest (Search for Card)" }
    let widths = [9]f32{ 389.0, 389.0, 143.0, 189.0, 189.0, 335.0, 151.0, 289.0, 289.0 }
    let xs = [9]f32{ 321.0, 321.0, 149.0, 371.0, 371.0, 371.0, 406.0, 20.0, 20.0 }
    let ys = [9]f32{ 71.0, 71.0, 41.0, 71.0, 71.0, 99.0, 278.0, 70.0, 70.0 }
    // Where the pointer lands, from the control's left: the drop button (width less 9) or 100 px in.
    let over = [9]f32{ 380.0, 100.0, 134.0, 180.0, 100.0, 326.0, 142.0, 280.0, 100.0 }
    let drives = [9]looks.Drive{ .Hover, .Hover, .FocusHover, .Hover, .None, .Hover, .Hover, .FocusHover, .Focus }
    var i = 0usize
    while i < 9usize {
        var node: widget.Node = zero
        let key = u64(i + 1usize) * 100u64
        if i == 0usize || i == 1usize {
            let (made, made_error) = plain(a, t, key, "Against Card Color", true, widths[i], xs[i], ys[i])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i == 2usize {
            let (made, made_error) = plain(a, t, key, "All", true, widths[i], xs[i], ys[i])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 3usize && i <= 6usize {
            var words = "No Authentication"
            if i == 5usize { words = "Unknown" }
            if i == 6usize { words = "Stretch" }
            let (made, made_error) = imaged(a, t, key, words, widths[i], xs[i], ys[i])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 7usize {
            let (made, made_error) = plain(a, t, key, "", false, widths[i], xs[i], ys[i])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let (at, at_error) = placed(a, node, 400.0 - over[i])
        if at_error != ok { ret (0usize, at_error) }
        cells[i] = looks.Cell { caption: captions[i], node: at, drive: drives[i] }
        i += 1usize
    }
    ret (9usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "combo_hover", cells: 9usize, columns: 1usize, cell_w: 800.0, cell_h: 29.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
