// The Android look's number field (spin edit), docs/ui/looks/material/spin_edit.png: an outlined text field flanked by
// two 40 dp tonal icon buttons (M3 has no spinner arrows). Rest, hovered, focused, pressed, selected, at a bound,
// disabled and error. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: i64) -> err { ret ok }
fn noop_typed(ctx: *void, value: str) -> err { ret ok }

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

// `node` `left` px from the start of the cell, at its top: the harness drives the middle of the cell box, so the
// left offset decides which part of the control sits under the pointer.
fn at_left(a: *mem.Arena, node: widget.Node, left: f32, across: f32, high: f32) -> (widget.Node, err) {
    var column = looks.size_style(across, high)
    column.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = node
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, column, parts[0usize..1usize]), ok)
}

// 12 cells, 4 per row.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [12]str{ "Enabled", "Hovered (field)", "Hovered (minus)", "Hovered (plus)", "Pressed (plus)", "Focused", "Selected text", "At minimum", "At maximum", "Disabled", "Error", "Pressed (minus)" }
    var i = 0usize
    while i < 12usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 24usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var value = 7i64
        if i == 7usize { value = 1i64 }
        if i == 8usize { value = 99i64 }
        let key = u64(10usize * (i + 1usize))
        let (spin, spin_error) = control.spin_box_full(a, key, t, "Quantity", buffer, value, 1i64, 99i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_typed }, 96.0, i != 9usize, i == 10usize)
        if spin_error != ok { ret (0usize, spin_error) }
        var node = spin
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 5usize || i == 6usize { drive = .Focus }
        if i == 2usize || i == 11usize {
            let (aim, aim_error) = at_left(a, spin, 150.0, 340.0, 84.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
            if i == 11usize { drive = .Press }
        }
        if i == 3usize || i == 4usize {
            let (aim, aim_error) = at_left(a, spin, 6.0, 340.0, 84.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
            if i == 4usize { drive = .Press }
        }
        if i == 6usize { select_all(t, key, 1usize) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "spin_edit", cells: 12usize, columns: 3usize, cell_w: 340.0, cell_h: 84.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
