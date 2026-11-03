// Round 86, lane x: Windows and Windows Dark completion. datagrid.e calls this file with plain values.

use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.wintile
use e.ui.winedpic

// v3's open in-cell editor of the current row, light 1:1 capture (data_grid_bottom): the spin editor's step buttons one pixel inside the
// cell's left and right edges, the button editor's three-dots button two pixels inside the right edge, the value between them.
fn one_of(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

// The value centred in the cell (`width` wide, 18 tall), the tiles on top at the capture's pixels.
fn editor(a: *mem.Arena, value: widget.Node, width: f32, tile: widget.Node, tile_x: f32, tile_y: f32, other: widget.Node, other_x: f32, has_other: bool) -> (widget.Node, err) {
    var wide = style.defaults()
    wide.width = style.Length { Px: width - 1.0 }
    wide.height = style.Length { Px: 18.0 }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.aligned(0u64, .Start, .Center, wide, one_of(a, value))
    parts[1usize] = widget.positioned(0u64, tile_x, tile_y, style.defaults(), one_of(a, tile))
    var n = 2usize
    if has_other {
        parts[2usize] = widget.positioned(0u64, other_x, tile_y, style.defaults(), one_of(a, other))
        n = 3usize
    }
    ret (widget.stack(0u64, style.defaults(), parts[0usize..n]), ok)
}

fn spin(a: *mem.Arena, value: widget.Node, width: f32, pad: f32) -> (widget.Node, err) {
    var left_px = winedpic.spin_left()
    var right_px = winedpic.spin_right()
    let (left, left_error) = wintile.tile_node(a, winedpic.spin_left_w(), winedpic.spin_left_h(), left_px[0usize..winedpic.spin_left_w() * winedpic.spin_left_h()])
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = wintile.tile_node(a, winedpic.spin_right_w(), winedpic.spin_right_h(), right_px[0usize..winedpic.spin_right_w() * winedpic.spin_right_h()])
    if right_error != ok { ret (zero, right_error) }
    let (node, node_error) = editor(a, value, width, left, 1.0 - pad, 1.0, right, width - 10.0 - pad, true)
    ret (node, node_error)
}

fn dots(a: *mem.Arena, value: widget.Node, width: f32, pad: f32) -> (widget.Node, err) {
    var dots_px = winedpic.dots()
    let (button, button_error) = wintile.tile_node(a, winedpic.dots_w(), winedpic.dots_h(), dots_px[0usize..winedpic.dots_w() * winedpic.dots_h()])
    if button_error != ok { ret (zero, button_error) }
    let (node, node_error) = editor(a, value, width, button, width - 18.0 - pad, 2.0, button, 0.0, false)
    ret (node, node_error)
}

// The hot Favorite header of the 1:1 capture (data_grid_hover3): star and filter button on the hot fill #D9EBF9, 23 x 22.
fn fav_hot(a: *mem.Arena) -> (widget.Node, err) {
    var px = winedpic.fav_hot()
    let (tile, tile_error) = wintile.tile_node(a, winedpic.fav_hot_w(), winedpic.fav_hot_h(), px[0usize..winedpic.fav_hot_w() * winedpic.fav_hot_h()])
    ret (tile, tile_error)
}

// The marked picture column's header of the 1:1 capture (data_grid_bottom): the colour marker and the hollow triangle in #A0A0A0, 19 x 19.
fn pic_head(a: *mem.Arena) -> (widget.Node, err) {
    var px = winedpic.pic_head()
    let (tile, tile_error) = wintile.tile_node(a, winedpic.pic_head_w(), winedpic.pic_head_h(), px[0usize..winedpic.pic_head_w() * winedpic.pic_head_h()])
    ret (tile, tile_error)
}

// The row indicator's header glyph of the 1:1 capture (7 x 9): three bars with a dot before the first, third and fifth line (rows 0, 4, 8: dot
// and bar; rows 2, 6: bar), clear elsewhere.
fn list_glyph(a: *mem.Arena) -> (widget.Node, err) {
    var g: [63]u32 = zero
    var row = 0usize
    while row < 9usize {
        if row % 2usize == 0usize {
            var c = 3usize
            while c < 7usize {
                g[row * 7usize + c] = 0xFF000000u32
                c += 1usize
            }
            if row % 4usize == 0usize { g[row * 7usize + 1usize] = 0xFF000000u32 }
        }
        row += 1usize
    }
    let (tile, tile_error) = wintile.tile_node(a, 7usize, 9usize, g[0usize..63usize])
    ret (tile, tile_error)
}
