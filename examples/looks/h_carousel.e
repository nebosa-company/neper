// The collection carousel. A carousel: a page view between Previous and Next buttons with a dot indicator below.
// Sheet "carousel": first, middle and last page, hover, pressed, keyboard focus.
// Derived: page box, buttons and dots come from the shared tokens of each look; no per-platform drawing, no reference capture.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.looks_z84
use e.ui.looks_z87
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "first page", "middle page", "last page", "hover", "pressed", "focus" }
    let cur = [6]usize{ 0usize, 1usize, 2usize, 1usize, 1usize, 1usize }
    var i = 0usize
    while i < 6usize {
        let labels = [3]str{ "Welcome to the app", "Swipe to explore", "Get started" }
        var pages: [3]widget.Node = zero
        try h.words(a, t, labels[0usize..3usize], pages[0usize..3usize])
        let (node, node_error) = collection.carousel(a, u64((i + 1usize) * 100usize), t, pages[0usize..3usize], cur[i], widget.Change[usize] { ctx: zero, invoke: h.noop_usize }, 240.0, 110.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize { drive = .Hover }
        if i == 4usize { drive = .Press }
        // Android: hover and press point at the Next arrow
        if i == 3usize || i == 4usize { looks_z87.aim(t, i, 144.0, 0.0 - 10.0) }
        if i == 5usize { drive = .Focus }
        // Android: four Tab presses land the keyboard on the Previous arrow (other counts leave it on the page view)
        if i == 5usize && t.tokens.profile == .MaterialLike {
            looks_z84.stops(4usize)
            drive = .Tabs
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "carousel", cells: 6usize, columns: 2usize, cell_w: 330.0, cell_h: 200.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
