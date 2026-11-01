// The collection pagination (collection.pagination): Previous, a window of page numbers (current selected), Next.
// Sheet "pagination": first page, middle page, last page, hover, pressed, keyboard focus.
// Derived: drawn through the shared button and token styles of each look; no per-platform pagination drawing, no reference capture.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "first page", "middle page", "last page", "hover", "pressed", "focus" }
    let current = [6]usize{ 0usize, 4usize, 8usize, 4usize, 4usize, 4usize }
    var i = 0usize
    while i < 6usize {
        let (node, node_error) = collection.pagination(a, u64((i + 1usize) * 100usize), t, "Pages", 9usize, current[i], 5usize, widget.Change[usize] { ctx: zero, invoke: h.noop_usize })
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize { drive = .Hover }
        if i == 4usize { drive = .Press }
        if i == 5usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "pagination", cells: 6usize, columns: 2usize, cell_w: 420.0, cell_h: 80.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
