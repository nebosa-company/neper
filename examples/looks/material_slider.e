// The Android look's slider, docs/ui/looks/material/slider.png: enabled, hovered, focused, pressed (dragged) and
// disabled, at 50 %, and a range slider. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

fn drive_of(column: usize) -> looks.Drive {
    if column == 1usize { ret .Hover }
    if column == 2usize { ret .Focus }
    if column == 3usize { ret .Press }
    ret .None
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let states = [5]str{ "Enabled", "Hovered", "Focused", "Pressed", "Disabled" }
    let values = [1]f32{ 50.0 }
    var i = 0usize
    while i < 10usize {
        let row = i / 5usize
        let column = i % 5usize
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        var node: widget.Node = zero
        var made: err = ok
        if row < 1usize {
            let (n, e) = control.slider(a, u64(i + 1usize), t, "", values[row], 0.0, 100.0, 1.0, change, column != 4usize)
            node = n
            made = e
        } else {
            let (n, e) = control.range_slider(a, u64((i + 1usize) * 4usize), t, "", 25.0, 75.0, 0.0, 100.0, 1.0, change, change, column != 4usize)
            node = n
            made = e
        }
        if made != ok { ret (0usize, made) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "slider", cells: 10usize, columns: 5usize, cell_w: 134.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
