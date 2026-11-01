// The range slider (two handles) in every look: docs/ui/looks/<look>/range_slider.png. 25 to 75 of 0 to 100 at rest, with the
// first handle hovered and pressed, keyboard focus, disabled, a stepped one (10) and the two handles together. Run from the
// repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [7]str{ "rest", "hover handle", "pressed handle", "focus", "disabled", "step 10", "touching" }
    var i = 0usize
    while i < 7usize {
        var first: f32 = 25.0
        var second: f32 = 75.0
        var step: f32 = 0.0
        if i == 5usize { step = 10.0 }
        if i == 6usize {
            first = 50.0
            second = 52.0
        }
        let first_change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        let second_change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        let (node, node_error) = control.range_slider(a, u64((i + 1usize) * 10usize), t, "Price", first, second, 0.0, 100.0, step, first_change, second_change, i != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 2usize {
            looks.aim(i, -30.0, 0.0)
            drive = .Hover
        }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "range_slider", cells: 7usize, columns: 4usize, cell_w: 190.0, cell_h: 70.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
