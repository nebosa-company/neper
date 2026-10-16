// The spin edit (TcxSpinEdit) in every state under every look: docs/ui/looks/<look>/spin_edit.png.
// Run from the repository root; see docs/ui/looks-howto.md.

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

// The control with spacers round it (above, below, right) so that the middle of the whole box,
// which is what the harness drives, lands on a chosen point of the control: an arrow button.
fn aimed(a: *mem.Arena, node: widget.Node, above: f32, below: f32, right: f32) -> (widget.Node, err) {
    let (column, column_error) = mem.alloc[widget.Node](a, 3usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.box(0u64, sized(1.0, above), zero)
    column[1usize] = node
    column[2usize] = widget.box(0u64, sized(1.0, below), zero)
    let (row, row_error) = mem.alloc[widget.Node](a, 2usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), column[0usize..3usize])
    row[1usize] = widget.box(0u64, sized(right, 1.0), zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), row[0usize..2usize]), ok)
}

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// Eleven cells (the last, a disabled one, from the native captures only): at rest, hovered over the field, over the up arrow, over the down arrow, the up and
// down arrows pressed, focused, at its lower bound (down arrow dimmed), at its upper bound, and
// with its text selected.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [11]str{ "Rest", "Hover field", "Hover up", "Hover down", "Press up", "Press down", "Focused", "At minimum", "At maximum", "Selected text", "Disabled" }
    var i = 0usize
    while i < 11usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 24usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        var value = 7i64
        if i == 7usize { value = 1i64 }
        if i == 8usize { value = 99i64 }
        let key = u64(10usize * (i + 1usize))
        let (spin, spin_error) = control.spin_box_full(a, key, t, "Quantity", buffer, value, 1i64, 99i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_change }, widget.Change[str] { ctx: zero, invoke: noop_typed }, 70.0, i != 10usize, false)
        if spin_error != ok { ret (0usize, spin_error) }
        var node = spin
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 6usize || i == 9usize { drive = .Focus }
        if i == 2usize || i == 4usize {
            let (aim, aim_error) = aimed(a, spin, 8.0, 0.0, 51.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
            if i == 4usize { drive = .Press }
        }
        if i == 3usize || i == 5usize {
            let (aim, aim_error) = aimed(a, spin, 0.0, 10.0, 51.0)
            if aim_error != ok { ret (0usize, aim_error) }
            node = aim
            drive = .Hover
            if i == 5usize { drive = .Press }
        }
        if i == 9usize { select_all(t, key, 1usize) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (11usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "spin_edit", cells: 11usize, columns: 5usize, cell_w: 130.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
