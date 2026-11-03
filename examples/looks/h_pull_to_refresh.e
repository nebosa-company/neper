// The collection pull to refresh (collection.pull_to_refresh): a feed that a pull down refreshes, an indicator while refreshing.
// Sheet "pull_to_refresh": rest, refreshing, hover, keyboard focus.
// Derived: the indicator comes from the shared tokens of each look; a pull gesture mid-drag is not drawn (no cell drives it),
// and no reference capture exists.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "rest", "refreshing", "hover", "focus" }
    var i = 0usize
    while i < 4usize {
        let labels = [3]str{ "Latest news", "Second story", "Third story" }
        var items: [3]widget.Node = zero
        try h.words(a, t, labels[0usize..3usize], items[0usize..3usize])
        let (column, column_error) = h.column(a, items[0usize..3usize], 8.0)
        if column_error != ok { ret (0usize, column_error) }
        let submit = widget.Submit { ctx: zero, invoke: h.noop_submit }
        let (node, node_error) = collection.pull_to_refresh(a, u64((i + 1usize) * 100usize), t, column, i == 1usize, &submit, 240.0, 130.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize {
            drive = .Hover
            if t.tokens.profile == .MaterialLike { looks.aim(2usize, -84.0, -61.0) }
        }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    looks.pad_neper(12.0, 16.0)
    let sheet = looks.Sheet { name: "pull_to_refresh", cells: 4usize, columns: 2usize, cell_w: 270.0, cell_h: 160.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
