// The Cupertino (iOS) slider: docs/ui/looks/cupertino/slider.png (and cupertino-dark). Rows at 0, 35 and 100 %;
// columns rest, hover, pressed, keyboard focus, disabled.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let columns = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    let values = [3]f32{ 0.0, 35.0, 100.0 }
    var i = 0usize
    while i < 15usize {
        let row = i / 5usize
        let column = i % 5usize
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        let (node, node_error) = control.slider(a, u64((i + 1usize) * 10usize), t, "Volume", values[row], 0.0, 100.0, 0.0, change, column != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if column == 1usize { drive = .Hover }
        if column == 2usize { drive = .Press }
        if column == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: columns[column], node: node, drive: drive }
        i += 1usize
    }
    ret (15usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "slider", cells: 15usize, columns: 5usize, cell_w: 224.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
