// The collection grid view (collection.grid_view): tiles wrapped across the width, a chosen tile on the secondary container.
// Sheet "grid_view": rest, one chosen, two chosen, narrow (wraps to two columns).
// Derived: tiles come from the shared tokens of each look; no per-platform grid drawing, no reference capture.

use e.mem
use e.gfx.geometry
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "rest", "one chosen", "two chosen", "narrow" }
    var i = 0usize
    while i < 4usize {
        let labels = [6]str{ "Photos", "Music", "Maps", "Notes", "Mail", "Files" }
        var items: [6]widget.Node = zero
        try h.words(a, t, labels[0usize..6usize], items[0usize..6usize])
        var keys: [6]widget.Key = zero
        var k = 0usize
        while k < 6usize {
            keys[k] = u64((i + 1usize) * 100usize + k + 1usize)
            k += 1usize
        }
        var chosen: [2]widget.Key = zero
        var chosen_count = 0usize
        if i == 1usize || i == 2usize {
            chosen[0usize] = keys[1usize]
            chosen_count = 1usize
        }
        if i == 2usize {
            chosen[1usize] = keys[4usize]
            chosen_count = 2usize
        }
        var width: f32 = 260.0
        if i == 3usize { width = 170.0 }
        let (node, node_error) = collection.grid_view(a, u64((i + 1usize) * 100usize), t, "Apps", items[0usize..6usize], keys[0usize..6usize], chosen[0usize..chosen_count], geometry.Size { width: 76.0, height: 56.0 }, 8.0, width)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "grid_view", cells: 4usize, columns: 2usize, cell_w: 290.0, cell_h: 210.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
