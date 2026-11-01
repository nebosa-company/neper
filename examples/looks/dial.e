// The dial in every look: docs/ui/looks/<look>/dial.png. A 96 px knob at 35 of 100 at rest, hover, pressed and keyboard focus,
// a 64 px one, and 0 and 100. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_a
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [7]str{ "rest", "hover", "pressed", "focus", "small", "0", "100" }
    let values = [7]f32{ 35.0, 35.0, 35.0, 35.0, 35.0, 0.0, 100.0 }
    var i = 0usize
    while i < 7usize {
        var size: f32 = 96.0
        if i == 4usize { size = 64.0 }
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        let (node, node_error) = control.dial(a, u64((i + 1usize) * 10usize), t, "Volume", values[i], 0.0, 100.0, change, size)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dial", cells: 7usize, columns: 4usize, cell_w: 120.0, cell_h: 124.0, ctx: zero, build: build }
    ret looks_a.run_every(a, &sheet)
}
