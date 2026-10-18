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
    var i = 0usize
    while i < 10usize {
        let row = i / 5usize
        let column = i % 5usize
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        var node: widget.Node = zero
        var made: err = ok
        if row < 1usize {
            // md-slider's pressed capture is taken with the pointer at the middle: the handle sits at 50.
            var value: f32 = 40.0
            if column == 3usize { value = 50.0 }
            let (n, e) = control.slider(a, u64(i + 1usize), t, "", value, 0.0, 100.0, 1.0, change, column != 4usize)
            node = n
            made = e
        } else {
            var second: f32 = 70.0
            if column == 3usize { second = 50.0 }
            let (n, e) = control.range_slider(a, u64((i + 1usize) * 4usize), t, "", 20.0, second, 0.0, 100.0, 1.0, change, change, column != 4usize)
            node = n
            made = e
        }
        if made != ok { ret (0usize, made) }
        cells[i] = looks.Cell { caption: states[column], node: node, drive: drive_of(column) }
        i += 1usize
    }
    // Rows 2 and 3: the labeled slider and the one with ticks (0 to 10, at 4), in the same five states.
    var j = 0usize
    while j < 10usize {
        let row = j / 5usize
        let column = j % 5usize
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        var value: f32 = 40.0
        if column == 3usize { value = 50.0 }
        var high: f32 = 100.0
        if row == 1usize {
            value = 4.0
            if column == 3usize { value = 5.0 }
            high = 10.0
        }
        let (n, e) = control.slider_material(a, u64(200usize + j), t, "", value, 0.0, high, 1.0, change, column != 4usize, row == 1usize, row == 0usize)
        if e != ok { ret (0usize, e) }
        cells[10usize + j] = looks.Cell { caption: states[column], node: n, drive: drive_of(column) }
        j += 1usize
    }
    ret (20usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "slider", cells: 20usize, columns: 5usize, cell_w: 220.0, cell_h: 72.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
