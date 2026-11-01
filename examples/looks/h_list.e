// The collection list (collection.list): static rows over separators, the chosen rows on the secondary container.
// Sheet "list_rows" (docs/ui/looks/<look>/list_rows.png): rest, one row chosen, two rows chosen, no separators, a long row.
// Derived: the rows, separators and the chosen fill come from the shared tokens of each look; there is no per-platform
// list drawing, and no reference capture exists for any look. A list row has no hover or press of its own.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [5]str{ "rest", "one chosen", "two chosen", "no separators", "long row" }
    var i = 0usize
    while i < 5usize {
        var labels = [5]str{ "Inbox", "Drafts", "Sent", "Archive", "Trash" }
        if i == 4usize { labels[1usize] = "A draft with a rather long title that does not fit the row" }
        var items: [5]widget.Node = zero
        try h.words(a, t, labels[0usize..5usize], items[0usize..5usize])
        var keys: [5]widget.Key = zero
        var k = 0usize
        while k < 5usize {
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
            chosen[1usize] = keys[3usize]
            chosen_count = 2usize
        }
        let (node, node_error) = collection.list(a, u64((i + 1usize) * 100usize), t, "Mailboxes", items[0usize..5usize], keys[0usize..5usize], chosen[0usize..chosen_count], i != 3usize, 220.0)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "list_rows", cells: 5usize, columns: 3usize, cell_w: 240.0, cell_h: 230.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
