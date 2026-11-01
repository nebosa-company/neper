// The collection page_view. A page view: one page alone in a clipped box; swipe or Left and Right turn it.
// Sheet "page_view": first, middle and last page, hover, pressed, keyboard focus.
// Derived: page box, buttons and dots come from the shared tokens of each look; no per-platform drawing, no reference capture.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "first page", "middle page", "last page", "hover", "pressed", "focus" }
    let cur = [6]usize{ 0usize, 1usize, 2usize, 1usize, 1usize, 1usize }
    var i = 0usize
    while i < 6usize {
        let labels = [3]str{ "Welcome to the app", "Swipe to explore", "Get started" }
        var pages: [3]widget.Node = zero
        try h.words(a, t, labels[0usize..3usize], pages[0usize..3usize])
        let (node, node_error) = collection.page_view(a, u64((i + 1usize) * 100usize), t, pages[0usize..3usize], cur[i], widget.Change[usize] { ctx: zero, invoke: h.noop_usize }, 240.0, 110.0)
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
    let sheet = looks.Sheet { name: "page_view", cells: 6usize, columns: 2usize, cell_w: 330.0, cell_h: 200.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
