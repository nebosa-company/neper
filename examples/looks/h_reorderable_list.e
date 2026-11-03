// The collection reorderable list (collection.reorderable_list): rows with a drag handle, moved by drag or keyboard.
// Sheet "reorderable_list": rest, hover, pressed, keyboard focus.
// Derived: rows and handles come from the shared tokens of each look; no per-platform drawing, no reference capture.
// The cell centre lands on the third row, so hover, press and focus show that row.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.looks_z87
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "rest", "hover", "pressed", "focus" }
    var i = 0usize
    while i < 4usize {
        let labels = [5]str{ "Alpha", "Beta", "Gamma", "Delta", "Epsilon" }
        var items: [5]widget.Node = zero
        try h.words(a, t, labels[0usize..5usize], items[0usize..5usize])
        var keys: [5]widget.Key = zero
        var k = 0usize
        while k < 5usize {
            keys[k] = u64((i + 1usize) * 100usize + k + 1usize)
            k += 1usize
        }
        // Android: 56 dp list items (a 24 dp drag handle leads each)
        var extent: f32 = 32.0
        if t.tokens.profile == .MaterialLike { extent = 56.0 }
        let (node, node_error) = collection.reorderable_list(a, u64((i + 1usize) * 100usize), t, "Order", items[0usize..5usize], keys[0usize..5usize], extent, widget.Change[collection.Reorder] { ctx: zero, invoke: h.noop_move }, 220.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        // Android: the pointer goes down onto the third row (the cell centre is the seam between the second and third)
        if i == 1usize || i == 2usize {
            var down: f32 = 16.0
            if t.tokens.profile == .MaterialLike { down = 0.0 }
            looks_z87.aim(t, i, 0.0, down)
        }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "reorderable_list", cells: 4usize, columns: 2usize, cell_w: 250.0, cell_h: 200.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    // Android: 56 dp rows, five of them, in a taller cell
    let android = looks.Sheet { name: "reorderable_list", cells: 4usize, columns: 2usize, cell_w: 250.0, cell_h: 310.0, ctx: zero, build: build }
    ret looks.run_material(a, &android)
}
